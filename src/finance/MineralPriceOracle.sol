// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IMineNetRegistry} from "src/access/interfaces/IMineNetRegistry.sol";

/**
 * @title MineralPriceOracle
 * @author 0xEmmyb2
 * @notice International reference prices of minerals, in USD.
 * @dev Prices come from Chainlink price feeds where they exist (e.g. XAU / USD for gold on Base), or from
 * MineNet's {OracleRateFeed} (same interface) for minerals Chainlink does not cover (tin, tantalum,
 * tungsten...), posted by oracle nodes from an approved market source.
 *
 * The AI market assistant reads these for price analysis, the marketplace can show them beside listings, and
 * oracle nodes use them for the price check (sale price vs market reference).
 */
contract MineralPriceOracle {
    /**
     * @notice Fixed-point scale of returned prices (1e18).
     */
    uint256 public constant PRICE_PRECISION = 1e18;

    /**
     * @notice Price feed configuration of a mineral.
     * @param feed Feed giving USD per `unit` of the mineral.
     * @param maxStaleness Maximum age of a price, in seconds.
     * @param unit Unit the price is quoted per, e.g. "TROY_OUNCE", "TONNE", "KG".
     */
    struct Feed {
        AggregatorV3Interface feed;
        uint32 maxStaleness;
        bytes32 unit;
    }

    /**
     * @notice Participant, role and permission registry.
     */
    IMineNetRegistry public immutable registry;

    /**
     * @dev Mineral => feed configuration.
     */
    mapping(bytes32 mineralType => Feed) private _feeds;

    /**
     * @dev Minerals that have (or had) a feed, in the order they were first configured.
     */
    bytes32[] private _minerals;

    /**
     * @dev Whether a mineral is already in `_minerals`.
     */
    mapping(bytes32 mineralType => bool) private _listed;

    /**
     * @notice Emitted when the admin sets or removes a mineral's price feed.
     * @param mineralType Mineral identifier.
     * @param feed Feed address (zero = removed).
     * @param maxStaleness Maximum price age, in seconds.
     * @param unit Unit the price is quoted per.
     */
    event FeedSet(bytes32 indexed mineralType, address feed, uint32 maxStaleness, bytes32 unit);

    /**
     * @notice `account` is not an admin of {MineNetRegistry}.
     * @param account The account.
     */
    error MineralPriceOracle__NotRegistryAdmin(address account);

    /**
     * @notice A feed was set with a zero staleness or unit.
     */
    error MineralPriceOracle__InvalidConfig();

    /**
     * @notice `mineralType` has no price feed.
     * @param mineralType The mineral.
     */
    error MineralPriceOracle__NoFeed(bytes32 mineralType);

    /**
     * @notice The feed for `mineralType` returned a non-positive price.
     * @param mineralType The mineral.
     * @param answer The returned price.
     */
    error MineralPriceOracle__InvalidAnswer(bytes32 mineralType, int256 answer);

    /**
     * @notice The price for `mineralType` is older than its maximum staleness.
     * @param mineralType The mineral.
     * @param updatedAt When it was last updated (0 = never).
     */
    error MineralPriceOracle__Stale(bytes32 mineralType, uint256 updatedAt);

    /**
     * @param registry_ Participant, role and permission registry.
     */
    constructor(IMineNetRegistry registry_) {
        registry = registry_;
    }

    /**
     * @notice Sets, or removes with a zero feed, the price feed of a mineral.
     * @dev Only a {MineNetRegistry} admin.
     * @param mineralType Mineral identifier.
     * @param feed Feed giving USD per `unit` (zero to remove).
     * @param maxStaleness Maximum price age, in seconds; non-zero when setting a feed.
     * @param unit Unit the price is quoted per; non-zero when setting a feed.
     * @custom:emits FeedSet
     */
    function setFeed(bytes32 mineralType, AggregatorV3Interface feed, uint32 maxStaleness, bytes32 unit) external {
        if (!registry.isAdmin(msg.sender)) revert MineralPriceOracle__NotRegistryAdmin(msg.sender);
        if (address(feed) != address(0) && (maxStaleness == 0 || unit == bytes32(0))) {
            revert MineralPriceOracle__InvalidConfig();
        }
        if (!_listed[mineralType] && address(feed) != address(0)) {
            _listed[mineralType] = true;
            _minerals.push(mineralType);
        }
        _feeds[mineralType] = Feed({feed: feed, maxStaleness: maxStaleness, unit: unit});
        emit FeedSet(mineralType, address(feed), maxStaleness, unit);
    }

    /**
     * @notice The latest USD price of one `unit` of a mineral.
     * @dev Reverts if there is no feed, or its answer is non-positive or stale.
     * @param mineralType Mineral identifier.
     * @return price USD per `unit`, scaled to {PRICE_PRECISION}.
     * @return unit Unit the price is quoted per.
     * @return updatedAt When the price was last updated.
     */
    function latestPrice(bytes32 mineralType) external view returns (uint256 price, bytes32 unit, uint256 updatedAt) {
        Feed memory f = _feeds[mineralType];
        if (address(f.feed) == address(0)) revert MineralPriceOracle__NoFeed(mineralType);
        int256 answer;
        (, answer,, updatedAt,) = f.feed.latestRoundData();
        if (answer <= 0) revert MineralPriceOracle__InvalidAnswer(mineralType, answer);
        if (updatedAt == 0 || block.timestamp > updatedAt + f.maxStaleness) {
            revert MineralPriceOracle__Stale(mineralType, updatedAt);
        }
        // forge-lint: disable-next-line(unsafe-typecast)
        price = Math.mulDiv(uint256(answer), PRICE_PRECISION, 10 ** f.feed.decimals());
        unit = f.unit;
    }

    /**
     * @notice Returns a mineral's feed configuration.
     * @param mineralType Mineral identifier.
     * @return The feed configuration (zero feed if none).
     */
    function getFeed(bytes32 mineralType) external view returns (Feed memory) {
        return _feeds[mineralType];
    }

    /**
     * @notice Minerals that have (or had) a feed.
     * @return Mineral identifiers.
     */
    function minerals() external view returns (bytes32[] memory) {
        return _minerals;
    }
}
