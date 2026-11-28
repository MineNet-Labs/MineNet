// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {IMineNetRegistry} from "src/access/interfaces/IMineNetRegistry.sol";
import {ILotPassport} from "src/traceability/interfaces/ILotPassport.sol";
import {ISupplyChain} from "src/traceability/interfaces/ISupplyChain.sol";
import {IEscrowManager} from "src/trade/interfaces/IEscrowManager.sol";
import {ICurrencyManager} from "src/finance/interfaces/ICurrencyManager.sol";
import {Actions} from "src/access/libraries/Actions.sol";
import {MarketplaceLib} from "src/trade/libraries/MarketplaceLib.sol";
import {EscrowLib} from "src/trade/libraries/EscrowLib.sol";
import {PassportLib} from "src/traceability/libraries/PassportLib.sol";
import {CurrencyLib} from "src/finance/libraries/CurrencyLib.sol";

/**
 * @title Marketplace
 * @author 0xEmmyb2
 * @notice The MineNet marketplace for verified mineral lots (project.md 4.2, 6.4 steps 7 and 8).
 * @dev Listings (sellers):
 * - {createListing}: list an inspected lot at a fixed total or per kg of its trusted weight, priced in USD or in
 *   the seller's local currency (e.g. RWF), paid in USDC or a local stablecoin.
 * - {updateListing}: change currency, pricing model, price, delivery window, expiry or terms in place.
 * - {updatePrice}: reprice only.
 * - {delist}: take the lot off the market.
 *
 * Purchases (buyers):
 * - {buyListing}: pay the quote (converted at the live exchange rate) into escrow, with a `maxTotal` guard
 *   against repricing and exchange-rate moves.
 *
 * Buy requests (reverse market): {createBuyRequest}, {claimBuyRequest} and {cancelBuyRequest}, priced in the
 * payment token. A request can be filled by several lots until less than its minimum lot weight is left.
 *
 * Negotiated sales: offers and counter-offers happen off-chain; the final terms are signed by one party (EIP-712,
 * EIP-1271 for contract wallets) and submitted by the other ({acceptOffer}), which opens the escrow order. Each
 * signer nonce works once and can be cancelled ({cancelOfferNonce}).
 *
 * The lot stays in the seller's wallet while listed; a sale locks it inside {EscrowManager} (which is why sellers
 * approve the escrow on the passport). Payment, delivery, settlement and decentralised disputes all happen in
 * {EscrowManager}. Types, events, errors and pricing maths live in {MarketplaceLib}.
 */
