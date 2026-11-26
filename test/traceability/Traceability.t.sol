// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {MineNetFixture} from "test/utils/MineNetFixture.sol";
import {TraceLib} from "src/traceability/libraries/TraceLib.sol";

contract TraceabilityTest is MineNetFixture {
    bytes32 constant TAG = keccak256("QR:MN-0001:random-serial");
    bytes32 constant TAG2 = keccak256("QR:MN-0001:replacement");
    bytes32 constant OCR = keccak256("ocr-text");
    bytes32 constant TRACKER = keccak256("GPS-TRK-01");
    address device = makeAddr("gps-device");

    uint256 lot;

    function setUp() public override {
        super.setUp();
        lot = _register(10_000);
    }

    function _tagged() internal {
        vm.prank(miner);
        tags.bindTag(lot, TAG);
    }

    // ---------------------------------------------------------------- QR tags

    function test_BindAndVerifyTag() public {
        _tagged();
        assertEq(tags.tagOf(lot), TAG);
        (uint256 tokenId, bool active, bool frozen) = tags.verifyTag(TAG);
        assertEq(tokenId, lot);
        assertTrue(active);
        assertFalse(frozen);
    }

    function test_BindTag_Rules() public {
        vm.prank(buyer);
        vm.expectRevert(abi.encodeWithSelector(TraceLib.LotTagRegistry__NotOwnerOrCustodian.selector, lot, buyer));
        tags.bindTag(lot, TAG);

        _tagged();
        vm.prank(miner);
        vm.expectRevert(abi.encodeWithSelector(TraceLib.LotTagRegistry__LotHasTag.selector, lot, TAG));
        tags.bindTag(lot, TAG2);

        // a tag can never be reused on another lot
        uint256 other = _register(5_000);
        vm.prank(miner);
        vm.expectRevert(abi.encodeWithSelector(TraceLib.LotTagRegistry__TagUsed.selector, TAG));
        tags.bindTag(other, TAG);
    }

    function test_Scan_MatchDoesNotFlag() public {
        _tagged();
        vm.prank(transporter);
        TraceLib.ScanResult r = tags.recordScan(TAG, OCR, true, keccak256("kigali"));
        assertEq(uint8(r), uint8(TraceLib.ScanResult.Match));
        assertFalse(passport.isFrozen(lot));
        assertEq(tags.getTag(TAG).scans, 1);
    }

    function test_Scan_OcrMismatchFlagsLot() public {
        _tagged();
        vm.prank(customs);
        TraceLib.ScanResult r = tags.recordScan(TAG, OCR, false, keccak256("border"));
        assertEq(uint8(r), uint8(TraceLib.ScanResult.OcrMismatch));
        assertTrue(passport.isFrozen(lot));
    }

    function test_ReplaceTag_VoidsOldTagAndFlagsItsUse() public {
        _tagged();
        vm.prank(miner); // the owner cannot swap its own tag
        vm.expectRevert(abi.encodeWithSelector(TraceLib.LotTagRegistry__Unauthorized.selector, miner));
        tags.replaceTag(lot, TAG2, H);

        vm.prank(inspector);
        tags.replaceTag(lot, TAG2, keccak256("tag damaged"));
        assertEq(tags.tagOf(lot), TAG2);
        assertEq(uint8(tags.getTag(TAG).status), uint8(TraceLib.TagStatus.Void));

        // the old tag turns up again: possible clone
        vm.prank(warehouse);
        TraceLib.ScanResult r = tags.recordScan(TAG, OCR, true, H);
        assertEq(uint8(r), uint8(TraceLib.ScanResult.VoidTag));
        assertTrue(passport.isFrozen(lot));
    }

    function test_Scan_UnknownTagIsReported() public {
        bytes32 rogue = keccak256("untracked-bag");
        vm.expectEmit(true, true, true, true);
        emit TraceLib.TagScanned(rogue, 0, customs, TraceLib.ScanResult.UnknownTag, OCR, H);
        vm.prank(customs);
        TraceLib.ScanResult r = tags.recordScan(rogue, OCR, false, H);
        assertEq(uint8(r), uint8(TraceLib.ScanResult.UnknownTag));
    }

    function test_Scan_OnlyAuthorisedScanners() public {
        vm.prank(outsider);
        vm.expectRevert(abi.encodeWithSelector(TraceLib.LotTagRegistry__Unauthorized.selector, outsider));
        tags.recordScan(TAG, OCR, true, H);
    }

    // ---------------------------------------------------------------- GPS trackers

    function _shipment() internal returns (uint256 sid) {
        uint256[] memory ids = new uint256[](1);
        ids[0] = lot;
        vm.prank(miner);
        sid = delivery.createShipment(ids, transporter, warehouse, uint64(block.timestamp + 1 days), SEAL, H);
    }

    function _pickedUp(uint256 sid) internal {
        uint128[] memory weights = _weights(1, supplyChain.lastWeight(lot)); // before the prank
        vm.prank(transporter);
        delivery.confirmPickup(sid, weights, SEAL, H);
    }

    function _trackedShipment() internal returns (uint256 sid) {
        vm.prank(admin);
        tracker.registerTracker(TRACKER, device);
        sid = _shipment();
        vm.prank(miner);
        tracker.attachTracker(sid, TRACKER);
        _pickedUp(sid);
    }

    function test_Tracker_ReportsPositions() public {
        uint256 sid = _trackedShipment();
        vm.prank(device);
        tracker.reportPosition(sid, -1_944_000, 30_061_000, uint64(block.timestamp), 0);
        TraceLib.Position memory p = tracker.lastPosition(sid);
        assertEq(p.latE6, -1_944_000);
        assertEq(p.lonE6, 30_061_000);
        assertEq(p.pings, 1);

        // reports must move forward in time and come from the attached device
        vm.prank(device);
        vm.expectRevert(abi.encodeWithSelector(TraceLib.CargoTracker__StaleReport.selector, uint64(block.timestamp)));
        tracker.reportPosition(sid, 0, 0, uint64(block.timestamp), 0);
        vm.prank(transporter);
        vm.expectRevert(abi.encodeWithSelector(TraceLib.CargoTracker__Unauthorized.selector, transporter));
        tracker.reportPosition(sid, 0, 0, uint64(block.timestamp + 1), 0);
    }

    function test_Tracker_InvalidCoordinates() public {
        uint256 sid = _trackedShipment();
        vm.prank(device);
        vm.expectRevert(TraceLib.CargoTracker__InvalidPosition.selector);
        tracker.reportPosition(sid, 91e6, 0, uint64(block.timestamp), 0);
    }

    function test_Tracker_TamperAlertFlagsLots() public {
        uint256 sid = _trackedShipment();
        vm.prank(device);
        tracker.reportPosition(sid, -1_944_000, 30_061_000, uint64(block.timestamp), TraceLib.ALERT_TAMPER);
        assertTrue(passport.isFrozen(lot));
    }

    function test_Tracker_RouteDeviationByIndependentOracle() public {
        uint256 sid = _trackedShipment();
        vm.prank(transporter);
        vm.expectRevert(abi.encodeWithSelector(TraceLib.CargoTracker__Unauthorized.selector, transporter));
        tracker.reportRouteDeviation(sid, H);

        vm.prank(oracle);
        tracker.reportRouteDeviation(sid, keccak256("off-route 40km"));
        assertTrue(passport.isFrozen(lot));
    }

    function test_Tracker_Silence() public {
        uint256 sid = _trackedShipment();
        assertFalse(tracker.isSilent(sid));
        vm.warp(block.timestamp + 2 hours + 1);
        assertTrue(tracker.isSilent(sid));
        vm.prank(device);
        tracker.reportPosition(sid, 0, 0, uint64(block.timestamp), 0);
        assertFalse(tracker.isSilent(sid));
    }

    function test_Tracker_BusyOnAnotherLiveShipment() public {
        uint256 sid = _trackedShipment();
        uint256 other = _register(5_000);
        uint256[] memory ids = new uint256[](1);
        ids[0] = other;
        vm.prank(miner);
        uint256 sid2 = delivery.createShipment(ids, transporter, warehouse, uint64(block.timestamp + 1 days), SEAL, H);
        vm.prank(miner);
        vm.expectRevert(abi.encodeWithSelector(TraceLib.CargoTracker__TrackerBusy.selector, TRACKER, sid));
        tracker.attachTracker(sid2, TRACKER);
    }

    function test_Tracker_OnlyShipperOrCarrierAttaches() public {
        vm.prank(admin);
        tracker.registerTracker(TRACKER, device);
        uint256 sid = _shipment();
        vm.prank(buyer);
        vm.expectRevert(abi.encodeWithSelector(TraceLib.CargoTracker__Unauthorized.selector, buyer));
        tracker.attachTracker(sid, TRACKER);
    }
}
