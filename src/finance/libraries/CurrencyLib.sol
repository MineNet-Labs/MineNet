// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/**
 * @title CurrencyLib
 * @author 0xEmmyb2
 * @notice Shared types, events, custom errors and conversion maths of {CurrencyManager} and {OracleRateFeed}.
 * @dev Every currency has a rate: how many US dollars one whole unit is worth, scaled to {RATE_PRECISION} (USD
 * itself is exactly 1e18). Converting between any two currencies goes through USD:
 * `out = amount * rate(from) * 10^decimals(to) / (rate(to) * 10^decimals(from))`.
 */
library CurrencyLib {
    /**
     * @notice The US dollar. Currency codes are ISO 4217 codes as left-aligned bytes32, e.g. `bytes32("RWF")`.
     */
    bytes32 internal constant USD = "USD";

    /**
     * @notice Fixed-point scale of USD rates (1e18).
     */
    uint256 internal constant RATE_PRECISION = 1e18;

    /**
     * @notice Decimals of USD amounts reported for general use (6, same as USDC).
     */
    uint8 internal constant USD_DECIMALS = 6;

    /**
     * @notice Configuration of a pricing currency.
     * @param enabled Whether prices may be quoted in it.
     * @param decimals Decimals of prices quoted in this currency (e.g. USD 6, RWF 0).
     * @param maxStaleness Maximum age of a rate, in seconds; an older rate is rejected.
     * @param usdFeed Feed giving USD per one unit of the currency; none for USD.
     */
    struct Currency {
        bool enabled;
        uint8 decimals;
        uint32 maxStaleness;
        AggregatorV3Interface usdFeed;
    }

    /**
     * @notice Configuration of an ERC-20 token accepted for settlement.
     * @param enabled Whether the token is accepted.
     * @param decimals The token's own decimals.
     * @param currency Currency the token is pegged to (USDC -> USD, a RWF stablecoin -> RWF).
     */
    struct SettlementToken {
        bool enabled;
        uint8 decimals;
        bytes32 currency;
    }

    /**
     * @notice Emitted when the admin configures a currency.
     * @param code Currency code.
     * @param decimals Decimals of prices quoted in it.
     * @param usdFeed USD rate feed.
     * @param maxStaleness Maximum rate age, in seconds.
     * @param enabled Whether it is enabled.
     */
    event CurrencySet(bytes32 indexed code, uint8 decimals, address usdFeed, uint32 maxStaleness, bool enabled);

    /**
     * @notice Emitted when the admin configures a settlement token.
     * @param token The token.
     * @param currency Currency it is pegged to.
     * @param decimals The token's decimals.
     * @param enabled Whether it is accepted.
     */
    event SettlementTokenSet(IERC20 indexed token, bytes32 indexed currency, uint8 decimals, bool enabled);

    /**
     * @notice Emitted when an oracle node posts a new rate round.
     * @param roundId New round id.
     * @param answer Posted rate, in the feed's decimals.
     * @param reporter Oracle node.
     */
    event RatePosted(uint80 indexed roundId, int256 answer, address indexed reporter);

    /**
     * @notice Emitted when the admin sets the maximum change between two consecutive rates.
     * @param maxDeviationBps Maximum deviation, in basis points (0 = unlimited).
     */
    event MaxDeviationSet(uint16 maxDeviationBps);

    /**
     * @notice `account` is not an admin of {MineNetRegistry}.
     * @param account The account.
     */
    error CurrencyManager__NotRegistryAdmin(address account);

    /**
     * @notice Currency `code` is not enabled.
     * @param code The currency code.
     */
    error CurrencyManager__UnknownCurrency(bytes32 code);

    /**
     * @notice `token` is not an accepted settlement token.
     * @param token The token.
     */
    error CurrencyManager__NotSettlementToken(IERC20 token);

    /**
     * @notice The feed for `code` returned a non-positive rate.
     * @param code The currency code.
     */
    error CurrencyManager__InvalidRate(bytes32 code);

    /**
     * @notice The rate for `code` is older than the currency's maximum staleness.
     * @param code The currency code.
     * @param updatedAt When the rate was last updated (0 = never).
     */
    error CurrencyManager__StaleRate(bytes32 code, uint256 updatedAt);

    /**
     * @notice The currency or settlement-token configuration is invalid (zero or reserved code, too many decimals,
     * missing feed or staleness, or zero token).
     */
    error CurrencyManager__InvalidConfig();

    /**
     * @notice `account` may not post rates.
     * @param account The account.
     */
    error OracleRateFeed__Unauthorized(address account);

    /**
     * @notice The posted rate is not positive.
     * @param answer The posted rate.
     */
    error OracleRateFeed__InvalidAnswer(int256 answer);

    /**
     * @notice The posted rate moves too far from the previous one.
     * @param previous Previous rate.
     * @param answer Posted rate.
     */
    error OracleRateFeed__DeviationTooLarge(int256 previous, int256 answer);

    /**
     * @notice The requested round has no data.
     */
    error OracleRateFeed__NoData();

    /**
     * @notice Reads a currency's USD rate from its feed, scaled to {RATE_PRECISION}.
     * @dev Reverts on a non-positive answer or a rate older than `c.maxStaleness`.
     * @param code Currency code (for error reporting).
     * @param c Currency configuration.
     * @return USD per one unit of the currency, scaled to 1e18.
     */
    function readRate(bytes32 code, Currency memory c) internal view returns (uint256) {
        (, int256 answer,, uint256 updatedAt,) = c.usdFeed.latestRoundData();
        if (answer <= 0) revert CurrencyManager__InvalidRate(code);
        if (updatedAt == 0 || block.timestamp > updatedAt + c.maxStaleness) {
            revert CurrencyManager__StaleRate(code, updatedAt);
        }
        // forge-lint: disable-next-line(unsafe-typecast)
        return Math.mulDiv(uint256(answer), RATE_PRECISION, 10 ** c.usdFeed.decimals());
    }

    /**
     * @notice Converts an amount between two currencies via their USD rates.
     * @param amount Amount to convert, with `fromDecimals` decimals.
     * @param fromDecimals Decimals of `amount`.
     * @param fromRate USD rate of the source currency.
     * @param toDecimals Decimals of the result.
     * @param toRate USD rate of the target currency.
     * @param rounding Rounding direction.
     * @return The converted amount, with `toDecimals` decimals.
     */
    function convert(
        uint256 amount,
        uint8 fromDecimals,
        uint256 fromRate,
        uint8 toDecimals,
        uint256 toRate,
        Math.Rounding rounding
    ) internal pure returns (uint256) {
        return Math.mulDiv(amount, fromRate * 10 ** toDecimals, toRate * 10 ** fromDecimals, rounding);
    }
}
