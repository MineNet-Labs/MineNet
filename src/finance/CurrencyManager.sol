// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {ICurrencyManager} from "src/finance/interfaces/ICurrencyManager.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IMineNetRegistry} from "src/access/interfaces/IMineNetRegistry.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {CurrencyLib} from "src/finance/libraries/CurrencyLib.sol";

/**
 * @title CurrencyManager
 * @author 0xEmmyb2
 * @notice Prices and payments in USD or in a seller's local currency.
 * @dev Pricing currencies: USD is built in (rate 1). The admin adds local currencies, e.g. RWF, KES or UGX, each
 * with a USD exchange-rate feed (Chainlink where one exists, otherwise MineNet's {OracleRateFeed} run by oracle
 * nodes) and a staleness limit.
 *
 * Settlement tokens: the stablecoins escrow accepts, each pegged to one currency (USDC -> USD, or a
 * local-currency stablecoin -> RWF).
 *
 * So a seller can price a lot in RWF and be paid in USDC (converted at the live rate when the buyer pays), or be
 * paid in a RWF stablecoin if one is registered. Every amount can also be shown in USD for general use
 * ({toUsd}).
 */
contract CurrencyManager is ICurrencyManager {
    /**
     * @notice Participant, role and permission registry.
     */
    IMineNetRegistry public immutable registry;

    /**
     * @dev Currency code => configuration.
     */
    mapping(bytes32 code => CurrencyLib.Currency) private _currencies;

    /**
     * @dev Token => settlement configuration.
     */
    mapping(IERC20 token => CurrencyLib.SettlementToken) private _tokens;

    /**
     * @dev Enables USD with {CurrencyLib.USD_DECIMALS} decimals and a fixed rate of 1.
     * @param registry_ Participant, role and permission registry.
     */
    constructor(IMineNetRegistry registry_) {
        registry = registry_;
        _currencies[CurrencyLib.USD] = CurrencyLib.Currency({
            enabled: true,
            decimals: CurrencyLib.USD_DECIMALS,
            maxStaleness: 0,
            usdFeed: AggregatorV3Interface(address(0))
        });
        emit CurrencyLib.CurrencySet(CurrencyLib.USD, CurrencyLib.USD_DECIMALS, address(0), 0, true);
    }

    /*//////////////////////////////////////////////////////////////
                                  ADMIN
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Adds or updates a pricing currency (not USD, which is fixed).
     * @dev Only a {MineNetRegistry} admin. An enabled currency needs a feed and a non-zero staleness.
     * @param code ISO 4217 code as left-aligned bytes32, e.g. `bytes32("RWF")`.
     * @param decimals Decimals of prices quoted in it (RWF prices are usually whole francs: 0); at most 18.
     * @param usdFeed Feed giving USD per one unit of the currency.
     * @param maxStaleness Seconds after which the feed's answer is too old to use.
     * @param enabled Whether prices may be quoted in it.
     * @custom:emits CurrencySet
     */
    function setCurrency(bytes32 code, uint8 decimals, AggregatorV3Interface usdFeed, uint32 maxStaleness, bool enabled)
        external
    {
        _onlyAdmin();
        if (code == CurrencyLib.USD || code == bytes32(0) || decimals > 18) {
            revert CurrencyLib.CurrencyManager__InvalidConfig();
        }
        if (enabled && (address(usdFeed) == address(0) || maxStaleness == 0)) {
            revert CurrencyLib.CurrencyManager__InvalidConfig();
        }
        _currencies[code] =
            CurrencyLib.Currency({enabled: enabled, decimals: decimals, maxStaleness: maxStaleness, usdFeed: usdFeed});
        emit CurrencyLib.CurrencySet(code, decimals, address(usdFeed), maxStaleness, enabled);
    }

    /**
     * @notice Allows or disallows a stablecoin for settlement, pegged to `currency`.
     * @dev Only a {MineNetRegistry} admin. Only plain tokens: fee-on-transfer or rebasing tokens break escrow
     * accounting.
     * @param token The stablecoin.
     * @param currency Currency it is pegged to; must be enabled when enabling the token.
     * @param enabled Whether it is accepted.
     * @custom:emits SettlementTokenSet
     */
    function setSettlementToken(IERC20 token, bytes32 currency, bool enabled) external {
        _onlyAdmin();
        if (address(token) == address(0)) revert CurrencyLib.CurrencyManager__InvalidConfig();
        if (enabled && !_currencies[currency].enabled) revert CurrencyLib.CurrencyManager__UnknownCurrency(currency);
        uint8 dec = IERC20Metadata(address(token)).decimals();
        _tokens[token] = CurrencyLib.SettlementToken({enabled: enabled, decimals: dec, currency: currency});
        emit CurrencyLib.SettlementTokenSet(token, currency, dec, enabled);
    }

    /*//////////////////////////////////////////////////////////////
                               CONVERSIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice USD per one unit of a currency.
     * @dev Reverts if the currency is unknown or its rate is stale.
     * @param code Currency code.
     * @return Rate, scaled to {CurrencyLib.RATE_PRECISION}.
     */
    function usdRate(bytes32 code) public view returns (uint256) {
        CurrencyLib.Currency memory c = _requireCurrency(code);
        if (code == CurrencyLib.USD) return CurrencyLib.RATE_PRECISION;
        return CurrencyLib.readRate(code, c);
    }

    /**
     * @notice Converts an amount between two pricing currencies at the live rates.
     * @param amount Amount, in `from` units.
     * @param from Source currency.
     * @param to Target currency.
     * @param roundUp Round up (true) or down (false).
     * @return Amount, in `to` units.
     */
    function convert(uint256 amount, bytes32 from, bytes32 to, bool roundUp) public view returns (uint256) {
        if (from == to) return amount;
        uint8 fromDec = _requireCurrency(from).decimals;
        uint8 toDec = _requireCurrency(to).decimals;
        return CurrencyLib.convert(amount, fromDec, usdRate(from), toDec, usdRate(to), _rounding(roundUp));
    }

    /**
     * @notice How many units of settlement `token` an amount priced in `currency` costs right now.
     * @param amount Amount, in `currency` units.
     * @param currency Pricing currency.
     * @param token Settlement token.
     * @param roundUp Round up (true) or down (false).
     * @return Amount, in `token` units.
     */
    function toTokenAmount(uint256 amount, bytes32 currency, IERC20 token, bool roundUp)
        external
        view
        returns (uint256)
    {
        CurrencyLib.SettlementToken memory t = _requireToken(token);
        uint8 fromDec = _requireCurrency(currency).decimals;
        uint256 fromRate = usdRate(currency);
        uint256 toRate = t.currency == currency ? fromRate : usdRate(t.currency);
        return CurrencyLib.convert(amount, fromDec, fromRate, t.decimals, toRate, _rounding(roundUp));
    }

    /**
     * @notice The USD value of an amount priced in `currency`, for general display and reporting.
     * @param amount Amount, in `currency` units.
     * @param currency Pricing currency.
     * @return USD value, 6 decimals, rounded down.
     */
    function toUsd(uint256 amount, bytes32 currency) external view returns (uint256) {
        return convert(amount, currency, CurrencyLib.USD, false);
    }

    /**
     * @notice The USD value of an amount of settlement `token`.
     * @param token Settlement token.
     * @param amount Amount, in `token` units.
     * @return USD value, 6 decimals, rounded down.
     */
    function tokenToUsd(IERC20 token, uint256 amount) external view returns (uint256) {
        CurrencyLib.SettlementToken memory t = _requireToken(token);
        return CurrencyLib.convert(
            amount,
            t.decimals,
            usdRate(t.currency),
            CurrencyLib.USD_DECIMALS,
            CurrencyLib.RATE_PRECISION,
            Math.Rounding.Floor
        );
    }

    /*//////////////////////////////////////////////////////////////
                                  VIEWS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Whether `token` is an accepted settlement token.
     * @param token The token.
     * @return True if accepted.
     */
    function isSettlementToken(IERC20 token) external view returns (bool) {
        return _tokens[token].enabled;
    }

    /**
     * @notice Whether `code` is an enabled pricing currency.
     * @param code Currency code.
     * @return True if enabled.
     */
    function isCurrency(bytes32 code) external view returns (bool) {
        return _currencies[code].enabled;
    }

    /**
     * @notice The currency a settlement token is pegged to.
     * @dev Reverts if `token` is not an accepted settlement token.
     * @param token The token.
     * @return Currency code.
     */
    function currencyOf(IERC20 token) external view returns (bytes32) {
        return _requireToken(token).currency;
    }

    /**
     * @notice Returns a currency's configuration.
     * @param code Currency code.
     * @return The configuration (disabled if unknown).
     */
    function getCurrency(bytes32 code) external view returns (CurrencyLib.Currency memory) {
        return _currencies[code];
    }

    /**
     * @notice Returns a settlement token's configuration.
     * @param token The token.
     * @return The configuration (disabled if unknown).
     */
    function getSettlementToken(IERC20 token) external view returns (CurrencyLib.SettlementToken memory) {
        return _tokens[token];
    }

    /*//////////////////////////////////////////////////////////////
                                 INTERNAL
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Returns an enabled currency's configuration, reverting otherwise.
     * @param code Currency code.
     * @return c The configuration.
     */
    function _requireCurrency(bytes32 code) private view returns (CurrencyLib.Currency memory c) {
        c = _currencies[code];
        if (!c.enabled) revert CurrencyLib.CurrencyManager__UnknownCurrency(code);
    }

    /**
     * @dev Returns an accepted settlement token's configuration, reverting otherwise.
     * @param token The token.
     * @return t The configuration.
     */
    function _requireToken(IERC20 token) private view returns (CurrencyLib.SettlementToken memory t) {
        t = _tokens[token];
        if (!t.enabled) revert CurrencyLib.CurrencyManager__NotSettlementToken(token);
    }

    /**
     * @dev Maps a round-up flag to a rounding mode.
     * @param roundUp Round up (true) or down (false).
     * @return The rounding mode.
     */
    function _rounding(bool roundUp) private pure returns (Math.Rounding) {
        return roundUp ? Math.Rounding.Ceil : Math.Rounding.Floor;
    }

    /**
     * @dev Reverts unless the caller is a {MineNetRegistry} admin.
     */
    function _onlyAdmin() private view {
        if (!registry.isAdmin(msg.sender)) {
            revert CurrencyLib.CurrencyManager__NotRegistryAdmin(msg.sender);
        }
    }
}
