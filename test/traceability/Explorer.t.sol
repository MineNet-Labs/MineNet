// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {MineNetFixture} from "test/utils/MineNetFixture.sol";
import {ExplorerLib} from "src/traceability/libraries/ExplorerLib.sol";
import {PassportLib} from "src/traceability/libraries/PassportLib.sol";
import {SupplyChainLib} from "src/traceability/libraries/SupplyChainLib.sol";
import {SupplyChainExplorer} from "src/traceability/SupplyChainExplorer.sol";

contract ExplorerTest is MineNetFixture {
    bytes32 constant TAG = keccak256("QR:explorer");

    /// A lot that was registered, tagged, inspected, graded and delivered to the warehouse.
    function _journey() internal returns (uint256 id) {
        id = _register(10_000);
        vm.prank(miner);
        tags.bindTag(id, TAG);
        vm.warp(block.timestamp + 1 hours);
        _assignTo(id, inspector);
        vm.prank(inspector);
        passport.submitInspection(id, true, H);
        vm.warp(block.timestamp + 1 hours);
        _grade(id, 6_500);
        vm.warp(block.timestamp + 1 hours);
        _deliver(id, miner, warehouse);
    }

    function test_Summary() public {
        uint256 id = _journey();
        ExplorerLib.LotSummary memory s = explorer.summary(id);
        assertEq(s.tokenId, id);
        assertEq(s.mineralType, TIN);
        assertEq(s.registeredQty, 10_000);
        assertEq(uint8(s.status), uint8(PassportLib.LotStatus.Inspected));
        assertEq(s.owner, miner);
        assertEq(s.custodian, warehouse);
        assertEq(s.siteId, site);
        assertEq(s.siteRef, bytes32("site-1"));
        assertEq(s.producerOrg, bytes32("org-miner"));
        assertEq(s.tagHash, TAG);
        assertEq(s.gradeBps, 6_500);
        assertFalse(s.frozen);
    }

    function test_Timeline_MergesPassportAndCheckpointsInOrder() public {
        uint256 id = _journey();
        ExplorerLib.Step[] memory steps = explorer.timeline(id);
        assertEq(steps.length, passport.eventCount(id) + supplyChain.checkpointCount(id));

        // starts at registration, and every step is in time order
        assertEq(uint8(steps[0].source), uint8(ExplorerLib.Source.Passport));
        assertEq(steps[0].kind, uint8(PassportLib.EventType.Registration));
        for (uint256 i = 1; i < steps.length; ++i) {
            assertGe(steps[i].timestamp, steps[i - 1].timestamp);
        }

        // the grade, pickup and arrival checkpoints are all there
        bool graded;
        bool pickedUp;
        bool arrived;
        for (uint256 i; i < steps.length; ++i) {
            if (steps[i].source != ExplorerLib.Source.Checkpoint) continue;
            if (steps[i].kind == uint8(SupplyChainLib.CheckpointType.Inspection)) graded = steps[i].gradeBps == 6_500;
            if (steps[i].kind == uint8(SupplyChainLib.CheckpointType.Pickup)) pickedUp = steps[i].quantity == 10_000;
            if (steps[i].kind == uint8(SupplyChainLib.CheckpointType.Arrival)) arrived = steps[i].ok;
        }
        assertTrue(graded && pickedUp && arrived);
    }

    function test_Timeline_ShowsFailedInspection() public {
        uint256 id = _register(1_000);
        _assignTo(id, inspector);
        vm.prank(inspector);
        passport.submitInspection(id, false, H);
        ExplorerLib.Step[] memory steps = explorer.timeline(id);
        assertEq(steps[1].kind, uint8(PassportLib.EventType.Inspection));
        assertFalse(steps[1].ok);
    }

    /// Two mine lots are refined into one product: the explorer traces it back to both.
    function test_Provenance_RefinedProductBackToTheMine() public {
        uint256 a = _inspected(6_000);
        uint256 b = _inspected(4_000);
        _moveCustody(a, miner, refinery);
        _moveCustody(b, miner, refinery);
        uint256[] memory inputs = new uint256[](2);
        inputs[0] = a;
        inputs[1] = b;
        PassportLib.LotOutput[] memory outs = new PassportLib.LotOutput[](1);
        outs[0] = PassportLib.LotOutput("ingot-1", keccak256("TIN_INGOT"), 7_000, H);
        vm.prank(refinery);
        uint256 ingot = passport.processLots(inputs, outs, H)[0];

        uint256[] memory chain = explorer.provenance(ingot);
        assertEq(chain.length, 3);
        assertEq(chain[2], ingot); // reads mine -> product

        (uint256[] memory roots, uint256[] memory rootSites) = explorer.origins(ingot);
        assertEq(roots.length, 2);
        assertEq(rootSites[0], site);
        assertEq(rootSites[1], site);

        ExplorerLib.LotJourney[] memory journey = explorer.fullJourney(ingot);
        assertEq(journey.length, 3);
        assertEq(journey[2].lot.tokenId, ingot);
        assertEq(journey[2].lot.parents.length, 2);
        assertEq(journey[2].lot.siteId, 0); // derived: its origin is in its parents
        assertEq(uint8(journey[0].lot.status), uint8(PassportLib.LotStatus.Consumed));
        assertGt(journey[0].steps.length, 0);
    }

    function test_UnknownLotReverts() public {
        vm.expectRevert(abi.encodeWithSelector(PassportLib.LotPassport__UnknownLot.selector, 999));
        explorer.summary(999);
        vm.expectRevert(abi.encodeWithSelector(PassportLib.LotPassport__UnknownLot.selector, 999));
        explorer.provenance(999);
    }

    function test_TimelineOfFreshLotIsJustRegistration() public {
        uint256 id = _register(1_000);
        ExplorerLib.Step[] memory steps = explorer.timeline(id);
        assertEq(steps.length, 1);
        assertEq(steps[0].actor, miner);
        // silence unused-import warnings for the explorer type
        assertEq(address(SupplyChainExplorer(address(explorer)).passport()), address(passport));
    }
}
