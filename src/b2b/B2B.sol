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
import {IB2B} from "src/b2b/interfaces/IB2B.sol";
import {B2BLib} from "src/b2b/libraries/B2BLib.sol";
import {B2BLogic} from "src/b2b/libraries/B2BLogic.sol";

/**
 * @title B2B
 * @author 0xEmmyb2
 * @notice Recurring mineral supply agreements between MineNet companies: a miner supplying a refinery, a
 * processor supplying a smelter, a trader buying from a cooperative, with an optional named transporter and an
 * independent destination inspection. Every delivery is filled with traceable lot passports, weighed by the supply-chain ledger, and
 * paid for the kilograms actually delivered.
 * @dev ## Negotiation
 * A company (`ENTER_AGREEMENT`) proposes terms to another company: who sells, the mineral, the quantity per
 * delivery, the number of deliveries and the interval between them, the price per kilogram, the quantity
 * tolerance and minimum grade, the review period, and optionally a transporter (paid per delivery,
 * `distanceKm x feePerKm`), whether a destination inspection is required, and a neutral arbiter. Proposing signs version 1. Either party can
 * amend (a counter-offer, new version). The agreement becomes Active once both parties have signed, and a
 * named transporter has accepted, the same version before the deadline. The seller must be able to sell lots
 * (`SELL_LOT`) and the buyer to own them (`OWN_LOT`); the transporter and arbiter must be neutral.
 *
 * ## Schedule
 * Delivery `i` is due `firstDeliveryOffset + i x deliveryInterval` after activation, for `quantityPerDelivery`
 * grams at `pricePerKg`. Deliveries are stored lazily, so a long schedule costs nothing up front. Before a
 * delivery is funded, either party can request a one-off change to its quantity, price or due date, which the
 * other confirms.
 *
 * ## One delivery
 * 1. Funding (escrowed agreements): the buyer escrows the goods price at the upper quantity tolerance plus the
 *    transport fee. A buyer who has not funded a delivery by its due date can be marked in default.
 * 2. Dispatch: the seller commits lot passports of the agreed mineral that passed inspection, are not frozen
 *    or locked, meet the minimum grade, and whose trusted weights ({SupplyChain-lastWeight}) add up to the
 *    quantity within tolerance. The seller approves this contract on the passport so title can pass on
 *    payment. With a named transporter the lots must travel in a {DeliveryManager} shipment it carries to
 *    the buyer, which checks weights and seals at both handovers.
 * 3. Arrival: once the buyer's organisation holds custody of every lot (and the shipment is delivered), the
 *    review period starts.
 * 4. Payment: the buyer accepts, or after the review period anyone releases it. When inspection is
 *    required, automatic release waits for an inspection of every lot by the inspector the platform assigns
 *    ({InspectionRegistry}; the parties never choose the inspector), or {INSPECTION_GRACE}, and never happens for
 *    a flagged lot or one inspected below the minimum grade. On payment the seller receives the price of the
 *    delivered weight, the unused escrow returns to the buyer, the transporter receives its fee, and the
 *    lots' ownership passes to the buyer.
 * 5. Problems: a lot flagged before arrival lets the buyer refuse the delivery at once (the transporter is
 *    paid if it picked the lots up). An arrived delivery can be rejected within the review period (or later if
 *    a lot is flagged or below grade), opening a dispute the parties settle with matching offers, or that the
 *    agreed arbiter decides after {NEGOTIATION_PERIOD}. A delivery not made {REFUND_GRACE} after its due date
 *    is refunded as missed; the seller may also give one up early.
 *
 * ## Ending
 * The agreement completes when every delivery is resolved. It can be terminated by mutual consent, or for
 * cause by one party once the other has missed (or failed to fund) `maxMissed` deliveries; funded deliveries
 * not yet dispatched are refunded. Every company builds an on-chain track record ({performanceOf}): deliveries
 * made, on time, missed, rejected, funding defaults and disputes lost.
 *
 * Payouts use the pull pattern ({withdraw}). Pausing stops new business (proposals, signatures, funding,
 * dispatch, adjustments) but never payments, refunds, disputes or termination. Only document hashes are
 * stored.
 */
