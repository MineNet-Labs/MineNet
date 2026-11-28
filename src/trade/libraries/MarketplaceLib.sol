// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/**
 * @title MarketplaceLib
 * @author 0xEmmyb2
 * @notice Shared types, events, custom errors and pricing maths of {Marketplace}.
 */
library MarketplaceLib {
    /**
     * @notice How a listing is priced. `FixedTotal`: `price` is the total for the lot. `PerKilogram`: `price` is
     * per
     * kg of the lot's last trusted weight.
     */
    enum PriceModel {
        FixedTotal, // `price` is the total for the lot
        PerKilogram // `price` is per kg of the lot's last trusted weight
    }

    /**
     * @notice Lifecycle status of a listing.
     */
    enum ListingStatus {
        None,
        Active,
        Delisted,
        Sold
    }

    /**
     * @notice Lifecycle status of a buy request.
     */
    enum RequestStatus {
        None,
        Open,
        Filled,
        Cancelled
    }

    /**
     * @notice A lot offered for sale.
     * @param tokenId Lot.
     * @param seller Seller.
     * @param paymentToken What the buyer pays with (USDC, or a local-currency stablecoin).
     * @param priceModel How the price is applied.
     * @param status Current status.
     * @param deliveryWindow Seconds the seller has to deliver once sold.
     * @param version Bumped on every update, so clients can detect stale quotes.
     * @param createdAt When it was created.
     * @param updatedAt When it was last updated.
     * @param expiresAt When it expires.
     * @param priceCurrency Currency the price is quoted in: "USD" or the seller's local currency (e.g. "RWF").
     * @param price Price, in `priceCurrency` units (its decimals).
     * @param orderId Escrow order once sold.
     * @param termsHash Hash of the off-chain terms (Incoterm, delivery point, sampling rules...).
     */
    struct Listing {
        uint256 tokenId;
        address seller;
        IERC20 paymentToken;
        PriceModel priceModel;
        ListingStatus status;
        uint32 deliveryWindow;
        uint32 version;
        uint64 createdAt;
        uint64 updatedAt;
        uint64 expiresAt;
        bytes32 priceCurrency;
        uint256 price;
        uint256 orderId;
        bytes32 termsHash;
    }

    /**
     * @notice Everything a seller supplies to list a lot.
     * @param tokenId Lot.
     * @param paymentToken Settlement token.
     * @param priceCurrency Pricing currency; 0 = the seller's preferred currency (or USD if none is set).
     * @param priceModel How the price is applied.
     * @param price Price, in `priceCurrency` units.
     * @param deliveryWindow Seconds the seller has to deliver once sold.
     * @param expiresAt When the listing expires.
     * @param termsHash Hash of the off-chain terms.
     */
    struct ListingParams {
        uint256 tokenId;
        IERC20 paymentToken;
        bytes32 priceCurrency;
        PriceModel priceModel;
        uint256 price;
        uint32 deliveryWindow;
        uint64 expiresAt;
        bytes32 termsHash;
    }

    /**
     * @notice Everything a seller supplies to update a listing.
     * @param priceCurrency New pricing currency; 0 = keep the current currency.
     * @param priceModel New price model.
     * @param price New price.
     * @param deliveryWindow New delivery window.
     * @param expiresAt New expiry.
     * @param termsHash New terms hash.
     */
    struct ListingUpdate {
        bytes32 priceCurrency;
        PriceModel priceModel;
        uint256 price;
        uint32 deliveryWindow;
        uint64 expiresAt;
        bytes32 termsHash;
    }

    /**
     * @notice A buyer's standing request for a mineral, funded upfront. Several lots can fill it: each lot must
     * weigh at least `minQty` and fit in what is left of `maxQty`; the request closes as Filled once less than
     * `minQty` is left.
     * @param buyer Buyer.
     * @param status Current status.
     * @param minGradeBps Minimum grade, in basis points (0 = any grade).
     * @param deliveryWindow Seconds the seller has to deliver once filled.
     * @param createdAt When it was created.
     * @param expiresAt When it expires.
     * @param mineralType Mineral wanted.
     * @param paymentToken Token the request is priced in, so the deposit never moves with FX.
     * @param minQty Minimum weight of each filling lot, in grams.
     * @param maxQty Total quantity wanted across all fills, in grams.
     * @param filledQty Quantity filled so far, in grams.
     * @param maxPricePerKg Maximum price, in token units per kg.
     * @param lockedAmount Deposit still locked: `maxPricePerKg x (maxQty - filledQty)`, rounded up (0 once
     * closed).
     * @param orderId Escrow order of the latest fill.
     * @param filledTokenId Lot of the latest fill.
     * @param fills Number of fills.
     * @param termsHash Hash of the off-chain terms.
     */
    struct BuyRequest {
        address buyer;
        RequestStatus status;
        uint16 minGradeBps;
        uint32 deliveryWindow;
        uint64 createdAt;
        uint64 expiresAt;
        bytes32 mineralType;
        IERC20 paymentToken;
        uint128 minQty;
        uint128 maxQty;
        uint128 filledQty;
        uint32 fills;
        uint256 maxPricePerKg;
        uint256 lockedAmount;
        uint256 orderId;
        uint256 filledTokenId;
        bytes32 termsHash;
    }

    /**
     * @notice A sale agreed off-chain (offers and counter-offers), signed by one party (EIP-712) and submitted by
     * the other with {Marketplace-acceptOffer}.
     * @param tokenId Lot sold.
     * @param seller Seller (the lot's owner).
     * @param buyer Buyer.
     * @param paymentToken Settlement token.
     * @param amount Total price, in token units.
     * @param deliveryWindow Seconds the seller has to deliver.
     * @param deadline Last moment the offer can be accepted.
     * @param nonce Signer's nonce; each can be used or cancelled once.
     * @param termsHash Hash of the off-chain terms (the negotiation thread's final message).
     */
    struct Offer {
        uint256 tokenId;
        address seller;
        address buyer;
        IERC20 paymentToken;
        uint256 amount;
        uint32 deliveryWindow;
        uint64 deadline;
        uint256 nonce;
        bytes32 termsHash;
    }

    /**
     * @notice Everything a buyer supplies to post a buy request.
     * @param mineralType Mineral wanted.
     * @param paymentToken Settlement token.
     * @param minQty Minimum quantity, in grams.
     * @param maxQty Maximum quantity, in grams.
     * @param maxPricePerKg Maximum price, in token units per kg.
     * @param minGradeBps Minimum grade, in basis points (0 = any).
     * @param deliveryWindow Seconds the seller has to deliver once filled.
     * @param expiresAt When the request expires.
     * @param termsHash Hash of the off-chain terms.
     */
    struct RequestParams {
        bytes32 mineralType;
        IERC20 paymentToken;
        uint128 minQty;
        uint128 maxQty;
        uint256 maxPricePerKg;
        uint16 minGradeBps;
        uint32 deliveryWindow;
        uint64 expiresAt;
        bytes32 termsHash;
    }

    /**
     * @notice Emitted when an account sets its preferred pricing currency.
     * @param account The account.
     * @param currency Currency code (0 = none).
     */
    event PreferredCurrencySet(address indexed account, bytes32 indexed currency);

    /**
     * @notice Emitted when a lot is listed.
     * @param listingId New listing id.
     * @param tokenId Lot.
     * @param seller Seller.
     * @param paymentToken Settlement token.
     * @param priceCurrency Pricing currency.
     * @param priceModel Price model.
     * @param price Price.
     * @param deliveryWindow Delivery window, in seconds.
     * @param expiresAt Expiry.
     * @param termsHash Hash of the terms.
     */
    event ListingCreated(
        uint256 indexed listingId,
        uint256 indexed tokenId,
        address indexed seller,
        IERC20 paymentToken,
        bytes32 priceCurrency,
        PriceModel priceModel,
        uint256 price,
        uint32 deliveryWindow,
        uint64 expiresAt,
        bytes32 termsHash
    );

    /**
     * @notice Emitted when a listing is updated.
     * @param listingId Listing id.
     * @param version New version.
     * @param priceCurrency Pricing currency.
     * @param priceModel Price model.
     * @param oldPrice Previous price.
     * @param newPrice New price.
     * @param deliveryWindow Delivery window, in seconds.
     * @param expiresAt Expiry.
     * @param termsHash Hash of the terms.
     */
    event ListingUpdated(
        uint256 indexed listingId,
        uint32 version,
        bytes32 priceCurrency,
        PriceModel priceModel,
        uint256 oldPrice,
        uint256 newPrice,
        uint32 deliveryWindow,
        uint64 expiresAt,
        bytes32 termsHash
    );

    /**
     * @notice Emitted when a listing is withdrawn.
     * @param listingId Listing id.
     * @param tokenId Lot.
     * @param by The seller.
     */
    event ListingDelisted(uint256 indexed listingId, uint256 indexed tokenId, address indexed by);

    /**
     * @notice Emitted when a listing is bought and an escrow order opened.
     * @param listingId Listing id.
     * @param tokenId Lot.
     * @param buyer Buyer.
     * @param total Amount paid, in payment-token units.
     * @param usdValue USD value, 6 decimals.
     * @param orderId Escrow order.
     */
    event ListingSold(
        uint256 indexed listingId,
        uint256 indexed tokenId,
        address indexed buyer,
        uint256 total,
        uint256 usdValue,
        uint256 orderId
    );

    /**
     * @notice Emitted when a buyer posts a buy request.
     * @param requestId New request id.
     * @param buyer Buyer.
     * @param mineralType Mineral wanted.
     * @param paymentToken Settlement token.
     * @param minQty Minimum quantity, in grams.
     * @param maxQty Maximum quantity, in grams.
     * @param maxPricePerKg Maximum price per kg.
     * @param minGradeBps Minimum grade, in basis points.
     * @param expiresAt Expiry.
     */
    event BuyRequestCreated(
        uint256 indexed requestId,
        address indexed buyer,
        bytes32 indexed mineralType,
        IERC20 paymentToken,
        uint128 minQty,
        uint128 maxQty,
        uint256 maxPricePerKg,
        uint16 minGradeBps,
        uint64 expiresAt
    );

    /**
     * @notice Emitted when a lot bigger than what is left of a buy request is split to fill it.
     * @param requestId Buy request.
     * @param parentId Lot split (now consumed).
     * @param soldId New lot sold to the buyer.
     * @param weight Weight sold, in grams.
     */
    event LotSplitForRequest(
        uint256 indexed requestId, uint256 indexed parentId, uint256 indexed soldId, uint128 weight
    );

    /**
     * @notice Emitted when a seller fills a buy request with a lot.
     * @param requestId Request id.
     * @param tokenId Lot.
     * @param seller Seller.
     * @param pricePerKg Price per kg applied.
     * @param total Amount moved into escrow.
     * @param refund Unused deposit credited back to the buyer.
     * @param orderId Escrow order.
     */
    event BuyRequestClaimed(
        uint256 indexed requestId,
        uint256 indexed tokenId,
        address indexed seller,
        uint256 pricePerKg,
        uint256 total,
        uint256 refund,
        uint256 orderId
    );

    /**
     * @notice Emitted when a buy request is cancelled.
     * @param requestId Request id.
     * @param refund Deposit credited back to the buyer.
     */
    event BuyRequestCancelled(uint256 indexed requestId, uint256 refund);

    /**
     * @notice Emitted when a signed offer is accepted and its order opened.
     * @param offerHash EIP-712 digest of the offer.
     * @param tokenId Lot.
     * @param seller Seller.
     * @param buyer Buyer.
     * @param amount Amount moved into escrow.
     * @param orderId Escrow order.
     */
    event OfferAccepted(
        bytes32 indexed offerHash,
        uint256 indexed tokenId,
        address indexed seller,
        address buyer,
        uint256 amount,
        uint256 orderId
    );

    /**
     * @notice Emitted when an account cancels one of its offer nonces.
     * @param account The signer.
     * @param nonce Cancelled nonce.
     */
    event OfferNonceCancelled(address indexed account, uint256 nonce);

    /**
     * @notice Emitted when an account withdraws its credited balance.
     * @param token Token.
     * @param account Withdrawing account.
     * @param amount Amount withdrawn.
     */
    event Withdrawn(IERC20 indexed token, address indexed account, uint256 amount);

    /**
     * @notice `account` is not an admin of {MineNetRegistry}.
     * @param account The account.
     */
    error Marketplace__NotRegistryAdmin(address account);

    /**
     * @notice `account` may not sell, or is not the listing's seller.
     * @param account The account.
     */
    error Marketplace__NotSeller(address account);

    /**
     * @notice `account` may not buy, or is not the request's buyer.
     * @param account The account.
     */
    error Marketplace__NotBuyer(address account);

    /**
     * @notice `account` does not own lot `tokenId`.
     * @param tokenId The lot.
     * @param account The account.
     */
    error Marketplace__NotLotOwner(uint256 tokenId, address account);

    /**
     * @notice Lot `tokenId` has not passed inspection.
     * @param tokenId The lot.
     */
    error Marketplace__LotNotInspected(uint256 tokenId);

    /**
     * @notice Lot `tokenId` is frozen.
     * @param tokenId The lot.
     */
    error Marketplace__LotFrozen(uint256 tokenId);

    /**
     * @notice Lot `tokenId` is locked under an escrow order.
     * @param tokenId The lot.
     */
    error Marketplace__LotLocked(uint256 tokenId);

    /**
     * @notice Lot `tokenId` already has active listing `listingId`.
     * @param tokenId The lot.
     * @param listingId The listing.
     */
    error Marketplace__AlreadyListed(uint256 tokenId, uint256 listingId);

    /**
     * @notice The escrow is not approved to transfer lot `tokenId`.
     * @param tokenId The lot.
     */
    error Marketplace__EscrowNotApproved(uint256 tokenId);

    /**
     * @notice `token` is not an accepted settlement token.
     * @param token The token.
     */
    error Marketplace__TokenNotAllowed(IERC20 token);

    /**
     * @notice `currency` is not an enabled currency.
     * @param currency The currency code.
     */
    error Marketplace__UnknownCurrency(bytes32 currency);

    /**
     * @notice The price is zero.
     */
    error Marketplace__InvalidPrice();

    /**
     * @notice The delivery window is outside the allowed range.
     */
    error Marketplace__InvalidWindow();

    /**
     * @notice `expiresAt` is in the past or beyond the maximum duration.
     * @param expiresAt The expiry.
     */
    error Marketplace__InvalidExpiry(uint64 expiresAt);

    /**
     * @notice The quantity range is empty or inverted.
     */
    error Marketplace__InvalidQuantity();

    /**
     * @notice `gradeBps` exceeds 100%.
     * @param gradeBps The grade.
     */
    error Marketplace__InvalidGrade(uint16 gradeBps);

    /**
     * @notice Listing `listingId` does not exist.
     * @param listingId The listing.
     */
    error Marketplace__ListingNotFound(uint256 listingId);

    /**
     * @notice Listing `listingId` is not active or has expired.
     * @param listingId The listing.
     */
    error Marketplace__ListingNotLive(uint256 listingId);

    /**
     * @notice Listing `listingId` changed since the buyer's quote.
     * @param listingId The listing.
     */
    error Marketplace__ListingStale(uint256 listingId);

    /**
     * @notice Buyer and seller are the same.
     */
    error Marketplace__SelfTrade();

    /**
     * @notice The total `total` exceeds the buyer's maximum `maxTotal`.
     * @param total Amount due.
     * @param maxTotal Buyer's maximum.
     */
    error Marketplace__PriceAboveMax(uint256 total, uint256 maxTotal);

    /**
     * @notice Buy request `requestId` does not exist.
     * @param requestId The request.
     */
    error Marketplace__RequestNotFound(uint256 requestId);

    /**
     * @notice Buy request `requestId` is not open.
     * @param requestId The request.
     */
    error Marketplace__RequestNotOpen(uint256 requestId);

    /**
     * @notice Buy request `requestId` has expired.
     * @param requestId The request.
     */
    error Marketplace__RequestExpired(uint256 requestId);

    /**
     * @notice The lot's mineral `actual` is not the requested `expected`.
     * @param expected Requested mineral.
     * @param actual Lot's mineral.
     */
    error Marketplace__MineralMismatch(bytes32 expected, bytes32 actual);

    /**
     * @notice The lot's weight is outside the request's range.
     * @param weight Lot's trusted weight, in grams.
     * @param minQty Minimum quantity, in grams.
     * @param maxQty Maximum quantity, in grams.
     */
    error Marketplace__WeightOutOfRange(uint128 weight, uint128 minQty, uint128 maxQty);

    /**
     * @notice The lot's grade is below the request's minimum.
     * @param grade Lot's attested grade, in basis points.
     * @param minGrade Minimum grade, in basis points.
     */
    error Marketplace__GradeTooLow(uint16 grade, uint16 minGrade);

    /**
     * @notice The caller has no balance to withdraw.
     */
    error Marketplace__NothingToWithdraw();

    /**
     * @notice The caller is neither the offer's buyer nor its seller.
     * @param account The caller.
     */
    error Marketplace__NotOfferParty(address account);

    /**
     * @notice The offer's deadline has passed.
     * @param deadline The deadline.
     */
    error Marketplace__OfferExpired(uint64 deadline);

    /**
     * @notice The signer's nonce was already used or cancelled.
     * @param signer The signer.
     * @param nonce The nonce.
     */
    error Marketplace__NonceUsed(address signer, uint256 nonce);

    /**
     * @notice The signature is not the other party's.
     */
    error Marketplace__InvalidSignature();

    /**
     * @notice Grams per kilogram.
     */
    uint256 internal constant GRAMS_PER_KG = 1_000;

    /**
     * @notice Maximum lifetime of a listing.
     */
    uint64 internal constant MAX_LISTING_DURATION = 90 days;

    /**
     * @notice Maximum lifetime of a buy request.
     */
    uint64 internal constant MAX_REQUEST_DURATION = 90 days;

    /**
     * @notice A listing's price in its own currency, for the lot's current trusted weight.
     * @param l The listing.
     * @param weight Lot's trusted weight, in grams.
     * @return The total price, in `l.priceCurrency` units (rounded up for per-kg pricing).
     */
    function amountInCurrency(Listing storage l, uint128 weight) internal view returns (uint256) {
        if (l.priceModel == PriceModel.FixedTotal) return l.price;
        return Math.mulDiv(l.price, weight, GRAMS_PER_KG, Math.Rounding.Ceil);
    }

    /**
     * @notice The deposit a buy request locks: `maxPricePerKg x maxQty`, rounded up.
     * @param maxPricePerKg Maximum price, in token units per kg.
     * @param maxQty Maximum quantity, in grams.
     * @return Deposit, in token units.
     */
    function requestDeposit(uint256 maxPricePerKg, uint128 maxQty) internal pure returns (uint256) {
        return Math.mulDiv(maxPricePerKg, maxQty, GRAMS_PER_KG, Math.Rounding.Ceil);
    }

    /**
     * @notice The total for a claimed buy request: `pricePerKg x weight`, rounded down (never above the deposit).
     * @param pricePerKg Price, in token units per kg.
     * @param weight Lot's trusted weight, in grams.
     * @return Total, in token units.
     */
    function claimTotal(uint256 pricePerKg, uint128 weight) internal pure returns (uint256) {
        return Math.mulDiv(pricePerKg, weight, GRAMS_PER_KG);
    }

    /**
     * @notice Reverts unless the price, delivery window and expiry are acceptable.
     * @param price Price; must be non-zero.
     * @param deliveryWindow Delivery window, in seconds; must be within `[minWindow, maxWindow]`.
     * @param expiresAt Expiry; must be in the future and at most `maxDuration` away.
     * @param maxDuration Maximum lifetime.
     * @param minWindow Minimum delivery window.
     * @param maxWindow Maximum delivery window.
     */
    function validateTerms(
        uint256 price,
        uint32 deliveryWindow,
        uint64 expiresAt,
        uint64 maxDuration,
        uint32 minWindow,
        uint32 maxWindow
    ) internal view {
        if (price == 0) revert Marketplace__InvalidPrice();
        if (deliveryWindow < minWindow || deliveryWindow > maxWindow) revert Marketplace__InvalidWindow();
        if (expiresAt <= block.timestamp || expiresAt > block.timestamp + maxDuration) {
            revert Marketplace__InvalidExpiry(expiresAt);
        }
    }
}
