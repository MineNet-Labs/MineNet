// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {IEscrowManager} from "src/trade/interfaces/IEscrowManager.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {IMineNetRegistry} from "src/access/interfaces/IMineNetRegistry.sol";
import {ILotPassport} from "src/traceability/interfaces/ILotPassport.sol";
import {ICertificateRegistry} from "src/compliance/interfaces/ICertificateRegistry.sol";
import {ISupplyChain} from "src/traceability/interfaces/ISupplyChain.sol";
import {ICurrencyManager} from "src/finance/interfaces/ICurrencyManager.sol";
import {Actions} from "src/access/libraries/Actions.sol";
import {EscrowLib} from "src/trade/libraries/EscrowLib.sol";
import {DisputeLib} from "src/trade/libraries/DisputeLib.sol";
import {SupplyChainLib} from "src/traceability/libraries/SupplyChainLib.sol";

/**
 * @title EscrowManager
 * @author 0xEmmyb2
 * @notice Holds stablecoin payments for marketplace sales and settles them against the lot passport.
 * @dev Orders are opened only by the {Marketplace}. Opening an order locks the lot to it and moves the payment
 * in. When the buyer holds custody on the passport, the lot counts as delivered. The buyer then releases
 * payment, or anyone settles after the dispute window. If the lot is not delivered by the deadline, the buyer
 * gets a full refund.
 *
 * Decentralised disputes (project.md 8.4). No regulator, admin or arbiter decides:
 * 1. The buyer opens a dispute; an evidence period ({EVIDENCE_PERIOD}) starts and the escrow stays locked.
 * 2. Both parties submit evidence ({submitEvidence}): references to {SupplyChain} checkpoints of the lot
 *    recorded after the sale (weights, seal and condition checks, grades, audits, oracle reports), plus
 *    optional document hashes for the record.
 * 3. After the period anyone calls {resolveDispute}. {DisputeLib-judge} weighs the evidence (independent
 *    signers are decisive; party-signed claims count unless rebutted by later independent facts) and the
 *    verdict is executed at once: refund, split or payment. {evaluateDispute} shows the verdict and winner in
 *    advance.
 * If the verdict gives the lot to the buyer while it is frozen by a compliance flag, the money is paid out and
 * the title transfer waits until the lot is unfrozen ({finalizeTitle}).
 *
 * Types, events and errors live in {EscrowLib}; the verdict logic in {DisputeLib}. Payouts use the pull pattern
 * ({withdraw}). Withdrawals, refunds and dispute resolution keep working while paused.
 */
