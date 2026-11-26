// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {B2BLib} from "src/b2b/libraries/B2BLib.sol";
import {ServicesLib} from "src/b2b/libraries/ServicesLib.sol";

/**
 * @title IB2BServices
 * @author 0xEmmyb2
 * @notice External API of {B2BServices}: recurring service agreements between MineNet companies (haulage,
 * storage, toll processing and refining, inspection and assay, audit, customs clearing, and general services),
 * billed on work verified on-chain or claimed with evidence.
 * @dev For frontends, indexers and integrating contracts. Types, events and custom errors are in {ServicesLib}
 * and {B2BLib}; the validation limits are public constants on {B2BServices}.
 */
interface IB2BServices {
    /*//////////////////////////////////////////////////////////////
                   USER-FACING STATE-CHANGING FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Pauses new business: proposals, signatures, funding and claims.
     * @dev Only a {MineNetRegistry} admin. The admin has no power over any agreement or its funds.
     */
    function pause() external;

    /**
     * @notice Resumes normal operation.
     * @dev Only a {MineNetRegistry} admin.
     */
    function unpause() external;

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
    function propose(address counterparty, ServicesLib.Terms calldata terms) external returns (uint256 agreementId);

    /**
     * @notice Amends a proposal (a counter-offer). The new version is signed by the amending party only.
     * @dev Either party, with `ENTER_AGREEMENT`, while the agreement is a proposal. The caller becomes its side's
     * account of record.
     * @param agreementId Agreement id.
     * @param terms The amended terms.
     * @custom:emits ServiceAmended
     * @custom:emits AgreementSigned
     */
    function amend(uint256 agreementId, ServicesLib.Terms calldata terms) external;

    /**
     * @notice Signs the current version of a proposal. The agreement becomes Active once both parties have.
     * @dev Either party, with `ENTER_AGREEMENT`, before the deadline. The caller becomes its side's account of
     * record; on the provider side it must hold the permission the service kind requires.
     * @param agreementId Agreement id.
     * @param version The version being signed; must be the current one.
     * @custom:emits AgreementSigned
     * @custom:emits ServiceActivated (once both have signed)
     */
    function sign(uint256 agreementId, uint32 version) external;

    /**
     * @notice Ends a proposal: the proposer withdraws it, or the counterparty rejects it.
     * @dev Either party, while the agreement is a proposal.
     * @param agreementId Agreement id.
     * @param reasonHash Hash of the reason.
     * @custom:emits AgreementDeclined
     */
    function decline(uint256 agreementId, bytes32 reasonHash) external;

    /**
     * @notice Escrows the budget of one job (`maxUnitsPerJob x ratePerUnit`). The tokens are pulled from the
     * caller.
     * @dev The client side, on an Active escrowed agreement, while the job is scheduled (also after its due date,
     * until it is marked in default). The caller must have approved this contract for {budgetOf}.
     * @param agreementId Agreement id.
     * @param index Job index (0-based).
     * @custom:emits JobFunded
     */
    function fundJob(uint256 agreementId, uint256 index) external;

    /**
     * @notice The provider bills a job for its work. For verified kinds the units are computed on-chain from
     * `refs`; for claimed kinds they are `claimedUnits`. Billing is capped at the job's budget.
     * @dev The provider side, on an Active agreement, once the job is funded (or while scheduled when paid
     * off-chain). Storage can only be billed from the job's due date (end of the period). See the contract
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
    ) external;

    /**
     * @notice The client accepts a claim: the provider is paid and the unused budget returns to the client.
     * @dev The client side, while the job is claimed.
     * @param agreementId Agreement id.
     * @param index Job index.
     * @custom:emits JobAccepted
     */
    function acceptJob(uint256 agreementId, uint256 index) external;

    /**
     * @notice Releases a claim the client neither accepted nor disputed within the review period.
     * @dev Callable by anyone.
     * @param agreementId Agreement id.
     * @param index Job index.
     * @custom:emits JobAccepted
     */
    function releaseAfterReview(uint256 agreementId, uint256 index) external;

    /**
     * @notice The client disputes a claim, opening a dispute.
     * @dev The client side, within the review period.
     * @param agreementId Agreement id.
     * @param index Job index.
     * @param reasonHash Hash of the reasons (work not done, poor quality, overbilling...).
     * @custom:emits JobDisputed
     */
    function disputeJob(uint256 agreementId, uint256 index, bytes32 reasonHash) external;

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
    function offerSettlement(uint256 agreementId, uint256 index, uint256 amount) external;

    /**
     * @notice The arbiter named in the agreement decides a dispute the parties could not settle.
     * @dev Only the agreement's arbiter, after {NEGOTIATION_PERIOD} from the dispute.
     * @param agreementId Agreement id.
     * @param index Disputed job.
     * @param amount Amount awarded to the provider; at most the billed amount.
     * @param awardHash Hash of the arbitral award.
     * @custom:emits JobSettled
     */
    function arbitrate(uint256 agreementId, uint256 index, uint256 amount, bytes32 awardHash) external;

