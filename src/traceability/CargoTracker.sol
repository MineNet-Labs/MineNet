// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {IMineNetRegistry} from "src/access/interfaces/IMineNetRegistry.sol";
import {ILotPassport} from "src/traceability/interfaces/ILotPassport.sol";
import {IDeliveryManager} from "src/traceability/interfaces/IDeliveryManager.sol";
import {Actions} from "src/access/libraries/Actions.sol";
import {DeliveryLib} from "src/traceability/libraries/DeliveryLib.sol";
import {TraceLib} from "src/traceability/libraries/TraceLib.sol";

/**
 * @title CargoTracker
 * @author 0xEmmyb2
 * @notice GPS tracking of cargo in transit.
 * @dev Each tracker is a registered device that signs its own position reports from its own key, so positions
 * come from the device rather than from the carrier.
 *
 * The shipper or carrier attaches a tracker to a {DeliveryManager} shipment, which links it to the shipment's
 * seal and the lots' QR tags. While the shipment moves the device reports its position (the latest one is kept
 * on-chain, the full track is in the events):
 * - a tamper alert from the device (case opened, seal sensor) flags every lot in the shipment;
 * - an oracle node that compares the GPS track with the planned route (the shipment's `routeHash`) reports a
 *   deviation, which flags the lots too;
 * - a tracker that stays silent longer than {maxSilence} shows up in {isSilent}.
 * A flag freezes the lots on the passport, so custody cannot move at delivery until a regulator resolves it.
 *
 * Must be enabled as a passport module (`passport.setModule`) so it can raise flags.
 */
