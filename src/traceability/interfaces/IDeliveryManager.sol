// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {DeliveryLib} from "src/traceability/libraries/DeliveryLib.sol";

/**
 * @title IDeliveryManager
 * @author 0xEmmyb2
 * @notice What other MineNet contracts need from {DeliveryManager}: shipments and the lots they carry.
 */
interface IDeliveryManager {
    /**
     * @notice The open shipment a lot is in (0 if none).
     * @param tokenId Lot.
     * @return shipmentId The shipment id.
     */
    function activeShipmentOf(uint256 tokenId) external view returns (uint256 shipmentId);

    /**
     * @notice Returns a shipment.
     * @param shipmentId Shipment id.
     * @return The shipment (status `None` if unknown).
     */
    function getShipment(uint256 shipmentId) external view returns (DeliveryLib.Shipment memory);

    /**
     * @notice Returns a shipment's lots, in booking order.
     * @param shipmentId Shipment id.
     * @return Lot token ids.
     */
    function lotsOf(uint256 shipmentId) external view returns (uint256[] memory);
}
