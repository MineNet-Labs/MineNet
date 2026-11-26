// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {DisputeLib} from "src/trade/libraries/DisputeLib.sol";

/**
 * @title EscrowLib
 * @author 0xEmmyb2
 * @notice Shared types, events and custom errors of {EscrowManager}.
 */
library EscrowLib {
    /**
     * @notice Lifecycle status of an escrow order.
     * @dev `Active`: funded, lot locked, delivery in progress. `Settled`: seller paid, lot transferred. `Refunded`:
     * non-delivery refund. `Resolved`: dispute judged.
     */
    enum OrderStatus {
        None,
        Active, // funded, lot locked, delivery in progress
        Disputed,
        Settled, // seller paid, lot transferred
        Refunded, // non-delivery refund
        Resolved // dispute judged
    }

    /**
     * @notice An escrow order: buyer funds held against a lot until delivery is confirmed.
     * @param tokenId Lot being sold.
     * @param buyer Buyer.
     * @param seller Seller (the lot's owner at opening).
     * @param paymentToken Settlement token.
     * @param amount Price, in payment-token units.
     * @param usdValue USD value at opening (6 decimals), for reporting.
     * @param feeBps Platform fee snapshot at opening, in basis points.
     * @param gradeAtSale Inspector-attested grade at opening (0 = ungraded).
     * @param disputeWindow Seconds after delivery in which the buyer can dispute.
     * @param createdAt When the order was opened.
     * @param deliveryDeadline Deadline for delivery; after it the buyer can claim a refund.
     * @param deliveredAt When delivery was confirmed (0 = not yet).
     * @param status Current status.
     * @param titlePending Judged "lot to buyer" while the lot was frozen: the transfer completes once it unfreezes.
     * @param termsHash Hash of the sale terms.
     */
    struct Order {
        uint256 tokenId;
        address buyer;
        address seller;
        IERC20 paymentToken;
        uint256 amount;
        uint256 usdValue;
        uint16 feeBps;
        uint16 gradeAtSale;
        uint32 disputeWindow;
        uint64 createdAt;
        uint64 deliveryDeadline;
        uint64 deliveredAt;
        OrderStatus status;
        bool titlePending;
        bytes32 termsHash;
    }

    /**
     * @notice A buyer's dispute over a delivered order.
     * @param openedAt When the dispute was opened.
     * @param evidenceDeadline End of the evidence period.
     * @param sellerResponded Whether the seller has responded.
     * @param buyerEvidenceCount Pieces of evidence submitted by the buyer.
     * @param sellerEvidenceCount Pieces of evidence submitted by the seller.
     * @param verdict Verdict reached ({DisputeLib}).
     * @param winner Winning side.
     * @param buyerRefund Amount refunded to the buyer.
     * @param claimHash Hash of the buyer's claim.
     * @param responseHash Hash of the seller's response.
     */
    struct Dispute {
        uint64 openedAt;
        uint64 evidenceDeadline;
        bool sellerResponded;
        uint8 buyerEvidenceCount;
        uint8 sellerEvidenceCount;
        DisputeLib.Verdict verdict;
        DisputeLib.Winner winner;
        uint256 buyerRefund;
        bytes32 claimHash;
        bytes32 responseHash;
    }

    /**
     * @notice One piece of dispute evidence.
     * @dev On-chain evidence points to a {SupplyChain} checkpoint of the lot recorded after the sale; its facts are
     * snapshotted and judged. Document-only evidence is kept for the record but does not move the verdict (a
     * contract cannot read a PDF).
     * @param submittedBy Submitting account.
     * @param fromBuyer True if submitted by the buyer's side.
     * @param onChain True if it references a supply-chain checkpoint.
     * @param checkpointIndex Referenced checkpoint index (on-chain evidence only).
     * @param submittedAt When it was submitted.
     * @param docHash Hash of the supporting document.
     * @param fact Facts snapshotted from the checkpoint.
     */
    struct Evidence {
        address submittedBy;
        bool fromBuyer;
        bool onChain;
        uint32 checkpointIndex;
        uint64 submittedAt;
        bytes32 docHash;
        DisputeLib.Fact fact;
    }

    /**
     * @notice Everything the {Marketplace} supplies to open an order.
     * @param tokenId Lot being sold.
     * @param buyer Buyer.
     * @param seller Seller.
     * @param paymentToken Settlement token.
     * @param amount Price, in payment-token units.
     * @param deliveryWindow Seconds from opening until the delivery deadline.
     * @param termsHash Hash of the sale terms.
     */
    struct OpenParams {
        uint256 tokenId;
        address buyer;
        address seller;
        IERC20 paymentToken;
        uint256 amount;
        uint32 deliveryWindow;
        bytes32 termsHash;
    }

    /**
     * @notice Emitted when an order is opened and funded.
     * @param orderId New order id.
     * @param tokenId Lot being sold.
     * @param buyer Buyer.
     * @param seller Seller.
     * @param paymentToken Settlement token.
     * @param amount Price, in payment-token units.
     * @param usdValue USD value, 6 decimals.
     * @param deliveryDeadline Delivery deadline.
     */
    event OrderOpened(
        uint256 indexed orderId,
        uint256 indexed tokenId,
        address indexed buyer,
        address seller,
        IERC20 paymentToken,
        uint256 amount,
        uint256 usdValue,
        uint64 deliveryDeadline
    );

    /**
     * @notice Emitted when the buyer confirms delivery; the dispute window starts.
     * @param orderId Order id.
     * @param deliveredAt Confirmation time.
     */
    event DeliveryConfirmed(uint256 indexed orderId, uint64 deliveredAt);

    /**
     * @notice Emitted when an order settles: the seller is paid and the lot goes to the buyer.
     * @param orderId Order id.
     * @param sellerAmount Amount credited to the seller.
     * @param fee Platform fee.
     */
    event OrderSettled(uint256 indexed orderId, uint256 sellerAmount, uint256 fee);

    /**
     * @notice Emitted when an undelivered order is refunded to the buyer.
     * @param orderId Order id.
     * @param amount Amount refunded.
     */
    event OrderRefunded(uint256 indexed orderId, uint256 amount);

    /**
     * @notice Emitted when the buyer opens a dispute.
     * @param orderId Order id.
     * @param claimHash Hash of the claim.
     * @param evidenceDeadline End of the evidence period.
     */
    event DisputeOpened(uint256 indexed orderId, bytes32 claimHash, uint64 evidenceDeadline);

    /**
     * @notice Emitted when the seller responds to a dispute.
     * @param orderId Order id.
     * @param responseHash Hash of the response.
     */
    event DisputeResponded(uint256 indexed orderId, bytes32 responseHash);

    /**
     * @notice Emitted when dispute evidence is submitted.
     * @param orderId Order id.
     * @param index Evidence index.
     * @param by Submitting account.
     * @param onChain Whether it references a supply-chain checkpoint.
     * @param checkpointIndex Referenced checkpoint index.
     * @param independent Whether the checkpoint was signed by an independent party.
     * @param docHash Hash of the supporting document.
     */
    event EvidenceSubmitted(
        uint256 indexed orderId,
        uint256 indexed index,
        address indexed by,
        bool onChain,
        uint32 checkpointIndex,
        bool independent,
        bytes32 docHash
    );

    /**
     * @notice Emitted when the buyer withdraws a dispute; the order settles normally.
     * @param orderId Order id.
     */
    event DisputeWithdrawn(uint256 indexed orderId);

    /**
     * @notice Emitted when a dispute is judged and the funds are distributed.
     * @param orderId Order id.
     * @param verdict Verdict reached.
     * @param winner Winning side.
     * @param buyerRefund Amount refunded to the buyer.
     * @param sellerAmount Amount credited to the seller.
     * @param lotToBuyer Whether the lot goes to the buyer.
     */
    event DisputeResolved(
        uint256 indexed orderId,
        DisputeLib.Verdict indexed verdict,
        DisputeLib.Winner winner,
        uint256 buyerRefund,
        uint256 sellerAmount,
        bool lotToBuyer
    );

    /**
     * @notice Emitted when a lot judged to the buyer is frozen; the transfer completes once it unfreezes.
     * @param orderId Order id.
     * @param tokenId Lot.
     */
    event TitlePending(uint256 indexed orderId, uint256 indexed tokenId);

    /**
     * @notice Emitted when a pending title transfer completes.
     * @param orderId Order id.
     * @param tokenId Lot.
     */
    event TitleFinalized(uint256 indexed orderId, uint256 indexed tokenId);

    /**
     * @notice Emitted when an account withdraws its credited balance.
     * @param token Settlement token.
     * @param account Withdrawing account.
     * @param amount Amount withdrawn.
     */
    event Withdrawn(IERC20 indexed token, address indexed account, uint256 amount);

    /**
     * @notice Emitted when the admin sets the marketplace allowed to open orders.
     * @param marketplace Marketplace contract.
     */
    event MarketplaceSet(address indexed marketplace);

    /**
     * @notice Emitted when the admin sets the platform fee.
     * @param feeBps Fee, in basis points.
     * @param treasury Account credited with fees.
     */
    event FeeUpdated(uint16 feeBps, address treasury);

    /**
     * @notice Emitted when the admin sets the dispute window.
     * @param disputeWindow Seconds after delivery in which the buyer can dispute.
     */
    event DisputeWindowUpdated(uint32 disputeWindow);

    /**
     * @notice Emitted when the admin sets the certificates a lot needs before it can be sold.
     * @param certTypes Required certificate types.
     */
    event RequiredCertTypesUpdated(bytes32[] certTypes);

    /**
     * @notice `account` is not an admin of {MineNetRegistry}.
     * @param account The account.
     */
    error EscrowManager__NotRegistryAdmin(address account);

    /**
     * @notice `account` is not the marketplace.
     * @param account The account.
     */
    error EscrowManager__NotMarketplace(address account);

    /**
     * @notice `account` is not the order party allowed to act, or the buyer may not buy lots.
     * @param account The account.
     */
    error EscrowManager__Unauthorized(address account);

    /**
     * @notice `token` is not an accepted settlement token.
     * @param token The token.
     */
    error EscrowManager__TokenNotAllowed(IERC20 token);

    /**
     * @notice The amount is zero.
     */
    error EscrowManager__InvalidAmount();

    /**
     * @notice The delivery or dispute window is outside the allowed range.
     */
    error EscrowManager__InvalidWindow();

    /**
     * @notice The fee exceeds the maximum fee.
     */
    error EscrowManager__InvalidFee();

    /**
     * @notice An address is zero.
     */
    error EscrowManager__ZeroAddress();

    /**
     * @notice Buyer and seller are the same account.
     */
    error EscrowManager__SelfDealing();

    /**
     * @notice `seller` does not own lot `tokenId`.
     * @param tokenId The lot.
     * @param seller The seller.
     */
    error EscrowManager__SellerNotOwner(uint256 tokenId, address seller);

    /**
     * @notice Order `orderId` is in `status`, which does not allow the operation.
     * @param orderId The order.
     * @param status Its current status.
     */
    error EscrowManager__InvalidState(uint256 orderId, OrderStatus status);

    /**
     * @notice Lot `tokenId` lacks a valid certificate required for sale.
     * @param tokenId The lot.
     */
    error EscrowManager__MissingCertificates(uint256 tokenId);

    /**
     * @notice Delivery of order `orderId` has not been confirmed.
     * @param orderId The order.
     */
    error EscrowManager__NotDelivered(uint256 orderId);

    /**
     * @notice The dispute window of order `orderId` is still open.
     * @param orderId The order.
     */
    error EscrowManager__DisputeWindowOpen(uint256 orderId);

    /**
     * @notice The dispute window of order `orderId` has closed.
     * @param orderId The order.
     */
    error EscrowManager__DisputeWindowClosed(uint256 orderId);

    /**
     * @notice The delivery deadline of order `orderId` has not passed.
     * @param orderId The order.
     */
    error EscrowManager__DeadlineNotReached(uint256 orderId);

    /**
     * @notice The evidence period of order `orderId` runs until `evidenceDeadline`.
     * @param orderId The order.
     * @param evidenceDeadline End of the evidence period.
     */
    error EscrowManager__EvidencePeriodOpen(uint256 orderId, uint64 evidenceDeadline);

    /**
     * @notice The evidence period of order `orderId` has closed.
     * @param orderId The order.
     */
    error EscrowManager__EvidencePeriodClosed(uint256 orderId);

    /**
     * @notice The evidence for order `orderId` does not yet support a verdict.
     * @param orderId The order.
     */
    error EscrowManager__VerdictPending(uint256 orderId);

    /**
     * @notice This side has submitted the maximum amount of evidence for order `orderId`.
     * @param orderId The order.
     */
    error EscrowManager__TooMuchEvidence(uint256 orderId);

    /**
     * @notice Lot `tokenId` has no checkpoint at `index`.
     * @param tokenId The lot.
     * @param index Checkpoint index.
     */
    error EscrowManager__UnknownCheckpoint(uint256 tokenId, uint256 index);

    /**
     * @notice Checkpoint `index` was recorded before order `orderId` was opened.
     * @param orderId The order.
     * @param index Checkpoint index.
     */
    error EscrowManager__EvidenceBeforeSale(uint256 orderId, uint256 index);

    /**
     * @notice Checkpoint `index` was already submitted as evidence for order `orderId`.
     * @param orderId The order.
     * @param index Checkpoint index.
     */
    error EscrowManager__DuplicateEvidence(uint256 orderId, uint256 index);

    /**
     * @notice The evidence carries neither a checkpoint nor a document.
     */
    error EscrowManager__EmptyEvidence();

    /**
     * @notice Order `orderId` has no pending title transfer.
     * @param orderId The order.
     */
    error EscrowManager__TitleNotPending(uint256 orderId);

    /**
     * @notice Order `orderId` has already been disputed.
     * @param orderId The order.
     */
    error EscrowManager__AlreadyDisputed(uint256 orderId);

    /**
     * @notice The caller has no balance to withdraw.
     */
    error EscrowManager__NothingToWithdraw();
}
