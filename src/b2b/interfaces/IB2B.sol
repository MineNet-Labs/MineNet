// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {B2BLib} from "src/b2b/libraries/B2BLib.sol";

/**
 * @title IB2B
 * @author 0xEmmyb2
 * @notice External API of {B2B}: recurring mineral supply agreements between MineNet companies, with an optional
 * named transporter and an independent destination inspection, filled with lot passports and paid for the kilograms delivered.
 * @dev For frontends, indexers and integrating contracts. Types, events and custom errors are in {B2BLib}; the
 * validation limits are public constants on {B2B}.
 */
interface IB2B {
    /*//////////////////////////////////////////////////////////////
                   USER-FACING STATE-CHANGING FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Pauses new business: proposals, signatures, funding, dispatch and adjustments.
     * @dev Only a {MineNetRegistry} admin. The admin has no power over any agreement or its funds.
     */
    function pause() external;

    /**
     * @notice Resumes normal operation.
     * @dev Only a {MineNetRegistry} admin.
     */
    function unpause() external;

    /**
     * @notice Proposes a supply agreement to another company. Proposing signs the first version.
     * @dev The caller and `counterparty` need `ENTER_AGREEMENT` and must belong to different organisations.
     * @param counterparty An account of the company the agreement is proposed to.
     * @param terms The proposed terms.
     * @return agreementId New agreement id.
     * @custom:emits AgreementProposed
     * @custom:emits AgreementSigned
     */
    function propose(address counterparty, B2BLib.Terms calldata terms) external returns (uint256 agreementId);

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
    function amend(uint256 agreementId, B2BLib.Terms calldata terms) external;

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
    function sign(uint256 agreementId, uint32 version) external;

    /**
     * @notice The named transporter accepts to carry the agreement's deliveries for the agreed fee.
     * @dev Only the named transporter, still an authorised carrier, before the deadline.
     * @param agreementId Agreement id.
     * @param version The version being accepted; must be the current one.
     * @custom:emits TransporterAccepted
     * @custom:emits AgreementActivated (once every signature is in place)
     */
    function acceptAsTransporter(uint256 agreementId, uint32 version) external;

    /**
     * @notice The named transporter refuses the agreement, which ends the proposal.
     * @dev Only the named transporter, while the agreement is a proposal.
     * @param agreementId Agreement id.
     * @param reasonHash Hash of the reason.
     * @custom:emits AgreementDeclined
     */
    function declineAsTransporter(uint256 agreementId, bytes32 reasonHash) external;

    /**
     * @notice Ends a proposal: the proposer withdraws it, or the counterparty rejects it.
     * @dev Either party, while the agreement is a proposal.
     * @param agreementId Agreement id.
     * @param reasonHash Hash of the reason.
     * @custom:emits AgreementDeclined
     */
    function decline(uint256 agreementId, bytes32 reasonHash) external;

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
        external;

    /**
     * @notice Confirms the other party's pending adjustment, which then applies to the delivery.
     * @dev The party that did not request it, while the delivery is unfunded.
     * @param agreementId Agreement id.
     * @param index Delivery index.
     * @custom:emits AdjustmentConfirmed
     */
    function confirmAdjustment(uint256 agreementId, uint256 index) external;

