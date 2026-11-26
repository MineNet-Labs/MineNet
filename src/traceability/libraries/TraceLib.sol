// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

/**
 * @title TraceLib
 * @author 0xEmmyb2
 * @notice Shared types, events and custom errors of {LotTagRegistry} (QR tags) and {CargoTracker} (GPS).
 */
library TraceLib {
    /*//////////////////////////////////////////////////////////////
                                 QR TAGS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Status of a QR tag. `Void` tags were replaced (damaged or lost); any later scan is suspicious.
     */
    enum TagStatus {
        None,
        Active,
        Void // replaced (damaged or lost); any later scan is suspicious
    }

    /**
     * @notice Outcome of a tag scan.
     * @dev `Match`: the tag is active and the OCR read of the label / documents matches the lot. `OcrMismatch`: the
     * tag is active but the OCR read does not match (flagged). `VoidTag`: a replaced tag is still in circulation,
     * possibly a clone (flagged). `UnknownTag`: no lot has this tag, possibly smuggled material.
     */
    enum ScanResult {
        Match, // the tag is active and the OCR read of the label / documents matches the lot
        OcrMismatch, // the tag is active but the OCR read does not match the lot: flagged
        VoidTag, // a replaced tag is still in circulation (possible clone): flagged
        UnknownTag // no lot has this tag: possible smuggled material
    }

    /**
     * @notice A QR tag bound to a lot.
     * @param tokenId Lot the tag is bound to.
     * @param status Tag status.
     * @param boundAt When the tag was bound.
     * @param scans Number of scans.
     */
    struct Tag {
        uint256 tokenId;
        TagStatus status;
        uint64 boundAt;
        uint32 scans;
    }

    /**
     * @notice Emitted when a QR tag is bound to a lot.
     * @param tokenId The lot.
     * @param tagHash Hash of the tag serial.
     * @param by Account that bound it.
     */
    event TagBound(uint256 indexed tokenId, bytes32 indexed tagHash, address indexed by);

    /**
     * @notice Emitted when a lot's tag is voided (damaged or lost).
     * @param tokenId The lot.
     * @param tagHash Hash of the voided tag.
     * @param by Account that voided it.
     * @param reasonHash Hash of the reason.
     */
    event TagVoided(uint256 indexed tokenId, bytes32 indexed tagHash, address indexed by, bytes32 reasonHash);

    /**
     * @notice Emitted for every tag scan.
     * @param tagHash Hash of the scanned tag.
     * @param tokenId Lot it belongs to (0 if unknown).
     * @param scanner Scanning account.
     * @param result Scan outcome.
     * @param ocrHash Hash of the OCR read.
     * @param locationHash Hash of the scan location.
     */
    event TagScanned(
        bytes32 indexed tagHash,
        uint256 indexed tokenId,
        address indexed scanner,
        ScanResult result,
        bytes32 ocrHash,
        bytes32 locationHash
    );

    /**
     * @notice The tag hash is zero.
     */
    error LotTagRegistry__InvalidTag();

    /**
     * @notice Tag `tagHash` has already been bound to a lot.
     * @param tagHash The tag.
     */
    error LotTagRegistry__TagUsed(bytes32 tagHash);

    /**
     * @notice Lot `tokenId` already has active tag `tagHash`.
     * @param tokenId The lot.
     * @param tagHash Its active tag.
     */
    error LotTagRegistry__LotHasTag(uint256 tokenId, bytes32 tagHash);

    /**
     * @notice Lot `tokenId` has no active tag.
     * @param tokenId The lot.
     */
    error LotTagRegistry__NoActiveTag(uint256 tokenId);

    /**
     * @notice `account` is neither the owner nor the custodian of lot `tokenId`.
     * @param tokenId The lot.
     * @param account The account.
     */
    error LotTagRegistry__NotOwnerOrCustodian(uint256 tokenId, address account);

    /**
     * @notice `account` may not scan tags.
     * @param account The account.
     */
    error LotTagRegistry__Unauthorized(address account);

    /*//////////////////////////////////////////////////////////////
                               GPS TRACKERS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice A GPS tracker device.
     * @param device Device account that signs the tracker's own position reports.
     * @param active Whether the tracker may be used.
     * @param shipmentId Currently attached shipment (0 = none).
     */
    struct Tracker {
        address device;
        bool active;
        uint256 shipmentId;
    }

    /**
     * @notice The last position reported for a shipment.
     * @param latE6 Latitude, in micro-degrees.
     * @param lonE6 Longitude, in micro-degrees.
     * @param recordedAt Device time of the reading.
     * @param pings Number of position reports.
     */
    struct Position {
        int32 latE6;
        int32 lonE6;
        uint64 recordedAt;
        uint32 pings;
    }

    /**
     * @notice Alert bit: the case was opened or the seal sensor tripped. Flags the shipment's lots.
     */
    uint8 internal constant ALERT_TAMPER = 1;

    /**
     * @notice Alert bit: the tracker's battery is low.
     */
    uint8 internal constant ALERT_LOW_BATTERY = 2;

    /**
     * @notice Emitted when the admin registers a tracker.
     * @param trackerId Tracker id.
     * @param device Device signing account.
     */
    event TrackerRegistered(bytes32 indexed trackerId, address indexed device);

    /**
     * @notice Emitted when a tracker is enabled or disabled.
     * @param trackerId Tracker id.
     * @param active New state.
     */
    event TrackerActiveSet(bytes32 indexed trackerId, bool active);

    /**
     * @notice Emitted when a tracker is attached to a shipment.
     * @param shipmentId Shipment id.
     * @param trackerId Tracker id.
     * @param sealId Seal the tracker is fixed to.
     * @param by Shipper or carrier.
     */
    event TrackerAttached(uint256 indexed shipmentId, bytes32 indexed trackerId, bytes32 sealId, address by);

    /**
     * @notice Emitted when a tracker is detached from a shipment.
     * @param shipmentId Shipment id.
     * @param trackerId Tracker id.
     */
    event TrackerDetached(uint256 indexed shipmentId, bytes32 indexed trackerId);

    /**
     * @notice Emitted for every position report.
     * @param shipmentId Shipment id.
     * @param trackerId Tracker id.
     * @param latE6 Latitude, in micro-degrees.
     * @param lonE6 Longitude, in micro-degrees.
     * @param recordedAt Device time of the reading.
     * @param alerts Alert bits ({ALERT_TAMPER}, {ALERT_LOW_BATTERY}).
     */
    event PositionReported(
        uint256 indexed shipmentId, bytes32 indexed trackerId, int32 latE6, int32 lonE6, uint64 recordedAt, uint8 alerts
    );

    /**
     * @notice Emitted when a tracker reports tampering.
     * @param shipmentId Shipment id.
     * @param trackerId Tracker id.
     * @param recordedAt Device time of the reading.
     */
    event TamperAlert(uint256 indexed shipmentId, bytes32 indexed trackerId, uint64 recordedAt);

    /**
     * @notice Emitted when an oracle node reports that a shipment left its planned route.
     * @param shipmentId Shipment id.
     * @param oracle Reporting oracle node.
     * @param evidenceHash Hash of the comparison evidence.
     */
    event RouteDeviationReported(uint256 indexed shipmentId, address indexed oracle, bytes32 evidenceHash);

    /**
     * @notice Emitted when the admin sets the maximum time without a position report.
     * @param maxSilence Maximum silence, in seconds.
     */
    event MaxSilenceSet(uint32 maxSilence);

    /**
     * @notice `account` is not an admin of {MineNetRegistry}.
     * @param account The account.
     */
    error CargoTracker__NotRegistryAdmin(address account);

    /**
     * @notice Tracker `trackerId` is unknown, inactive or already registered.
     * @param trackerId The tracker.
     */
    error CargoTracker__InvalidTracker(bytes32 trackerId);

    /**
     * @notice Tracker `trackerId` is already attached to shipment `shipmentId`.
     * @param trackerId The tracker.
     * @param shipmentId Its current shipment.
     */
    error CargoTracker__TrackerBusy(bytes32 trackerId, uint256 shipmentId);

    /**
     * @notice Shipment `shipmentId` already has tracker `trackerId`.
     * @param shipmentId The shipment.
     * @param trackerId Its tracker.
     */
    error CargoTracker__ShipmentHasTracker(uint256 shipmentId, bytes32 trackerId);

    /**
     * @notice Shipment `shipmentId` has no tracker attached.
     * @param shipmentId The shipment.
     */
    error CargoTracker__NoTracker(uint256 shipmentId);

    /**
     * @notice `account` may not perform the operation.
     * @param account The account.
     */
    error CargoTracker__Unauthorized(address account);

    /**
     * @notice Shipment `shipmentId` is not in a status that allows the operation.
     * @param shipmentId The shipment.
     */
    error CargoTracker__InvalidShipmentState(uint256 shipmentId);

    /**
     * @notice The coordinates are out of range (also used for a zero maximum silence).
     */
    error CargoTracker__InvalidPosition();

    /**
     * @notice The report is not newer than the last one, or is in the future.
     * @param recordedAt Device time of the report.
     */
    error CargoTracker__StaleReport(uint64 recordedAt);

    /**
     * @notice `account` is a party to the shipment and cannot report on it.
     * @param account The account.
     */
    error CargoTracker__NotIndependent(address account);
}