    /**
     * @notice Closes a job the provider did not perform; any budget is refunded to the client.
     * @dev The provider side may give up a scheduled or funded job at any time. The client side may close a
     * funded (or, when paid off-chain, scheduled) job once {MISSED_GRACE} has passed since its due date. Counts
     * as a miss in the provider's track record.
     * @param agreementId Agreement id.
     * @param index Job index.
     * @custom:emits JobClosed
     */
    function closeMissed(uint256 agreementId, uint256 index) external;

    /**
     * @notice Marks a job the client did not fund by its due date as a client default.
     * @dev The provider side, on an escrowed agreement, once the due date has passed.
     * @param agreementId Agreement id.
     * @param index Unfunded job.
     * @custom:emits JobClosed
     */
    function markDefaulted(uint256 agreementId, uint256 index) external;

    /**
     * @notice Requests to end an Active agreement early by mutual consent.
     * @dev Either party, with `ENTER_AGREEMENT`, when no request is pending.
     * @param agreementId Agreement id.
     * @param reasonHash Hash of the reason.
     * @custom:emits TerminationRequested
     */
    function requestTermination(uint256 agreementId, bytes32 reasonHash) external;

    /**
     * @notice Confirms the other party's termination request; the agreement ends.
     * @dev The party that did not request it, with `ENTER_AGREEMENT`. No job may be claimed or disputed; funded
     * jobs are refunded and the rest cancelled.
     * @param agreementId Agreement id.
     * @custom:emits JobClosed (per refunded job)
     * @custom:emits AgreementClosed
     */
    function confirmTermination(uint256 agreementId) external;

    /**
     * @notice Withdraws one's own pending termination request.
     * @dev The requesting party.
     * @param agreementId Agreement id.
     * @custom:emits TerminationRequestWithdrawn
     */
    function withdrawTerminationRequest(uint256 agreementId) external;

    /**
     * @notice Ends an agreement unilaterally after the other party repeatedly failed it: the client once the
     * provider has missed `maxMissed` jobs, the provider once the client has failed to fund `maxMissed`.
     * @dev Either party, with `ENTER_AGREEMENT`, when the agreement sets `maxMissed`. No job may be in flight.
     * @param agreementId Agreement id.
     * @param reasonHash Hash of the notice of termination.
     * @custom:emits TerminationRequested
     * @custom:emits AgreementClosed
     */
    function terminateForCause(uint256 agreementId, bytes32 reasonHash) external;

    /**
     * @notice Withdraws the caller's credited balance of `token`.
     * @param token Settlement token.
     * @custom:emits Withdrawn
     */
    function withdraw(IERC20 token) external;

    /*//////////////////////////////////////////////////////////////
                     USER-FACING READ-ONLY FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Whether a piece of on-chain work (shipment, consumed lot, checkpoint, lot-period) has been billed.
     * @param workKey Work key.
     * @return billed True if billed.
     */
    function workBilled(bytes32 workKey) external view returns (bool billed);

    /**
     * @notice Balance owed to `account` in `token` (pull pattern; see {withdraw}).
     * @param token Settlement token.
     * @param account Provider or client.
     * @return amount Amount withdrawable.
     */
    function claimable(IERC20 token, address account) external view returns (uint256 amount);

    /**
     * @notice Returns an agreement.
     * @param agreementId Agreement id.
     * @return The agreement (status `None` if unknown).
     */
    function getAgreement(uint256 agreementId) external view returns (ServicesLib.Agreement memory);

    /**
     * @notice Returns one job.
     * @dev Jobs left scheduled when an agreement was terminated are reported as `Cancelled`.
     * @param agreementId Agreement id.
     * @param index Job index.
     * @return j The job.
     */
    function getJob(uint256 agreementId, uint256 index) external view returns (ServicesLib.Job memory j);

    /**
     * @notice Due date of a job: `activatedAt + firstJobOffset + index x jobInterval` (0 before activation). For
     * storage it is the end of the billing period.
     * @param agreementId Agreement id.
     * @param index Job index.
     * @return The due date.
     */
    function dueAt(uint256 agreementId, uint256 index) external view returns (uint64);

    /**
     * @notice The budget a client escrows per job: `maxUnitsPerJob x ratePerUnit`, rounded up.
     * @param agreementId Agreement id.
     * @return The budget.
     */
    function budgetOf(uint256 agreementId) external view returns (uint256);

    /**
     * @notice Returns the dispute over a job.
     * @param agreementId Agreement id.
     * @param index Job index.
     * @return The dispute (all zero if none).
     */
    function getDispute(uint256 agreementId, uint256 index) external view returns (B2BLib.DeliveryDispute memory);

    /**
     * @notice Returns all agreements an organisation is party to.
     * @param orgId Organisation id.
     * @return Agreement ids, in proposal order.
     */
    function agreementsOf(bytes32 orgId) external view returns (uint256[] memory);

    /**
     * @notice A company's track record across all its service agreements.
     * @param orgId Organisation id.
     * @return The track record.
     */
    function performanceOf(bytes32 orgId) external view returns (ServicesLib.Performance memory);

    /**
     * @notice Number of agreements ever proposed.
     * @return Total agreement count.
     */
    function totalAgreements() external view returns (uint256);
}