contract B2B is ReentrancyGuardTransient, Pausable, IB2B {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Maximum number of deliveries in one agreement (e.g. daily for a year, weekly for seven years).
     */
    uint32 public constant MAX_DELIVERIES = B2BLogic.MAX_DELIVERIES;

    /**
     * @notice Maximum number of lot passports in one delivery.
     */
    uint256 public constant MAX_LOTS_PER_DELIVERY = 50;

    /**
     * @notice Shortest interval between two deliveries.
     */
    uint32 public constant MIN_DELIVERY_INTERVAL = B2BLogic.MIN_DELIVERY_INTERVAL;

    /**
     * @notice Longest interval between two deliveries.
     */
    uint32 public constant MAX_DELIVERY_INTERVAL = B2BLogic.MAX_DELIVERY_INTERVAL;

    /**
     * @notice Longest time from activation to the first delivery.
     */
    uint32 public constant MAX_FIRST_DELIVERY_OFFSET = B2BLogic.MAX_FIRST_DELIVERY_OFFSET;

    /**
     * @notice Largest quantity tolerance (20%), in basis points.
     */
    uint16 public constant MAX_QUANTITY_TOLERANCE_BPS = B2BLogic.MAX_QUANTITY_TOLERANCE_BPS;

    /**
     * @notice Shortest review period a buyer may be given.
     */
    uint32 public constant MIN_REVIEW_PERIOD = B2BLogic.MIN_REVIEW_PERIOD;

    /**
     * @notice Longest review period a buyer may be given.
     */
    uint32 public constant MAX_REVIEW_PERIOD = B2BLogic.MAX_REVIEW_PERIOD;

    /**
     * @notice Longest time a proposal may stay open for signature.
     */
    uint64 public constant MAX_PROPOSAL_DURATION = B2BLogic.MAX_PROPOSAL_DURATION;

    /**
     * @notice Time the parties have to settle a dispute themselves before the arbiter may decide.
     */
    uint64 public constant NEGOTIATION_PERIOD = 14 days;

    /**
     * @notice Time after a delivery's due date before the buyer may close it as missed and be refunded.
     */
    uint64 public constant REFUND_GRACE = 30 days;

    /**
     * @notice Time after arrival an automatic release waits for the destination inspection.
     */
    uint64 public constant INSPECTION_GRACE = B2BLogic.INSPECTION_GRACE;

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
     * @notice Lot passports that fill deliveries and whose title passes on payment.
     */
    ILotPassport public immutable passport;

    /**
     * @notice Supply-chain ledger: trusted weights, grades and inspections.
     */
    ISupplyChain public immutable supplyChain;

    /**
     * @notice Shipments that carry the lots.
     */
    IDeliveryManager public immutable deliveryManager;

    /**
     * @dev Next agreement id; ids start at 1 so that 0 means "none".
     */
    uint256 private _nextAgreementId = 1;

    /**
     * @dev Agreement id => agreement.
     */
    mapping(uint256 agreementId => B2BLib.Agreement) private _agreements;

    /**
     * @dev Agreement id => delivery index => delivery (lazily stored).
     */
    mapping(uint256 agreementId => mapping(uint256 index => B2BLib.Delivery)) private _deliveries;

    /**
     * @dev Agreement id => delivery index => lot passports committed to it.
     */
    mapping(uint256 agreementId => mapping(uint256 index => uint256[])) private _lots;

    /**
     * @dev Agreement id => delivery index => pending adjustment.
     */
    mapping(uint256 agreementId => mapping(uint256 index => B2BLib.Adjustment)) private _adjustments;

    /**
     * @dev Agreement id => delivery index => dispute.
     */
    mapping(uint256 agreementId => mapping(uint256 index => B2BLib.DeliveryDispute)) private _disputes;

    /**
     * @dev Organisation => agreements it is party to, in proposal order.
     */
    mapping(bytes32 orgId => uint256[]) private _agreementsOf;

    /**
     * @dev Organisation => B2B track record.
     */
    mapping(bytes32 orgId => B2BLib.Performance) private _performance;

    /**
     * @notice Whether a lot is committed to an open delivery (a lot fills one delivery at a time).
     */
    mapping(uint256 tokenId => bool) public lotCommitted;

    /**
     * @notice Balances owed to sellers, buyers and transporters (pull pattern).
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
     * @notice Pauses new business: proposals, signatures, funding, dispatch and adjustments.
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
     * @notice Proposes a supply agreement to another company. Proposing signs the first version.
     * @dev The caller and `counterparty` need `ENTER_AGREEMENT` and must belong to different organisations.
     * @param counterparty An account of the company the agreement is proposed to.
     * @param terms The proposed terms.
     * @return agreementId New agreement id.
     * @custom:emits AgreementProposed
     * @custom:emits AgreementSigned
     */
    function propose(address counterparty, B2BLib.Terms calldata terms)
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
        B2BLib.Agreement storage a = _agreements[agreementId];
        a.status = B2BLib.AgreementStatus.Proposed;
        a.proposer = B2BLib.Party({orgId: proposerOrg, account: msg.sender});
        a.counterparty = B2BLib.Party({orgId: counterpartyOrg, account: counterparty});
        B2BLogic.setTerms(a, terms, registry, currencies);
        a.proposerSigned = true;
        _agreementsOf[proposerOrg].push(agreementId);
        _agreementsOf[counterpartyOrg].push(agreementId);

        emit B2BLib.AgreementProposed(
            agreementId, proposerOrg, counterpartyOrg, terms.seller, terms.supply, terms.termsHash
        );
        emit B2BLib.AgreementSigned(agreementId, a.version, B2BLib.Side.Proposer, msg.sender);
    }

    /**
     * @notice Amends a proposal (a counter-offer). The new version is signed by the amending party only; the
     * other party and a named transporter must sign or accept it again.
     * @dev Either party, with `ENTER_AGREEMENT`, while the agreement is a proposal. The caller becomes its
     * side's account of record.
     * @param agreementId Agreement id.
     * @param terms The amended terms.
     * @custom:emits AgreementAmended
     * @custom:emits AgreementSigned
     */
    function amend(uint256 agreementId, B2BLib.Terms calldata terms) external whenNotPaused {
        B2BLib.Agreement storage a = _requireStatus(agreementId, B2BLib.AgreementStatus.Proposed);
        B2BLib.Side side = _authorizedSide(agreementId, a);
        _party(a, side).account = msg.sender;
        B2BLogic.setTerms(a, terms, registry, currencies);
        if (side == B2BLib.Side.Proposer) a.proposerSigned = true;
        else a.counterpartySigned = true;

        emit B2BLib.AgreementAmended(agreementId, a.version, msg.sender, terms.supply, terms.termsHash);
        emit B2BLib.AgreementSigned(agreementId, a.version, side, msg.sender);
    }

    /**
     * @notice Signs the current version of a proposal. The agreement becomes Active once both parties have
     * signed, and a named transporter has accepted, that version.
     * @dev Either party, with `ENTER_AGREEMENT`, before the deadline. The caller becomes its side's account of
     * record and must be able to sell (seller side) or own (buyer side) lots.
     * @param agreementId Agreement id.
     * @param version The version being signed; must be the current one.
     * @custom:emits AgreementSigned
     * @custom:emits AgreementActivated (once every signature is in place)
     */
    function sign(uint256 agreementId, uint32 version) external whenNotPaused {
        B2BLib.Agreement storage a = _requireOpenProposal(agreementId, version);
        B2BLib.Side side = _authorizedSide(agreementId, a);
        B2BLogic.requireTradingRole(a, side, msg.sender, registry);
        _party(a, side).account = msg.sender;
        if (side == B2BLib.Side.Proposer) a.proposerSigned = true;
        else a.counterpartySigned = true;
        emit B2BLib.AgreementSigned(agreementId, version, side, msg.sender);
        _activateIfReady(agreementId, a);
    }

    /**
     * @notice The named transporter accepts to carry the agreement's deliveries for the agreed fee.
     * @dev Only the named transporter, still an authorised carrier, before the deadline.
     * @param agreementId Agreement id.
     * @param version The version being accepted; must be the current one.
     * @custom:emits TransporterAccepted
     * @custom:emits AgreementActivated (once every signature is in place)
     */
    function acceptAsTransporter(uint256 agreementId, uint32 version) external whenNotPaused {
        B2BLib.Agreement storage a = _requireOpenProposal(agreementId, version);
        if (msg.sender != a.transport.transporter || !registry.isAuthorized(msg.sender, Actions.CARRY)) {
            revert B2BLib.B2B__NotTransporter(msg.sender);
        }
        a.transporterAccepted = true;
        emit B2BLib.TransporterAccepted(agreementId, version, msg.sender);
        _activateIfReady(agreementId, a);
    }

    /**
     * @notice The named transporter refuses the agreement, which ends the proposal.
     * @dev Only the named transporter, while the agreement is a proposal.
     * @param agreementId Agreement id.
     * @param reasonHash Hash of the reason.
     * @custom:emits AgreementDeclined
     */
    function declineAsTransporter(uint256 agreementId, bytes32 reasonHash) external {
        B2BLib.Agreement storage a = _requireStatus(agreementId, B2BLib.AgreementStatus.Proposed);
        if (msg.sender != a.transport.transporter) revert B2BLib.B2B__NotTransporter(msg.sender);
        a.status = B2BLib.AgreementStatus.Rejected;
        emit B2BLib.AgreementDeclined(agreementId, a.status, msg.sender, reasonHash);
    }

    /**
     * @notice Ends a proposal: the proposer withdraws it, or the counterparty rejects it.
     * @dev Either party, while the agreement is a proposal.
     * @param agreementId Agreement id.
     * @param reasonHash Hash of the reason.
     * @custom:emits AgreementDeclined
     */
    function decline(uint256 agreementId, bytes32 reasonHash) external {
        B2BLib.Agreement storage a = _requireStatus(agreementId, B2BLib.AgreementStatus.Proposed);
        B2BLib.Side side = _sideOf(agreementId, a, msg.sender);
        a.status = side == B2BLib.Side.Proposer ? B2BLib.AgreementStatus.Withdrawn : B2BLib.AgreementStatus.Rejected;
        emit B2BLib.AgreementDeclined(agreementId, a.status, msg.sender, reasonHash);
    }

    /*//////////////////////////////////////////////////////////////
                         SCHEDULE ADJUSTMENTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Requests a one-off change to the quantity, price and due date of one scheduled delivery (e.g.
     * a smaller shipment during the rainy season, or a renegotiated price).
     * @dev Either party, on an Active agreement, while the delivery is unfunded. Replaces any pending request.
     * @param agreementId Agreement id.
     * @param index Delivery index (0-based).
     * @param quantity New quantity, in grams; non-zero.
     * @param pricePerKg New price per kilogram; non-zero on escrowed agreements.
     * @param dueAt New due date; in the future.
     * @custom:emits AdjustmentRequested
     */
    function requestAdjustment(uint256 agreementId, uint256 index, uint128 quantity, uint256 pricePerKg, uint64 dueAt)
        external
        whenNotPaused
    {
        B2BLib.Agreement storage a = _requireStatus(agreementId, B2BLib.AgreementStatus.Active);
        B2BLib.Side side = _sideOf(agreementId, a, msg.sender);
        _requireDeliveryStatus(index, _delivery(agreementId, a, index), B2BLib.DeliveryStatus.Scheduled);
        if (quantity == 0 || dueAt <= block.timestamp || (address(a.paymentToken) != address(0) && pricePerKg == 0)) {
            revert B2BLib.B2B__InvalidSchedule();
        }
        _adjustments[agreementId][index] =
            B2BLib.Adjustment({pending: true, by: side, dueAt: dueAt, quantity: quantity, pricePerKg: pricePerKg});
        emit B2BLib.AdjustmentRequested(agreementId, index, side, quantity, pricePerKg, dueAt);
    }

    /**
     * @notice Confirms the other party's pending adjustment, which then applies to the delivery.
     * @dev The party that did not request it, while the delivery is unfunded.
     * @param agreementId Agreement id.
     * @param index Delivery index.
     * @custom:emits AdjustmentConfirmed
     */
    function confirmAdjustment(uint256 agreementId, uint256 index) external whenNotPaused {
        B2BLib.Agreement storage a = _requireStatus(agreementId, B2BLib.AgreementStatus.Active);
        B2BLib.Side side = _sideOf(agreementId, a, msg.sender);
        B2BLib.Delivery storage d = _delivery(agreementId, a, index);
        _requireDeliveryStatus(index, d, B2BLib.DeliveryStatus.Scheduled);
        B2BLib.Adjustment memory adj = _adjustments[agreementId][index];
        if (!adj.pending || adj.by == side) revert B2BLib.B2B__InvalidAdjustment(index);

        delete _adjustments[agreementId][index];
        d.adjusted = true;
        d.quantity = adj.quantity;
        d.pricePerKg = adj.pricePerKg;
        d.dueAt = adj.dueAt;
        emit B2BLib.AdjustmentConfirmed(agreementId, index);
    }

    /**
     * @notice Rejects the other party's pending adjustment, or withdraws one's own.
     * @dev Either party.
     * @param agreementId Agreement id.
     * @param index Delivery index.
     * @custom:emits AdjustmentCleared
     */
    function clearAdjustment(uint256 agreementId, uint256 index) external {
        B2BLib.Agreement storage a = _requireStatus(agreementId, B2BLib.AgreementStatus.Active);
        _sideOf(agreementId, a, msg.sender);
        if (!_adjustments[agreementId][index].pending) revert B2BLib.B2B__InvalidAdjustment(index);
        delete _adjustments[agreementId][index];
        emit B2BLib.AdjustmentCleared(agreementId, index, msg.sender);
    }

    /*//////////////////////////////////////////////////////////////
                         DELIVERIES: FUND & DISPATCH
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Escrows the payment of one delivery: the goods price at the upper quantity tolerance plus the
     * transport fee. The tokens are pulled from the caller.
     * @dev The buyer side, on an Active escrowed agreement, while the delivery is scheduled (also after its due
     * date, until it is marked in default). The caller must have approved this contract for {amountDue}. A
     * pending adjustment is discarded: funding fixes the delivery's terms.
     * @param agreementId Agreement id.
     * @param index Delivery index.
     * @custom:emits DeliveryFunded
     */
    function fundDelivery(uint256 agreementId, uint256 index) external nonReentrant whenNotPaused {
        B2BLib.Agreement storage a = _requireStatus(agreementId, B2BLib.AgreementStatus.Active);
        if (address(a.paymentToken) == address(0)) revert B2BLib.B2B__NotEscrowed();
        _requireSide(agreementId, a, B2BLib.other(a.seller));
        B2BLib.Delivery storage d = _delivery(agreementId, a, index);
        _requireDeliveryStatus(index, d, B2BLib.DeliveryStatus.Scheduled);
        _discardAdjustment(agreementId, index);

        (uint256 goods, uint256 fee) = amountDue(agreementId, index);
        d.status = B2BLib.DeliveryStatus.Funded;
        d.goodsFunded = goods;
        d.feeFunded = fee;
        a.progress.funded += 1;
        a.paymentToken.safeTransferFrom(msg.sender, address(this), goods + fee);
        emit B2BLib.DeliveryFunded(agreementId, index, goods, fee);
    }

    /**
     * @notice The seller commits the lot passports that fill a delivery.
     * @dev The seller side, on an Active agreement, once the delivery is funded (or while scheduled when paid
     * off-chain). Every lot must be of the agreed mineral, inspected, not frozen or escrow-locked, owned by the
     * seller's organisation, not committed elsewhere, at or above the minimum grade, and approved for transfer
     * to this contract. Their trusted weights must add up to the delivery's quantity within tolerance. With a
     * named transporter, `shipmentId` must be an open {DeliveryManager} shipment it carries from the seller's
     * to the buyer's organisation containing exactly these lots; without one it is optional (0 = direct custody
     * handover on the passport).
     * @param agreementId Agreement id.
     * @param index Delivery index.
     * @param tokenIds Lot passports filling the delivery (1 to {MAX_LOTS_PER_DELIVERY}).
     * @param shipmentId Shipment carrying them, or 0.
     * @param evidenceHash Hash of the dispatch documents (delivery note, assay, export papers...).
     * @custom:emits DeliveryDispatched
     */
    function dispatchDelivery(
        uint256 agreementId,
        uint256 index,
        uint256[] calldata tokenIds,
        uint256 shipmentId,
        bytes32 evidenceHash
    ) external nonReentrant whenNotPaused {
        B2BLib.Agreement storage a = _requireStatus(agreementId, B2BLib.AgreementStatus.Active);
        _requireSide(agreementId, a, a.seller);
        B2BLib.Delivery storage d = _delivery(agreementId, a, index);
        bool escrowed = address(a.paymentToken) != address(0);
        _requireDeliveryStatus(index, d, escrowed ? B2BLib.DeliveryStatus.Funded : B2BLib.DeliveryStatus.Scheduled);
        if (!escrowed) _discardAdjustment(agreementId, index);
        if (tokenIds.length == 0 || tokenIds.length > MAX_LOTS_PER_DELIVERY) revert B2BLib.B2B__InvalidLots();

        uint128 weight = B2BLogic.commitLots(a, lotCommitted, tokenIds, shipmentId, _deps());
        (uint128 quantity,,) = _effectiveTerms(a, d, index);
        (uint128 min, uint128 max) = B2BLib.bounds(quantity, a.supply.quantityToleranceBps);
        if (weight < min || weight > max) revert B2BLib.B2B__QuantityOutOfTolerance(weight, min, max);

        if (!d.adjusted) _pinDefaults(a, d, index);
        _lots[agreementId][index] = tokenIds;
        d.status = B2BLib.DeliveryStatus.Dispatched;
        d.deliveredQty = weight;
        d.dispatchedAt = uint64(block.timestamp);
        d.shipmentId = shipmentId;
        d.evidenceHash = evidenceHash;
        if (escrowed) a.progress.funded -= 1;
        a.progress.inFlight += 1;
        emit B2BLib.DeliveryDispatched(agreementId, index, tokenIds, weight, shipmentId, evidenceHash);
    }

    /**
     * @notice Records that the buyer's organisation holds custody of every lot of a dispatched delivery (and
     * its shipment is delivered); the buyer's review period starts.
     * @dev Callable by anyone.
     * @param agreementId Agreement id.
     * @param index Delivery index.
     * @custom:emits DeliveryArrived
     */
    function confirmArrival(uint256 agreementId, uint256 index) public {
        B2BLib.Agreement storage a = _requireStatus(agreementId, B2BLib.AgreementStatus.Active);
        B2BLib.Delivery storage d = _delivery(agreementId, a, index);
        _requireDeliveryStatus(index, d, B2BLib.DeliveryStatus.Dispatched);
        if (!B2BLogic.hasArrived(a, _lots[agreementId][index], d.shipmentId, _deps())) {
            revert B2BLib.B2B__NotArrived(index);
        }
        d.status = B2BLib.DeliveryStatus.Arrived;
        d.arrivedAt = uint64(block.timestamp);
        d.onTime = d.arrivedAt <= d.dueAt;
        emit B2BLib.DeliveryArrived(agreementId, index, d.onTime);
    }

    /*//////////////////////////////////////////////////////////////
                           DELIVERIES: PAYMENT
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice The buyer accepts a delivery: the seller is paid for the delivered weight, the transporter its
     * fee, the unused escrow returns to the buyer, and the lots' ownership passes to the buyer.
     * @dev The buyer side, once the delivery has arrived (arrival is confirmed here if needed). Accepting
     * waives the destination inspection.
     * @param agreementId Agreement id.
     * @param index Delivery index.
     * @custom:emits DeliveryArrived (if not yet confirmed)
     * @custom:emits DeliveryAccepted
     */
    function acceptDelivery(uint256 agreementId, uint256 index) external nonReentrant {
        B2BLib.Agreement storage a = _requireStatus(agreementId, B2BLib.AgreementStatus.Active);
        _requireSide(agreementId, a, B2BLib.other(a.seller));
        B2BLib.Delivery storage d = _delivery(agreementId, a, index);
        if (d.status == B2BLib.DeliveryStatus.Dispatched) confirmArrival(agreementId, index);
        _requireDeliveryStatus(index, d, B2BLib.DeliveryStatus.Arrived);
        _accept(agreementId, a, index, d, false);
    }

    /**
     * @notice Releases an arrived delivery the buyer neither accepted nor rejected within the review period.
     * @dev Callable by anyone. When inspection is required, every lot must have been inspected since dispatch by
     * an independent, platform-assigned inspector at or above the minimum grade, or {INSPECTION_GRACE} must have
     * passed since arrival. Never releases a
     * flagged lot.
     * @param agreementId Agreement id.
     * @param index Delivery index.
     * @custom:emits DeliveryAccepted
     */
    function releaseAfterReview(uint256 agreementId, uint256 index) external nonReentrant {
        B2BLib.Agreement storage a = _requireStatus(agreementId, B2BLib.AgreementStatus.Active);
        B2BLib.Delivery storage d = _delivery(agreementId, a, index);
        _requireDeliveryStatus(index, d, B2BLib.DeliveryStatus.Arrived);
        uint64 reviewEnds = d.arrivedAt + a.reviewPeriod;
        if (block.timestamp <= reviewEnds) revert B2BLib.B2B__ReviewPeriodOpen(index, reviewEnds);
        B2BLogic.requireCleared(a, _lots[agreementId][index], index, d, _deps());
        _accept(agreementId, a, index, d, true);
    }

    /**
     * @notice The buyer rejects an arrived delivery, opening a dispute.
     * @dev The buyer side, within the review period, or later while a lot is flagged or was inspected below the
     * minimum grade by an independent inspector.
     * @param agreementId Agreement id.
     * @param index Delivery index.
     * @param reasonHash Hash of the reasons (short weight, low grade, contamination...).
     * @custom:emits DeliveryDisputed
     */
    function rejectDelivery(uint256 agreementId, uint256 index, bytes32 reasonHash) external {
        B2BLib.Agreement storage a = _requireStatus(agreementId, B2BLib.AgreementStatus.Active);
        _requireSide(agreementId, a, B2BLib.other(a.seller));
        B2BLib.Delivery storage d = _delivery(agreementId, a, index);
        _requireDeliveryStatus(index, d, B2BLib.DeliveryStatus.Arrived);
        if (
            block.timestamp > uint256(d.arrivedAt) + a.reviewPeriod
                && !B2BLogic.hasProblem(a, _lots[agreementId][index], d.dispatchedAt, _deps())
        ) {
            revert B2BLib.B2B__ReviewPeriodOver(index);
        }
        d.status = B2BLib.DeliveryStatus.Disputed;
        B2BLib.DeliveryDispute storage disp = _disputes[agreementId][index];
        disp.openedAt = uint64(block.timestamp);
        disp.reasonHash = reasonHash;
        emit B2BLib.DeliveryDisputed(agreementId, index, msg.sender, reasonHash);
    }

    /**
     * @notice The buyer refuses a dispatched delivery because one of its lots was flagged before arrival
     * (weight mismatch, broken seal, failed audit, tag mismatch...). The goods payment is refunded at once;
     * the transporter is paid if it had picked the lots up, otherwise its fee is refunded too.
     * @dev The buyer side, while the delivery is dispatched and not yet arrived. Title never passes.
     * @param agreementId Agreement id.
     * @param index Delivery index.
     * @custom:emits DeliveryRejected
     */
    function rejectFlaggedDelivery(uint256 agreementId, uint256 index) external nonReentrant {
        B2BLib.Agreement storage a = _requireStatus(agreementId, B2BLib.AgreementStatus.Active);
        _requireSide(agreementId, a, B2BLib.other(a.seller));
        B2BLib.Delivery storage d = _delivery(agreementId, a, index);
        _requireDeliveryStatus(index, d, B2BLib.DeliveryStatus.Dispatched);
        uint256 flagged = B2BLogic.firstFrozenLot(_lots[agreementId][index], passport);
        if (flagged == 0) revert B2BLib.B2B__NotFlagged(index);

        bool feePaid = d.shipmentId != 0 && deliveryManager.getShipment(d.shipmentId).pickedUpAt != 0;
        address buyer = _party(a, B2BLib.other(a.seller)).account;
        _credit(a, buyer, d.goodsFunded);
        _credit(a, feePaid ? a.transport.transporter : buyer, d.feeFunded);

        d.status = B2BLib.DeliveryStatus.Rejected;
        a.progress.inFlight -= 1;
        a.progress.rejected += 1;
        _performance[_party(a, a.seller).orgId].deliveriesRejected += 1;
        _releaseLots(agreementId, index);
        emit B2BLib.DeliveryRejected(agreementId, index, flagged, feePaid);
        _completeIfDone(agreementId, a);
    }

    /*//////////////////////////////////////////////////////////////
                                DISPUTES
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Makes a settlement offer on a disputed delivery: the goods amount this side accepts the seller
     * receiving. The dispute settles as soon as the buyer offers at least what the seller asks, at the seller's
     * ask. Title passes to the buyer when the seller receives anything.
     * @dev Either party, at any time until settled. The amount is at most the price of the delivered weight.
     * @param agreementId Agreement id.
     * @param index Disputed delivery.
     * @param goodsAmount Amount for the seller.
     * @custom:emits SettlementOffered
     * @custom:emits DeliverySettled (when the offers meet)
     */
    function offerSettlement(uint256 agreementId, uint256 index, uint256 goodsAmount) external nonReentrant {
        B2BLib.Agreement storage a = _requireStatus(agreementId, B2BLib.AgreementStatus.Active);
        B2BLib.Side side = _sideOf(agreementId, a, msg.sender);
        B2BLib.Delivery storage d = _delivery(agreementId, a, index);
        _requireDeliveryStatus(index, d, B2BLib.DeliveryStatus.Disputed);
        uint256 payable_ = _payable(a, d);
        if (goodsAmount > payable_) revert B2BLib.B2B__InvalidSettlement(goodsAmount, payable_);

        B2BLib.DeliveryDispute storage disp = _disputes[agreementId][index];
        if (side == a.seller) {
            disp.payeeOffered = true;
            disp.payeeOffer = goodsAmount;
        } else {
            disp.payerOffered = true;
            disp.payerOffer = goodsAmount;
        }
        emit B2BLib.SettlementOffered(agreementId, index, side, goodsAmount);

        if (disp.payerOffered && disp.payeeOffered && disp.payerOffer >= disp.payeeOffer) {
            _settle(agreementId, a, index, d, disp.payeeOffer, address(0), bytes32(0));
        }
    }

    /**
     * @notice The arbiter named in the agreement decides a dispute the parties could not settle.
     * @dev Only the agreement's arbiter, after {NEGOTIATION_PERIOD} from the rejection.
     * @param agreementId Agreement id.
     * @param index Disputed delivery.
     * @param goodsAmount Amount awarded to the seller; at most the price of the delivered weight. The rest of
     * the goods escrow returns to the buyer.
     * @param awardHash Hash of the arbitral award.
     * @custom:emits DeliverySettled
     */
    function arbitrate(uint256 agreementId, uint256 index, uint256 goodsAmount, bytes32 awardHash)
        external
        nonReentrant
    {
        B2BLib.Agreement storage a = _requireStatus(agreementId, B2BLib.AgreementStatus.Active);
        if (a.arbiter == address(0) || msg.sender != a.arbiter) revert B2BLib.B2B__NotArbiter(msg.sender);
        B2BLib.Delivery storage d = _delivery(agreementId, a, index);
        _requireDeliveryStatus(index, d, B2BLib.DeliveryStatus.Disputed);
        uint64 until = _disputes[agreementId][index].openedAt + NEGOTIATION_PERIOD;
        if (block.timestamp <= until) revert B2BLib.B2B__NegotiationPeriod(until);
        uint256 payable_ = _payable(a, d);
        if (goodsAmount > payable_) revert B2BLib.B2B__InvalidSettlement(goodsAmount, payable_);
        _settle(agreementId, a, index, d, goodsAmount, msg.sender, awardHash);
    }

    /*//////////////////////////////////////////////////////////////
                      DELIVERIES NOT MADE OR NOT FUNDED
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Closes a delivery the seller did not make; any escrow is refunded to the buyer.
     * @dev The seller side may give up a scheduled or funded delivery at any time. The buyer side may close a
     * scheduled (off-chain payment only), funded or dispatched-but-not-arrived delivery once {REFUND_GRACE} has
     * passed since its due date. Counts as a miss in the seller's track record.
     * @param agreementId Agreement id.
     * @param index Delivery index.
     * @custom:emits DeliveryClosed
     */
    function closeMissed(uint256 agreementId, uint256 index) external nonReentrant {
        B2BLib.Agreement storage a = _requireStatus(agreementId, B2BLib.AgreementStatus.Active);
        B2BLib.Side side = _sideOf(agreementId, a, msg.sender);
        B2BLib.Delivery storage d = _delivery(agreementId, a, index);
        B2BLib.DeliveryStatus s = d.status;
        bool escrowed = address(a.paymentToken) != address(0);

        if (side == a.seller) {
            if (s != B2BLib.DeliveryStatus.Scheduled && s != B2BLib.DeliveryStatus.Funded) {
                revert B2BLib.B2B__InvalidDeliveryStatus(index, s);
            }
        } else {
            bool closable = s == B2BLib.DeliveryStatus.Funded || s == B2BLib.DeliveryStatus.Dispatched
                || (s == B2BLib.DeliveryStatus.Scheduled && !escrowed);
            if (!closable) revert B2BLib.B2B__InvalidDeliveryStatus(index, s);
            (,, uint64 dueAt) = _effectiveTerms(a, d, index);
            uint64 availableAt = dueAt + REFUND_GRACE;
            if (block.timestamp <= availableAt) revert B2BLib.B2B__TooEarly(index, availableAt);
            if (
                s == B2BLib.DeliveryStatus.Dispatched
                    && B2BLogic.hasArrived(a, _lots[agreementId][index], d.shipmentId, _deps())
            ) {
                revert B2BLib.B2B__InvalidDeliveryStatus(index, B2BLib.DeliveryStatus.Arrived);
            }
        }

        if (s == B2BLib.DeliveryStatus.Funded) a.progress.funded -= 1;
        if (s == B2BLib.DeliveryStatus.Dispatched) {
            a.progress.inFlight -= 1;
            _releaseLots(agreementId, index);
        }
        if (s == B2BLib.DeliveryStatus.Scheduled) _discardAdjustment(agreementId, index);
        uint256 refund = d.goodsFunded + d.feeFunded;
        _credit(a, _party(a, B2BLib.other(a.seller)).account, refund);
        d.status = B2BLib.DeliveryStatus.Missed;
        a.progress.missed += 1;
        _performance[_party(a, a.seller).orgId].deliveriesMissed += 1;
        emit B2BLib.DeliveryClosed(agreementId, index, B2BLib.DeliveryStatus.Missed, refund);
        _completeIfDone(agreementId, a);
    }

    /**
     * @notice Marks a delivery the buyer did not fund by its due date as a buyer default.
     * @dev The seller side, on an escrowed agreement, once the due date has passed. Counts as a funding default
     * in the buyer's track record.
     * @param agreementId Agreement id.
     * @param index Unfunded delivery.
     * @custom:emits DeliveryClosed
     */
    function markDefaulted(uint256 agreementId, uint256 index) external {
        B2BLib.Agreement storage a = _requireStatus(agreementId, B2BLib.AgreementStatus.Active);
        if (address(a.paymentToken) == address(0)) revert B2BLib.B2B__NotEscrowed();
        _requireSide(agreementId, a, a.seller);
        B2BLib.Delivery storage d = _delivery(agreementId, a, index);
        _requireDeliveryStatus(index, d, B2BLib.DeliveryStatus.Scheduled);
        (,, uint64 dueAt) = _effectiveTerms(a, d, index);
        if (block.timestamp <= dueAt) revert B2BLib.B2B__TooEarly(index, dueAt);

        _discardAdjustment(agreementId, index);
        d.status = B2BLib.DeliveryStatus.Defaulted;
        a.progress.defaulted += 1;
        _performance[_party(a, B2BLib.other(a.seller)).orgId].fundingDefaults += 1;
        emit B2BLib.DeliveryClosed(agreementId, index, B2BLib.DeliveryStatus.Defaulted, 0);
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
        B2BLib.Agreement storage a = _requireStatus(agreementId, B2BLib.AgreementStatus.Active);
        B2BLib.Side side = _authorizedSide(agreementId, a);
        if (a.terminationRequested) revert B2BLib.B2B__InvalidTermination(agreementId);
        a.terminationRequested = true;
        a.terminationRequestedBy = side;
        emit B2BLib.TerminationRequested(agreementId, side, reasonHash);
    }

    /**
     * @notice Confirms the other party's termination request; the agreement ends.
     * @dev The party that did not request it, with `ENTER_AGREEMENT`. No delivery may be dispatched, arrived
     * or disputed; funded deliveries are refunded and the rest cancelled.
     * @param agreementId Agreement id.
     * @custom:emits DeliveryClosed (per refunded delivery)
     * @custom:emits AgreementClosed
     */
    function confirmTermination(uint256 agreementId) external nonReentrant {
        B2BLib.Agreement storage a = _requireStatus(agreementId, B2BLib.AgreementStatus.Active);
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
        B2BLib.Agreement storage a = _requireStatus(agreementId, B2BLib.AgreementStatus.Active);
        B2BLib.Side side = _sideOf(agreementId, a, msg.sender);
        if (!a.terminationRequested || a.terminationRequestedBy != side) {
            revert B2BLib.B2B__InvalidTermination(agreementId);
        }
        a.terminationRequested = false;
        emit B2BLib.TerminationRequestWithdrawn(agreementId);
    }

    /**
     * @notice Ends an agreement unilaterally because the other party repeatedly failed it: the buyer once the
     * seller has missed `maxMissed` deliveries, the seller once the buyer has failed to fund `maxMissed`.
     * @dev Either party, with `ENTER_AGREEMENT`, when the agreement sets `maxMissed`. No delivery may be
     * dispatched, arrived or disputed.
     * @param agreementId Agreement id.
     * @param reasonHash Hash of the notice of termination.
     * @custom:emits TerminationRequested
     * @custom:emits AgreementClosed
     */
    function terminateForCause(uint256 agreementId, bytes32 reasonHash) external nonReentrant {
        B2BLib.Agreement storage a = _requireStatus(agreementId, B2BLib.AgreementStatus.Active);
        B2BLib.Side side = _authorizedSide(agreementId, a);
        uint32 count = side == a.seller ? a.progress.defaulted : a.progress.missed;
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
    function getAgreement(uint256 agreementId) external view returns (B2BLib.Agreement memory) {
        return _agreements[agreementId];
    }

    /**
     * @notice Returns one delivery with its effective quantity, price and due date.
     * @dev Deliveries left scheduled when an agreement was terminated are reported as `Cancelled`. Due dates
     * are 0 before activation.
     * @param agreementId Agreement id.
     * @param index Delivery index.
     * @return d The delivery.
     */
    function getDelivery(uint256 agreementId, uint256 index) public view returns (B2BLib.Delivery memory d) {
        B2BLib.Agreement storage a = _agreements[agreementId];
        if (index >= a.supply.totalDeliveries) revert B2BLib.B2B__UnknownDelivery(agreementId, index);
        B2BLib.Delivery storage s = _deliveries[agreementId][index];
        d = s;
        (d.quantity, d.pricePerKg, d.dueAt) = _effectiveTerms(a, s, index);
        if (a.status == B2BLib.AgreementStatus.Terminated && d.status == B2BLib.DeliveryStatus.Scheduled) {
            d.status = B2BLib.DeliveryStatus.Cancelled;
        }
    }

    /**
     * @notice Returns a page of an agreement's delivery schedule.
     * @param agreementId Agreement id.
     * @param offset First delivery index.
     * @param limit Maximum number of deliveries.
     * @return page Up to `limit` deliveries starting at `offset`.
     */
    function getDeliveries(uint256 agreementId, uint256 offset, uint256 limit)
        external
        view
        returns (B2BLib.Delivery[] memory page)
    {
        uint256 total = _agreements[agreementId].supply.totalDeliveries;
        if (offset >= total) return page;
        uint256 end = Math.min(offset + limit, total);
        page = new B2BLib.Delivery[](end - offset);
        for (uint256 i = offset; i < end; ++i) {
            page[i - offset] = getDelivery(agreementId, i);
        }
    }

    /**
     * @notice The lot passports committed to a delivery.
     * @param agreementId Agreement id.
     * @param index Delivery index.
     * @return Lot token ids.
     */
    function lotsOf(uint256 agreementId, uint256 index) external view returns (uint256[] memory) {
        return _lots[agreementId][index];
    }

    /**
     * @notice What the buyer escrows to fund a delivery.
     * @param agreementId Agreement id.
     * @param index Delivery index.
     * @return goodsAmount Price of the quantity at the upper tolerance, rounded up.
     * @return transportFee `distanceKm x feePerKm` (0 without a transporter).
     */
    function amountDue(uint256 agreementId, uint256 index)
        public
        view
        returns (uint256 goodsAmount, uint256 transportFee)
    {
        B2BLib.Agreement storage a = _agreements[agreementId];
        if (index >= a.supply.totalDeliveries) revert B2BLib.B2B__UnknownDelivery(agreementId, index);
        (uint128 quantity, uint256 pricePerKg,) = _effectiveTerms(a, _deliveries[agreementId][index], index);
        (, uint128 max) = B2BLib.bounds(quantity, a.supply.quantityToleranceBps);
        goodsAmount = Math.mulDiv(max, pricePerKg, B2BLib.GRAMS_PER_KG, Math.Rounding.Ceil);
        transportFee = uint256(a.transport.distanceKm) * a.transport.feePerKm;
    }

    /**
     * @notice Returns the pending adjustment of a delivery.
     * @param agreementId Agreement id.
     * @param index Delivery index.
     * @return The adjustment (`pending` false if none).
     */
    function getAdjustment(uint256 agreementId, uint256 index) external view returns (B2BLib.Adjustment memory) {
        return _adjustments[agreementId][index];
    }

    /**
     * @notice Returns the dispute over a delivery.
     * @param agreementId Agreement id.
     * @param index Delivery index.
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
     * @notice A company's track record across all its B2B agreements.
     * @param orgId Organisation id.
     * @return The track record.
     */
    function performanceOf(bytes32 orgId) external view returns (B2BLib.Performance memory) {
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

    /**
     * @dev Activates the agreement once both parties have signed and a named transporter has accepted.
     * @param agreementId Agreement id.
     * @param a The agreement.
     */
    function _activateIfReady(uint256 agreementId, B2BLib.Agreement storage a) private {
        if (!a.proposerSigned || !a.counterpartySigned) return;
        if (a.transport.transporter != address(0) && !a.transporterAccepted) return;
        a.status = B2BLib.AgreementStatus.Active;
        a.activatedAt = uint64(block.timestamp);
        emit B2BLib.AgreementActivated(
            agreementId, a.version, _defaultDueAt(a, 0), _defaultDueAt(a, a.supply.totalDeliveries - 1)
        );
    }

    /**
     * @dev Returns an open proposal, reverting on a wrong version or a passed deadline.
     * @param agreementId Agreement id.
     * @param version Version being signed or accepted.
     * @return a Storage pointer to the agreement.
     */
    function _requireOpenProposal(uint256 agreementId, uint32 version)
        private
        view
        returns (B2BLib.Agreement storage a)
    {
        a = _requireStatus(agreementId, B2BLib.AgreementStatus.Proposed);
        if (version != a.version) revert B2BLib.B2B__VersionMismatch(a.version, version);
        if (block.timestamp > a.proposalExpiresAt) revert B2BLib.B2B__ProposalExpired(agreementId);
    }

    /*//////////////////////////////////////////////////////////////
                            INTERNAL: SCHEDULE
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Default due date of delivery `index`: `activatedAt + firstDeliveryOffset + index x interval` (0
     * before activation).
     * @param a The agreement.
     * @param index Delivery index.
     * @return The due date.
     */
    function _defaultDueAt(B2BLib.Agreement storage a, uint256 index) private view returns (uint64) {
        if (a.activatedAt == 0) return 0;
        return uint64(a.activatedAt + uint256(a.supply.firstDeliveryOffset) + index * a.supply.deliveryInterval);
    }

    /**
     * @dev The effective quantity, price and due date of a delivery: its adjusted values, or the defaults.
     * @param a The agreement.
     * @param d The delivery.
     * @param index Delivery index.
     * @return quantity Quantity, in grams.
     * @return pricePerKg Price per kilogram.
     * @return dueAt Due date.
     */
    function _effectiveTerms(B2BLib.Agreement storage a, B2BLib.Delivery storage d, uint256 index)
        private
        view
        returns (uint128 quantity, uint256 pricePerKg, uint64 dueAt)
    {
        if (d.adjusted) return (d.quantity, d.pricePerKg, d.dueAt);
        return (a.supply.quantityPerDelivery, a.supply.pricePerKg, _defaultDueAt(a, index));
    }

    /**
     * @dev Stores a delivery's default terms so they are fixed from dispatch on.
     * @param a The agreement.
     * @param d The delivery.
     * @param index Delivery index.
     */
    function _pinDefaults(B2BLib.Agreement storage a, B2BLib.Delivery storage d, uint256 index) private {
        d.quantity = a.supply.quantityPerDelivery;
        d.pricePerKg = a.supply.pricePerKg;
        d.dueAt = _defaultDueAt(a, index);
    }

    /**
     * @dev Returns a delivery, reverting if the index is beyond the schedule.
     * @param agreementId Agreement id.
     * @param a The agreement.
     * @param index Delivery index.
     * @return Storage pointer to the delivery.
     */
    function _delivery(uint256 agreementId, B2BLib.Agreement storage a, uint256 index)
        private
        view
        returns (B2BLib.Delivery storage)
    {
        if (index >= a.supply.totalDeliveries) revert B2BLib.B2B__UnknownDelivery(agreementId, index);
        return _deliveries[agreementId][index];
    }

    /**
     * @dev Deletes a pending adjustment, emitting {B2BLib.AdjustmentCleared} if there was one.
     * @param agreementId Agreement id.
     * @param index Delivery index.
     */
    function _discardAdjustment(uint256 agreementId, uint256 index) private {
        if (_adjustments[agreementId][index].pending) {
            delete _adjustments[agreementId][index];
            emit B2BLib.AdjustmentCleared(agreementId, index, msg.sender);
        }
    }

    /*//////////////////////////////////////////////////////////////
                              INTERNAL: LOTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Frees a delivery's lots so they can fill another delivery.
     * @param agreementId Agreement id.
     * @param index Delivery index.
     */
    function _releaseLots(uint256 agreementId, uint256 index) private {
        uint256[] storage lots = _lots[agreementId][index];
        for (uint256 i; i < lots.length; ++i) {
            lotCommitted[lots[i]] = false;
        }
    }

    /*//////////////////////////////////////////////////////////////
                            INTERNAL: PAYMENT
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev The goods amount owed for a delivery's delivered weight, capped by the escrow when escrowed.
     * @param a The agreement.
     * @param d The delivery.
     * @return The payable amount.
     */
    function _payable(B2BLib.Agreement storage a, B2BLib.Delivery storage d) private view returns (uint256) {
        uint256 amount = B2BLib.priceOf(d.deliveredQty, d.pricePerKg);
        if (address(a.paymentToken) != address(0) && amount > d.goodsFunded) amount = d.goodsFunded;
        return amount;
    }

    /**
     * @dev Pays out an accepted delivery and transfers title.
     * @param agreementId Agreement id.
     * @param a The agreement.
     * @param index Delivery index.
     * @param d The delivery.
     * @param automatic Whether released after the review period.
     */
    function _accept(
        uint256 agreementId,
        B2BLib.Agreement storage a,
        uint256 index,
        B2BLib.Delivery storage d,
        bool automatic
    ) private {
        uint256 goodsPaid = _payable(a, d);
        uint256 refund = address(a.paymentToken) == address(0) ? 0 : d.goodsFunded - goodsPaid;
        d.status = B2BLib.DeliveryStatus.Accepted;
        a.progress.accepted += 1;
        _payParties(a, goodsPaid, refund, d.feeFunded);
        _recordSupplied(a, d, true);
        _releaseLots(agreementId, index); // effects before the external title transfer (CEI)
        B2BLogic.transferTitle(a, _lots[agreementId][index], _deps());
        emit B2BLib.DeliveryAccepted(agreementId, index, goodsPaid, refund, d.feeFunded, automatic);
        _completeIfDone(agreementId, a);
    }

    /**
     * @dev Settles a disputed delivery: `goodsPaid` to the seller, the rest of the goods escrow to the buyer,
     * the fee to the transporter (the lots arrived). Title passes when the seller receives anything.
     * @param agreementId Agreement id.
     * @param a The agreement.
     * @param index Delivery index.
     * @param d The delivery.
     * @param goodsPaid Amount for the seller.
     * @param arbiter Deciding arbiter, or zero when the parties agreed.
     * @param awardHash Hash of the award (zero when the parties agreed).
     */
    function _settle(
        uint256 agreementId,
        B2BLib.Agreement storage a,
        uint256 index,
        B2BLib.Delivery storage d,
        uint256 goodsPaid,
        address arbiter,
        bytes32 awardHash
    ) private {
        uint256 refund = address(a.paymentToken) == address(0) ? 0 : d.goodsFunded - goodsPaid;
        bool title = goodsPaid != 0;
        if (goodsPaid < _payable(a, d)) _performance[_party(a, a.seller).orgId].disputesLost += 1;
        d.status = B2BLib.DeliveryStatus.Settled;
        a.progress.settled += 1;
        _payParties(a, goodsPaid, refund, d.feeFunded);
        _recordSupplied(a, d, title);
        _releaseLots(agreementId, index); // effects before the external title transfer (CEI)
        if (title) B2BLogic.transferTitle(a, _lots[agreementId][index], _deps());
        emit B2BLib.DeliverySettled(agreementId, index, goodsPaid, refund, title, arbiter, awardHash);
        _completeIfDone(agreementId, a);
    }

    /**
     * @dev Credits the seller, the buyer's refund and the transporter's fee.
     * @param a The agreement.
     * @param goodsPaid Amount for the seller.
     * @param refund Amount for the buyer.
     * @param fee Amount for the transporter.
     */
    function _payParties(B2BLib.Agreement storage a, uint256 goodsPaid, uint256 refund, uint256 fee) private {
        _credit(a, _party(a, a.seller).account, goodsPaid);
        _credit(a, _party(a, B2BLib.other(a.seller)).account, refund);
        _credit(a, a.transport.transporter, fee);
    }

    /**
     * @dev Updates the in-flight counter and, when the goods were taken, the delivered totals and the seller's
     * track record.
     * @param a The agreement.
     * @param d The delivery.
     * @param supplied Whether the buyer took the goods.
     */
    function _recordSupplied(B2BLib.Agreement storage a, B2BLib.Delivery storage d, bool supplied) private {
        a.progress.inFlight -= 1;
        if (!supplied) return;
        a.progress.gramsDelivered += d.deliveredQty;
        B2BLib.Performance storage p = _performance[_party(a, a.seller).orgId];
        p.deliveriesMade += 1;
        p.gramsSupplied += d.deliveredQty;
        if (d.onTime) {
            a.progress.onTime += 1;
            p.onTimeDeliveries += 1;
        }
    }

    /**
     * @dev Credits `amount` of the agreement's token to `account`. No-op for off-chain agreements and zero
     * amounts.
     * @param a The agreement.
     * @param account Account to credit.
     * @param amount Amount.
     */
    function _credit(B2BLib.Agreement storage a, address account, uint256 amount) private {
        if (amount == 0 || address(a.paymentToken) == address(0)) return;
        claimable[a.paymentToken][account] += amount;
    }

    /*//////////////////////////////////////////////////////////////
                            INTERNAL: CLOSING
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Ends an agreement early: refunds funded deliveries and cancels the rest. No delivery may be in
     * flight.
     * @param agreementId Agreement id.
     * @param a The agreement.
     * @param forCause Whether it is a termination for cause.
     */
    function _terminate(uint256 agreementId, B2BLib.Agreement storage a, bool forCause) private {
        B2BLib.Progress storage p = a.progress;
        if (p.inFlight != 0) revert B2BLib.B2B__DeliveriesInFlight(p.inFlight);
        uint32 total = a.supply.totalDeliveries;
        if (p.funded != 0) {
            address buyer = _party(a, B2BLib.other(a.seller)).account;
            for (uint256 i; i < total; ++i) {
                B2BLib.Delivery storage d = _deliveries[agreementId][i];
                if (d.status != B2BLib.DeliveryStatus.Funded) continue;
                uint256 refund = d.goodsFunded + d.feeFunded;
                _credit(a, buyer, refund);
                d.status = B2BLib.DeliveryStatus.Cancelled;
                emit B2BLib.DeliveryClosed(agreementId, i, B2BLib.DeliveryStatus.Cancelled, refund);
            }
            p.funded = 0;
        }
        p.cancelled = total - (p.accepted + p.settled + p.rejected + p.missed + p.defaulted);
        a.status = B2BLib.AgreementStatus.Terminated;
        a.terminationRequested = false;
        emit B2BLib.AgreementClosed(agreementId, a.status, forCause);
    }

    /**
     * @dev Completes an Active agreement once every delivery is resolved.
     * @param agreementId Agreement id.
     * @param a The agreement.
     */
    function _completeIfDone(uint256 agreementId, B2BLib.Agreement storage a) private {
        B2BLib.Progress storage p = a.progress;
        if (p.accepted + p.settled + p.rejected + p.missed + p.defaulted + p.cancelled < a.supply.totalDeliveries) {
            return;
        }
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
        returns (B2BLib.Agreement storage a)
    {
        a = _agreements[agreementId];
        if (a.status == B2BLib.AgreementStatus.None) revert B2BLib.B2B__UnknownAgreement(agreementId);
        if (a.status != expected) revert B2BLib.B2B__InvalidStatus(agreementId, a.status);
    }

    /**
     * @dev Reverts unless the delivery is in `expected` status.
     * @param index Delivery index (for the error).
     * @param d The delivery.
     * @param expected Required status.
     */
    function _requireDeliveryStatus(uint256 index, B2BLib.Delivery storage d, B2BLib.DeliveryStatus expected)
        private
        view
    {
        if (d.status != expected) revert B2BLib.B2B__InvalidDeliveryStatus(index, d.status);
    }

    /**
     * @dev The side `account` acts for, by organisation.
     * @param agreementId Agreement id (for the error).
     * @param a The agreement.
     * @param account The account.
     * @return The side.
     */
    function _sideOf(uint256 agreementId, B2BLib.Agreement storage a, address account)
        private
        view
        returns (B2BLib.Side)
    {
        bytes32 orgId = registry.participant(account).orgId;
        if (orgId != bytes32(0)) {
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
    function _authorizedSide(uint256 agreementId, B2BLib.Agreement storage a) private view returns (B2BLib.Side) {
        _authorizedOrg(msg.sender);
        return _sideOf(agreementId, a, msg.sender);
    }

    /**
     * @dev Reverts unless the caller acts for `side`.
     * @param agreementId Agreement id.
     * @param a The agreement.
     * @param side Required side.
     */
    function _requireSide(uint256 agreementId, B2BLib.Agreement storage a, B2BLib.Side side) private view {
        if (_sideOf(agreementId, a, msg.sender) != side) revert B2BLib.B2B__WrongSide(agreementId, msg.sender);
    }

    /**
     * @dev The organisation of an account authorised for `ENTER_AGREEMENT`, reverting otherwise.
     * @param account The account.
     * @return orgId Its organisation.
     */
    function _authorizedOrg(address account) private view returns (bytes32 orgId) {
        orgId = registry.participant(account).orgId;
        if (orgId == bytes32(0) || !registry.isAuthorized(account, Actions.ENTER_AGREEMENT)) {
            revert B2BLib.B2B__NotAuthorized(account);
        }
    }

    /**
     * @dev A side's party record.
     * @param a The agreement.
     * @param side The side.
     * @return Storage pointer to the party.
     */
    function _party(B2BLib.Agreement storage a, B2BLib.Side side) private view returns (B2BLib.Party storage) {
        return side == B2BLib.Side.Proposer ? a.proposer : a.counterparty;
    }

    /**
     * @dev The contracts {B2BLogic} reads from.
     * @return The dependencies.
     */
    function _deps() private view returns (B2BLogic.Deps memory) {
        return B2BLogic.Deps({
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
