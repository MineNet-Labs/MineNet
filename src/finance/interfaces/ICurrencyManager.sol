// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title ICurrencyManager
 * @author 0xEmmyb2
 * @notice What other MineNet contracts need from {CurrencyManager}: settlement tokens, pricing currencies and
 * conversions at live rates.
 */
interface ICurrencyManager {
    /**
     * @notice USD per one unit of a currency, scaled to 1e18; reverts if unknown or stale.
     * @param code Currency code.
     * @return The rate.
     */
    function usdRate(bytes32 code) external view returns (uint256);

    /**
     * @notice Converts an amount between two pricing currencies at the live rates.
     * @param amount Amount, in `from` units.
     * @param from Source currency.
     * @param to Target currency.
     * @param roundUp Round up (true) or down (false).
     * @return Amount, in `to` units.
     */
    function convert(uint256 amount, bytes32 from, bytes32 to, bool roundUp) external view returns (uint256);

    /**
     * @notice How many units of settlement `token` an amount priced in `currency` costs right now.
     * @param amount Amount, in `currency` units.
     * @param currency Pricing currency.
     * @param token Settlement token.
     * @param roundUp Round up (true) or down (false).
     * @return Amount, in `token` units.
     */
    function toTokenAmount(uint256 amount, bytes32 currency, IERC20 token, bool roundUp) external view returns (uint256);

    /**
     * @notice The USD value (6 decimals) of an amount priced in `currency`.
     * @param amount Amount, in `currency` units.
     * @param currency Pricing currency.
     * @return USD value.
     */
    function toUsd(uint256 amount, bytes32 currency) external view returns (uint256);

    /**
     * @notice The USD value (6 decimals) of an amount of settlement `token`.
     * @param token Settlement token.
     * @param amount Amount, in `token` units.
     * @return USD value.
     */
    function tokenToUsd(IERC20 token, uint256 amount) external view returns (uint256);

    /**
     * @notice Whether `token` is an accepted settlement token.
     * @param token The token.
     * @return True if accepted.
     */
    function isSettlementToken(IERC20 token) external view returns (bool);

    /**
     * @notice Whether `code` is an enabled pricing currency.
     * @param code Currency code.
     * @return True if enabled.
     */
    function isCurrency(bytes32 code) external view returns (bool);

    /**
     * @notice The currency a settlement token is pegged to; reverts if not a settlement token.
     * @param token The token.
     * @return Currency code.
     */
    function currencyOf(IERC20 token) external view returns (bytes32);
}