contract Marketplace is ReentrancyGuardTransient, Pausable, EIP712 {
    using SafeERC20 for IERC20;

    /**
     * @notice EIP-712 type hash of {MarketplaceLib-Offer}.
     */
    bytes32 public constant OFFER_TYPEHASH = keccak256(
        "Offer(uint256 tokenId,address seller,address buyer,address paymentToken,uint256 amount,uint32 deliveryWindow,uint64 deadline,uint256 nonce,bytes32 termsHash)"
    );

    /**
     * @notice Participant, role and permission registry.
     */
    IMineNetRegistry public immutable registry;

    /**
     * @notice Lot passport.
     */
    ILotPassport public immutable passport;

    /**
     * @notice Supply-chain ledger (trusted weights and grades).
     */
    ISupplyChain public immutable supplyChain;

    /**
     * @notice Escrow that holds payments and lots under an order.
     */
    IEscrowManager public immutable escrow;

    /**
     * @notice Currencies, settlement tokens and conversion.
     */
    ICurrencyManager public immutable currencies;

    /**
     * @dev Next listing id; ids start at 1 so that 0 means "none".
     */
    uint256 private _nextListingId = 1;

    /**
     * @dev Next buy-request id; ids start at 1 so that 0 means "none".
     */
    uint256 private _nextRequestId = 1;

    /**
     * @dev Listing id => listing.
     */
    mapping(uint256 listingId => MarketplaceLib.Listing) private _listings;

    /**
     * @dev Request id => buy request.
     */
    mapping(uint256 requestId => MarketplaceLib.BuyRequest) private _requests;

    /**
     * @notice The current listing of a lot (0 if none). It may have expired; see {isListingLive}.
     */
    mapping(uint256 tokenId => uint256 listingId) public listingOf;

    /**
     * @notice The currency a seller quotes in by default (0 = USD).
     */
    mapping(address account => bytes32 currency) public preferredCurrency;

    /**
     * @notice Buy-request refunds owed to buyers (pull pattern).
     */
    mapping(IERC20 token => mapping(address account => uint256)) public claimable;

    /**
     * @notice Offer nonces each signer has used or cancelled.
     */
    mapping(address signer => mapping(uint256 nonce => bool)) public nonceUsed;

    /**
     * @param registry_ Participant, role and permission registry.
     * @param passport_ Lot passport.
     * @param supplyChain_ Supply-chain ledger.
     * @param escrow_ Escrow manager.
     * @param currencies_ Currency manager.
     */
    constructor(
        IMineNetRegistry registry_,
        ILotPassport passport_,
        ISupplyChain supplyChain_,
        IEscrowManager escrow_,
        ICurrencyManager currencies_
    ) EIP712("MineNet Marketplace", "1") {
        registry = registry_;
        passport = passport_;
        supplyChain = supplyChain_;
        escrow = escrow_;
        currencies = currencies_;
    }

    /*//////////////////////////////////////////////////////////////
                               PREFERENCES
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Chooses the currency the caller's listings are quoted in by default (e.g. "RWF").
     * @param currency An enabled currency code, or 0 to reset to USD.
     * @custom:emits PreferredCurrencySet
     */
    function setPreferredCurrency(bytes32 currency) external {
        if (currency != bytes32(0) && !currencies.isCurrency(currency)) {
            revert MarketplaceLib.Marketplace__UnknownCurrency(currency);
        }
        preferredCurrency[msg.sender] = currency;
        emit MarketplaceLib.PreferredCurrencySet(msg.sender, currency);
    }

    /*//////////////////////////////////////////////////////////////
                                 LISTINGS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Lists a lot the caller owns.
     * @dev The caller needs `SELL_LOT`. The lot must have passed inspection, not be frozen or under an escrow
     * order,
     * and the escrow must be approved on the passport. A lot can have only one live listing.
     * @param p Listing parameters.
     * @return listingId New listing id.
     * @custom:emits ListingCreated
     */
    function createListing(MarketplaceLib.ListingParams calldata p)
        external
        nonReentrant
        whenNotPaused
        returns (uint256 listingId)
    {
        address seller = msg.sender;
        _requireAction(seller, Actions.SELL_LOT, false);
        _requireSellable(p.tokenId, seller);

        uint256 current = listingOf[p.tokenId];
        if (current != 0 && isListingLive(current)) {
            revert MarketplaceLib.Marketplace__AlreadyListed(p.tokenId, current);
        }
        if (!currencies.isSettlementToken(p.paymentToken)) {
            revert MarketplaceLib.Marketplace__TokenNotAllowed(p.paymentToken);
        }
        bytes32 currency = _resolveCurrency(p.priceCurrency, seller);
        _validateTerms(p.price, p.deliveryWindow, p.expiresAt, MarketplaceLib.MAX_LISTING_DURATION);

        listingId = _nextListingId++;
        _listings[listingId] = MarketplaceLib.Listing({
            tokenId: p.tokenId,
            seller: seller,
            paymentToken: p.paymentToken,
            priceModel: p.priceModel,
            status: MarketplaceLib.ListingStatus.Active,
            deliveryWindow: p.deliveryWindow,
            version: 1,
            createdAt: uint64(block.timestamp),
            updatedAt: uint64(block.timestamp),
            expiresAt: p.expiresAt,
            priceCurrency: currency,
            price: p.price,
            orderId: 0,
            termsHash: p.termsHash
        });
        listingOf[p.tokenId] = listingId;

        emit MarketplaceLib.ListingCreated(
            listingId,
            p.tokenId,
            seller,
            p.paymentToken,
            currency,
            p.priceModel,
            p.price,
            p.deliveryWindow,
            p.expiresAt,
            p.termsHash
        );
    }

    /**
     * @notice Updates a live listing in place: currency, pricing model, price, delivery window, expiry and terms.
     * @dev Only the seller. The payment token cannot change. Buyers are protected from a last-second reprice by the
     * `maxTotal` they pass to {buyListing}.
     * @param listingId Listing id.
     * @param u New terms.
     * @custom:emits ListingUpdated
     */
    function updateListing(uint256 listingId, MarketplaceLib.ListingUpdate calldata u) external whenNotPaused {
        MarketplaceLib.Listing storage l = _liveListingOf(listingId);
        _validateTerms(u.price, u.deliveryWindow, u.expiresAt, MarketplaceLib.MAX_LISTING_DURATION);
        if (u.priceCurrency != bytes32(0)) {
            if (!currencies.isCurrency(u.priceCurrency)) {
                revert MarketplaceLib.Marketplace__UnknownCurrency(u.priceCurrency);
            }
            l.priceCurrency = u.priceCurrency;
        }

        uint256 oldPrice = l.price;
        l.priceModel = u.priceModel;
        l.price = u.price;
        l.deliveryWindow = u.deliveryWindow;
        l.expiresAt = u.expiresAt;
        l.termsHash = u.termsHash;
        _touch(l);
        _emitUpdated(listingId, l, oldPrice);
    }

    /**
     * @notice Reprices a live listing, keeping its currency, pricing model and other terms.
     * @dev Only the seller.
     * @param listingId Listing id.
     * @param newPrice New price, in the listing's currency; non-zero.
     * @custom:emits ListingUpdated
     */
    function updatePrice(uint256 listingId, uint256 newPrice) external whenNotPaused {
        MarketplaceLib.Listing storage l = _liveListingOf(listingId);
        if (newPrice == 0) revert MarketplaceLib.Marketplace__InvalidPrice();
        uint256 oldPrice = l.price;
        l.price = newPrice;
        _touch(l);
        _emitUpdated(listingId, l, oldPrice);
    }

    /**
     * @notice Takes a listing off the market. Works on expired listings too, so a seller can clean up.
     * @dev Only the seller, while the listing is active.
     * @param listingId Listing id.
     * @custom:emits ListingDelisted
     */
    function delist(uint256 listingId) external {
        MarketplaceLib.Listing storage l = _listings[listingId];
        if (l.status == MarketplaceLib.ListingStatus.None) {
            revert MarketplaceLib.Marketplace__ListingNotFound(listingId);
        }
        if (msg.sender != l.seller) revert MarketplaceLib.Marketplace__NotSeller(msg.sender);
        if (l.status != MarketplaceLib.ListingStatus.Active) {
            revert MarketplaceLib.Marketplace__ListingNotLive(listingId);
        }
        _closeListing(listingId, l);
    }

    /*//////////////////////////////////////////////////////////////
                                PURCHASES
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Buys a listed lot. The quote (see {quoteListing}) is converted at the live exchange rate and pulled
     * from the caller into escrow.
     * @dev The caller needs `BUY_LOT` and must have approved this contract for at least `maxTotal` of the payment
     * token. Reverts if the seller no longer owns the lot.
     * @param listingId Listing id.
     * @param maxTotal The most the buyer accepts to pay, in payment-token units. It protects against a reprice, a
     * weight change or an exchange-rate move after the quote.
     * @return orderId The {EscrowManager} order. Track delivery, settlement and disputes there.
     * @custom:emits ListingSold
     */
    function buyListing(uint256 listingId, uint256 maxTotal)
        external
        nonReentrant
        whenNotPaused
        returns (uint256 orderId)
    {
        MarketplaceLib.Listing storage l = _listings[listingId];
        if (!isListingLive(listingId)) revert MarketplaceLib.Marketplace__ListingNotLive(listingId);
        address buyer = msg.sender;
        _requireAction(buyer, Actions.BUY_LOT, true);
        if (buyer == l.seller) revert MarketplaceLib.Marketplace__SelfTrade();
        if (passport.ownerOf(l.tokenId) != l.seller) revert MarketplaceLib.Marketplace__ListingStale(listingId);

        uint256 total = _quote(l);
        if (total > maxTotal) revert MarketplaceLib.Marketplace__PriceAboveMax(total, maxTotal);

        l.status = MarketplaceLib.ListingStatus.Sold;
        delete listingOf[l.tokenId];

        IERC20 token = l.paymentToken;
        token.safeTransferFrom(buyer, address(this), total);
        token.forceApprove(address(escrow), total);
        orderId = escrow.openOrder(
            EscrowLib.OpenParams({
                tokenId: l.tokenId,
                buyer: buyer,
                seller: l.seller,
                paymentToken: token,
                amount: total,
                deliveryWindow: l.deliveryWindow,
                termsHash: l.termsHash
            })
        );
        l.orderId = orderId;
        emit MarketplaceLib.ListingSold(listingId, l.tokenId, buyer, total, escrow.getOrder(orderId).usdValue, orderId);
    }

    /*//////////////////////////////////////////////////////////////
                      BUY REQUESTS (REVERSE MARKET)
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Posts a request for a mineral and locks the maximum payment (`maxPricePerKg x maxQty`) in the payment
     * token.
     * @dev The caller needs `BUY_LOT` and must have approved this contract for the deposit first (see
     * {requestDeposit}).
     * @param p Request parameters.
     * @return requestId New request id.
     * @custom:emits BuyRequestCreated
     */
    function createBuyRequest(MarketplaceLib.RequestParams calldata p)
        external
        nonReentrant
        whenNotPaused
        returns (uint256 requestId)
    {
        address buyer = msg.sender;
        _requireAction(buyer, Actions.BUY_LOT, true);
        if (!currencies.isSettlementToken(p.paymentToken)) {
            revert MarketplaceLib.Marketplace__TokenNotAllowed(p.paymentToken);
        }
        if (p.minQty == 0 || p.maxQty < p.minQty) revert MarketplaceLib.Marketplace__InvalidQuantity();
        if (p.minGradeBps > 10_000) revert MarketplaceLib.Marketplace__InvalidGrade(p.minGradeBps);
        _validateTerms(p.maxPricePerKg, p.deliveryWindow, p.expiresAt, MarketplaceLib.MAX_REQUEST_DURATION);

        uint256 locked = MarketplaceLib.requestDeposit(p.maxPricePerKg, p.maxQty);
        requestId = _nextRequestId++;
        _requests[requestId] = MarketplaceLib.BuyRequest({
            buyer: buyer,
            status: MarketplaceLib.RequestStatus.Open,
            minGradeBps: p.minGradeBps,
            deliveryWindow: p.deliveryWindow,
            createdAt: uint64(block.timestamp),
            expiresAt: p.expiresAt,
            mineralType: p.mineralType,
            paymentToken: p.paymentToken,
            minQty: p.minQty,
            maxQty: p.maxQty,
            filledQty: 0,
            fills: 0,
            maxPricePerKg: p.maxPricePerKg,
            lockedAmount: locked,
            orderId: 0,
            filledTokenId: 0,
            termsHash: p.termsHash
        });

        p.paymentToken.safeTransferFrom(buyer, address(this), locked);
        emit MarketplaceLib.BuyRequestCreated(
            requestId,
            buyer,
            p.mineralType,
            p.paymentToken,
            p.minQty,
            p.maxQty,
            p.maxPricePerKg,
            p.minGradeBps,
            p.expiresAt
        );
    }

    /**
     * @notice Fills an open buy request, fully or in part, with a lot the caller owns. Claiming is the company's
     * approval of the order. A lot bigger than what is left of the order is split automatically: exactly the
     * remaining amount is sold and the rest stays with the seller as a new inspected lot.
     * @dev The caller needs `SELL_LOT` and the lot must be sellable. The lot must match the mineral, its trusted
     * weight must be at least `minQty` (a heavier lot is split, see {SupplyChain-splitLot}), and its latest
     * attested grade must meet the minimum. Any live listing of the lot is closed. The deposit for the rest of the request stays locked; the
     * unused part of this fill's share is credited back to the buyer, and once less than `minQty` is left the
     * request closes as Filled and the whole remainder is credited back.
     * @param requestId Request id.
     * @param tokenId Lot.
     * @param pricePerKg Price, in token units per kg; non-zero and at most the buyer's maximum.
     * @return orderId The {EscrowManager} order.
     * @custom:emits LotSplitForRequest (when the lot is split)
     * @custom:emits BuyRequestClaimed
     */
    function claimBuyRequest(uint256 requestId, uint256 tokenId, uint256 pricePerKg)
        external
        nonReentrant
        whenNotPaused
        returns (uint256 orderId)
    {
        MarketplaceLib.BuyRequest storage r = _requests[requestId];
        if (r.status == MarketplaceLib.RequestStatus.None) {
            revert MarketplaceLib.Marketplace__RequestNotFound(requestId);
        }
        if (r.status != MarketplaceLib.RequestStatus.Open) {
            revert MarketplaceLib.Marketplace__RequestNotOpen(requestId);
        }
        if (block.timestamp > r.expiresAt) revert MarketplaceLib.Marketplace__RequestExpired(requestId);

        address seller = msg.sender;
        if (seller == r.buyer) revert MarketplaceLib.Marketplace__SelfTrade();
        _requireAction(seller, Actions.SELL_LOT, false);
        _requireSellable(tokenId, seller);
        if (pricePerKg == 0 || pricePerKg > r.maxPricePerKg) revert MarketplaceLib.Marketplace__InvalidPrice();

        PassportLib.Lot memory lot = passport.getLot(tokenId);
        if (lot.mineralType != r.mineralType) {
            revert MarketplaceLib.Marketplace__MineralMismatch(r.mineralType, lot.mineralType);
        }
        uint128 weight = supplyChain.lastWeight(tokenId);
        uint128 remaining = r.maxQty - r.filledQty;
        if (weight < r.minQty) revert MarketplaceLib.Marketplace__WeightOutOfRange(weight, r.minQty, remaining);
        if (r.minGradeBps != 0) {
            uint16 grade = supplyChain.latestGrade(tokenId).gradeBps;
            if (grade < r.minGradeBps) revert MarketplaceLib.Marketplace__GradeTooLow(grade, r.minGradeBps);
        }
        if (weight > remaining) {
            // the batch is bigger than what is left of the order: split off exactly that amount and sell it
            uint256 listed = listingOf[tokenId];
            if (listed != 0 && _listings[listed].status == MarketplaceLib.ListingStatus.Active) {
                _closeListing(listed, _listings[listed]);
            }
            uint128[] memory parts = new uint128[](2);
            parts[0] = remaining;
            parts[1] = weight - remaining;
            uint256 parent = tokenId;
            tokenId = supplyChain.splitLot(parent, parts, keccak256(abi.encode("MINENET_ORDER", requestId)))[0];
            weight = remaining;
            emit MarketplaceLib.LotSplitForRequest(requestId, parent, tokenId, remaining);
        }

        uint256 total = MarketplaceLib.claimTotal(pricePerKg, weight);
        if (total == 0) revert MarketplaceLib.Marketplace__InvalidPrice();
        // What stays locked covers the rest at the maximum price. floor(P x w) + ceil(P x (R - w)) <= ceil(P x R),
        // so `total + keep` never exceeds the deposit.
        uint128 left = remaining - weight;
        uint256 keep = left >= r.minQty ? MarketplaceLib.requestDeposit(r.maxPricePerKg, left) : 0;
        uint256 refund = r.lockedAmount - total - keep;

        r.lockedAmount = keep;
        r.filledQty += weight;
        r.fills += 1;
        if (keep == 0) r.status = MarketplaceLib.RequestStatus.Filled;
        r.filledTokenId = tokenId;
        uint256 listingId = listingOf[tokenId];
        if (listingId != 0 && _listings[listingId].status == MarketplaceLib.ListingStatus.Active) {
            _closeListing(listingId, _listings[listingId]);
        }
        if (refund != 0) claimable[r.paymentToken][r.buyer] += refund;

        r.paymentToken.forceApprove(address(escrow), total);
        orderId = escrow.openOrder(
            EscrowLib.OpenParams({
                tokenId: tokenId,
                buyer: r.buyer,
                seller: seller,
                paymentToken: r.paymentToken,
                amount: total,
                deliveryWindow: r.deliveryWindow,
                termsHash: r.termsHash
            })
        );
        r.orderId = orderId;
        emit MarketplaceLib.BuyRequestClaimed(requestId, tokenId, seller, pricePerKg, total, refund, orderId);
    }

    /*//////////////////////////////////////////////////////////////
                      NEGOTIATED SALES (SIGNED OFFERS)
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Accepts a sale the other party signed: the buyer submits a seller-signed offer, or the seller a
     * buyer-signed one. The price is pulled from the buyer into escrow and the order opened.
     * @dev The caller must be the offer's buyer or seller; the other party must have signed it (EIP-712, or
     * EIP-1271 for a contract wallet) and its nonce must be unused. The buyer needs `BUY_LOT` and must have
     * approved this contract for `amount`; the seller needs `SELL_LOT` and the lot must be sellable. Any live listing
     * of the lot is closed.
     * @param o The offer.
     * @param signature The other party's signature over {hashOffer}.
     * @return orderId The {EscrowManager} order.
     * @custom:emits OfferAccepted
     */
    function acceptOffer(MarketplaceLib.Offer calldata o, bytes calldata signature)
        external
        nonReentrant
        whenNotPaused
        returns (uint256 orderId)
    {
        address signer;
        if (msg.sender == o.buyer) signer = o.seller;
        else if (msg.sender == o.seller) signer = o.buyer;
        else revert MarketplaceLib.Marketplace__NotOfferParty(msg.sender);
        if (o.buyer == o.seller) revert MarketplaceLib.Marketplace__SelfTrade();
        if (block.timestamp > o.deadline) revert MarketplaceLib.Marketplace__OfferExpired(o.deadline);
        if (nonceUsed[signer][o.nonce]) revert MarketplaceLib.Marketplace__NonceUsed(signer, o.nonce);
        bytes32 digest = hashOffer(o);
        if (!SignatureChecker.isValidSignatureNow(signer, digest, signature)) {
            revert MarketplaceLib.Marketplace__InvalidSignature();
        }
        nonceUsed[signer][o.nonce] = true;

        _requireAction(o.buyer, Actions.BUY_LOT, true);
        _requireAction(o.seller, Actions.SELL_LOT, false);
        _requireSellable(o.tokenId, o.seller);
        if (!currencies.isSettlementToken(o.paymentToken)) {
            revert MarketplaceLib.Marketplace__TokenNotAllowed(o.paymentToken);
        }
        if (o.amount == 0) revert MarketplaceLib.Marketplace__InvalidPrice();

        uint256 listingId = listingOf[o.tokenId];
        if (listingId != 0 && _listings[listingId].status == MarketplaceLib.ListingStatus.Active) {
            _closeListing(listingId, _listings[listingId]);
        }

        o.paymentToken.safeTransferFrom(o.buyer, address(this), o.amount);
        o.paymentToken.forceApprove(address(escrow), o.amount);
        orderId = escrow.openOrder(
            EscrowLib.OpenParams({
                tokenId: o.tokenId,
                buyer: o.buyer,
                seller: o.seller,
                paymentToken: o.paymentToken,
                amount: o.amount,
                deliveryWindow: o.deliveryWindow,
                termsHash: o.termsHash
            })
        );
        emit MarketplaceLib.OfferAccepted(digest, o.tokenId, o.seller, o.buyer, o.amount, orderId);
    }

    /**
     * @notice Cancels one of the caller's offer nonces, so an offer it signed with it can no longer be accepted.
     * @param nonce The nonce.
     * @custom:emits OfferNonceCancelled
     */
    function cancelOfferNonce(uint256 nonce) external {
        if (nonceUsed[msg.sender][nonce]) revert MarketplaceLib.Marketplace__NonceUsed(msg.sender, nonce);
        nonceUsed[msg.sender][nonce] = true;
        emit MarketplaceLib.OfferNonceCancelled(msg.sender, nonce);
    }

    /**
     * @notice Withdraws an open or expired request and returns the deposit still locked (for a partly filled
     * request: the part not yet filled).
     * @dev Only the buyer.
     * @param requestId Request id.
     * @custom:emits BuyRequestCancelled
     */
    function cancelBuyRequest(uint256 requestId) external nonReentrant {
        MarketplaceLib.BuyRequest storage r = _requests[requestId];
        if (r.status == MarketplaceLib.RequestStatus.None) {
            revert MarketplaceLib.Marketplace__RequestNotFound(requestId);
        }
        if (msg.sender != r.buyer) revert MarketplaceLib.Marketplace__NotBuyer(msg.sender);
        if (r.status != MarketplaceLib.RequestStatus.Open) {
            revert MarketplaceLib.Marketplace__RequestNotOpen(requestId);
        }

        r.status = MarketplaceLib.RequestStatus.Cancelled;
        uint256 refund = r.lockedAmount;
        r.paymentToken.safeTransfer(msg.sender, refund);
        emit MarketplaceLib.BuyRequestCancelled(requestId, refund);
    }

    /**
     * @notice Withdraws buy-request refunds credited to the caller.
     * @param token Token to withdraw.
     * @custom:emits Withdrawn
     */
    function withdraw(IERC20 token) external nonReentrant {
        uint256 amount = claimable[token][msg.sender];
        if (amount == 0) revert MarketplaceLib.Marketplace__NothingToWithdraw();
        claimable[token][msg.sender] = 0;
        token.safeTransfer(msg.sender, amount);
        emit MarketplaceLib.Withdrawn(token, msg.sender, amount);
    }

    /*//////////////////////////////////////////////////////////////
                                  ADMIN
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Pauses listing, buying and buy requests.
     * @dev Only a {MineNetRegistry} admin. Delisting, cancelling and withdrawing stay available.
     */
    function pause() external {
        _onlyAdmin();
        _pause();
    }

    /**
     * @notice Resumes listing, buying and buy requests.
     * @dev Only a {MineNetRegistry} admin.
     */
    function unpause() external {
        _onlyAdmin();
        _unpause();
    }

    /*//////////////////////////////////////////////////////////////
                                  VIEWS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns a listing.
     * @dev Reverts for an unknown listing.
     * @param listingId Listing id.
     * @return The listing.
     */
    function getListing(uint256 listingId) external view returns (MarketplaceLib.Listing memory) {
        if (_listings[listingId].status == MarketplaceLib.ListingStatus.None) {
            revert MarketplaceLib.Marketplace__ListingNotFound(listingId);
        }
        return _listings[listingId];
    }

    /**
     * @notice Returns a buy request.
     * @dev Reverts for an unknown request.
     * @param requestId Request id.
     * @return The buy request.
     */
    function getBuyRequest(uint256 requestId) external view returns (MarketplaceLib.BuyRequest memory) {
        if (_requests[requestId].status == MarketplaceLib.RequestStatus.None) {
            revert MarketplaceLib.Marketplace__RequestNotFound(requestId);
        }
        return _requests[requestId];
    }

    /**
     * @notice Whether a listing can be bought now: active and not expired.
     * @param listingId Listing id.
     * @return True if live.
     */
    function isListingLive(uint256 listingId) public view returns (bool) {
        MarketplaceLib.Listing storage l = _listings[listingId];
        return l.status == MarketplaceLib.ListingStatus.Active && block.timestamp <= l.expiresAt;
    }

    /**
     * @notice The exact payment-token amount {buyListing} would charge right now.
     * @param listingId Listing id.
     * @return Amount, in payment-token units.
     */
    function quoteListing(uint256 listingId) external view returns (uint256) {
        return _quote(_existing(listingId));
    }

    /**
     * @notice A listing's price in its own currency and in USD, for display.
     * @param listingId Listing id.
     * @return currency Pricing currency.
     * @return amountInCurrency Price, in `currency` units.
     * @return usdValue Price in USD, 6 decimals.
     * @return tokenAmount Amount {buyListing} would charge, in payment-token units.
     */
    function quoteListingDetailed(uint256 listingId)
        external
        view
        returns (bytes32 currency, uint256 amountInCurrency, uint256 usdValue, uint256 tokenAmount)
    {
        MarketplaceLib.Listing storage l = _existing(listingId);
        currency = l.priceCurrency;
        amountInCurrency = MarketplaceLib.amountInCurrency(l, supplyChain.lastWeight(l.tokenId));
        usdValue = currencies.toUsd(amountInCurrency, currency);
        tokenAmount = currencies.toTokenAmount(amountInCurrency, currency, l.paymentToken, true);
    }

    /**
     * @notice The deposit {createBuyRequest} locks for a given maximum price and weight.
     * @param maxPricePerKg Maximum price, in token units per kg.
     * @param maxQty Maximum quantity, in grams.
     * @return Deposit, in token units.
     */
    function requestDeposit(uint256 maxPricePerKg, uint128 maxQty) external pure returns (uint256) {
        return MarketplaceLib.requestDeposit(maxPricePerKg, maxQty);
    }

    /**
     * @notice The EIP-712 digest a party signs for an offer.
     * @param o The offer.
     * @return The digest.
     */
    function hashOffer(MarketplaceLib.Offer calldata o) public view returns (bytes32) {
        return _hashTypedDataV4(
            keccak256(
                abi.encode(
                    OFFER_TYPEHASH,
                    o.tokenId,
                    o.seller,
                    o.buyer,
                    o.paymentToken,
                    o.amount,
                    o.deliveryWindow,
                    o.deadline,
                    o.nonce,
                    o.termsHash
                )
            )
        );
    }

    /**
     * @notice A buy request's deposit expressed in USD, for display.
     * @param requestId Request id.
     * @return USD value, 6 decimals.
     */
    function requestUsdValue(uint256 requestId) external view returns (uint256) {
        MarketplaceLib.BuyRequest storage r = _requests[requestId];
        if (r.status == MarketplaceLib.RequestStatus.None) {
            revert MarketplaceLib.Marketplace__RequestNotFound(requestId);
        }
        return currencies.tokenToUsd(r.paymentToken, r.lockedAmount);
    }

    /*//////////////////////////////////////////////////////////////
                                 INTERNAL
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev A listing's current price in payment-token units, rounded up.
     * @param l The listing.
     * @return Amount, in payment-token units.
     */
    function _quote(MarketplaceLib.Listing storage l) private view returns (uint256) {
        uint256 amount = MarketplaceLib.amountInCurrency(l, supplyChain.lastWeight(l.tokenId));
        return currencies.toTokenAmount(amount, l.priceCurrency, l.paymentToken, true);
    }

    /**
     * @dev Returns a listing, reverting if it does not exist.
     * @param listingId Listing id.
     * @return l Storage pointer to the listing.
     */
    function _existing(uint256 listingId) private view returns (MarketplaceLib.Listing storage l) {
        l = _listings[listingId];
        if (l.status == MarketplaceLib.ListingStatus.None) {
            revert MarketplaceLib.Marketplace__ListingNotFound(listingId);
        }
    }

    /**
     * @dev Returns a live listing of the caller, reverting otherwise.
     * @param listingId Listing id.
     * @return l Storage pointer to the listing.
     */
    function _liveListingOf(uint256 listingId) private view returns (MarketplaceLib.Listing storage l) {
        l = _existing(listingId);
        if (msg.sender != l.seller) revert MarketplaceLib.Marketplace__NotSeller(msg.sender);
        if (!isListingLive(listingId)) revert MarketplaceLib.Marketplace__ListingNotLive(listingId);
    }

    /**
     * @dev The pricing currency: the requested one, else the seller's preferred one, else USD. Must be enabled.
     * @param requested Requested currency (0 = default).
     * @param seller The seller.
     * @return currency Resolved currency code.
     */
    function _resolveCurrency(bytes32 requested, address seller) private view returns (bytes32 currency) {
        currency = requested;
        if (currency == bytes32(0)) currency = preferredCurrency[seller];
        if (currency == bytes32(0)) currency = CurrencyLib.USD;
        if (!currencies.isCurrency(currency)) revert MarketplaceLib.Marketplace__UnknownCurrency(currency);
    }

    /**
     * @dev Bumps a listing's version and update time.
     * @param l The listing.
     */
    function _touch(MarketplaceLib.Listing storage l) private {
        l.version += 1;
        l.updatedAt = uint64(block.timestamp);
    }

    /**
     * @dev Emits {MarketplaceLib.ListingUpdated} for a listing.
     * @param listingId Listing id.
     * @param l The listing.
     * @param oldPrice Price before the update.
     */
    function _emitUpdated(uint256 listingId, MarketplaceLib.Listing storage l, uint256 oldPrice) private {
        emit MarketplaceLib.ListingUpdated(
            listingId,
            l.version,
            l.priceCurrency,
            l.priceModel,
            oldPrice,
            l.price,
            l.deliveryWindow,
            l.expiresAt,
            l.termsHash
        );
    }

    /**
     * @dev Marks a listing delisted and clears it from {listingOf}.
     * @param listingId Listing id.
     * @param l The listing.
     */
    function _closeListing(uint256 listingId, MarketplaceLib.Listing storage l) private {
        l.status = MarketplaceLib.ListingStatus.Delisted;
        if (listingOf[l.tokenId] == listingId) delete listingOf[l.tokenId];
        emit MarketplaceLib.ListingDelisted(listingId, l.tokenId, msg.sender);
    }

    /**
     * @dev Reverts with `Marketplace__NotBuyer` or `Marketplace__NotSeller` unless `account` may perform `action`.
     * @param account The account.
     * @param action Required action.
     * @param buying Whether the check is for the buying side.
     */
    function _requireAction(address account, bytes32 action, bool buying) private view {
        if (!registry.isAuthorized(account, action)) {
            if (buying) revert MarketplaceLib.Marketplace__NotBuyer(account);
            revert MarketplaceLib.Marketplace__NotSeller(account);
        }
    }

    /**
     * @dev Reverts unless the lot is owned by `seller`, passed inspection, not frozen, not under an escrow order,
     * and
     * the escrow is approved, so a sale can lock it.
     * @param tokenId Lot.
     * @param seller The seller.
     */
    function _requireSellable(uint256 tokenId, address seller) private view {
        if (passport.ownerOf(tokenId) != seller) revert MarketplaceLib.Marketplace__NotLotOwner(tokenId, seller);
        if (passport.getLot(tokenId).status != PassportLib.LotStatus.Inspected) {
            revert MarketplaceLib.Marketplace__LotNotInspected(tokenId);
        }
        if (passport.isFrozen(tokenId)) revert MarketplaceLib.Marketplace__LotFrozen(tokenId);
        if (passport.escrowLocked(tokenId)) revert MarketplaceLib.Marketplace__LotLocked(tokenId);
        if (passport.getApproved(tokenId) != address(escrow) && !passport.isApprovedForAll(seller, address(escrow))) {
            revert MarketplaceLib.Marketplace__EscrowNotApproved(tokenId);
        }
    }

    /**
     * @dev Validates price, delivery window (within the escrow's bounds) and expiry.
     * @param price Price; non-zero.
     * @param deliveryWindow Delivery window, in seconds.
     * @param expiresAt Expiry.
     * @param maxDuration Maximum lifetime.
     */
    function _validateTerms(uint256 price, uint32 deliveryWindow, uint64 expiresAt, uint64 maxDuration) private view {
        MarketplaceLib.validateTerms(
            price, deliveryWindow, expiresAt, maxDuration, escrow.MIN_DELIVERY_WINDOW(), escrow.MAX_DELIVERY_WINDOW()
        );
    }

    /**
     * @dev Reverts unless the caller is a {MineNetRegistry} admin.
     */
    function _onlyAdmin() private view {
        if (!registry.isAdmin(msg.sender)) {
            revert MarketplaceLib.Marketplace__NotRegistryAdmin(msg.sender);
        }
    }
}