    /**
     * @notice Rejects the other party's pending adjustment, or withdraws one's own.
     * @dev Either party.
     * @param agreementId Agreement id.
     * @param index Delivery index.
     * @custom:emits AdjustmentCleared
     */
    function clearAdjustment(uint256 agreementId, uint256 index) external;

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
    function fundDelivery(uint256 agreementId, uint256 index) external;

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
    ) external;

    /**
     * @notice Records that the buyer's organisation holds custody of every lot of a dispatched delivery (and
     * its shipment is delivered); the buyer's review period starts.
     * @dev Callable by anyone.
     * @param agreementId Agreement id.
     * @param index Delivery index.
     * @custom:emits DeliveryArrived
     */
    function confirmArrival(uint256 agreementId, uint256 index) external;

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
    function acceptDelivery(uint256 agreementId, uint256 index) external;

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
    function releaseAfterReview(uint256 agreementId, uint256 index) external;

    /**
     * @notice The buyer rejects an arrived delivery, opening a dispute.
     * @dev The buyer side, within the review period, or later while a lot is flagged or was inspected below the
     * minimum grade by an independent inspector.
     * @param agreementId Agreement id.
     * @param index Delivery index.
     * @param reasonHash Hash of the reasons (short weight, low grade, contamination...).
     * @custom:emits DeliveryDisputed
     */
    function rejectDelivery(uint256 agreementId, uint256 index, bytes32 reasonHash) external;

    /**
     * @notice The buyer refuses a dispatched delivery because one of its lots was flagged before arrival
     * (weight mismatch, broken seal, failed audit, tag mismatch...). The goods payment is refunded at once;
     * the transporter is paid if it had picked the lots up, otherwise its fee is refunded too.
     * @dev The buyer side, while the delivery is dispatched and not yet arrived. Title never passes.
     * @param agreementId Agreement id.
     * @param index Delivery index.
     * @custom:emits DeliveryRejected
     */
    function rejectFlaggedDelivery(uint256 agreementId, uint256 index) external;

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
    function offerSettlement(uint256 agreementId, uint256 index, uint256 goodsAmount) external;

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
    function arbitrate(uint256 agreementId, uint256 index, uint256 goodsAmount, bytes32 awardHash) external;

    /**
     * @notice Closes a delivery the seller did not make; any escrow is refunded to the buyer.
     * @dev The seller side may give up a scheduled or funded delivery at any time. The buyer side may close a
     * scheduled (off-chain payment only), funded or dispatched-but-not-arrived delivery once {REFUND_GRACE} has
     * passed since its due date. Counts as a miss in the seller's track record.
     * @param agreementId Agreement id.
     * @param index Delivery index.
     * @custom:emits DeliveryClosed
     */
    function closeMissed(uint256 agreementId, uint256 index) external;

    /**
     * @notice Marks a delivery the buyer did not fund by its due date as a buyer default.
     * @dev The seller side, on an escrowed agreement, once the due date has passed. Counts as a funding default
     * in the buyer's track record.
     * @param agreementId Agreement id.
     * @param index Unfunded delivery.
     * @custom:emits DeliveryClosed
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
     * @dev The party that did not request it, with `ENTER_AGREEMENT`. No delivery may be dispatched, arrived
     * or disputed; funded deliveries are refunded and the rest cancelled.
     * @param agreementId Agreement id.
     * @custom:emits DeliveryClosed (per refunded delivery)
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
     * @notice Ends an agreement unilaterally because the other party repeatedly failed it: the buyer once the
     * seller has missed `maxMissed` deliveries, the seller once the buyer has failed to fund `maxMissed`.
     * @dev Either party, with `ENTER_AGREEMENT`, when the agreement sets `maxMissed`. No delivery may be
     * dispatched, arrived or disputed.
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
     * @notice Whether a lot is committed to an open delivery (a lot fills one delivery at a time).
     * @param tokenId Lot.
     * @return committed True if committed.
     */
    function lotCommitted(uint256 tokenId) external view returns (bool committed);

    /**
     * @notice Balance owed to `account` in `token` (pull pattern; see {withdraw}).
     * @param token Settlement token.
     * @param account Seller, buyer or transporter.
     * @return amount Amount withdrawable.
     */
    function claimable(IERC20 token, address account) external view returns (uint256 amount);

    /**
     * @notice Returns an agreement.
     * @param agreementId Agreement id.
     * @return The agreement (status `None` if unknown).
     */
    function getAgreement(uint256 agreementId) external view returns (B2BLib.Agreement memory);

    /**
     * @notice Returns one delivery with its effective quantity, price and due date.
     * @dev Deliveries left scheduled when an agreement was terminated are reported as `Cancelled`. Due dates
     * are 0 before activation.
     * @param agreementId Agreement id.
     * @param index Delivery index.
     * @return d The delivery.
     */
    function getDelivery(uint256 agreementId, uint256 index) external view returns (B2BLib.Delivery memory d);

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
        returns (B2BLib.Delivery[] memory page);

    /**
     * @notice The lot passports committed to a delivery.
     * @param agreementId Agreement id.
     * @param index Delivery index.
     * @return Lot token ids.
     */
    function lotsOf(uint256 agreementId, uint256 index) external view returns (uint256[] memory);

    /**
     * @notice What the buyer escrows to fund a delivery.
     * @param agreementId Agreement id.
     * @param index Delivery index.
     * @return goodsAmount Price of the quantity at the upper tolerance, rounded up.
     * @return transportFee `distanceKm x feePerKm` (0 without a transporter).
     */
    function amountDue(uint256 agreementId, uint256 index)
        external
        view
        returns (uint256 goodsAmount, uint256 transportFee);

    /**
     * @notice Returns the pending adjustment of a delivery.
     * @param agreementId Agreement id.
     * @param index Delivery index.
     * @return The adjustment (`pending` false if none).
     */
    function getAdjustment(uint256 agreementId, uint256 index) external view returns (B2BLib.Adjustment memory);

    /**
     * @notice Returns the dispute over a delivery.
     * @param agreementId Agreement id.
     * @param index Delivery index.
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
     * @notice A company's track record across all its B2B agreements.
     * @param orgId Organisation id.
     * @return The track record.
     */
    function performanceOf(bytes32 orgId) external view returns (B2BLib.Performance memory);

    /**
     * @notice Number of agreements ever proposed.
     * @return Total agreement count.
     */
    function totalAgreements() external view returns (uint256);
}
