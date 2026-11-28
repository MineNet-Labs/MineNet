// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {MineNetFixture} from "test/utils/MineNetFixture.sol";
import {StaffLib} from "src/workforce/libraries/StaffLib.sol";
import {DeliveryLib} from "src/traceability/libraries/DeliveryLib.sol";
import {PassportLib} from "src/traceability/libraries/PassportLib.sol";
import {SupplyChainLib} from "src/traceability/libraries/SupplyChainLib.sol";

/**
 * @notice The site manager dispatches the company's lots with the vehicle, driver and receiving worker; batches are
 * split into inspected lots that keep their weights, grade and certificates.
 */
contract SiteDispatchTest is MineNetFixture {
    bytes32 constant MGR = keccak256("grace");
    bytes32 constant HR = keccak256("alice");
    bytes32 constant PLATE = "RAD 123 A";
    bytes32 constant DRIVER = keccak256("driver-licence-0042");
    bytes32 constant RECEIVER = keccak256("warehouse-worker-17");

    address mgrW = makeAddr("managerWallet");
    address hrW = makeAddr("hrWallet");

    function setUp() public override {
        super.setUp();
        vm.startPrank(miner);
        workforce.registerWorker(MGR, mgrW, site);
        workforce.registerWorker(HR, hrW, site);
        workforce.appointSiteSeat(site, StaffLib.SiteSeat.Manager, MGR);
        workforce.appointSiteSeat(site, StaffLib.SiteSeat.Hr, HR);
        vm.stopPrank();
    }

    function _dispatchInput(uint256 id, uint128 weight) internal view returns (DeliveryLib.DispatchInput memory d) {
        d.tokenIds = new uint256[](1);
        d.tokenIds[0] = id;
        d.carrier = transporter;
        d.consignee = warehouse;
        d.eta = uint64(block.timestamp + 2 days);
        d.sealId = SEAL;
        d.routeHash = H;
        d.plateNo = PLATE;
        d.driverRef = DRIVER;
        d.receiverRef = RECEIVER;
        d.weights = new uint128[](1);
        d.weights[0] = weight;
    }

    /*//////////////////////////////////////////////////////////////
                                DISPATCH
    //////////////////////////////////////////////////////////////*/

    function test_ManagerDispatchesCompanyLotWithTransportDetails() public {
        uint256 id = _inspected(10_000);
        vm.prank(mgrW);
        uint256 sid = delivery.dispatch(_dispatchInput(id, 10_000));

        DeliveryLib.Shipment memory s = delivery.getShipment(sid);
        assertEq(s.shipper, miner); // booked for the company, which holds custody
        assertEq(s.carrier, transporter);
        assertEq(s.consignee, warehouse);
        (bytes32 plate, bytes32 driver, bytes32 receiver, address by) = delivery.transportOf(sid);
        assertEq(plate, PLATE);
        assertEq(driver, DRIVER);
        assertEq(receiver, RECEIVER);
        assertEq(by, mgrW);

        // the transporter takes over custody after weighing, then the verified warehouse receives it
        uint128[] memory w = new uint128[](1);
        w[0] = 10_000;
        vm.prank(transporter);
        assertTrue(delivery.confirmPickup(sid, w, SEAL, H));
        assertEq(passport.custodianOf(id), transporter);

        vm.prank(warehouse);
        delivery.setReceiver(sid, keccak256("warehouse-worker-21"));
        (,, receiver,) = delivery.transportOf(sid);
        assertEq(receiver, keccak256("warehouse-worker-21"));
    }

    function test_ManagerCanCancelOwnDispatch() public {
        uint256 id = _inspected(10_000);
        vm.prank(mgrW);
        uint256 sid = delivery.dispatch(_dispatchInput(id, 10_000));
        vm.prank(mgrW);
        delivery.cancelShipment(sid, H);
        assertEq(delivery.activeShipmentOf(id), 0);
    }

    function test_RevertWhen_StaffWithoutDispatchRight() public {
        uint256 id = _inspected(10_000);
        DeliveryLib.DispatchInput memory d = _dispatchInput(id, 10_000);
        vm.prank(hrW);
        vm.expectRevert(abi.encodeWithSelector(DeliveryLib.DeliveryManager__Unauthorized.selector, hrW));
        delivery.dispatch(d);
        vm.prank(outsider);
        vm.expectRevert(abi.encodeWithSelector(DeliveryLib.DeliveryManager__Unauthorized.selector, outsider));
        delivery.dispatch(d);
    }

    function test_RevertWhen_RevokedManagerDispatches() public {
        uint256 id = _inspected(10_000);
        vm.prank(miner);
        workforce.appointSiteSeat(site, StaffLib.SiteSeat.Manager, bytes32(0));
        vm.prank(mgrW);
        vm.expectRevert(abi.encodeWithSelector(DeliveryLib.DeliveryManager__Unauthorized.selector, mgrW));
        delivery.dispatch(_dispatchInput(id, 10_000));
    }

    function test_RevertWhen_DispatchMissesVehicleOrDriver() public {
        uint256 id = _inspected(10_000);
        DeliveryLib.DispatchInput memory d = _dispatchInput(id, 10_000);
        d.plateNo = bytes32(0);
        vm.prank(mgrW);
        vm.expectRevert(DeliveryLib.DeliveryManager__InvalidTransport.selector);
        delivery.dispatch(d);
        d = _dispatchInput(id, 10_000);
        d.driverRef = bytes32(0);
        vm.prank(mgrW);
        vm.expectRevert(DeliveryLib.DeliveryManager__InvalidTransport.selector);
        delivery.dispatch(d);
    }

    function test_RevertWhen_ConsigneeNotVerified() public {
        uint256 id = _inspected(10_000);
        DeliveryLib.DispatchInput memory d = _dispatchInput(id, 10_000);
        d.consignee = outsider;
        vm.prank(mgrW);
        vm.expectRevert(abi.encodeWithSelector(DeliveryLib.DeliveryManager__InvalidConsignee.selector, outsider));
        delivery.dispatch(d);
    }

    /*//////////////////////////////////////////////////////////////
                                SPLITTING
    //////////////////////////////////////////////////////////////*/

    function test_OwnerSplitsBatchKeepingWeightsGradeAndCertificates(uint128 cut) public {
        cut = uint128(bound(cut, 1, 9_999));
        uint256 id = _inspected(10_000);
        _grade(id, 7_000);
        vm.prank(regulator);
        certs.issue(id, EXPORT_PERMIT, uint64(block.timestamp + 90 days), H);

        uint128[] memory w = new uint128[](2);
        w[0] = cut;
        w[1] = 10_000 - cut;
        vm.prank(miner);
        uint256[] memory kids = supplyChain.splitLot(id, w, H);

        assertEq(uint8(passport.getLot(id).status), uint8(PassportLib.LotStatus.Consumed));
        uint256 qty;
        for (uint256 i; i < 2; ++i) {
            assertEq(uint8(passport.getLot(kids[i]).status), uint8(PassportLib.LotStatus.Inspected));
            assertEq(supplyChain.lastWeight(kids[i]), w[i]);
            assertEq(supplyChain.latestGrade(kids[i]).gradeBps, 7_000);
            assertEq(passport.ownerOf(kids[i]), miner);
            assertEq(passport.siteOf(kids[i]), site);
            assertTrue(certs.hasValidCertificate(kids[i], EXPORT_PERMIT));
            assertEq(passport.parentsOf(kids[i])[0], id);
            qty += passport.getLot(kids[i]).quantity;
        }
        assertEq(qty, 10_000); // no mass created or lost
    }

    function test_RevertWhen_SplitWeightsDoNotAddUp() public {
        uint256 id = _inspected(10_000);
        uint128[] memory w = new uint128[](2);
        w[0] = 4_000;
        w[1] = 5_000;
        vm.prank(miner);
        vm.expectRevert(abi.encodeWithSelector(SupplyChainLib.SupplyChain__CannotSplit.selector, id));
        supplyChain.splitLot(id, w, H);
    }

    function test_RevertWhen_SplittingShippedLot() public {
        uint256 id = _inspected(10_000);
        vm.prank(mgrW);
        delivery.dispatch(_dispatchInput(id, 10_000));
        uint128[] memory w = new uint128[](2);
        w[0] = 4_000;
        w[1] = 6_000;
        vm.prank(miner);
        vm.expectRevert(abi.encodeWithSelector(SupplyChainLib.SupplyChain__CannotSplit.selector, id));
        supplyChain.splitLot(id, w, H);
    }

    function test_RevertWhen_NonOwnerSplits() public {
        uint256 id = _inspected(10_000);
        uint128[] memory w = new uint128[](2);
        w[0] = 4_000;
        w[1] = 6_000;
        vm.prank(mgrW);
        vm.expectRevert(abi.encodeWithSelector(SupplyChainLib.SupplyChain__NotLotOwner.selector, mgrW, id));
        supplyChain.splitLot(id, w, H);
    }
}
