// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {IDeliveryManager} from "src/traceability/interfaces/IDeliveryManager.sol";
import {IMineNetRegistry} from "src/access/interfaces/IMineNetRegistry.sol";
import {ILotPassport} from "src/traceability/interfaces/ILotPassport.sol";
import {ISupplyChain} from "src/traceability/interfaces/ISupplyChain.sol";
import {IStaffDirectory} from "src/workforce/interfaces/IStaffDirectory.sol";
import {StaffLib} from "src/workforce/libraries/StaffLib.sol";
import {Actions} from "src/access/libraries/Actions.sol";
import {DeliveryLib} from "src/traceability/libraries/DeliveryLib.sol";
import {SupplyChainLib} from "src/traceability/libraries/SupplyChainLib.sol";

/**
 * @title DeliveryManager
 * @author 0xEmmyb2
 * @notice Custody in motion (project.md 6.1 Transporter, 6.4 steps 10 and 13). A shipment carries one or more
 * lots from a shipper to a consignee (warehouse, processor, refinery or buyer).
 * @dev Every handover needs both sides, and custody moves only through this contract:
 * - Pickup: the shipper books the shipment (names the carrier, lots and seal id), then the carrier confirms
 *   pickup with measured weights and the seal it found. Custody moves shipper -> carrier.
 * - Delivery: the carrier marks arrival, then the consignee confirms with measured weights, the seal it found
 *   and the lots' condition. Custody moves carrier -> consignee.
 *
 * Every weight goes through {SupplyChain}'s mass-balance ledger, so weight continuity holds across warehouse
 * check-out, pickup, arrival and the next check-in. If a weight is outside tolerance, the seal does not match,
 * or a lot arrives damaged, the lot is flagged on the passport, the shipment goes on hold, and custody does NOT
 * move. The evidence is still recorded. The shipper and consignee resolve the hold between themselves
 * ({chooseHoldOutcome}); if they do not agree in time, anyone can cancel it ({expireHold}). No third party is
 * needed.
 *
 * Types, events and errors live in {DeliveryLib}; permissions are registry actions. Must be enabled as a module
 * on both {LotPassport} and {SupplyChain}.
 */
