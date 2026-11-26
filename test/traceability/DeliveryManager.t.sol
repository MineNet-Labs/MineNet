// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {MineNetFixture} from "test/utils/MineNetFixture.sol";
import {DeliveryManager} from "src/traceability/DeliveryManager.sol";
import {SupplyChain} from "src/traceability/SupplyChain.sol";
import {DeliveryLib} from "src/traceability/libraries/DeliveryLib.sol";
import {PassportLib} from "src/traceability/libraries/PassportLib.sol";
import {SupplyChainLib} from "src/traceability/libraries/SupplyChainLib.sol";
import {LotPassport} from "src/traceability/LotPassport.sol";

contract DeliveryManagerTest is MineNetFixture {
    function _ids(uint256 a, uint256 b) internal pure returns (uint256[] memory ids) {
        ids = new uint256[](2);
        ids[0] = a;
        ids[1] = b;
    }

    function _two(uint128 a, uint128 b) internal pure returns (uint128[] memory w) {
        w = new uint128[](2);
        w[0] = a;
        w[1] = b;
    }

    function _ship(uint256[] memory ids, address consignee) internal returns (uint256 sid) {
        vm.prank(miner);
        sid = delivery.createShipment(ids, transporter, consignee, uint64(block.timestamp + 2 days), SEAL, H);
    }

    function _pickedUp() internal returns (uint256 a, uint256 b, uint256 sid) {
        a = _register(1_000);
        b = _register(2_000);
        sid = _ship(_ids(a, b), warehouse);
        vm.prank(transporter);
        assertTrue(delivery.confirmPickup(sid, _two(1_000, 2_000), SEAL, H));
    }

    // ---------------------------------------------------------------- happy path

    function test_TwoPartyHandovers_MoveCustody() public {
        (uint256 a, uint256 b, uint256 sid) = _pickedUp();
        assertEq(passport.custodianOf(a), transporter);
        assertEq(passport.custodianOf(b), transporter);

        vm.prank(oracle); // GPS seal
        delivery.recordCheckpoint(sid, keccak256("geohash:kigali"), H);
        vm.prank(transporter);
        delivery.markArrived(sid, H);

        // custody does not move on the carrier's word alone
        assertEq(passport.custodianOf(a), transporter);

        vm.prank(warehouse);
        assertTrue(
            delivery.confirmDelivery(sid, _two(990, 1_985), SEAL, SupplyChainLib.Condition.Good, keccak256("pod"))
        );

        assertEq(passport.custodianOf(a), warehouse);
        assertEq(passport.custodianOf(b), warehouse);
        DeliveryLib.Shipment memory s = delivery.getShipment(sid);
        assertEq(uint8(s.status), uint8(DeliveryLib.ShipmentStatus.Delivered));
        assertEq(s.checkpointCount, 1);
        assertEq(delivery.activeShipmentOf(a), 0);
        assertEq(delivery.onTimeRateBps(transporter), 10_000);

        // weights flowed into the mass-balance ledger: pickup + arrival per lot
        assertEq(supplyChain.checkpointCount(a), 2);
        assertEq(supplyChain.lastWeight(a), 990);
        SupplyChainLib.Checkpoint memory arrival = supplyChain.getCheckpoint(a, 1);
        assertEq(uint8(arrival.cpType), uint8(SupplyChainLib.CheckpointType.Arrival));
        assertEq(arrival.signer, warehouse);
        assertEq(arrival.referenceQty, 1_000);
        assertEq(arrival.hopDeviationBps, 100);
    }

    function test_LateArrival_HurtsOnTimeRate() public {
        (,, uint256 sid) = _pickedUp();
        vm.warp(block.timestamp + 3 days);
        vm.prank(transporter);
        delivery.markArrived(sid, H);
        vm.prank(warehouse);
        delivery.confirmDelivery(sid, _two(1_000, 2_000), SEAL, SupplyChainLib.Condition.Good, H);
        assertEq(delivery.onTimeRateBps(transporter), 0);
    }

    // ---------------------------------------------------------------- weight / seal / condition failures

    function test_PickupWeightMismatch_HoldsAndKeepsCustody() public {
        uint256 a = _register(1_000);
        uint256 b = _register(2_000);
        uint256 sid = _ship(_ids(a, b), warehouse);

        vm.prank(transporter);
        bool ok = delivery.confirmPickup(sid, _two(1_000, 1_800), SEAL, H); // lot b 10% light
        assertFalse(ok);

        assertEq(passport.custodianOf(a), miner, "no partial handover");
        assertEq(passport.custodianOf(b), miner);
        assertTrue(passport.isFrozen(b));
        assertFalse(passport.isFrozen(a));
        DeliveryLib.Shipment memory s = delivery.getShipment(sid);
        assertTrue(s.onHold);
        assertEq(uint8(s.status), uint8(DeliveryLib.ShipmentStatus.Created));

        vm.prank(transporter);
        vm.expectRevert(abi.encodeWithSelector(DeliveryLib.DeliveryManager__OnHold.selector, sid));
        delivery.confirmPickup(sid, _two(1_000, 1_800), SEAL, H);

        // regulator investigates: the scale was mis-calibrated. Clear the flag and continue.
        vm.startPrank(regulator);
        passport.resolveFlag(passport.getEvent(b, passport.eventCount(b) - 1).corrects, false, H);
        delivery.resolveHold(sid, false, H);
        vm.stopPrank();

        assertEq(supplyChain.lastWeight(b), 2_000, "the failed reading did not become the reference");
        vm.prank(transporter);
        assertTrue(delivery.confirmPickup(sid, _two(1_000, 2_000), SEAL, H)); // re-weighed on a calibrated scale
        assertEq(passport.custodianOf(b), transporter);
    }

    function test_GenuineLoss_RegulatorRebaselines() public {
        uint256 a = _register(1_000);
        uint256 b = _register(2_000);
        uint256 sid = _ship(_ids(a, b), warehouse);
        vm.prank(transporter);
        assertFalse(delivery.confirmPickup(sid, _two(1_000, 1_800), SEAL, H));

        // investigation: drying loss confirmed. Accept 1_800 g as the true weight.
        vm.startPrank(regulator);
        supplyChain.rebaseline(b, 1_800, keccak256("moisture-report"));
        passport.resolveFlag(passport.getEvent(b, passport.eventCount(b) - 1).corrects, false, H);
        delivery.resolveHold(sid, false, H);
        vm.stopPrank();

        assertEq(supplyChain.baselineOf(b), 1_800);
        vm.prank(transporter);
        assertTrue(delivery.confirmPickup(sid, _two(1_000, 1_800), SEAL, H));

        vm.prank(warehouse);
        vm.expectRevert(abi.encodeWithSelector(SupplyChainLib.SupplyChain__NotFlagAuthority.selector, warehouse));
        supplyChain.rebaseline(b, 1, H);
    }

    function test_BrokenSeal_AtDelivery_FlagsEveryLot() public {
        (uint256 a, uint256 b, uint256 sid) = _pickedUp();
        vm.prank(transporter);
        delivery.markArrived(sid, H);

        vm.prank(warehouse);
        bool ok = delivery.confirmDelivery(
            sid, _two(1_000, 2_000), keccak256("other-seal"), SupplyChainLib.Condition.Good, H
        );
        assertFalse(ok);

        assertTrue(passport.isFrozen(a));
        assertTrue(passport.isFrozen(b));
        assertEq(passport.custodianOf(a), transporter, "custody stays with the carrier");
        assertEq(uint8(supplyChain.getCheckpoint(a, 1).condition), uint8(SupplyChainLib.Condition.SealBroken));
        assertTrue(delivery.getShipment(sid).onHold);
        (,, uint32 exceptions) = delivery.carrierStats(transporter);
        assertEq(exceptions, 1);
    }

    function test_DamagedOnArrival_Flags() public {
        (uint256 a,, uint256 sid) = _pickedUp();
        vm.prank(transporter);
        delivery.markArrived(sid, H);
        vm.prank(warehouse);
        assertFalse(delivery.confirmDelivery(sid, _two(1_000, 2_000), SEAL, SupplyChainLib.Condition.Damaged, H));
        assertTrue(passport.isFrozen(a));
    }

    // ---------------------------------------------------------------- guards

    function test_Create_Guards() public {
        uint256 a = _register(1_000);
        uint64 eta = uint64(block.timestamp + 1 days);

        vm.startPrank(miner);
        vm.expectRevert(abi.encodeWithSelector(DeliveryLib.DeliveryManager__InvalidCarrier.selector, warehouse));
        delivery.createShipment(_ids(a, a), warehouse, buyer, eta, SEAL, H);
        vm.expectRevert(abi.encodeWithSelector(DeliveryLib.DeliveryManager__InvalidConsignee.selector, inspector));
        delivery.createShipment(_ids(a, a), transporter, inspector, eta, SEAL, H);
        vm.expectRevert(
            abi.encodeWithSelector(DeliveryLib.DeliveryManager__InvalidEta.selector, uint64(block.timestamp))
        );
        delivery.createShipment(_ids(a, a), transporter, buyer, uint64(block.timestamp), SEAL, H);
        vm.expectRevert(DeliveryLib.DeliveryManager__InvalidSeal.selector);
        delivery.createShipment(_ids(a, a), transporter, buyer, eta, bytes32(0), H);
        vm.expectRevert(abi.encodeWithSelector(DeliveryLib.DeliveryManager__AlreadyInShipment.selector, a, 1));
        delivery.createShipment(_ids(a, a), transporter, buyer, eta, SEAL, H); // duplicate id
        vm.stopPrank();

        vm.prank(buyer);
        vm.expectRevert(abi.encodeWithSelector(DeliveryLib.DeliveryManager__NotCustodian.selector, a, buyer));
        delivery.createShipment(_ids(a, a), transporter, warehouse, eta, SEAL, H);
    }

    function test_OnlyTheRightPartyAtEachStep() public {
        uint256 a = _register(1_000);
        uint256 b = _register(2_000);
        uint256 sid = _ship(_ids(a, b), warehouse);

        vm.prank(miner);
        vm.expectRevert(abi.encodeWithSelector(DeliveryLib.DeliveryManager__Unauthorized.selector, miner));
        delivery.confirmPickup(sid, _two(1_000, 2_000), SEAL, H);

        vm.prank(transporter);
        vm.expectRevert(abi.encodeWithSelector(DeliveryLib.DeliveryManager__WeightCountMismatch.selector, 2, 1));
        delivery.confirmPickup(sid, _weights(1, 1_000), SEAL, H);

        vm.prank(transporter);
        vm.expectRevert(
            abi.encodeWithSelector(
                DeliveryLib.DeliveryManager__InvalidState.selector, sid, DeliveryLib.ShipmentStatus.Created
            )
        );
        delivery.markArrived(sid, H);

        vm.prank(transporter);
        delivery.confirmPickup(sid, _two(1_000, 2_000), SEAL, H);
        vm.prank(warehouse);
        vm.expectRevert(
            abi.encodeWithSelector(
                DeliveryLib.DeliveryManager__InvalidState.selector, sid, DeliveryLib.ShipmentStatus.InTransit
            )
        );
        delivery.confirmDelivery(sid, _two(1_000, 2_000), SEAL, SupplyChainLib.Condition.Good, H);
    }

    function test_Cancel_BeforePickupFreesLots() public {
        uint256 a = _register(1_000);
        uint256 b = _register(1_000);
        uint256 sid = _ship(_ids(a, b), warehouse);
        vm.prank(miner);
        delivery.cancelShipment(sid, H);
        assertEq(delivery.activeShipmentOf(a), 0);
        _ship(_ids(a, b), buyer); // can re-ship
    }

    function test_LossException_RegulatorCancels() public {
        (uint256 a,, uint256 sid) = _pickedUp();

        vm.prank(outsider);
        vm.expectRevert(abi.encodeWithSelector(DeliveryLib.DeliveryManager__Unauthorized.selector, outsider));
        delivery.reportException(sid, DeliveryLib.ExceptionKind.Loss, H);

        vm.prank(transporter);
        delivery.reportException(sid, DeliveryLib.ExceptionKind.Loss, H);
        assertTrue(delivery.getShipment(sid).onHold);

        vm.prank(regulator);
        delivery.resolveHold(sid, true, H);
        assertEq(uint8(delivery.getShipment(sid).status), uint8(DeliveryLib.ShipmentStatus.Cancelled));
        assertEq(delivery.activeShipmentOf(a), 0);
    }

    function test_DelayException_DoesNotHold() public {
        (,, uint256 sid) = _pickedUp();
        vm.startPrank(transporter);
        delivery.reportException(sid, DeliveryLib.ExceptionKind.Delay, H);
        delivery.updateEta(sid, uint64(block.timestamp + 5 days), H);
        vm.stopPrank();
        assertFalse(delivery.getShipment(sid).onHold);
    }

    // ---------------------------------------------------------------- module security

    function test_OnlyModulesMoveCustody() public {
        uint256 a = _register(1_000);
        vm.prank(miner);
        vm.expectRevert(abi.encodeWithSelector(PassportLib.LotPassport__NotModule.selector, miner));
        passport.moduleHandover(a, miner, miner, H);

        vm.prank(outsider);
        vm.expectRevert(abi.encodeWithSelector(PassportLib.LotPassport__NotModule.selector, outsider));
        passport.moduleFlag(a, outsider, H);
    }

    function test_DisablingModuleRevokesIt() public {
        uint256 a = _register(1_000);
        uint256 b = _register(2_000);
        uint256 sid = _ship(_ids(a, b), warehouse);

        vm.prank(admin);
        passport.setModule(address(delivery), false);

        vm.prank(transporter);
        vm.expectRevert(abi.encodeWithSelector(PassportLib.LotPassport__NotModule.selector, address(delivery)));
        delivery.confirmPickup(sid, _two(1_000, 2_000), SEAL, H);
    }
}