contract EscrowManager is ReentrancyGuardTransient, Pausable, IEscrowManager {
    using SafeERC20 for IERC20;

    /**
     * @notice Maximum platform fee (5%), in basis points.
     */
    uint16 public constant MAX_FEE_BPS = 500;

    /**
     * @notice Shortest configurable dispute window.
     */
    uint32 public constant MIN_DISPUTE_WINDOW = 1 days;

    /**
     * @notice Longest configurable dispute window.
     */
    uint32 public constant MAX_DISPUTE_WINDOW = 30 days;

    /**
     * @notice Shortest delivery window an order may have.
     */
    uint32 public constant MIN_DELIVERY_WINDOW = 1 hours;

    /**
     * @notice Longest delivery window an order may have.
     */
    uint32 public constant MAX_DELIVERY_WINDOW = 180 days;

    /**
     * @notice Time both parties have to put evidence forward.
     */
    uint32 public constant EVIDENCE_PERIOD = 7 days;

    /**
     * @notice Maximum pieces of evidence each side may submit.
     */
    uint8 public constant MAX_EVIDENCE_PER_SIDE = 10;

    /**
     * @notice Time a buyer refunded after delivery has to bring the goods back to the seller.
     */
    uint32 public constant RETURN_WINDOW = 30 days;

    /**
     * @notice Participant, role and permission registry.
     */
    IMineNetRegistry public immutable registry;

    /**
     * @notice Lot passport on which lots are locked and transferred.
     */
    ILotPassport public immutable passport;

    /**
     * @notice Certificates required for sale and settlement.
     */
    ICertificateRegistry public immutable certificates;

    /**
     * @notice Supply-chain ledger whose checkpoints serve as dispute evidence.
     */
    ISupplyChain public immutable supplyChain;

    /**
     * @notice Settlement tokens and USD conversion.
     */
    ICurrencyManager public immutable currencies;

    /**
     * @notice The marketplace allowed to open orders.
     */
    address public marketplace;

    /**
     * @notice Account credited with platform fees.
     */
    address public treasury;

    /**
     * @notice Platform fee for new orders, in basis points.
     */
    uint16 public feeBps;

    /**
     * @notice Dispute window for new orders: time after delivery in which the buyer can dispute.
     */
    uint32 public disputeWindow = 3 days;

    /**
     * @dev Certificate types a lot must hold to be sold and settled.
     */
    bytes32[] private _requiredCertTypes;

    /**
     * @dev Next order id; ids start at 1 so that 0 means "none".
     */
    uint256 private _nextOrderId = 1;

    /**
     * @dev Order id => order.
     */
    mapping(uint256 orderId => EscrowLib.Order) private _orders;

    /**
     * @dev Order id => dispute.
     */
    mapping(uint256 orderId => EscrowLib.Dispute) private _disputes;

    /**
     * @dev Order id => evidence submitted, in order.
     */
    mapping(uint256 orderId => EscrowLib.Evidence[]) private _evidence;

    /**
     * @dev Order id => checkpoint index => already cited as evidence.
     */
    mapping(uint256 orderId => mapping(uint256 checkpointIndex => bool)) private _usedCheckpoint;

    /**
     * @notice The open order a lot is locked under (0 if none).
     */
    mapping(uint256 tokenId => uint256 orderId) public activeOrderOf;

    /**
     * @notice Balances owed to buyers, sellers and the treasury (pull pattern).
     */
    mapping(IERC20 token => mapping(address account => uint256)) public claimable;

    /**
     * @notice Where the seller wants the goods of an order `AwaitingReturn` sent back (e.g. its warehouse), for sellers
     * whose own accounts do not hold custody (a miner's goods go back to a warehouse). Zero: the seller's own
     * organisation.
     */
    mapping(uint256 orderId => address custodian) public returnTo;

    /**
     * @notice Restricts a function to {MineNetRegistry} admins.
     */
    modifier onlyAdmin() {
        _onlyAdmin();
        _;
    }

    /**
     * @param registry_ Participant, role and permission registry.
     * @param passport_ Lot passport.
     * @param certificates_ Certificate registry.
     * @param supplyChain_ Supply-chain ledger.
     * @param currencies_ Currency manager.
     * @param treasury_ Fee recipient; non-zero.
     * @param feeBps_ Initial platform fee, in basis points; at most {MAX_FEE_BPS}.
     */
    constructor(
        IMineNetRegistry registry_,
        ILotPassport passport_,
        ICertificateRegistry certificates_,
        ISupplyChain supplyChain_,
        ICurrencyManager currencies_,
        address treasury_,
        uint16 feeBps_
    ) {
        if (treasury_ == address(0)) revert EscrowLib.EscrowManager__ZeroAddress();
        if (feeBps_ > MAX_FEE_BPS) revert EscrowLib.EscrowManager__InvalidFee();
        registry = registry_;
        passport = passport_;
        certificates = certificates_;
        supplyChain = supplyChain_;
        currencies = currencies_;
        treasury = treasury_;
        feeBps = feeBps_;
    }

    /*//////////////////////////////////////////////////////////////
      ADMIN (PLATFORM PARAMETERS ONLY: NO POWER OVER ORDERS OR DISPUTES)
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Sets the marketplace allowed to open orders.
     * @dev Only a {MineNetRegistry} admin. In production, put this setter behind a timelock.
     * @param marketplace_ Marketplace contract; non-zero.
     * @custom:emits MarketplaceSet
     */
    function setMarketplace(address marketplace_) external onlyAdmin {
        if (marketplace_ == address(0)) revert EscrowLib.EscrowManager__ZeroAddress();
        marketplace = marketplace_;
        emit EscrowLib.MarketplaceSet(marketplace_);
    }

    /**
     * @notice Sets the platform fee and treasury. New fees apply only to orders opened afterwards.
     * @dev Only a {MineNetRegistry} admin.
     * @param feeBps_ Fee, in basis points; at most {MAX_FEE_BPS}.
     * @param treasury_ Fee recipient; non-zero.
     * @custom:emits FeeUpdated
     */
    function setFee(uint16 feeBps_, address treasury_) external onlyAdmin {
        if (feeBps_ > MAX_FEE_BPS) revert EscrowLib.EscrowManager__InvalidFee();
        if (treasury_ == address(0)) revert EscrowLib.EscrowManager__ZeroAddress();
        feeBps = feeBps_;
        treasury = treasury_;
        emit EscrowLib.FeeUpdated(feeBps_, treasury_);
    }

    /**
     * @notice Sets the dispute window. New windows apply only to orders opened afterwards.
     * @dev Only a {MineNetRegistry} admin.
     * @param window Window, in seconds; within `[MIN_DISPUTE_WINDOW, MAX_DISPUTE_WINDOW]`.
     * @custom:emits DisputeWindowUpdated
     */
    function setDisputeWindow(uint32 window) external onlyAdmin {
        if (window < MIN_DISPUTE_WINDOW || window > MAX_DISPUTE_WINDOW) {
            revert EscrowLib.EscrowManager__InvalidWindow();
        }
        disputeWindow = window;
        emit EscrowLib.DisputeWindowUpdated(window);
    }

    /**
     * @notice Sets the certificate types a lot must hold to be sold and settled (e.g. EXPORT_PERMIT,
     * CONFLICT_FREE).
     * @dev Only a {MineNetRegistry} admin.
     * @param certTypes Certificate types.
     * @custom:emits RequiredCertTypesUpdated
     */
    function setRequiredCertTypes(bytes32[] calldata certTypes) external onlyAdmin {
        _requiredCertTypes = certTypes;
        emit EscrowLib.RequiredCertTypesUpdated(certTypes);
    }

    /**
     * @notice Pauses opening, releasing and settling orders.
     * @dev Only a {MineNetRegistry} admin. Withdrawals, refunds and dispute resolution keep working.
     */
    function pause() external onlyAdmin {
        _pause();
    }

    /**
     * @notice Resumes opening, releasing and settling orders.
     * @dev Only a {MineNetRegistry} admin.
     */
    function unpause() external onlyAdmin {
        _unpause();
    }

    /*//////////////////////////////////////////////////////////////
                        MARKETPLACE: OPEN AN ORDER
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Opens a funded order, locking the lot and pulling the payment in.
     * @dev Only the marketplace. The payment is always pulled from the marketplace, never from a third party.
     * Locking the lot needs the seller's passport approval to this contract (its consent). The fee, dispute window
     * and grade at sale are snapshotted.
     * @param p Order parameters.
     * @return orderId New order id.
     * @custom:emits OrderOpened
     */
    function openOrder(EscrowLib.OpenParams calldata p) external nonReentrant whenNotPaused returns (uint256 orderId) {
        if (msg.sender != marketplace) revert EscrowLib.EscrowManager__NotMarketplace(msg.sender);
        if (!currencies.isSettlementToken(p.paymentToken)) {
            revert EscrowLib.EscrowManager__TokenNotAllowed(p.paymentToken);
        }
        if (p.amount == 0) revert EscrowLib.EscrowManager__InvalidAmount();
        if (p.deliveryWindow < MIN_DELIVERY_WINDOW || p.deliveryWindow > MAX_DELIVERY_WINDOW) {
            revert EscrowLib.EscrowManager__InvalidWindow();
        }
        if (p.buyer == p.seller) revert EscrowLib.EscrowManager__SelfDealing();
        if (!registry.isAuthorized(p.buyer, Actions.BUY_LOT)) revert EscrowLib.EscrowManager__Unauthorized(p.buyer);
        if (!registry.isAuthorized(p.seller, Actions.SELL_LOT)) revert EscrowLib.EscrowManager__Unauthorized(p.seller);
        if (passport.ownerOf(p.tokenId) != p.seller) {
            revert EscrowLib.EscrowManager__SellerNotOwner(p.tokenId, p.seller);
        }
        if (!_certificatesValid(p.tokenId)) revert EscrowLib.EscrowManager__MissingCertificates(p.tokenId);

        orderId = _nextOrderId++;
        uint64 deadline = uint64(block.timestamp) + p.deliveryWindow;
        uint256 usdValue = currencies.tokenToUsd(p.paymentToken, p.amount);
        _orders[orderId] = EscrowLib.Order({
            tokenId: p.tokenId,
            buyer: p.buyer,
            seller: p.seller,
            paymentToken: p.paymentToken,
            amount: p.amount,
            usdValue: usdValue,
            feeBps: feeBps,
            gradeAtSale: supplyChain.latestGrade(p.tokenId).gradeBps,
            disputeWindow: disputeWindow,
            createdAt: uint64(block.timestamp),
            deliveryDeadline: deadline,
            deliveredAt: 0,
            returnDeadline: 0,
            status: EscrowLib.OrderStatus.Active,
            titlePending: false,
            termsHash: p.termsHash
        });
        activeOrderOf[p.tokenId] = orderId;

        passport.lockForEscrow(p.tokenId); // reverts if frozen, already locked, or not approved by the seller
        p.paymentToken.safeTransferFrom(msg.sender, address(this), p.amount);

        emit EscrowLib.OrderOpened(orderId, p.tokenId, p.buyer, p.seller, p.paymentToken, p.amount, usdValue, deadline);
    }

    /*//////////////////////////////////////////////////////////////
                          DELIVERY & SETTLEMENT
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Records delivery once custody of the lot reached the buyer's organisation on the passport.
     * @dev Callable by anyone while the order is active or disputed; a no-op if already recorded. The delivery time
     * is when custody first reached the buyer's organisation under this order, as the passport recorded it, so it
     * stays proven even if the buyer has since passed the goods on (e.g. to a warehouse).
     * @param orderId Order id.
     * @custom:emits DeliveryConfirmed
     */
    function confirmDelivery(uint256 orderId) public {
        EscrowLib.Order storage o = _orders[orderId];
        if (o.status != EscrowLib.OrderStatus.Active && o.status != EscrowLib.OrderStatus.Disputed) {
            revert EscrowLib.EscrowManager__InvalidState(orderId, o.status);
        }
        if (o.deliveredAt != 0) return;
        uint64 reachedAt = _reachedBuyerAt(o);
        if (reachedAt == 0) revert EscrowLib.EscrowManager__NotDelivered(orderId);
        o.deliveredAt = reachedAt;
        emit EscrowLib.DeliveryConfirmed(orderId, reachedAt);
    }

    /**
     * @notice The buyer accepts delivery and releases payment without waiting for the dispute window.
     * @dev Only the buyer, once custody reached its organisation and the required certificates are still valid.
     * @param orderId Order id.
     * @custom:emits DeliveryConfirmed (if not yet recorded)
     * @custom:emits OrderSettled
     */
    function releaseFunds(uint256 orderId) external nonReentrant whenNotPaused {
        EscrowLib.Order storage o = _orders[orderId];
        if (msg.sender != o.buyer) revert EscrowLib.EscrowManager__Unauthorized(msg.sender);
        _requireStatus(orderId, EscrowLib.OrderStatus.Active);
        confirmDelivery(orderId);
        _requireCertificates(o.tokenId);
        o.status = EscrowLib.OrderStatus.Settled;
        _payout(orderId, 0, true, false);
    }

    /**
     * @notice Settles an order once the dispute window has passed since delivery.
     * @dev Callable by anyone; records the delivery first if nobody did. The required certificates must still be
     * valid.
     * @param orderId Order id.
     * @custom:emits DeliveryConfirmed (if not yet recorded)
     * @custom:emits OrderSettled
     */
    function settle(uint256 orderId) external nonReentrant whenNotPaused {
        EscrowLib.Order storage o = _orders[orderId];
        _requireStatus(orderId, EscrowLib.OrderStatus.Active);
        confirmDelivery(orderId);
        if (block.timestamp < uint256(o.deliveredAt) + o.disputeWindow) {
            revert EscrowLib.EscrowManager__DisputeWindowOpen(orderId);
        }
        _requireCertificates(o.tokenId);
        o.status = EscrowLib.OrderStatus.Settled;
        _payout(orderId, 0, true, false);
    }

    /**
     * @notice Refunds the buyer in full and unlocks the lot when it was not delivered by the deadline.
     * @dev Only the buyer, after the deadline, and only if custody never reached the buyer's organisation under this
     * order (passing the goods on after receiving them does not count as non-delivery).
     * @param orderId Order id.
     * @custom:emits OrderRefunded
     */
    function cancelForNonDelivery(uint256 orderId) external nonReentrant {
        EscrowLib.Order storage o = _orders[orderId];
        if (msg.sender != o.buyer) revert EscrowLib.EscrowManager__Unauthorized(msg.sender);
        _requireStatus(orderId, EscrowLib.OrderStatus.Active);
        if (block.timestamp <= o.deliveryDeadline) revert EscrowLib.EscrowManager__DeadlineNotReached(orderId);
        if (o.deliveredAt != 0 || _reachedBuyerAt(o) != 0) {
            revert EscrowLib.EscrowManager__InvalidState(orderId, o.status);
        }
        o.status = EscrowLib.OrderStatus.Refunded;
        _payout(orderId, o.amount, false, false);
    }

    /*//////////////////////////////////////////////////////////////
         DISPUTES: EVIDENCE FROM BOTH SIDES, JUDGED BY DISPUTELIB
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice The buyer opens a dispute; the evidence period starts.
     * @dev Only the buyer, once per order. After delivery it must be within the dispute window.
     * @param orderId Order id.
     * @param claimHash Hash of the claim.
     * @custom:emits DisputeOpened
     */
    function openDispute(uint256 orderId, bytes32 claimHash) external {
        EscrowLib.Order storage o = _orders[orderId];
        if (msg.sender != o.buyer) revert EscrowLib.EscrowManager__Unauthorized(msg.sender);
        _requireStatus(orderId, EscrowLib.OrderStatus.Active);
        if (o.deliveredAt != 0 && block.timestamp >= uint256(o.deliveredAt) + o.disputeWindow) {
            revert EscrowLib.EscrowManager__DisputeWindowClosed(orderId);
        }
        EscrowLib.Dispute storage d = _disputes[orderId];
        if (d.openedAt != 0) revert EscrowLib.EscrowManager__AlreadyDisputed(orderId); // one dispute per order
        uint64 deadline = uint64(block.timestamp) + EVIDENCE_PERIOD;
        o.status = EscrowLib.OrderStatus.Disputed;
        d.openedAt = uint64(block.timestamp);
        d.evidenceDeadline = deadline;
        d.claimHash = claimHash;
        emit EscrowLib.DisputeOpened(orderId, claimHash, deadline);
    }

    /**
     * @notice The seller contests the claim without (or before) submitting evidence.
     * @dev Only the seller, during the evidence period. Without any response or evidence from the seller, the
     * default verdict (full refund) applies.
     * @param orderId Order id.
     * @param responseHash Hash of the response.
     * @custom:emits DisputeResponded
     */
    function respondToDispute(uint256 orderId, bytes32 responseHash) external {
        EscrowLib.Order storage o = _orders[orderId];
        if (msg.sender != o.seller) revert EscrowLib.EscrowManager__Unauthorized(msg.sender);
        EscrowLib.Dispute storage d = _openDisputeFor(orderId);
        d.sellerResponded = true;
        d.responseHash = responseHash;
        emit EscrowLib.DisputeResponded(orderId, responseHash);
    }

    /**
     * @notice Puts a piece of evidence forward.
     * @dev Either party, during the evidence period, up to {MAX_EVIDENCE_PER_SIDE} each. A cited checkpoint must
     * belong to the lot, be recorded after the sale, and not have been cited before. Seller evidence counts as a
     * response.
     * @param orderId Order id.
     * @param onChain True to cite a {SupplyChain} checkpoint of the lot (judged); false for a document only.
     * @param checkpointIndex The checkpoint's index in the lot's log (ignored if `onChain` is false).
     * @param docHash Hash of the supporting document (required for document-only evidence).
     * @return index Position of the evidence in the order's list.
     * @custom:emits EvidenceSubmitted
     */
    function submitEvidence(uint256 orderId, bool onChain, uint32 checkpointIndex, bytes32 docHash)
        external
        returns (uint256 index)
    {
        EscrowLib.Order storage o = _orders[orderId];
        bool fromBuyer = msg.sender == o.buyer;
        if (!fromBuyer && msg.sender != o.seller) revert EscrowLib.EscrowManager__Unauthorized(msg.sender);
        EscrowLib.Dispute storage d = _openDisputeFor(orderId);

        if (fromBuyer) {
            if (d.buyerEvidenceCount >= MAX_EVIDENCE_PER_SIDE) {
                revert EscrowLib.EscrowManager__TooMuchEvidence(orderId);
            }
            d.buyerEvidenceCount += 1;
        } else {
            if (d.sellerEvidenceCount >= MAX_EVIDENCE_PER_SIDE) {
                revert EscrowLib.EscrowManager__TooMuchEvidence(orderId);
            }
            d.sellerEvidenceCount += 1;
            d.sellerResponded = true;
        }

        DisputeLib.Fact memory fact;
        if (onChain) {
            fact = _factOf(orderId, o, checkpointIndex);
        } else if (docHash == bytes32(0)) {
            revert EscrowLib.EscrowManager__EmptyEvidence();
        }

        index = _evidence[orderId].length;
        _evidence[orderId].push(
            EscrowLib.Evidence({
                submittedBy: msg.sender,
                fromBuyer: fromBuyer,
                onChain: onChain,
                checkpointIndex: onChain ? checkpointIndex : 0,
                submittedAt: uint64(block.timestamp),
                docHash: docHash,
                fact: fact
            })
        );
        emit EscrowLib.EvidenceSubmitted(
            orderId, index, msg.sender, onChain, checkpointIndex, fact.independent, docHash
        );
    }

    /**
     * @notice The buyer drops the claim for good. The order returns to `Active`, and its timers keep running.
     * @dev Only the buyer. A withdrawn dispute cannot be reopened.
     * @param orderId Order id.
     * @custom:emits DisputeWithdrawn
     */
    function withdrawDispute(uint256 orderId) external {
        EscrowLib.Order storage o = _orders[orderId];
        if (msg.sender != o.buyer) revert EscrowLib.EscrowManager__Unauthorized(msg.sender);
        _requireStatus(orderId, EscrowLib.OrderStatus.Disputed);
        o.status = EscrowLib.OrderStatus.Active;
        emit EscrowLib.DisputeWithdrawn(orderId);
    }

    /**
     * @notice Judges a dispute once the evidence period is over and executes the verdict.
     * @dev Callable by anyone. Reverts while the verdict is `Pending` (no custody yet and the deadline has not
     * passed). A refund owed to a buyer who already received the goods is not paid at once: the order waits in
     * `AwaitingReturn` until the goods are back with the seller ({completeReturn}); if the buyer keeps them past
     * {RETURN_WINDOW}, the sale completes instead ({claimUnreturned}). A frozen lot cannot move (it is under the
     * regulator's control), so its refund is paid at once.
     * @param orderId Order id.
     * @return verdict The verdict executed.
     * @custom:emits DisputeResolved
     * @custom:emits OrderSettled or OrderRefunded
     */
    function resolveDispute(uint256 orderId) external nonReentrant returns (DisputeLib.Verdict verdict) {
        EscrowLib.Order storage o = _orders[orderId];
        _requireStatus(orderId, EscrowLib.OrderStatus.Disputed);
        EscrowLib.Dispute storage d = _disputes[orderId];
        if (block.timestamp <= d.evidenceDeadline) {
            revert EscrowLib.EscrowManager__EvidencePeriodOpen(orderId, d.evidenceDeadline);
        }

        uint256 refund;
        bool lotToBuyer;
        (verdict, refund, lotToBuyer) = DisputeLib.judge(_buildCase(orderId));
        if (verdict == DisputeLib.Verdict.Pending) revert EscrowLib.EscrowManager__VerdictPending(orderId);
        if (lotToBuyer && o.deliveredAt == 0) o.deliveredAt = uint64(block.timestamp);

        DisputeLib.Winner winner = DisputeLib.winnerOf(verdict, refund, o.amount);
        d.verdict = verdict;
        d.winner = winner;
        d.buyerRefund = refund;
        if (!lotToBuyer && _reachedBuyerAt(o) != 0 && !_heldBySeller(o) && !passport.isFrozen(o.tokenId)) {
            // goods with the buyer's side: the refund waits for their return
            uint64 deadline = uint64(block.timestamp) + RETURN_WINDOW;
            o.status = EscrowLib.OrderStatus.AwaitingReturn;
            o.returnDeadline = deadline;
            emit EscrowLib.DisputeResolved(orderId, verdict, winner, refund, 0, false);
            emit EscrowLib.ReturnRequired(orderId, deadline);
            return verdict;
        }
        o.status = EscrowLib.OrderStatus.Resolved;
        uint256 sellerAmount = _payout(orderId, refund, lotToBuyer, true);
        emit EscrowLib.DisputeResolved(orderId, verdict, winner, refund, sellerAmount, lotToBuyer);
    }

    /**
     * @notice The seller names the custodian (e.g. its warehouse) the buyer must return the goods to.
     * @dev Only the seller, while the order is `AwaitingReturn`. The custodian must be able to hold custody and must
     * be outside the buyer's organisation.
     * @param orderId Order id.
     * @param custodian Return custodian.
     * @custom:emits ReturnAddressSet
     */
    function setReturnAddress(uint256 orderId, address custodian) external {
        EscrowLib.Order storage o = _orders[orderId];
        if (msg.sender != o.seller) revert EscrowLib.EscrowManager__Unauthorized(msg.sender);
        _requireStatus(orderId, EscrowLib.OrderStatus.AwaitingReturn);
        if (!registry.isAuthorized(custodian, Actions.HOLD_CUSTODY) || registry.sameOrg(custodian, o.buyer)) {
            revert EscrowLib.EscrowManager__Unauthorized(custodian);
        }
        returnTo[orderId] = custodian;
        emit EscrowLib.ReturnAddressSet(orderId, custodian);
    }

    /**
     * @notice Releases the buyer's refund once the goods of a refunded order are back with the seller.
     * @dev Callable by anyone while the order is `AwaitingReturn` and the lot's custodian is in the seller's
     * organisation or is the seller's return custodian ({setReturnAddress}), or the lot was frozen meanwhile (it is then under the regulator's control and cannot move). The
     * lot is unlocked for the seller.
     * @param orderId Order id.
     * @custom:emits GoodsReturned
     * @custom:emits OrderRefunded or OrderSettled
     */
    function completeReturn(uint256 orderId) external nonReentrant {
        EscrowLib.Order storage o = _orders[orderId];
        _requireStatus(orderId, EscrowLib.OrderStatus.AwaitingReturn);
        if (!_returned(orderId, o) && !passport.isFrozen(o.tokenId)) {
            revert EscrowLib.EscrowManager__NotReturned(orderId);
        }
        o.status = EscrowLib.OrderStatus.Resolved;
        emit EscrowLib.GoodsReturned(orderId);
        _payout(orderId, _disputes[orderId].buyerRefund, false, false);
    }

    /**
     * @notice The buyer kept the goods past the return deadline: the sale completes as if no refund were due.
     * @dev Callable by anyone after {RETURN_WINDOW}, while the goods are not back with the seller. The seller is
     * paid in full and the title passes to the buyer (deferred while the lot is frozen).
     * @param orderId Order id.
     * @custom:emits ReturnDefaulted
     * @custom:emits OrderSettled
     */
    function claimUnreturned(uint256 orderId) external nonReentrant {
        EscrowLib.Order storage o = _orders[orderId];
        _requireStatus(orderId, EscrowLib.OrderStatus.AwaitingReturn);
        if (block.timestamp <= o.returnDeadline) {
            revert EscrowLib.EscrowManager__ReturnWindowOpen(orderId, o.returnDeadline);
        }
        if (_returned(orderId, o) || passport.isFrozen(o.tokenId)) {
            revert EscrowLib.EscrowManager__InvalidState(orderId, o.status);
        }
        o.status = EscrowLib.OrderStatus.Resolved;
        _disputes[orderId].buyerRefund = 0;
        emit EscrowLib.ReturnDefaulted(orderId);
        _payout(orderId, 0, true, true);
    }

    /**
     * @notice Completes a title transfer that waited for the lot to be unfrozen.
     * @dev Callable by anyone; reverts while the lot is still frozen.
     * @param orderId Order id.
     * @custom:emits TitleFinalized
     */
    function finalizeTitle(uint256 orderId) external nonReentrant {
        EscrowLib.Order storage o = _orders[orderId];
        if (!o.titlePending) revert EscrowLib.EscrowManager__TitleNotPending(orderId);
        o.titlePending = false;
        delete activeOrderOf[o.tokenId];
        passport.escrowTransfer(o.tokenId, o.buyer); // reverts while still frozen
        emit EscrowLib.TitleFinalized(orderId, o.tokenId);
    }

    /**
     * @notice The verdict and winner the evidence gives right now.
     * @param orderId Disputed order.
     * @return verdict Current verdict (`Pending` while it cannot be decided yet).
     * @return winner Winning side.
     * @return buyerRefund Amount that would be refunded to the buyer.
     * @return lotToBuyer Whether the lot would go to the buyer.
     */
    function evaluateDispute(uint256 orderId)
        external
        view
        returns (DisputeLib.Verdict verdict, DisputeLib.Winner winner, uint256 buyerRefund, bool lotToBuyer)
    {
        _requireStatus(orderId, EscrowLib.OrderStatus.Disputed);
        (verdict, buyerRefund, lotToBuyer) = DisputeLib.judge(_buildCase(orderId));
        winner = DisputeLib.winnerOf(verdict, buyerRefund, _orders[orderId].amount);
    }

    /*//////////////////////////////////////////////////////////////
                               WITHDRAWALS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Withdraws the caller's credited balance of `token`.
     * @param token Settlement token.
     * @custom:emits Withdrawn
     */
    function withdraw(IERC20 token) external nonReentrant {
        uint256 amount = claimable[token][msg.sender];
        if (amount == 0) revert EscrowLib.EscrowManager__NothingToWithdraw();
        claimable[token][msg.sender] = 0;
        token.safeTransfer(msg.sender, amount);
        emit EscrowLib.Withdrawn(token, msg.sender, amount);
    }

    /*//////////////////////////////////////////////////////////////
                                  VIEWS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns an order.
     * @param orderId Order id.
     * @return The order (status `None` if unknown).
     */
    function getOrder(uint256 orderId) external view returns (EscrowLib.Order memory) {
        return _orders[orderId];
    }

    /**
     * @notice Returns an order's dispute.
     * @param orderId Order id.
     * @return The dispute (all zero if none).
     */
    function getDispute(uint256 orderId) external view returns (EscrowLib.Dispute memory) {
        return _disputes[orderId];
    }

    /**
     * @notice Returns all evidence submitted for an order.
     * @param orderId Order id.
     * @return The evidence, in submission order.
     */
    function getEvidence(uint256 orderId) external view returns (EscrowLib.Evidence[] memory) {
        return _evidence[orderId];
    }

    /**
     * @notice Certificate types a lot must hold to be sold and settled.
     * @return Certificate types.
     */
    function requiredCertTypes() external view returns (bytes32[] memory) {
        return _requiredCertTypes;
    }

    /*//////////////////////////////////////////////////////////////
                                 INTERNAL
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Snapshots the facts of a checkpoint cited as evidence, after checking that it belongs to the lot, was
     * recorded after the sale, and has not been cited before in this dispute.
     * @param orderId Order id.
     * @param o The order.
     * @param checkpointIndex Checkpoint index in the lot's log.
     * @return fact The snapshotted fact.
     */
    function _factOf(uint256 orderId, EscrowLib.Order storage o, uint32 checkpointIndex)
        private
        returns (DisputeLib.Fact memory fact)
    {
        if (checkpointIndex >= supplyChain.checkpointCount(o.tokenId)) {
            revert EscrowLib.EscrowManager__UnknownCheckpoint(o.tokenId, checkpointIndex);
        }
        if (_usedCheckpoint[orderId][checkpointIndex]) {
            revert EscrowLib.EscrowManager__DuplicateEvidence(orderId, checkpointIndex);
        }
        SupplyChainLib.Checkpoint memory cp = supplyChain.getCheckpoint(o.tokenId, checkpointIndex);
        if (cp.timestamp < o.createdAt) revert EscrowLib.EscrowManager__EvidenceBeforeSale(orderId, checkpointIndex);
        _usedCheckpoint[orderId][checkpointIndex] = true;

        fact = DisputeLib.Fact({
            cpType: cp.cpType,
            condition: cp.condition,
            withinTolerance: cp.withinTolerance,
            independent: !registry.sameOrg(cp.signer, o.buyer) && !registry.sameOrg(cp.signer, o.seller),
            gradeBps: cp.gradeBps,
            timestamp: cp.timestamp,
            measuredQty: cp.measuredQty,
            referenceQty: cp.referenceQty
        });
    }

    /**
     * @dev Assembles the {DisputeLib.Case} for an order from its state and on-chain evidence.
     * @param orderId Order id.
     * @return c The case.
     */
    function _buildCase(uint256 orderId) private view returns (DisputeLib.Case memory c) {
        EscrowLib.Order storage o = _orders[orderId];
        EscrowLib.Dispute storage d = _disputes[orderId];
        EscrowLib.Evidence[] storage ev = _evidence[orderId];

        c.amount = o.amount;
        c.gradeAtSale = o.gradeAtSale;
        c.deliveryDeadline = o.deliveryDeadline;
        c.now_ = uint64(block.timestamp);
        c.sellerResponded = d.sellerResponded;
        c.delivered = o.deliveredAt != 0 || _reachedBuyerAt(o) != 0;
        c.certificatesValid = _certificatesValid(o.tokenId);

        uint256 nb;
        uint256 ns;
        for (uint256 i; i < ev.length; ++i) {
            if (!ev[i].onChain) continue;
            if (ev[i].fromBuyer) ++nb;
            else ++ns;
        }
        c.buyerFacts = new DisputeLib.Fact[](nb);
        c.sellerFacts = new DisputeLib.Fact[](ns);
        nb = 0;
        ns = 0;
        for (uint256 i; i < ev.length; ++i) {
            if (!ev[i].onChain) continue;
            if (ev[i].fromBuyer) c.buyerFacts[nb++] = ev[i].fact;
            else c.sellerFacts[ns++] = ev[i].fact;
        }
    }

    /**
     * @dev Pays out an order: `buyerRefund` to the buyer, the rest to the seller minus the fee. The lot either
     * moves
     * to the buyer or is unlocked and stays with the seller. After a dispute verdict a frozen lot keeps its lock
     * and
     * the title transfer waits ({finalizeTitle}). The caller sets the status first (checks-effects-interactions).
     * @param orderId Order id.
     * @param buyerRefund Amount refunded to the buyer.
     * @param lotToBuyer Whether the lot goes to the buyer.
     * @param deferTitleIfFrozen Whether to defer the transfer of a frozen lot instead of reverting.
     * @return sellerAmount Amount credited to the seller.
     */
    function _payout(uint256 orderId, uint256 buyerRefund, bool lotToBuyer, bool deferTitleIfFrozen)
        private
        returns (uint256 sellerAmount)
    {
        EscrowLib.Order storage o = _orders[orderId];

        uint256 sellerGross = o.amount - buyerRefund;
        uint256 fee = (sellerGross * o.feeBps) / 10_000;
        sellerAmount = sellerGross - fee;
        if (buyerRefund != 0) claimable[o.paymentToken][registry.payoutOf(o.buyer)] += buyerRefund;
        if (sellerAmount != 0) claimable[o.paymentToken][registry.payoutOf(o.seller)] += sellerAmount;
        if (fee != 0) claimable[o.paymentToken][treasury] += fee;

        if (lotToBuyer && deferTitleIfFrozen && passport.isFrozen(o.tokenId)) {
            o.titlePending = true; // keep the lock: only this order can complete the transfer
            emit EscrowLib.TitlePending(orderId, o.tokenId);
        } else {
            delete activeOrderOf[o.tokenId];
            if (lotToBuyer) passport.escrowTransfer(o.tokenId, o.buyer); // reverts if the lot is frozen
            else passport.unlockFromEscrow(o.tokenId);
        }

        if (buyerRefund == o.amount) emit EscrowLib.OrderRefunded(orderId, buyerRefund);
        else emit EscrowLib.OrderSettled(orderId, sellerAmount, fee);
    }

    /**
     * @dev Returns a disputed order's dispute, reverting if the evidence period has closed.
     * @param orderId Order id.
     * @return d Storage pointer to the dispute.
     */
    function _openDisputeFor(uint256 orderId) private view returns (EscrowLib.Dispute storage d) {
        _requireStatus(orderId, EscrowLib.OrderStatus.Disputed);
        d = _disputes[orderId];
        if (block.timestamp > d.evidenceDeadline) revert EscrowLib.EscrowManager__EvidencePeriodClosed(orderId);
    }

    /**
     * @dev When custody of the order's lot first reached the buyer's organisation under this order (0 = never).
     * @param o The order.
     * @return The time.
     */
    function _reachedBuyerAt(EscrowLib.Order storage o) private view returns (uint64) {
        return passport.custodyReachedAt(o.tokenId, registry.participant(o.buyer).orgId);
    }

    /**
     * @dev Whether the order's lot is currently held by the seller's organisation.
     * @param o The order.
     * @return True if the custodian is in the seller's organisation.
     */
    function _heldBySeller(EscrowLib.Order storage o) private view returns (bool) {
        return registry.sameOrg(passport.custodianOf(o.tokenId), o.seller);
    }

    /**
     * @dev Whether the goods of an order are back: with the seller's organisation or its return custodian.
     * @param orderId Order id.
     * @param o The order.
     * @return True if returned.
     */
    function _returned(uint256 orderId, EscrowLib.Order storage o) private view returns (bool) {
        address custodian = returnTo[orderId];
        return _heldBySeller(o) || (custodian != address(0) && passport.custodianOf(o.tokenId) == custodian);
    }

    /**
     * @dev Reverts unless the order is in `expected` status.
     * @param orderId Order id.
     * @param expected Required status.
     */
    function _requireStatus(uint256 orderId, EscrowLib.OrderStatus expected) private view {
        EscrowLib.OrderStatus s = _orders[orderId].status;
        if (s != expected) revert EscrowLib.EscrowManager__InvalidState(orderId, s);
    }

    /**
     * @dev Whether a lot holds every required certificate.
     * @param tokenId Lot.
     * @return True if valid (or none are required).
     */
    function _certificatesValid(uint256 tokenId) private view returns (bool) {
        return _requiredCertTypes.length == 0 || certificates.hasValidCertificates(tokenId, _requiredCertTypes);
    }

    /**
     * @dev Reverts unless a lot holds every required certificate.
     * @param tokenId Lot.
     */
    function _requireCertificates(uint256 tokenId) private view {
        if (!_certificatesValid(tokenId)) revert EscrowLib.EscrowManager__MissingCertificates(tokenId);
    }

    /**
     * @dev Reverts unless the caller is a {MineNetRegistry} admin.
     */
    function _onlyAdmin() private view {
        if (!registry.isAdmin(msg.sender)) {
            revert EscrowLib.EscrowManager__NotRegistryAdmin(msg.sender);
        }
    }
}