contract DeliveryManager is IDeliveryManager {
    /**
     * @notice Maximum number of lots in one shipment.
     */
    uint256 public constant MAX_LOTS_PER_SHIPMENT = 50;

    /**
     * @notice How long the parties have to agree on an on-hold shipment before anyone can cancel it.
     */
    uint64 public constant HOLD_TIMEOUT = 14 days;

    /**
     * @notice Participant, role and permission registry.
     */
    IMineNetRegistry public immutable registry;

    /**
     * @notice Lot passport on which custody moves.
     */
    ILotPassport public immutable passport;

    /**
     * @notice Mass-balance ledger that records every weighing.
     */
    ISupplyChain public immutable supplyChain;

    /**
     * @dev Next shipment id; ids start at 1 so that 0 means "none".
     */
    uint256 private _nextShipmentId = 1;

    /**
     * @dev Shipment id => shipment.
     */
    mapping(uint256 shipmentId => DeliveryLib.Shipment) private _shipments;

    /**
     * @dev Shipment id => its lots, in booking order.
     */
    mapping(uint256 shipmentId => uint256[]) private _shipmentLots;

    /**
     * @notice The open shipment a lot is in (0 if none).
     */
    mapping(uint256 tokenId => uint256 shipmentId) public activeShipmentOf;

    /**
     * @notice Delivery performance of each carrier.
     */
    mapping(address carrier => DeliveryLib.CarrierStats) public carrierStats;

    /**
     * @notice Company staff directory, for site managers dispatching their company's lots (zero = none).
     */
    IStaffDirectory public staffDirectory;

    /**
     * @notice Vehicle, driver, receiving worker and dispatcher of a dispatched shipment.
     */
    mapping(uint256 shipmentId => DeliveryLib.Transport) public transportOf;

    /**
     * @param registry_ Participant, role and permission registry.
     * @param passport_ Lot passport.
     * @param supplyChain_ Supply-chain ledger.
     */
    constructor(IMineNetRegistry registry_, ILotPassport passport_, ISupplyChain supplyChain_) {
        registry = registry_;
        passport = passport_;
        supplyChain = supplyChain_;
    }

    /*//////////////////////////////////////////////////////////////
                                  ADMIN
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Sets the company staff directory ({WorkforceManager}) checked when staff dispatch lots.
     * @dev Only a {MineNetRegistry} admin.
     * @param staff_ The directory, or zero to disable staff dispatch.
     * @custom:emits StaffDirectorySet
     */
    function setStaffDirectory(IStaffDirectory staff_) external {
        if (!registry.isAdmin(msg.sender)) revert DeliveryLib.DeliveryManager__Unauthorized(msg.sender);
        staffDirectory = staff_;
        emit DeliveryLib.StaffDirectorySet(address(staff_));
    }

    /*//////////////////////////////////////////////////////////////
                 SHIPPER (SENDER OF THE PICKUP HANDOVER)
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Books a shipment: the custodian of every lot names the carrier, the consignee and the seal it
     * applied.
     * @dev The caller must be the custodian of every lot, none of which may be in another open shipment.
     * @param tokenIds Lots to ship (1 to {MAX_LOTS_PER_SHIPMENT}, no duplicates).
     * @param carrier Authorised carrier (`CARRY`), not the caller.
     * @param consignee Authorised receiver (`RECEIVE_SHIPMENT`), neither the caller nor the carrier.
     * @param eta Expected time of arrival; in the future.
     * @param sealId Hash of the seal applied at dispatch; non-zero.
     * @param routeHash Hash of the planned route / transport permit.
     * @return shipmentId New shipment id.
     * @custom:emits ShipmentCreated
     */
    function createShipment(
        uint256[] calldata tokenIds,
        address carrier,
        address consignee,
        uint64 eta,
        bytes32 sealId,
        bytes32 routeHash
    ) external returns (uint256 shipmentId) {
        shipmentId = _book(msg.sender, tokenIds, carrier, consignee, eta, sealId, routeHash);
    }

    /**
     * @notice Dispatches lots to a carrier, signing the physical handover: the vehicle plate, the driver, the
     * receiving worker at the (verified) consignee, and the weight handed over per lot.
     * @dev The custodian of every lot, or staff of the custodian's company holding `DISPATCH_LOTS` at every lot's
     * mine site (the site manager dispatching the company's lots; the shipment is booked for the company). The
     * same rules as {createShipment} apply. The carrier checks the weights at pickup ({confirmPickup}).
     * @param d The dispatch.
     * @return shipmentId New shipment id.
     * @custom:emits ShipmentCreated
     * @custom:emits Dispatched
     */
    function dispatch(DeliveryLib.DispatchInput calldata d) external returns (uint256 shipmentId) {
        uint256 n = d.tokenIds.length;
        if (n == 0) revert DeliveryLib.DeliveryManager__EmptyShipment();
        if (d.plateNo == bytes32(0) || d.driverRef == bytes32(0) || d.weights.length != n) {
            revert DeliveryLib.DeliveryManager__InvalidTransport();
        }
        address shipper = passport.custodianOf(d.tokenIds[0]);
        if (msg.sender != shipper) {
            if (d.carrier == msg.sender) revert DeliveryLib.DeliveryManager__InvalidCarrier(d.carrier);
            IStaffDirectory dir = staffDirectory;
            bytes32 orgId = registry.participant(shipper).orgId;
            for (uint256 i; i < n; ++i) {
                if (
                    address(dir) == address(0) || orgId == bytes32(0)
                        || dir.staffOrg(msg.sender, passport.siteOf(d.tokenIds[i]), StaffLib.DISPATCH_LOTS) != orgId
                ) revert DeliveryLib.DeliveryManager__Unauthorized(msg.sender);
            }
        }
        shipmentId = _book(shipper, d.tokenIds, d.carrier, d.consignee, d.eta, d.sealId, d.routeHash);
        transportOf[shipmentId] = DeliveryLib.Transport({
            plateNo: d.plateNo, driverRef: d.driverRef, receiverRef: d.receiverRef, dispatchedBy: msg.sender
        });
        emit DeliveryLib.Dispatched(shipmentId, msg.sender, d.plateNo, d.driverRef, d.receiverRef, d.weights);
    }

    /**
     * @notice The consignee names (or changes) the worker who will receive the shipment.
     * @dev Only the consignee, before delivery.
     * @param shipmentId Shipment id.
     * @param receiverRef Hashed id of the receiving worker.
     * @custom:emits ReceiverNamed
     */
    function setReceiver(uint256 shipmentId, bytes32 receiverRef) external {
        DeliveryLib.Shipment storage s = _shipments[shipmentId];
        if (msg.sender != s.consignee) revert DeliveryLib.DeliveryManager__Unauthorized(msg.sender);
        if (s.status == DeliveryLib.ShipmentStatus.Delivered || s.status == DeliveryLib.ShipmentStatus.Cancelled) {
            revert DeliveryLib.DeliveryManager__InvalidState(shipmentId, s.status);
        }
        transportOf[shipmentId].receiverRef = receiverRef;
        emit DeliveryLib.ReceiverNamed(shipmentId, receiverRef);
    }

    /**
     * @notice Cancels a shipment before pickup and frees its lots.
     * @dev Only the shipper (or the staff member who dispatched it), while the shipment is `Created`.
     * @param shipmentId Shipment id.
     * @param reasonHash Hash of the reason.
     * @custom:emits ShipmentCancelled
     */
    function cancelShipment(uint256 shipmentId, bytes32 reasonHash) external {
        DeliveryLib.Shipment storage s = _shipments[shipmentId];
        if (msg.sender != s.shipper && msg.sender != transportOf[shipmentId].dispatchedBy) {
            revert DeliveryLib.DeliveryManager__Unauthorized(msg.sender);
        }
        _requireStatus(shipmentId, DeliveryLib.ShipmentStatus.Created);
        _cancel(shipmentId, reasonHash);
    }

    /*//////////////////////////////////////////////////////////////
                                 CARRIER
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice The carrier confirms pickup: it weighs every lot and checks the seal it received.
     * @dev Only the carrier, while the shipment is `Created` and not on hold. If everything matches, custody moves
     * shipper -> carrier and the shipment is `InTransit`. If not, the mismatch is recorded, the lots are flagged
     * and
     * the shipment goes on hold.
     * @param shipmentId Shipment id.
     * @param weights Measured weight in grams per lot, in the shipment's lot order.
     * @param sealId Seal the carrier found.
     * @param evidenceHash Hash of the pickup evidence (weighbridge tickets, photos...).
     * @return ok True if custody moved.
     * @custom:emits ShipmentPickedUp (on success)
     * @custom:emits ExceptionReported (on a mismatch)
     */
    function confirmPickup(uint256 shipmentId, uint128[] calldata weights, bytes32 sealId, bytes32 evidenceHash)
        external
        returns (bool ok)
    {
        DeliveryLib.Shipment storage s = _shipments[shipmentId];
        if (msg.sender != s.carrier) revert DeliveryLib.DeliveryManager__Unauthorized(msg.sender);
        _requireStatus(shipmentId, DeliveryLib.ShipmentStatus.Created);
        if (s.onHold) revert DeliveryLib.DeliveryManager__OnHold(shipmentId);

        ok = _verifyLots(
            shipmentId,
            SupplyChainLib.CheckpointType.Pickup,
            weights,
            sealId,
            SupplyChainLib.Condition.Good,
            evidenceHash
        );
        if (!ok) return false;

        _handover(shipmentId, s.shipper, s.carrier, evidenceHash);
        s.status = DeliveryLib.ShipmentStatus.InTransit;
        s.pickedUpAt = uint64(block.timestamp);
        emit DeliveryLib.ShipmentPickedUp(shipmentId, s.pickedUpAt, evidenceHash);
    }

    /**
     * @notice Records a location or sensor reading in transit (GPS seal, temperature...).
     * @dev The carrier or an oracle device (`REPORT_READING`), while the shipment is `InTransit`. Only a counter is
     * stored; the data is in the event.
     * @param shipmentId Shipment id.
     * @param locationHash Hash of the location.
     * @param dataHash Hash of the reading.
     * @custom:emits CheckpointRecorded
     */
    function recordCheckpoint(uint256 shipmentId, bytes32 locationHash, bytes32 dataHash) external {
        DeliveryLib.Shipment storage s = _shipments[shipmentId];
        if (msg.sender != s.carrier && !registry.isAuthorized(msg.sender, Actions.REPORT_READING)) {
            revert DeliveryLib.DeliveryManager__Unauthorized(msg.sender);
        }
        _requireStatus(shipmentId, DeliveryLib.ShipmentStatus.InTransit);
        s.checkpointCount += 1;
        emit DeliveryLib.CheckpointRecorded(shipmentId, msg.sender, locationHash, dataHash, uint64(block.timestamp));
    }

    /**
     * @notice Updates a shipment's expected time of arrival.
     * @dev Only the carrier, before arrival.
     * @param shipmentId Shipment id.
     * @param newEta New ETA; in the future.
     * @param reasonHash Hash of the reason.
     * @custom:emits EtaUpdated
     */
    function updateEta(uint256 shipmentId, uint64 newEta, bytes32 reasonHash) external {
        DeliveryLib.Shipment storage s = _shipments[shipmentId];
        if (msg.sender != s.carrier) revert DeliveryLib.DeliveryManager__Unauthorized(msg.sender);
        if (s.status != DeliveryLib.ShipmentStatus.Created && s.status != DeliveryLib.ShipmentStatus.InTransit) {
            revert DeliveryLib.DeliveryManager__InvalidState(shipmentId, s.status);
        }
        if (newEta <= block.timestamp) revert DeliveryLib.DeliveryManager__InvalidEta(newEta);
        s.eta = newEta;
        emit DeliveryLib.EtaUpdated(shipmentId, newEta, reasonHash);
    }

    /**
     * @notice The carrier declares arrival at the consignee (its side of the delivery handover). On-time
     * performance is measured at this point.
     * @dev Only the carrier, while the shipment is `InTransit`.
     * @param shipmentId Shipment id.
     * @param evidenceHash Hash of the arrival evidence.
     * @custom:emits ShipmentArrived
     */
    function markArrived(uint256 shipmentId, bytes32 evidenceHash) external {
        DeliveryLib.Shipment storage s = _shipments[shipmentId];
        if (msg.sender != s.carrier) revert DeliveryLib.DeliveryManager__Unauthorized(msg.sender);
        _requireStatus(shipmentId, DeliveryLib.ShipmentStatus.InTransit);
        s.status = DeliveryLib.ShipmentStatus.Arrived;
        s.arrivedAt = uint64(block.timestamp);
        emit DeliveryLib.ShipmentArrived(shipmentId, s.arrivedAt, evidenceHash);
    }

    /*//////////////////////////////////////////////////////////////
              CONSIGNEE (RECEIVER OF THE DELIVERY HANDOVER)
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice The consignee weighs every lot, checks the seal and records the lots' condition.
     * @dev Only the consignee, while the shipment is `Arrived` and not on hold. If everything matches, custody
     * moves
     * carrier -> consignee and the shipment is `Delivered`. Otherwise the lots are flagged and the shipment goes on
     * hold, with custody staying with the carrier.
     * @param shipmentId Shipment id.
     * @param weights Measured weight in grams per lot, in the shipment's lot order.
     * @param sealId Seal the consignee found.
     * @param condition Condition of the lots on arrival.
     * @param podHash Hash of the proof of delivery.
     * @return ok True if custody moved.
     * @custom:emits ShipmentDelivered (on success)
     * @custom:emits ExceptionReported (on a mismatch)
     */
    function confirmDelivery(
        uint256 shipmentId,
        uint128[] calldata weights,
        bytes32 sealId,
        SupplyChainLib.Condition condition,
        bytes32 podHash
    ) external returns (bool ok) {
        DeliveryLib.Shipment storage s = _shipments[shipmentId];
        if (msg.sender != s.consignee) revert DeliveryLib.DeliveryManager__Unauthorized(msg.sender);
        _requireStatus(shipmentId, DeliveryLib.ShipmentStatus.Arrived);
        if (s.onHold) revert DeliveryLib.DeliveryManager__OnHold(shipmentId);

        ok = _verifyLots(shipmentId, SupplyChainLib.CheckpointType.Arrival, weights, sealId, condition, podHash);
        if (!ok) return false;

        _handover(shipmentId, s.carrier, s.consignee, podHash);
        s.status = DeliveryLib.ShipmentStatus.Delivered;
        s.deliveredAt = uint64(block.timestamp);
        s.podHash = podHash;
        bool onTime = s.arrivedAt <= s.eta;

        DeliveryLib.CarrierStats storage cs = carrierStats[s.carrier];
        cs.delivered += 1;
        if (onTime) cs.onTime += 1;

        _clearLots(shipmentId);
        emit DeliveryLib.ShipmentDelivered(shipmentId, s.deliveredAt, onTime, podHash);
    }

    /*//////////////////////////////////////////////////////////////
                            EXCEPTIONS & HOLDS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Reports a problem with a shipment. A `Loss` or `Tamper` report puts the shipment on hold.
     * @dev The shipper, carrier, consignee, an oracle node or a regulator, while the shipment is open.
     * @param shipmentId Shipment id.
     * @param kind Kind of problem.
     * @param evidenceHash Hash of the evidence.
     * @custom:emits ExceptionReported
     */
    function reportException(uint256 shipmentId, DeliveryLib.ExceptionKind kind, bytes32 evidenceHash) external {
        DeliveryLib.Shipment storage s = _shipments[shipmentId];
        if (
            msg.sender != s.shipper && msg.sender != s.carrier && msg.sender != s.consignee
                && !registry.isAuthorized(msg.sender, Actions.REPORT_READING)
                && !registry.isAuthorized(msg.sender, Actions.REGULATE)
        ) revert DeliveryLib.DeliveryManager__Unauthorized(msg.sender);
        if (
            s.status == DeliveryLib.ShipmentStatus.None || s.status == DeliveryLib.ShipmentStatus.Delivered
                || s.status == DeliveryLib.ShipmentStatus.Cancelled
        ) {
            revert DeliveryLib.DeliveryManager__InvalidState(shipmentId, s.status);
        }
        _exception(
            shipmentId,
            kind,
            msg.sender,
            evidenceHash,
            kind == DeliveryLib.ExceptionKind.Loss || kind == DeliveryLib.ExceptionKind.Tamper
        );
    }

    /**
     * @notice The shipper and the consignee settle a hold between themselves, with no third party.
     * @dev Each states whether the shipment should `Continue` (the failed step can be retried) or be `Cancelled`
     * (its lots are freed). Once both agree, it is applied. Custody stays with whoever held it when the hold began;
     * money is settled separately by the escrow dispute rules.
     * @param shipmentId Shipment on hold.
     * @param choice The caller's choice; not `None`.
     * @custom:emits HoldChoiceMade
     * @custom:emits HoldResolved (once both agree)
     */
    function chooseHoldOutcome(uint256 shipmentId, DeliveryLib.HoldChoice choice) external {
        DeliveryLib.Shipment storage s = _shipments[shipmentId];
        if (!s.onHold) revert DeliveryLib.DeliveryManager__NotOnHold(shipmentId);
        if (choice == DeliveryLib.HoldChoice.None) revert DeliveryLib.DeliveryManager__InvalidChoice();
        if (msg.sender == s.shipper) s.shipperChoice = choice;
        else if (msg.sender == s.consignee) s.consigneeChoice = choice;
        else revert DeliveryLib.DeliveryManager__Unauthorized(msg.sender);
        emit DeliveryLib.HoldChoiceMade(shipmentId, msg.sender, choice);

        if (s.shipperChoice == s.consigneeChoice) {
            _releaseHold(shipmentId, choice == DeliveryLib.HoldChoice.Cancel, bytes32(0));
        }
    }

    /**
     * @notice Cancels an on-hold shipment the parties did not agree on within {HOLD_TIMEOUT}, freeing its lots.
     * @dev Callable by anyone after the timeout, so nothing stays stuck waiting for a third party.
     * @param shipmentId Shipment on hold.
     * @custom:emits HoldResolved
     * @custom:emits ShipmentCancelled
     */
    function expireHold(uint256 shipmentId) external {
        DeliveryLib.Shipment storage s = _shipments[shipmentId];
        if (!s.onHold) revert DeliveryLib.DeliveryManager__NotOnHold(shipmentId);
        uint64 expiresAt = s.heldAt + HOLD_TIMEOUT;
        if (block.timestamp <= expiresAt) revert DeliveryLib.DeliveryManager__HoldNotExpired(shipmentId, expiresAt);
        _releaseHold(shipmentId, true, bytes32(0));
    }

    /**
     * @notice Compliance override: a regulator ends a hold (e.g. confirmed theft or fraud).
     * @dev Only a regulator. This is law enforcement, not dispute settlement, which the parties and the escrow
     * rules handle.
     * @param shipmentId Shipment on hold.
     * @param cancel Whether to cancel the shipment (true) or let it continue (false).
     * @param resolutionHash Hash of the decision.
     * @custom:emits HoldResolved
     */
    function resolveHold(uint256 shipmentId, bool cancel, bytes32 resolutionHash) external {
        if (!registry.isAuthorized(msg.sender, Actions.REGULATE)) {
            revert DeliveryLib.DeliveryManager__Unauthorized(msg.sender);
        }
        if (!_shipments[shipmentId].onHold) revert DeliveryLib.DeliveryManager__NotOnHold(shipmentId);
        _releaseHold(shipmentId, cancel, resolutionHash);
    }

    /*//////////////////////////////////////////////////////////////
                                  VIEWS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns a shipment.
     * @param shipmentId Shipment id.
     * @return The shipment (status `None` if unknown).
     */
    function getShipment(uint256 shipmentId) external view returns (DeliveryLib.Shipment memory) {
        return _shipments[shipmentId];
    }

    /**
     * @notice Returns a shipment's lots, in booking order.
     * @param shipmentId Shipment id.
     * @return Lot token ids.
     */
    function lotsOf(uint256 shipmentId) external view returns (uint256[] memory) {
        return _shipmentLots[shipmentId];
    }

    /**
     * @notice Share of a carrier's deliveries that arrived by the ETA.
     * @param carrier The carrier.
     * @return Rate in basis points (0 if it has no deliveries).
     */
    function onTimeRateBps(address carrier) external view returns (uint256) {
        DeliveryLib.CarrierStats memory cs = carrierStats[carrier];
        return cs.delivered == 0 ? 0 : (uint256(cs.onTime) * 10_000) / cs.delivered;
    }

    /*//////////////////////////////////////////////////////////////
                                 INTERNAL
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Books a shipment for `shipper`, the custodian of every lot.
     * @param shipper Custodian shipping the lots.
     * @param tokenIds Lots to ship.
     * @param carrier Carrier.
     * @param consignee Consignee.
     * @param eta Expected time of arrival.
     * @param sealId Dispatch seal.
     * @param routeHash Planned route / transport permit.
     * @return shipmentId New shipment id.
     */
    function _book(
        address shipper,
        uint256[] calldata tokenIds,
        address carrier,
        address consignee,
        uint64 eta,
        bytes32 sealId,
        bytes32 routeHash
    ) private returns (uint256 shipmentId) {
        uint256 n = tokenIds.length;
        if (n == 0) revert DeliveryLib.DeliveryManager__EmptyShipment();
        if (n > MAX_LOTS_PER_SHIPMENT) revert DeliveryLib.DeliveryManager__TooManyLots();
        if (sealId == bytes32(0)) revert DeliveryLib.DeliveryManager__InvalidSeal();
        if (carrier == shipper || !registry.isAuthorized(carrier, Actions.CARRY)) {
            revert DeliveryLib.DeliveryManager__InvalidCarrier(carrier);
        }
        if (consignee == shipper || consignee == carrier || !_isConsignee(consignee)) {
            revert DeliveryLib.DeliveryManager__InvalidConsignee(consignee);
        }
        if (eta <= block.timestamp) revert DeliveryLib.DeliveryManager__InvalidEta(eta);

        shipmentId = _nextShipmentId++;
        for (uint256 i; i < n; ++i) {
            uint256 id = tokenIds[i];
            if (passport.custodianOf(id) != shipper) {
                revert DeliveryLib.DeliveryManager__NotCustodian(id, shipper);
            }
            uint256 existing = activeShipmentOf[id];
            if (existing != 0) revert DeliveryLib.DeliveryManager__AlreadyInShipment(id, existing); // also catches duplicate ids
            activeShipmentOf[id] = shipmentId;
        }

        DeliveryLib.Shipment storage s = _shipments[shipmentId];
        s.shipper = shipper;
        s.carrier = carrier;
        s.consignee = consignee;
        s.createdAt = uint64(block.timestamp);
        s.eta = eta;
        s.status = DeliveryLib.ShipmentStatus.Created;
        s.sealId = sealId;
        s.routeHash = routeHash;
        _shipmentLots[shipmentId] = tokenIds;

        emit DeliveryLib.ShipmentCreated(shipmentId, shipper, carrier, consignee, tokenIds, eta, sealId, routeHash);
    }

    /**
     * @dev Records one {SupplyChain} checkpoint per lot (weight + condition). A seal mismatch is recorded as
     * `SealBroken` for every lot. On any problem the shipment is put on hold and false is returned.
     * @param shipmentId Shipment id.
     * @param cpType `Pickup` or `Arrival`.
     * @param weights Measured weight per lot, in lot order.
     * @param sealId Seal found.
     * @param condition Condition reported.
     * @param evidenceHash Hash of the evidence.
     * @return ok True if every lot passed.
     */
    function _verifyLots(
        uint256 shipmentId,
        SupplyChainLib.CheckpointType cpType,
        uint128[] calldata weights,
        bytes32 sealId,
        SupplyChainLib.Condition condition,
        bytes32 evidenceHash
    ) private returns (bool ok) {
        uint256[] storage lots = _shipmentLots[shipmentId];
        if (weights.length != lots.length) {
            revert DeliveryLib.DeliveryManager__WeightCountMismatch(lots.length, weights.length);
        }

        DeliveryLib.Shipment storage s = _shipments[shipmentId];
        bool sealOk = sealId == s.sealId;
        if (!sealOk) condition = SupplyChainLib.Condition.SealBroken;

        ok = true;
        for (uint256 i; i < lots.length; ++i) {
            (, uint256 flagId) = supplyChain.recordFromModule(
                SupplyChainLib.CheckpointInput({
                    tokenId: lots[i],
                    cpType: cpType,
                    measuredQty: weights[i],
                    condition: condition,
                    gradeBps: 0,
                    evidenceHash: evidenceHash,
                    locationHash: bytes32(0)
                }),
                msg.sender
            );
            if (flagId != 0) ok = false;
        }

        if (!ok) {
            DeliveryLib.ExceptionKind kind = !sealOk
                ? DeliveryLib.ExceptionKind.SealMismatch
                : condition == SupplyChainLib.Condition.Damaged
                    ? DeliveryLib.ExceptionKind.Damage
                    : DeliveryLib.ExceptionKind.WeightMismatch;
            _exception(shipmentId, kind, msg.sender, evidenceHash, true);
        }
    }

    /**
     * @dev Moves custody of every lot in a shipment.
     * @param shipmentId Shipment id.
     * @param from Current custodian.
     * @param to New custodian.
     * @param evidenceHash Hash of the evidence.
     */
    function _handover(uint256 shipmentId, address from, address to, bytes32 evidenceHash) private {
        uint256[] storage lots = _shipmentLots[shipmentId];
        for (uint256 i; i < lots.length; ++i) {
            passport.moduleHandover(lots[i], from, to, evidenceHash);
        }
    }

    /**
     * @dev Records an exception and optionally puts the shipment on hold (resetting both parties' choices).
     * @param shipmentId Shipment id.
     * @param kind Kind of problem.
     * @param reporter Reporting account.
     * @param evidenceHash Hash of the evidence.
     * @param hold Whether to put the shipment on hold.
     */
    function _exception(
        uint256 shipmentId,
        DeliveryLib.ExceptionKind kind,
        address reporter,
        bytes32 evidenceHash,
        bool hold
    ) private {
        DeliveryLib.Shipment storage s = _shipments[shipmentId];
        s.exceptionCount += 1;
        carrierStats[s.carrier].exceptions += 1;
        if (hold && !s.onHold) {
            s.onHold = true;
            s.heldAt = uint64(block.timestamp);
            s.shipperChoice = DeliveryLib.HoldChoice.None;
            s.consigneeChoice = DeliveryLib.HoldChoice.None;
        }
        emit DeliveryLib.ExceptionReported(shipmentId, kind, reporter, evidenceHash);
    }

    /**
     * @dev Ends a hold, cancelling the shipment if requested.
     * @param shipmentId Shipment id.
     * @param cancel Whether to cancel the shipment.
     * @param resolutionHash Hash of the resolution.
     */
    function _releaseHold(uint256 shipmentId, bool cancel, bytes32 resolutionHash) private {
        DeliveryLib.Shipment storage s = _shipments[shipmentId];
        s.onHold = false;
        s.heldAt = 0;
        s.shipperChoice = DeliveryLib.HoldChoice.None;
        s.consigneeChoice = DeliveryLib.HoldChoice.None;
        emit DeliveryLib.HoldResolved(shipmentId, msg.sender, cancel, resolutionHash);
        if (cancel) _cancel(shipmentId, resolutionHash);
    }

    /**
     * @dev Cancels a shipment and frees its lots.
     * @param shipmentId Shipment id.
     * @param reasonHash Hash of the reason.
     */
    function _cancel(uint256 shipmentId, bytes32 reasonHash) private {
        _shipments[shipmentId].status = DeliveryLib.ShipmentStatus.Cancelled;
        _clearLots(shipmentId);
        emit DeliveryLib.ShipmentCancelled(shipmentId, reasonHash);
    }

    /**
     * @dev Removes a shipment's lots from {activeShipmentOf}.
     * @param shipmentId Shipment id.
     */
    function _clearLots(uint256 shipmentId) private {
        uint256[] storage lots = _shipmentLots[shipmentId];
        for (uint256 i; i < lots.length; ++i) {
            delete activeShipmentOf[lots[i]];
        }
    }

    /**
     * @dev Whether an account may receive shipments.
     * @param account The account.
     * @return True if authorised for `RECEIVE_SHIPMENT`.
     */
    function _isConsignee(address account) private view returns (bool) {
        return registry.isAuthorized(account, Actions.RECEIVE_SHIPMENT);
    }

    /**
     * @dev Reverts unless the shipment is in `expected` status.
     * @param shipmentId Shipment id.
     * @param expected Required status.
     */
    function _requireStatus(uint256 shipmentId, DeliveryLib.ShipmentStatus expected) private view {
        DeliveryLib.ShipmentStatus st = _shipments[shipmentId].status;
        if (st != expected) revert DeliveryLib.DeliveryManager__InvalidState(shipmentId, st);
    }
}
