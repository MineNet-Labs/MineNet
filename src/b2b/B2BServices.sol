// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IMineNetRegistry} from "src/access/interfaces/IMineNetRegistry.sol";
import {ICurrencyManager} from "src/finance/interfaces/ICurrencyManager.sol";
import {ILotPassport} from "src/traceability/interfaces/ILotPassport.sol";
import {ISupplyChain} from "src/traceability/interfaces/ISupplyChain.sol";
import {IDeliveryManager} from "src/traceability/interfaces/IDeliveryManager.sol";
import {Actions} from "src/access/libraries/Actions.sol";
import {IB2BServices} from "src/b2b/interfaces/IB2BServices.sol";
import {B2BLib} from "src/b2b/libraries/B2BLib.sol";
import {ServicesLib} from "src/b2b/libraries/ServicesLib.sol";
import {ServicesLogic} from "src/b2b/libraries/ServicesLogic.sol";

/**
 * @title B2BServices
 * @author 0xEmmyb2
 * @notice Recurring service agreements between MineNet companies: haulage, storage, toll processing and
 * refining, inspection and assay, audit, customs clearing, and general services (equipment rental,
 * maintenance, security, consulting, labour). Mineral supply agreements live in {B2B}.
 * @dev ## Negotiation
 * A company (`ENTER_AGREEMENT`) proposes terms to another company: the kind of service, who provides it, the
 * rate per unit, the budget of each job (in units), the number of jobs or billing periods and the interval
 * between them, the review period, and optionally a neutral arbiter. The provider must hold the permission its
 * kind requires (`CARRY` for haulage, `OPERATE_WAREHOUSE` for storage, `PROCESS_LOTS` for tolling, `INSPECT_LOT`
 * for inspection, `AUDIT` for audit, `FILE_CUSTOMS` for customs clearing). Proposing signs version 1; either
 * party can amend (a counter-offer, new version); the agreement becomes Active once both have signed the same
 * version before the deadline.
 *
 * ## Billing verified on-chain
 * Work only counts if it happened after activation, and each piece of work is billed once:
 * - Haulage: {DeliveryManager} shipments in `Delivered` status, carried by the provider's organisation, sent or
 *   received by the client's organisation; billed on the lots' trusted weight.
 * - Storage: the client's lots in the provider's custody, billed between the end of the period (its due date)
 *   and the end of the next one (or {MISSED_GRACE} for a single period); on their trusted weight, once per lot
 *   and period.
 * - Toll processing / refining: the client's lots consumed by `processLots` in the provider's custody into
 *   output lots created after activation; billed on their input weight.
 * - Inspection and assay / Audit / Customs clearing: `Inspection` / `Audit` / `CustomsDeclared` checkpoints
 *   signed by the provider's organisation on lots the client owns or holds; customs lots must since have been
 *   released. Billed per checkpoint.
 * - Equipment rental, maintenance, security, consulting, labour, other: units claimed with an evidence hash.
 * Billing is capped at the job's budget (`maxUnitsPerJob`).
 *
 * ## One job
 * The client funds the job's budget (escrowed agreements); the provider bills its work; the client accepts, or
 * after the review period anyone releases it; the unused budget returns to the client. The client can dispute
 * within the review period: the parties settle with matching offers, or the agreed arbiter decides after
 * {NEGOTIATION_PERIOD}. A job not billed {MISSED_GRACE} after its due date can be closed as missed (refunded); a
 * job the client did not fund by its due date can be marked in default.
 *
 * ## Ending
 * The agreement completes when every job is resolved; it can be terminated by mutual consent, or for cause
 * after `maxMissed` misses or defaults by the other side. Every company builds a track record
 * ({performanceOf}). Payouts use the pull pattern ({withdraw}); pausing stops new business but never payments,
 * refunds, disputes or termination.
 */
