// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {EscrowLib} from "src/trade/libraries/EscrowLib.sol";

/**
 * @title IEscrowManager
 * @author 0xEmmyb2
 * @notice What the {Marketplace} needs from {EscrowManager}: opening orders and reading them.
 */
interface IEscrowManager {
    /**
     * @notice Shortest delivery window an order may have.
     * @return Seconds.
     */
    function MIN_DELIVERY_WINDOW() external view returns (uint32);

    /**
     * @notice Longest delivery window an order may have.
     * @return Seconds.
     */
    function MAX_DELIVERY_WINDOW() external view returns (uint32);

    /**
     * @notice Opens a funded order, locking the lot and pulling the payment in; only the marketplace.
     * @param p Order parameters.
     * @return orderId New order id.
     */
    function openOrder(EscrowLib.OpenParams calldata p) external returns (uint256 orderId);

    /**
     * @notice Returns an order.
     * @param orderId Order id.
     * @return The order (status `None` if unknown).
     */
    function getOrder(uint256 orderId) external view returns (EscrowLib.Order memory);
}