contract CargoTracker {
    /**
     * @notice Participant, role and permission registry.
     */
    IMineNetRegistry public immutable registry;

    /**
     * @notice Lot passport on which lots are flagged.
     */
    ILotPassport public immutable passport;

    /**
     * @notice Shipments that trackers are attached to.
     */
    IDeliveryManager public immutable delivery;

    /**
     * @notice Longest acceptable gap between position reports of a shipment in transit.
     */
    uint32 public maxSilence = 2 hours;

    /**
     * @dev Tracker id => tracker.
     */
    mapping(bytes32 trackerId => TraceLib.Tracker) private _trackers;

    /**
     * @notice The tracker attached to a shipment (zero if none).
     */
    mapping(uint256 shipmentId => bytes32 trackerId) public trackerOf;

    /**
     * @dev Shipment => last reported position.
     */
    mapping(uint256 shipmentId => TraceLib.Position) private _lastPosition;

    /**
     * @param registry_ Participant, role and permission registry.
     * @param passport_ Lot passport.
     * @param delivery_ Delivery manager.
     */
    constructor(IMineNetRegistry registry_, ILotPassport passport_, IDeliveryManager delivery_) {
        registry = registry_;
        passport = passport_;
        delivery = delivery_;
    }

    /*//////////////////////////////////////////////////////////////
                              ADMIN: DEVICES
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Registers a tracker device.
     * @dev Only a {MineNetRegistry} admin. The tracker starts active.
     * @param trackerId Tracker id; non-zero and not yet registered.
     * @param device Device account that signs the tracker's position reports.
     * @custom:emits TrackerRegistered
     */
    function registerTracker(bytes32 trackerId, address device) external {
        _onlyAdmin();
        if (trackerId == bytes32(0) || device == address(0) || _trackers[trackerId].device != address(0)) {
            revert TraceLib.CargoTracker__InvalidTracker(trackerId);
        }
        _trackers[trackerId] = TraceLib.Tracker({device: device, active: true, shipmentId: 0});
        emit TraceLib.TrackerRegistered(trackerId, device);
    }

    /**
     * @notice Enables or disables a tracker.
     * @dev Only a {MineNetRegistry} admin.
     * @param trackerId Tracker id.
     * @param active New state.
     * @custom:emits TrackerActiveSet
     */
    function setTrackerActive(bytes32 trackerId, bool active) external {
        _onlyAdmin();
        if (_trackers[trackerId].device == address(0)) revert TraceLib.CargoTracker__InvalidTracker(trackerId);
        _trackers[trackerId].active = active;
        emit TraceLib.TrackerActiveSet(trackerId, active);
    }

    /**
     * @notice Sets the longest acceptable gap between position reports.
     * @dev Only a {MineNetRegistry} admin.
     * @param maxSilence_ Maximum silence, in seconds; non-zero.
     * @custom:emits MaxSilenceSet
     */
    function setMaxSilence(uint32 maxSilence_) external {
        _onlyAdmin();
        if (maxSilence_ == 0) revert TraceLib.CargoTracker__InvalidPosition();
        maxSilence = maxSilence_;
        emit TraceLib.MaxSilenceSet(maxSilence_);
    }

    /*//////////////////////////////////////////////////////////////
                            SHIPPER / CARRIER
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Attaches a tracker to a shipment that has not been delivered yet.
     * @dev Only the shipment's shipper or carrier. Attaching another tracker later (e.g. after a device failure)
     * replaces the first one, and the swap is recorded.
     * @param shipmentId Shipment id (status `Created` or `InTransit`).
     * @param trackerId Active tracker that is not on another live shipment.
     * @custom:emits TrackerDetached (when replacing a tracker)
     * @custom:emits TrackerAttached
     */
    function attachTracker(uint256 shipmentId, bytes32 trackerId) external {
        DeliveryLib.Shipment memory s = delivery.getShipment(shipmentId);
        if (msg.sender != s.shipper && msg.sender != s.carrier) revert TraceLib.CargoTracker__Unauthorized(msg.sender);
        if (s.status != DeliveryLib.ShipmentStatus.Created && s.status != DeliveryLib.ShipmentStatus.InTransit) {
            revert TraceLib.CargoTracker__InvalidShipmentState(shipmentId);
        }
        TraceLib.Tracker storage t = _trackers[trackerId];
        if (t.device == address(0) || !t.active) revert TraceLib.CargoTracker__InvalidTracker(trackerId);
        if (t.shipmentId != 0 && t.shipmentId != shipmentId && _isLive(t.shipmentId)) {
            revert TraceLib.CargoTracker__TrackerBusy(trackerId, t.shipmentId);
        }
        bytes32 previous = trackerOf[shipmentId];
        if (previous == trackerId) revert TraceLib.CargoTracker__ShipmentHasTracker(shipmentId, trackerId);
        if (previous != bytes32(0)) {
            _trackers[previous].shipmentId = 0;
            emit TraceLib.TrackerDetached(shipmentId, previous);
        }
        t.shipmentId = shipmentId;
        trackerOf[shipmentId] = trackerId;
        emit TraceLib.TrackerAttached(shipmentId, trackerId, s.sealId, msg.sender);
    }

    /*//////////////////////////////////////////////////////////////
                              TRACKER DEVICE
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice The attached device reports a position and any alerts. A tamper alert flags every lot in the
     * shipment.
     * @dev Only the device of the shipment's tracker, while the shipment is `InTransit` or `Arrived`. Reports must
     * be strictly newer than the last one and not in the future.
     * @param shipmentId Shipment id.
     * @param latE6 Latitude, in micro-degrees.
     * @param lonE6 Longitude, in micro-degrees.
     * @param recordedAt Device time of the reading.
     * @param alerts Alert bits ({TraceLib.ALERT_TAMPER}, {TraceLib.ALERT_LOW_BATTERY}).
     * @custom:emits PositionReported
     * @custom:emits TamperAlert (on a tamper alert)
     */
    function reportPosition(uint256 shipmentId, int32 latE6, int32 lonE6, uint64 recordedAt, uint8 alerts) external {
        bytes32 trackerId = trackerOf[shipmentId];
        if (trackerId == bytes32(0)) revert TraceLib.CargoTracker__NoTracker(shipmentId);
        TraceLib.Tracker storage t = _trackers[trackerId];
        if (msg.sender != t.device || !t.active) revert TraceLib.CargoTracker__Unauthorized(msg.sender);
        DeliveryLib.ShipmentStatus status = delivery.getShipment(shipmentId).status;
        if (status != DeliveryLib.ShipmentStatus.InTransit && status != DeliveryLib.ShipmentStatus.Arrived) {
            revert TraceLib.CargoTracker__InvalidShipmentState(shipmentId);
        }
        if (latE6 < -90e6 || latE6 > 90e6 || lonE6 < -180e6 || lonE6 > 180e6) {
            revert TraceLib.CargoTracker__InvalidPosition();
        }
        TraceLib.Position storage p = _lastPosition[shipmentId];
        if (recordedAt <= p.recordedAt || recordedAt > block.timestamp) {
            revert TraceLib.CargoTracker__StaleReport(recordedAt);
        }

        p.latE6 = latE6;
        p.lonE6 = lonE6;
        p.recordedAt = recordedAt;
        p.pings += 1;
        emit TraceLib.PositionReported(shipmentId, trackerId, latE6, lonE6, recordedAt, alerts);

        if (alerts & TraceLib.ALERT_TAMPER != 0) {
            emit TraceLib.TamperAlert(shipmentId, trackerId, recordedAt);
            _flagLots(shipmentId, msg.sender, keccak256(abi.encode("GPS_TAMPER", trackerId, recordedAt)));
        }
    }

    /*//////////////////////////////////////////////////////////////
                                  ORACLE
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice An oracle node reports that the GPS track left the planned route. The shipment's lots are flagged.
     * @dev Only an oracle node (`REPORT_READING`) that is not a party to the shipment, while it is `InTransit` or
     * `Arrived`.
     * @param shipmentId Shipment id.
     * @param evidenceHash Hash of the track-versus-route comparison.
     * @custom:emits RouteDeviationReported
     */
    function reportRouteDeviation(uint256 shipmentId, bytes32 evidenceHash) external {
        if (!registry.isAuthorized(msg.sender, Actions.REPORT_READING)) {
            revert TraceLib.CargoTracker__Unauthorized(msg.sender);
        }
        DeliveryLib.Shipment memory s = delivery.getShipment(shipmentId);
        if (msg.sender == s.shipper || msg.sender == s.carrier || msg.sender == s.consignee) {
            revert TraceLib.CargoTracker__NotIndependent(msg.sender);
        }
        if (s.status != DeliveryLib.ShipmentStatus.InTransit && s.status != DeliveryLib.ShipmentStatus.Arrived) {
            revert TraceLib.CargoTracker__InvalidShipmentState(shipmentId);
        }
        emit TraceLib.RouteDeviationReported(shipmentId, msg.sender, evidenceHash);
        _flagLots(shipmentId, msg.sender, evidenceHash);
    }

    /*//////////////////////////////////////////////////////////////
                                  VIEWS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns a tracker.
     * @param trackerId Tracker id.
     * @return The tracker (zero device if unknown).
     */
    function getTracker(bytes32 trackerId) external view returns (TraceLib.Tracker memory) {
        return _trackers[trackerId];
    }

    /**
     * @notice Returns the last position reported for a shipment.
     * @param shipmentId Shipment id.
     * @return The position (all zero if none).
     */
    function lastPosition(uint256 shipmentId) external view returns (TraceLib.Position memory) {
        return _lastPosition[shipmentId];
    }

    /**
     * @notice Whether a shipment in transit has gone quiet.
     * @param shipmentId Shipment id.
     * @return True if the shipment is `InTransit` and has no tracker, or has not reported for longer than
     * {maxSilence} since its last report or pickup.
     */
    function isSilent(uint256 shipmentId) external view returns (bool) {
        DeliveryLib.Shipment memory s = delivery.getShipment(shipmentId);
        if (s.status != DeliveryLib.ShipmentStatus.InTransit) return false;
        if (trackerOf[shipmentId] == bytes32(0)) return true;
        uint64 last = _lastPosition[shipmentId].recordedAt;
        if (last < s.pickedUpAt) last = s.pickedUpAt;
        return block.timestamp > last + maxSilence;
    }

    /*//////////////////////////////////////////////////////////////
                                 INTERNAL
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Raises a flag on every lot of a shipment.
     * @param shipmentId Shipment id.
     * @param reporter Account recorded as raising the flag.
     * @param evidenceHash Hash of the evidence.
     */
    function _flagLots(uint256 shipmentId, address reporter, bytes32 evidenceHash) private {
        uint256[] memory lots = delivery.lotsOf(shipmentId);
        for (uint256 i; i < lots.length; ++i) {
            passport.moduleFlag(lots[i], reporter, evidenceHash);
        }
    }

    /**
     * @dev Whether a shipment is still open (`Created`, `InTransit` or `Arrived`).
     * @param shipmentId Shipment id.
     * @return True if open.
     */
    function _isLive(uint256 shipmentId) private view returns (bool) {
        DeliveryLib.ShipmentStatus st = delivery.getShipment(shipmentId).status;
        return st == DeliveryLib.ShipmentStatus.Created || st == DeliveryLib.ShipmentStatus.InTransit
            || st == DeliveryLib.ShipmentStatus.Arrived;
    }

    /**
     * @dev Reverts unless the caller is a {MineNetRegistry} admin.
     */
    function _onlyAdmin() private view {
        if (!registry.isAdmin(msg.sender)) {
            revert TraceLib.CargoTracker__NotRegistryAdmin(msg.sender);
        }
    }
}