contract B2BServices is ReentrancyGuardTransient, Pausable, IB2BServices {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Maximum number of jobs or billing periods in one agreement.
     */
    uint32 public constant MAX_JOBS = ServicesLogic.MAX_JOBS;

    /**
     * @notice Maximum number of references (shipments, lots, checkpoints) in one claim.
     */
    uint256 public constant MAX_REFS_PER_CLAIM = 50;

    /**
     * @notice Shortest interval between two jobs.
     */
    uint32 public constant MIN_JOB_INTERVAL = ServicesLogic.MIN_JOB_INTERVAL;

    /**
     * @notice Longest interval between two jobs.
     */
    uint32 public constant MAX_JOB_INTERVAL = ServicesLogic.MAX_JOB_INTERVAL;

    /**
     * @notice Longest time from activation to the first job.
     */
    uint32 public constant MAX_FIRST_JOB_OFFSET = ServicesLogic.MAX_FIRST_JOB_OFFSET;

    /**
     * @notice Shortest review period a client may be given.
     */
    uint32 public constant MIN_REVIEW_PERIOD = ServicesLogic.MIN_REVIEW_PERIOD;

    /**
     * @notice Longest review period a client may be given.
     */
    uint32 public constant MAX_REVIEW_PERIOD = ServicesLogic.MAX_REVIEW_PERIOD;

    /**
     * @notice Longest time a proposal may stay open for signature.
     */
    uint64 public constant MAX_PROPOSAL_DURATION = ServicesLogic.MAX_PROPOSAL_DURATION;

    /**
     * @notice Time the parties have to settle a dispute themselves before the arbiter may decide.
     */
    uint64 public constant NEGOTIATION_PERIOD = 14 days;

    /**
     * @notice Time after a job's due date before the client may close it as missed and be refunded.
     */
    uint64 public constant MISSED_GRACE = ServicesLogic.MISSED_GRACE;

    /*//////////////////////////////////////////////////////////////
                                 STORAGE
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Participant, role and permission registry.
     */
    IMineNetRegistry public immutable registry;

    /**
     * @notice Settlement tokens.
     */
    ICurrencyManager public immutable currencies;

    /**
     * @notice Lot passports: ownership, custody, processing links.
     */
    ILotPassport public immutable passport;

    /**
     * @notice Supply-chain ledger: trusted weights and signed checkpoints.
     */
    ISupplyChain public immutable supplyChain;

    /**
     * @notice Shipments billed by haulage agreements.
     */
    IDeliveryManager public immutable deliveryManager;

    /**
     * @dev Next agreement id; ids start at 1 so that 0 means "none".
     */
    uint256 private _nextAgreementId = 1;

    /**
     * @dev Agreement id => agreement.
     */
    mapping(uint256 agreementId => ServicesLib.Agreement) private _agreements;

    /**
     * @dev Agreement id => job index => job (lazily stored).
     */
    mapping(uint256 agreementId => mapping(uint256 index => ServicesLib.Job)) private _jobs;

    /**
     * @dev Agreement id => job index => dispute.
     */
    mapping(uint256 agreementId => mapping(uint256 index => B2BLib.DeliveryDispute)) private _disputes;

    /**
     * @dev Organisation => agreements it is party to, in proposal order.
     */
    mapping(bytes32 orgId => uint256[]) private _agreementsOf;

    /**
     * @dev Organisation => service track record.
     */
    mapping(bytes32 orgId => ServicesLib.Performance) private _performance;

    /**
     * @notice Whether a piece of on-chain work (shipment, consumed lot, checkpoint, lot-period) has been billed.
     */
    mapping(bytes32 workKey => bool) public workBilled;

    /**
     * @notice Balances owed to providers and clients (pull pattern).
     */
    mapping(IERC20 token => mapping(address account => uint256)) public claimable;

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @param registry_ Participant, role and permission registry.
     * @param currencies_ Currency manager.
     * @param passport_ Lot passport.
     * @param supplyChain_ Supply-chain ledger.
     * @param deliveryManager_ Delivery manager.
     */
    constructor(
        IMineNetRegistry registry_,
        ICurrencyManager currencies_,
        ILotPassport passport_,
        ISupplyChain supplyChain_,
        IDeliveryManager deliveryManager_
    ) {
        registry = registry_;
        currencies = currencies_;
        passport = passport_;
        supplyChain = supplyChain_;
        deliveryManager = deliveryManager_;
    }

    /*//////////////////////////////////////////////////////////////
                                  ADMIN
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Pauses new business: proposals, signatures, funding and claims.
     * @dev Only a {MineNetRegistry} admin. The admin has no power over any agreement or its funds.
     */
    function pause() external {
        _onlyAdmin();
        _pause();
    }

    /**
     * @notice Resumes normal operation.
     * @dev Only a {MineNetRegistry} admin.
     */
    function unpause() external {
        _onlyAdmin();
        _unpause();
    }

    /*//////////////////////////////////////////////////////////////
                               NEGOTIATION
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Proposes a service agreement to another company. Proposing signs the first version.
     * @dev The caller and `counterparty` need `ENTER_AGREEMENT` and must belong to different organisations; the
     * provider side must hold the permission its service kind requires.
     * @param counterparty An account of the company the agreement is proposed to.
     * @param terms The proposed terms.
     * @return agreementId New agreement id.
     * @custom:emits ServiceProposed
     * @custom:emits AgreementSigned
     */
    function propose(address counterparty, ServicesLib.Terms calldata terms)
        external
        whenNotPaused
        returns (uint256 agreementId)
    {
        bytes32 proposerOrg = _authorizedOrg(msg.sender);
        bytes32 counterpartyOrg = registry.participant(counterparty).orgId;
        if (
            !registry.isAuthorized(counterparty, Actions.ENTER_AGREEMENT) || counterpartyOrg == bytes32(0)
                || counterpartyOrg == proposerOrg
        ) revert B2BLib.B2B__InvalidCounterparty(counterparty);

        agreementId = _nextAgreementId++;
        ServicesLib.Agreement storage a = _agreements[agreementId];
        a.status = B2BLib.AgreementStatus.Proposed;
        a.proposer = B2BLib.Party({orgId: proposerOrg, account: msg.sender});
        a.counterparty = B2BLib.Party({orgId: counterpartyOrg, account: counterparty});
        ServicesLogic.setTerms(a, terms, registry, currencies);
        a.proposerSigned = true;
        _agreementsOf[proposerOrg].push(agreementId);
        _agreementsOf[counterpartyOrg].push(agreementId);

        emit ServicesLib.ServiceProposed(agreementId, proposerOrg, counterpartyOrg, terms.service, terms.termsHash);
        emit B2BLib.AgreementSigned(agreementId, a.version, B2BLib.Side.Proposer, msg.sender);
    }

    /**
     * @notice Amends a proposal (a counter-offer). The new version is signed by the amending party only.
     * @dev Either party, with `ENTER_AGREEMENT`, while the agreement is a proposal. The caller becomes its side's
     * account of record.
     * @param agreementId Agreement id.
     * @param terms The amended terms.
     * @custom:emits ServiceAmended
     * @custom:emits AgreementSigned
     */
    function amend(uint256 agreementId, ServicesLib.Terms calldata terms) external whenNotPaused {
        ServicesLib.Agreement storage a = _requireStatus(agreementId, B2BLib.AgreementStatus.Proposed);
        B2BLib.Side side = _authorizedSide(agreementId, a);
        _party(a, side).account = msg.sender;
        ServicesLogic.setTerms(a, terms, registry, currencies);
        if (side == B2BLib.Side.Proposer) a.proposerSigned = true;
        else a.counterpartySigned = true;
        emit ServicesLib.ServiceAmended(agreementId, a.version, msg.sender, terms.service, terms.termsHash);
        emit B2BLib.AgreementSigned(agreementId, a.version, side, msg.sender);
    }

    /**
     * @notice Signs the current version of a proposal. The agreement becomes Active once both parties have.
     * @dev Either party, with `ENTER_AGREEMENT`, before the deadline. The caller becomes its side's account of
     * record; on the provider side it must hold the permission the service kind requires.
     * @param agreementId Agreement id.
     * @param version The version being signed; must be the current one.
     * @custom:emits AgreementSigned
     * @custom:emits ServiceActivated (once both have signed)
     */
    function sign(uint256 agreementId, uint32 version) external whenNotPaused {
        ServicesLib.Agreement storage a = _requireStatus(agreementId, B2BLib.AgreementStatus.Proposed);
        if (version != a.version) revert B2BLib.B2B__VersionMismatch(a.version, version);
        if (block.timestamp > a.proposalExpiresAt) revert B2BLib.B2B__ProposalExpired(agreementId);
        B2BLib.Side side = _authorizedSide(agreementId, a);
        if (side == a.service.provider) ServicesLogic.requireQualified(a.service.kind, msg.sender, registry);
        _party(a, side).account = msg.sender;
        if (side == B2BLib.Side.Proposer) a.proposerSigned = true;
        else a.counterpartySigned = true;
        emit B2BLib.AgreementSigned(agreementId, version, side, msg.sender);

        if (a.proposerSigned && a.counterpartySigned) {
            a.status = B2BLib.AgreementStatus.Active;
            a.activatedAt = uint64(block.timestamp);
            emit ServicesLib.ServiceActivated(
                agreementId, version, dueAt(agreementId, 0), dueAt(agreementId, a.service.totalJobs - 1)
            );
        }
    }

    /**
     * @notice Ends a proposal: the proposer withdraws it, or the counterparty rejects it.
     * @dev Either party, while the agreement is a proposal.
     * @param agreementId Agreement id.
     * @param reasonHash Hash of the reason.
     * @custom:emits AgreementDeclined
     */
    function decline(uint256 agreementId, bytes32 reasonHash) external {
        ServicesLib.Agreement storage a = _requireStatus(agreementId, B2BLib.AgreementStatus.Proposed);
        B2BLib.Side side = _sideOf(agreementId, a, msg.sender);
        a.status = side == B2BLib.Side.Proposer ? B2BLib.AgreementStatus.Withdrawn : B2BLib.AgreementStatus.Rejected;
        emit B2BLib.AgreementDeclined(agreementId, a.status, msg.sender, reasonHash);
    }

    /*//////////////////////////////////////////////////////////////
                                  JOBS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Escrows the budget of one job (`maxUnitsPerJob x ratePerUnit`). The tokens are pulled from the
     * caller.
     * @dev The client side, on an Active escrowed agreement, while the job is scheduled (also after its due date,
     * until it is marked in default). The caller must have approved this contract for {budgetOf}.
     * @param agreementId Agreement id.
     * @param index Job index (0-based).
     * @custom:emits JobFunded
     */
    function fundJob(uint256 agreementId, uint256 index) external nonReentrant whenNotPaused {
        ServicesLib.Agreement storage a = _requireStatus(agreementId, B2BLib.AgreementStatus.Active);
        if (address(a.paymentToken) == address(0)) revert B2BLib.B2B__NotEscrowed();
        _requireSide(agreementId, a, B2BLib.other(a.service.provider));
        ServicesLib.Job storage j = _job(agreementId, a, index);
        _requireJobStatus(index, j, ServicesLib.JobStatus.Scheduled);

        uint256 budget = budgetOf(agreementId);
        j.status = ServicesLib.JobStatus.Funded;
        j.funded = budget;
        a.progress.funded += 1;
        a.paymentToken.safeTransferFrom(msg.sender, address(this), budget);
        emit ServicesLib.JobFunded(agreementId, index, budget);
    }

    /**
     * @notice The provider bills a job for its work. For verified kinds the units are computed on-chain from
     * `refs`; for claimed kinds they are `claimedUnits`. Billing is capped at the job's budget.
     * @dev The provider side, on an Active agreement, once the job is funded (or while scheduled when paid
     * off-chain). Storage and claimed kinds (security, consulting...) can only be billed from the job's due date,
     * so self-declared work is never billed before it was scheduled to happen. See the contract
     * documentation for what `refs` and `checkpointIndexes` mean per kind.
     * @param agreementId Agreement id.
     * @param index Job index.
     * @param refs Shipment ids (haulage) or lot ids (other verified kinds); empty for claimed kinds.
     * @param checkpointIndexes For inspection, audit and customs: the checkpoint index of each lot in `refs`.
     * @param claimedUnits Units for claimed kinds (ignored otherwise).
     * @param evidenceHash Hash of the provider's evidence (job card, timesheet, report...).
     * @custom:emits JobClaimed
     */
    function claimJob(
        uint256 agreementId,
        uint256 index,
        uint256[] calldata refs,
        uint256[] calldata checkpointIndexes,
        uint128 claimedUnits,
        bytes32 evidenceHash
    ) external nonReentrant whenNotPaused {
        ServicesLib.Agreement storage a = _requireStatus(agreementId, B2BLib.AgreementStatus.Active);
        _requireSide(agreementId, a, a.service.provider);
        ServicesLib.Job storage j = _job(agreementId, a, index);
        bool escrowed = address(a.paymentToken) != address(0);
        _requireJobStatus(index, j, escrowed ? ServicesLib.JobStatus.Funded : ServicesLib.JobStatus.Scheduled);
        if (refs.length > MAX_REFS_PER_CLAIM) revert ServicesLib.B2BServices__InvalidWork(refs.length);

        uint256 units =
            ServicesLogic.verifyWork(agreementId, a, workBilled, index, refs, checkpointIndexes, claimedUnits, _deps());
        if (units == 0) revert ServicesLib.B2BServices__NothingToBill();
        uint128 billed = uint128(Math.min(units, a.service.maxUnitsPerJob));
        uint256 amount = ServicesLib.priceOf(a.service.kind, billed, a.service.ratePerUnit);
        if (escrowed && amount > j.funded) amount = j.funded;

        j.status = ServicesLib.JobStatus.Claimed;
        j.claimedAt = uint64(block.timestamp);
        j.units = billed;
        j.amount = amount;
        j.evidenceHash = evidenceHash;
        if (escrowed) a.progress.funded -= 1;
        a.progress.inFlight += 1;
        emit ServicesLib.JobClaimed(agreementId, index, refs, billed, amount, evidenceHash);
    }

    /**
     * @notice The client accepts a claim: the provider is paid and the unused budget returns to the client.
     * @dev The client side, while the job is claimed.
     * @param agreementId Agreement id.
     * @param index Job index.
     * @custom:emits JobAccepted
     */
    function acceptJob(uint256 agreementId, uint256 index) external nonReentrant {
        ServicesLib.Agreement storage a = _requireStatus(agreementId, B2BLib.AgreementStatus.Active);
        _requireSide(agreementId, a, B2BLib.other(a.service.provider));
        ServicesLib.Job storage j = _job(agreementId, a, index);
        _requireJobStatus(index, j, ServicesLib.JobStatus.Claimed);
        _pay(agreementId, a, index, j, j.amount, false, address(0), bytes32(0));
    }

    /**
     * @notice Releases a claim the client neither accepted nor disputed within the review period.
     * @dev Callable by anyone.
     * @param agreementId Agreement id.
     * @param index Job index.
     * @custom:emits JobAccepted
     */
    function releaseAfterReview(uint256 agreementId, uint256 index) external nonReentrant {
        ServicesLib.Agreement storage a = _requireStatus(agreementId, B2BLib.AgreementStatus.Active);
        ServicesLib.Job storage j = _job(agreementId, a, index);
        _requireJobStatus(index, j, ServicesLib.JobStatus.Claimed);
        uint64 reviewEnds = j.claimedAt + a.reviewPeriod;
        if (block.timestamp <= reviewEnds) revert B2BLib.B2B__ReviewPeriodOpen(index, reviewEnds);
        _pay(agreementId, a, index, j, j.amount, true, address(0), bytes32(0));
    }

    /**
     * @notice The client disputes a claim, opening a dispute.
     * @dev The client side, within the review period.
     * @param agreementId Agreement id.
     * @param index Job index.
     * @param reasonHash Hash of the reasons (work not done, poor quality, overbilling...).
     * @custom:emits JobDisputed
     */
    function disputeJob(uint256 agreementId, uint256 index, bytes32 reasonHash) external {
        ServicesLib.Agreement storage a = _requireStatus(agreementId, B2BLib.AgreementStatus.Active);
        _requireSide(agreementId, a, B2BLib.other(a.service.provider));
        ServicesLib.Job storage j = _job(agreementId, a, index);
        _requireJobStatus(index, j, ServicesLib.JobStatus.Claimed);
        if (block.timestamp > uint256(j.claimedAt) + a.reviewPeriod) revert B2BLib.B2B__ReviewPeriodOver(index);
        j.status = ServicesLib.JobStatus.Disputed;
        B2BLib.DeliveryDispute storage d = _disputes[agreementId][index];
        d.openedAt = uint64(block.timestamp);
        d.reasonHash = reasonHash;
        emit ServicesLib.JobDisputed(agreementId, index, reasonHash);
    }

    /**
     * @notice Makes a settlement offer on a disputed job: the amount this side accepts the provider receiving.
     * The dispute settles as soon as the client offers at least what the provider asks, at the provider's ask.
     * @dev Either party, at any time until settled. The amount is at most the billed amount.
     * @param agreementId Agreement id.
     * @param index Disputed job.
     * @param amount Amount for the provider.
     * @custom:emits SettlementOffered
     * @custom:emits JobSettled (when the offers meet)
     */
    function offerSettlement(uint256 agreementId, uint256 index, uint256 amount) external nonReentrant {
        ServicesLib.Agreement storage a = _requireStatus(agreementId, B2BLib.AgreementStatus.Active);
        B2BLib.Side side = _sideOf(agreementId, a, msg.sender);
        ServicesLib.Job storage j = _job(agreementId, a, index);
        _requireJobStatus(index, j, ServicesLib.JobStatus.Disputed);
        if (amount > j.amount) revert B2BLib.B2B__InvalidSettlement(amount, j.amount);

        B2BLib.DeliveryDispute storage d = _disputes[agreementId][index];
        if (side == a.service.provider) {
            d.payeeOffered = true;
            d.payeeOffer = amount;
        } else {
            d.payerOffered = true;
            d.payerOffer = amount;
        }
        emit B2BLib.SettlementOffered(agreementId, index, side, amount);
        if (d.payerOffered && d.payeeOffered && d.payerOffer >= d.payeeOffer) {
            _pay(agreementId, a, index, j, d.payeeOffer, false, address(0), bytes32(0));
        }
    }

    /**
     * @notice The arbiter named in the agreement decides a dispute the parties could not settle.
     * @dev The agreement's arbiter, after {NEGOTIATION_PERIOD} from the dispute. When no arbiter was agreed, or the
     * arbiter has not ruled within {B2BLib.ARBITRATION_PERIOD} after that, the platform (a registry admin) decides
     * instead, so a dispute can never lock the escrow forever.
     * @param agreementId Agreement id.
     * @param index Disputed job.
     * @param amount Amount awarded to the provider; at most the billed amount.
     * @param awardHash Hash of the arbitral award.
     * @custom:emits JobSettled
     */
    function arbitrate(uint256 agreementId, uint256 index, uint256 amount, bytes32 awardHash) external nonReentrant {
        ServicesLib.Agreement storage a = _requireStatus(agreementId, B2BLib.AgreementStatus.Active);
        ServicesLib.Job storage j = _job(agreementId, a, index);
        _requireJobStatus(index, j, ServicesLib.JobStatus.Disputed);
        ServicesLogic.requireArbiter(a.arbiter, _disputes[agreementId][index].openedAt, NEGOTIATION_PERIOD, registry);
        if (amount > j.amount) revert B2BLib.B2B__InvalidSettlement(amount, j.amount);
        _pay(agreementId, a, index, j, amount, false, msg.sender, awardHash);
    }

    /**
     * @notice Closes a job the provider did not perform; any budget is refunded to the client.
     * @dev The provider side may give up a scheduled or funded job at any time. The client side may close a
     * funded (or, when paid off-chain, scheduled) job once {MISSED_GRACE} has passed since its due date. Counts
     * as a miss in the provider's track record.
     * @param agreementId Agreement id.
     * @param index Job index.
     * @custom:emits JobClosed
     */
    function closeMissed(uint256 agreementId, uint256 index) external nonReentrant {
        ServicesLib.Agreement storage a = _requireStatus(agreementId, B2BLib.AgreementStatus.Active);
        B2BLib.Side side = _sideOf(agreementId, a, msg.sender);
        ServicesLib.Job storage j = _job(agreementId, a, index);
        ServicesLib.JobStatus s = j.status;
        bool closable = s == ServicesLib.JobStatus.Funded
            || (s == ServicesLib.JobStatus.Scheduled
                && (side == a.service.provider || address(a.paymentToken) == address(0)));
        if (!closable) revert ServicesLib.B2BServices__InvalidJobStatus(index, s);
        if (side != a.service.provider) {
            uint64 availableAt = dueAt(agreementId, index) + MISSED_GRACE;
            if (block.timestamp <= availableAt) revert B2BLib.B2B__TooEarly(index, availableAt);
        }

        if (s == ServicesLib.JobStatus.Funded) a.progress.funded -= 1;
        uint256 refund = j.funded;
        j.status = ServicesLib.JobStatus.Missed;
        a.progress.missed += 1;
        _performance[_party(a, a.service.provider).orgId].jobsMissed += 1;
        _credit(a, _party(a, B2BLib.other(a.service.provider)).account, refund);
        emit ServicesLib.JobClosed(agreementId, index, ServicesLib.JobStatus.Missed, refund);
        _completeIfDone(agreementId, a);
    }

    /**
     * @notice Marks a job the client did not fund by its due date as a client default.
     * @dev The provider side, on an escrowed agreement, once the due date has passed.
     * @param agreementId Agreement id.
     * @param index Unfunded job.
     * @custom:emits JobClosed
     */
    function markDefaulted(uint256 agreementId, uint256 index) external {
        ServicesLib.Agreement storage a = _requireStatus(agreementId, B2BLib.AgreementStatus.Active);
        if (address(a.paymentToken) == address(0)) revert B2BLib.B2B__NotEscrowed();
        _requireSide(agreementId, a, a.service.provider);
        ServicesLib.Job storage j = _job(agreementId, a, index);
        _requireJobStatus(index, j, ServicesLib.JobStatus.Scheduled);
        uint64 due = dueAt(agreementId, index);
        if (block.timestamp <= due) revert B2BLib.B2B__TooEarly(index, due);

        j.status = ServicesLib.JobStatus.Defaulted;
        a.progress.defaulted += 1;
        _performance[_party(a, B2BLib.other(a.service.provider)).orgId].fundingDefaults += 1;
        emit ServicesLib.JobClosed(agreementId, index, ServicesLib.JobStatus.Defaulted, 0);
        _completeIfDone(agreementId, a);
    }

    /*//////////////////////////////////////////////////////////////
                               TERMINATION
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Requests to end an Active agreement early by mutual consent.
     * @dev Either party, with `ENTER_AGREEMENT`, when no request is pending.
     * @param agreementId Agreement id.
     * @param reasonHash Hash of the reason.
     * @custom:emits TerminationRequested
     */
    function requestTermination(uint256 agreementId, bytes32 reasonHash) external {
        ServicesLib.Agreement storage a = _requireStatus(agreementId, B2BLib.AgreementStatus.Active);
        B2BLib.Side side = _authorizedSide(agreementId, a);
        if (a.terminationRequested) revert B2BLib.B2B__InvalidTermination(agreementId);
        a.terminationRequested = true;
        a.terminationRequestedBy = side;
        emit B2BLib.TerminationRequested(agreementId, side, reasonHash);
    }

    /**
     * @notice Confirms the other party's termination request; the agreement ends.
     * @dev The party that did not request it, with `ENTER_AGREEMENT`. No job may be claimed or disputed; funded
     * jobs are refunded and the rest cancelled.
     * @param agreementId Agreement id.
     * @custom:emits JobClosed (per refunded job)
     * @custom:emits AgreementClosed
     */
    function confirmTermination(uint256 agreementId) external nonReentrant {
        ServicesLib.Agreement storage a = _requireStatus(agreementId, B2BLib.AgreementStatus.Active);
        B2BLib.Side side = _authorizedSide(agreementId, a);
        if (!a.terminationRequested || a.terminationRequestedBy == side) {
            revert B2BLib.B2B__InvalidTermination(agreementId);
        }
        _terminate(agreementId, a, false);
    }

    /**
     * @notice Withdraws one's own pending termination request.
     * @dev The requesting party.
     * @param agreementId Agreement id.
     * @custom:emits TerminationRequestWithdrawn
     */
    function withdrawTerminationRequest(uint256 agreementId) external {
        ServicesLib.Agreement storage a = _requireStatus(agreementId, B2BLib.AgreementStatus.Active);
        B2BLib.Side side = _sideOf(agreementId, a, msg.sender);
        if (!a.terminationRequested || a.terminationRequestedBy != side) {
            revert B2BLib.B2B__InvalidTermination(agreementId);
        }
        a.terminationRequested = false;
        emit B2BLib.TerminationRequestWithdrawn(agreementId);
    }

    /**
     * @notice Ends an agreement unilaterally after the other party repeatedly failed it: the client once the
     * provider has missed `maxMissed` jobs, the provider once the client has failed to fund `maxMissed`.
     * @dev Either party, with `ENTER_AGREEMENT`, when the agreement sets `maxMissed`. No job may be in flight.
     * @param agreementId Agreement id.
     * @param reasonHash Hash of the notice of termination.
     * @custom:emits TerminationRequested
     * @custom:emits AgreementClosed
     */
    function terminateForCause(uint256 agreementId, bytes32 reasonHash) external nonReentrant {
        ServicesLib.Agreement storage a = _requireStatus(agreementId, B2BLib.AgreementStatus.Active);
        B2BLib.Side side = _authorizedSide(agreementId, a);
        uint32 count = side == a.service.provider ? a.progress.defaulted : a.progress.missed;
        if (a.maxMissed == 0 || count < a.maxMissed) revert B2BLib.B2B__NoCause(count, a.maxMissed);
        emit B2BLib.TerminationRequested(agreementId, side, reasonHash);
        _terminate(agreementId, a, true);
    }

    /**
     * @notice Withdraws the caller's credited balance of `token`.
     * @param token Settlement token.
     * @custom:emits Withdrawn
     */
    function withdraw(IERC20 token) external nonReentrant {
        uint256 amount = claimable[token][msg.sender];
        if (amount == 0) revert B2BLib.B2B__NothingToWithdraw();
        claimable[token][msg.sender] = 0;
        token.safeTransfer(msg.sender, amount);
        emit B2BLib.Withdrawn(token, msg.sender, amount);
    }

    /*//////////////////////////////////////////////////////////////
                                  VIEWS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns an agreement.
     * @param agreementId Agreement id.
     * @return The agreement (status `None` if unknown).
     */
    function getAgreement(uint256 agreementId) external view returns (ServicesLib.Agreement memory) {
        return _agreements[agreementId];
    }

    /**
     * @notice Returns one job.
     * @dev Jobs left scheduled when an agreement was terminated are reported as `Cancelled`.
     * @param agreementId Agreement id.
     * @param index Job index.
     * @return j The job.
     */
    function getJob(uint256 agreementId, uint256 index) external view returns (ServicesLib.Job memory j) {
        ServicesLib.Agreement storage a = _agreements[agreementId];
        j = _job(agreementId, a, index);
        if (a.status == B2BLib.AgreementStatus.Terminated && j.status == ServicesLib.JobStatus.Scheduled) {
            j.status = ServicesLib.JobStatus.Cancelled;
        }
    }

    /**
     * @notice Due date of a job: `activatedAt + firstJobOffset + index x jobInterval` (0 before activation). For
     * storage it is the end of the billing period.
     * @param agreementId Agreement id.
     * @param index Job index.
     * @return The due date.
     */
    function dueAt(uint256 agreementId, uint256 index) public view returns (uint64) {
        ServicesLib.Agreement storage a = _agreements[agreementId];
        if (a.activatedAt == 0) return 0;
        return uint64(a.activatedAt + uint256(a.service.firstJobOffset) + index * a.service.jobInterval);
    }

    /**
     * @notice The budget a client escrows per job: `maxUnitsPerJob x ratePerUnit`, rounded up.
     * @param agreementId Agreement id.
     * @return The budget.
     */
    function budgetOf(uint256 agreementId) public view returns (uint256) {
        ServicesLib.ServiceTerms storage s = _agreements[agreementId].service;
        uint256 scale = ServicesLib.isWeightBased(s.kind) ? B2BLib.GRAMS_PER_KG : 1;
        return Math.mulDiv(s.maxUnitsPerJob, s.ratePerUnit, scale, Math.Rounding.Ceil);
    }

    /**
     * @notice Returns the dispute over a job.
     * @param agreementId Agreement id.
     * @param index Job index.
     * @return The dispute (all zero if none).
     */
    function getDispute(uint256 agreementId, uint256 index) external view returns (B2BLib.DeliveryDispute memory) {
        return _disputes[agreementId][index];
    }

    /**
     * @notice Returns all agreements an organisation is party to.
     * @param orgId Organisation id.
     * @return Agreement ids, in proposal order.
     */
    function agreementsOf(bytes32 orgId) external view returns (uint256[] memory) {
        return _agreementsOf[orgId];
    }

    /**
     * @notice A company's track record across all its service agreements.
     * @param orgId Organisation id.
     * @return The track record.
     */
    function performanceOf(bytes32 orgId) external view returns (ServicesLib.Performance memory) {
        return _performance[orgId];
    }

    /**
     * @notice Number of agreements ever proposed.
     * @return Total agreement count.
     */
    function totalAgreements() external view returns (uint256) {
        return _nextAgreementId - 1;
    }

    /*//////////////////////////////////////////////////////////////
                           INTERNAL: NEGOTIATION
    //////////////////////////////////////////////////////////////*/

    /*//////////////////////////////////////////////////////////////
                         INTERNAL: WORK VERIFICATION
    //////////////////////////////////////////////////////////////*/

    /*//////////////////////////////////////////////////////////////
                            INTERNAL: PAYMENT
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Closes a claimed or disputed job: `amount` to the provider, the rest of the budget to the client.
     * @param agreementId Agreement id.
     * @param a The agreement.
     * @param index Job index.
     * @param j The job.
     * @param amount Amount for the provider.
     * @param automatic Whether released after the review period (claimed jobs only).
     * @param arbiter Deciding arbiter (disputes only; zero when the parties agreed).
     * @param awardHash Hash of the award (disputes only).
     */
    function _pay(
        uint256 agreementId,
        ServicesLib.Agreement storage a,
        uint256 index,
        ServicesLib.Job storage j,
        uint256 amount,
        bool automatic,
        address arbiter,
        bytes32 awardHash
    ) private {
        bool disputed = j.status == ServicesLib.JobStatus.Disputed;
        uint256 refund = address(a.paymentToken) == address(0) ? 0 : j.funded - amount;
        ServicesLib.Performance storage p = _performance[_party(a, a.service.provider).orgId];
        if (amount != 0) {
            p.jobsCompleted += 1;
            p.unitsDelivered += j.units;
            a.progress.unitsBilled += j.units;
        }
        a.progress.inFlight -= 1;
        if (disputed) {
            j.status = ServicesLib.JobStatus.Settled;
            a.progress.settled += 1;
            if (amount < j.amount) p.disputesLost += 1;
        } else {
            j.status = ServicesLib.JobStatus.Accepted;
            a.progress.accepted += 1;
        }
        _credit(a, _party(a, a.service.provider).account, amount);
        _credit(a, _party(a, B2BLib.other(a.service.provider)).account, refund);
        if (disputed) emit ServicesLib.JobSettled(agreementId, index, amount, refund, arbiter, awardHash);
        else emit ServicesLib.JobAccepted(agreementId, index, amount, refund, automatic);
        _completeIfDone(agreementId, a);
    }

    /**
     * @dev Credits `amount` of the agreement's token to `account`'s payout account (its company's, if the admin set
     * one: {MineNetRegistry-payoutOf}). No-op for off-chain agreements and zero amounts.
     * @param a The agreement.
     * @param account Account to credit.
     * @param amount Amount.
     */
    function _credit(ServicesLib.Agreement storage a, address account, uint256 amount) private {
        if (amount == 0 || address(a.paymentToken) == address(0)) return;
        claimable[a.paymentToken][registry.payoutOf(account)] += amount;
    }

    /*//////////////////////////////////////////////////////////////
                            INTERNAL: CLOSING
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Ends an agreement early: refunds funded jobs and cancels the rest. No job may be in flight.
     * @param agreementId Agreement id.
     * @param a The agreement.
     * @param forCause Whether it is a termination for cause.
     */
    function _terminate(uint256 agreementId, ServicesLib.Agreement storage a, bool forCause) private {
        ServicesLib.Progress storage p = a.progress;
        if (p.inFlight != 0) revert B2BLib.B2B__DeliveriesInFlight(p.inFlight);
        uint32 total = a.service.totalJobs;
        if (p.funded != 0) {
            address client = _party(a, B2BLib.other(a.service.provider)).account;
            for (uint256 i; i < total; ++i) {
                ServicesLib.Job storage j = _jobs[agreementId][i];
                if (j.status != ServicesLib.JobStatus.Funded) continue;
                _credit(a, client, j.funded);
                j.status = ServicesLib.JobStatus.Cancelled;
                emit ServicesLib.JobClosed(agreementId, i, ServicesLib.JobStatus.Cancelled, j.funded);
            }
            p.funded = 0;
        }
        p.cancelled = total - (p.accepted + p.settled + p.missed + p.defaulted);
        a.status = B2BLib.AgreementStatus.Terminated;
        a.terminationRequested = false;
        emit B2BLib.AgreementClosed(agreementId, a.status, forCause);
    }

    /**
     * @dev Completes an Active agreement once every job is resolved.
     * @param agreementId Agreement id.
     * @param a The agreement.
     */
    function _completeIfDone(uint256 agreementId, ServicesLib.Agreement storage a) private {
        ServicesLib.Progress storage p = a.progress;
        if (p.accepted + p.settled + p.missed + p.defaulted + p.cancelled < a.service.totalJobs) return;
        a.status = B2BLib.AgreementStatus.Completed;
        emit B2BLib.AgreementClosed(agreementId, a.status, false);
    }

    /*//////////////////////////////////////////////////////////////
                            INTERNAL: ACCESS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Returns an agreement in `expected` status, reverting otherwise.
     * @param agreementId Agreement id.
     * @param expected Required status.
     * @return a Storage pointer to the agreement.
     */
    function _requireStatus(uint256 agreementId, B2BLib.AgreementStatus expected)
        private
        view
        returns (ServicesLib.Agreement storage a)
    {
        a = _agreements[agreementId];
        if (a.status == B2BLib.AgreementStatus.None) revert B2BLib.B2B__UnknownAgreement(agreementId);
        if (a.status != expected) revert B2BLib.B2B__InvalidStatus(agreementId, a.status);
    }

    /**
     * @dev Returns a job, reverting if the index is beyond the schedule.
     * @param agreementId Agreement id.
     * @param a The agreement.
     * @param index Job index.
     * @return Storage pointer to the job.
     */
    function _job(uint256 agreementId, ServicesLib.Agreement storage a, uint256 index)
        private
        view
        returns (ServicesLib.Job storage)
    {
        if (index >= a.service.totalJobs) revert B2BLib.B2B__UnknownDelivery(agreementId, index);
        return _jobs[agreementId][index];
    }

    /**
     * @dev Reverts unless the job is in `expected` status.
     * @param index Job index (for the error).
     * @param j The job.
     * @param expected Required status.
     */
    function _requireJobStatus(uint256 index, ServicesLib.Job storage j, ServicesLib.JobStatus expected) private view {
        if (j.status != expected) revert ServicesLib.B2BServices__InvalidJobStatus(index, j.status);
    }

    /**
     * @dev The side `account` acts for, by organisation. The account must itself be authorised to enter agreements
     * (in good standing, licensed, with a trading role): any other employee of the company cannot act for it.
     * @param agreementId Agreement id (for the error).
     * @param a The agreement.
     * @param account The account.
     * @return The side.
     */
    function _sideOf(uint256 agreementId, ServicesLib.Agreement storage a, address account)
        private
        view
        returns (B2BLib.Side)
    {
        bytes32 orgId = _orgOf(account);
        if (orgId != bytes32(0) && registry.isAuthorized(account, Actions.ENTER_AGREEMENT)) {
            if (orgId == a.proposer.orgId) return B2BLib.Side.Proposer;
            if (orgId == a.counterparty.orgId) return B2BLib.Side.Counterparty;
        }
        revert B2BLib.B2B__NotParty(agreementId, account);
    }

    /**
     * @dev The side the caller acts for, also requiring `ENTER_AGREEMENT`.
     * @param agreementId Agreement id.
     * @param a The agreement.
     * @return The side.
     */
    function _authorizedSide(uint256 agreementId, ServicesLib.Agreement storage a) private view returns (B2BLib.Side) {
        _authorizedOrg(msg.sender);
        return _sideOf(agreementId, a, msg.sender);
    }

    /**
     * @dev Reverts unless the caller acts for `side`.
     * @param agreementId Agreement id.
     * @param a The agreement.
     * @param side Required side.
     */
    function _requireSide(uint256 agreementId, ServicesLib.Agreement storage a, B2BLib.Side side) private view {
        if (_sideOf(agreementId, a, msg.sender) != side) revert B2BLib.B2B__WrongSide(agreementId, msg.sender);
    }

    /**
     * @dev The organisation of an account authorised for `ENTER_AGREEMENT`, reverting otherwise.
     * @param account The account.
     * @return orgId Its organisation.
     */
    function _authorizedOrg(address account) private view returns (bytes32 orgId) {
        orgId = _orgOf(account);
        if (orgId == bytes32(0) || !registry.isAuthorized(account, Actions.ENTER_AGREEMENT)) {
            revert B2BLib.B2B__NotAuthorized(account);
        }
    }

    /**
     * @dev An account's organisation (zero if not a participant).
     * @param account The account.
     * @return The organisation id.
     */
    function _orgOf(address account) private view returns (bytes32) {
        return registry.participant(account).orgId;
    }

    /**
     * @dev A side's party record.
     * @param a The agreement.
     * @param side The side.
     * @return Storage pointer to the party.
     */
    function _party(ServicesLib.Agreement storage a, B2BLib.Side side) private view returns (B2BLib.Party storage) {
        return side == B2BLib.Side.Proposer ? a.proposer : a.counterparty;
    }

    /**
     * @dev The contracts {ServicesLogic} reads from.
     * @return The dependencies.
     */
    function _deps() private view returns (ServicesLogic.Deps memory) {
        return ServicesLogic.Deps({
            registry: registry, passport: passport, supplyChain: supplyChain, deliveryManager: deliveryManager
        });
    }

    /**
     * @dev Reverts unless the caller is a {MineNetRegistry} admin.
     */
    function _onlyAdmin() private view {
        if (!registry.isAdmin(msg.sender)) {
            revert B2BLib.B2B__NotRegistryAdmin(msg.sender);
        }
    }
}
