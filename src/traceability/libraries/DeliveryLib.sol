// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

/**
 * @title DeliveryLib
 * @author 0xEmmyb2
 * @notice Shared types, events and custom errors of {DeliveryManager}.
 */
library DeliveryLib {
    /**
     * @notice Lifecycle status of a shipment.
     * @dev `Created`: booked by the shipper, waiting for pickup. `InTransit`: the carrier holds custody. `Arrived`:
     * the carrier says it is at the consignee. `Delivered`: the consignee holds custody. `Cancelled`: terminal.
     */
    enum ShipmentStatus {
        None,
        Created, // booked by the shipper, waiting for pickup
        InTransit, // the carrier holds custody
        Arrived, // the carrier says it is at the consignee
        Delivered, // the consignee holds custody
        Cancelled
    }

    /**
     * @notice Kind of problem reported on a shipment.
     */
    enum ExceptionKind {
        Delay,
        Damage,
        Loss,
        Tamper,
        RouteDeviation,
        WeightMismatch,
        SealMismatch,
        Other
    }

    /**
     * @notice How a party wants an on-hold shipment to end.
     */
    enum HoldChoice {
        None,
        Continue,
        Cancel
    }

    /**
     * @notice A shipment of one or more lots from a shipper to a consignee.
     * @param shipper Account that booked the shipment and held custody at dispatch.
     * @param carrier Carrier (`CARRY`).
     * @param consignee Receiver (`RECEIVE_SHIPMENT`).
     * @param createdAt When the shipment was booked.
     * @param eta Expected time of arrival.
     * @param pickedUpAt When the carrier took custody (0 = not yet).
     * @param arrivedAt When the carrier reported arrival (0 = not yet).
     * @param deliveredAt When the consignee took custody (0 = not yet).
     * @param heldAt When the current hold began (0 = not on hold).
     * @param status Current status.
     * @param onHold True while a serious exception holds the shipment.
     * @param shipperChoice Shipper's choice for ending the hold.
     * @param consigneeChoice Consignee's choice for ending the hold.
     * @param exceptionCount Number of exceptions reported.
     * @param checkpointCount Number of checkpoints recorded.
     * @param sealId Hash of the seal applied at dispatch.
     * @param routeHash Hash of the planned route / transport permit.
     * @param podHash Hash of the proof of delivery.
     */
    struct Shipment {
        address shipper;
        address carrier;
        address consignee;
        uint64 createdAt;
        uint64 eta;
        uint64 pickedUpAt;
        uint64 arrivedAt;
        uint64 deliveredAt;
        uint64 heldAt;
        ShipmentStatus status;
        bool onHold;
        HoldChoice shipperChoice;
        HoldChoice consigneeChoice;
        uint32 exceptionCount;
        uint32 checkpointCount;
        bytes32 sealId;
        bytes32 routeHash;
        bytes32 podHash;
    }

    /**
     * @notice Delivery performance of a carrier.
     * @param delivered Shipments delivered.
     * @param onTime Shipments delivered by their ETA.
     * @param exceptions Exceptions reported on its shipments.
     */
    struct CarrierStats {
        uint32 delivered;
        uint32 onTime;
        uint32 exceptions;
    }

    /**
     * @notice Emitted when a shipment is booked.
     * @param shipmentId New shipment id.
     * @param shipper Shipper.
     * @param carrier Carrier.
     * @param consignee Consignee.
     * @param tokenIds Lots in the shipment.
     * @param eta Expected time of arrival.
     * @param sealId Hash of the dispatch seal.
     * @param routeHash Hash of the planned route / transport permit.
     */
    event ShipmentCreated(
        uint256 indexed shipmentId,
        address indexed shipper,
        address indexed carrier,
        address consignee,
        uint256[] tokenIds,
        uint64 eta,
        bytes32 sealId,
        bytes32 routeHash
    );

    /**
     * @notice Emitted when the carrier takes custody.
     * @param shipmentId Shipment id.
     * @param at Block timestamp.
     * @param evidenceHash Hash of the pickup evidence.
     */
    event ShipmentPickedUp(uint256 indexed shipmentId, uint64 at, bytes32 evidenceHash);

    /**
     * @notice Emitted when the carrier reports arrival at the consignee.
     * @param shipmentId Shipment id.
     * @param at Block timestamp.
     * @param evidenceHash Hash of the arrival evidence.
     */
    event ShipmentArrived(uint256 indexed shipmentId, uint64 at, bytes32 evidenceHash);

    /**
     * @notice Emitted when the consignee takes custody.
     * @param shipmentId Shipment id.
     * @param at Block timestamp.
     * @param onTime Whether it was delivered by its ETA.
     * @param podHash Hash of the proof of delivery.
     */
    event ShipmentDelivered(uint256 indexed shipmentId, uint64 at, bool onTime, bytes32 podHash);

    /**
     * @notice Emitted when a shipment is cancelled.
     * @param shipmentId Shipment id.
     * @param reasonHash Hash of the cancellation reason.
     */
    event ShipmentCancelled(uint256 indexed shipmentId, bytes32 reasonHash);

    /**
     * @notice Emitted when a checkpoint is recorded on a shipment's route.
     * @param shipmentId Shipment id.
     * @param reporter Account that recorded it.
     * @param locationHash Hash of the location.
     * @param dataHash Hash of the checkpoint data.
     * @param at Block timestamp.
     */
    event CheckpointRecorded(
        uint256 indexed shipmentId, address indexed reporter, bytes32 locationHash, bytes32 dataHash, uint64 at
    );

    /**
     * @notice Emitted when a shipment's ETA changes.
     * @param shipmentId Shipment id.
     * @param newEta New expected time of arrival.
     * @param reasonHash Hash of the reason.
     */
    event EtaUpdated(uint256 indexed shipmentId, uint64 newEta, bytes32 reasonHash);

    /**
     * @notice Emitted when a problem is reported on a shipment.
     * @param shipmentId Shipment id.
     * @param kind Kind of problem.
     * @param reporter Reporting account.
     * @param evidenceHash Hash of the evidence.
     */
    event ExceptionReported(
        uint256 indexed shipmentId, ExceptionKind indexed kind, address indexed reporter, bytes32 evidenceHash
    );

    /**
     * @notice Emitted when a party chooses how an on-hold shipment should end.
     * @param shipmentId Shipment id.
     * @param party Shipper or consignee.
     * @param choice Their choice.
     */
    event HoldChoiceMade(uint256 indexed shipmentId, address indexed party, HoldChoice choice);

    /**
     * @notice Emitted when a hold ends.
     * @param shipmentId Shipment id.
     * @param by Account that resolved it.
     * @param cancelled True if the shipment was cancelled, false if it continues.
     * @param resolutionHash Hash of the resolution.
     */
    event HoldResolved(uint256 indexed shipmentId, address indexed by, bool cancelled, bytes32 resolutionHash);

    /**
     * @notice The shipment contains no lots.
     */
    error DeliveryManager__EmptyShipment();

    /**
     * @notice The shipment contains more than `MAX_LOTS_PER_SHIPMENT` lots.
     */
    error DeliveryManager__TooManyLots();

    /**
     * @notice `account` is not the custodian of lot `tokenId`.
     * @param tokenId The lot.
     * @param account The account.
     */
    error DeliveryManager__NotCustodian(uint256 tokenId, address account);

    /**
     * @notice Lot `tokenId` is already in open shipment `shipmentId`.
     * @param tokenId The lot.
     * @param shipmentId The open shipment.
     */
    error DeliveryManager__AlreadyInShipment(uint256 tokenId, uint256 shipmentId);

    /**
     * @notice `carrier` is not an authorised carrier, or is the shipper.
     * @param carrier The carrier.
     */
    error DeliveryManager__InvalidCarrier(address carrier);

    /**
     * @notice `consignee` cannot receive the shipment (not authorised, or the shipper or carrier).
     * @param consignee The consignee.
     */
    error DeliveryManager__InvalidConsignee(address consignee);

    /**
     * @notice `eta` is not in the future.
     * @param eta The ETA.
     */
    error DeliveryManager__InvalidEta(uint64 eta);

    /**
     * @notice The seal id is zero.
     */
    error DeliveryManager__InvalidSeal();

    /**
     * @notice Shipment `shipmentId` is in `status`, which does not allow the operation.
     * @param shipmentId The shipment.
     * @param status Its current status.
     */
    error DeliveryManager__InvalidState(uint256 shipmentId, ShipmentStatus status);

    /**
     * @notice `account` may not perform the operation on this shipment.
     * @param account The account.
     */
    error DeliveryManager__Unauthorized(address account);

    /**
     * @notice Shipment `shipmentId` is on hold.
     * @param shipmentId The shipment.
     */
    error DeliveryManager__OnHold(uint256 shipmentId);

    /**
     * @notice Shipment `shipmentId` is not on hold.
     * @param shipmentId The shipment.
     */
    error DeliveryManager__NotOnHold(uint256 shipmentId);

    /**
     * @notice The hold on shipment `shipmentId` cannot be force-resolved before `expiresAt`.
     * @param shipmentId The shipment.
     * @param expiresAt When the hold times out.
     */
    error DeliveryManager__HoldNotExpired(uint256 shipmentId, uint64 expiresAt);

    /**
     * @notice The hold choice is `None`.
     */
    error DeliveryManager__InvalidChoice();

    /**
     * @notice The number of weights does not match the number of lots in the shipment.
     * @param expected Number of lots.
     * @param given Number of weights supplied.
     */
    error DeliveryManager__WeightCountMismatch(uint256 expected, uint256 given);
}
