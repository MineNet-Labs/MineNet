// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {MineNetFixture} from "test/utils/MineNetFixture.sol";
import {SupplyChain} from "src/traceability/SupplyChain.sol";
import {LotPassport} from "src/traceability/LotPassport.sol";
import {SupplyChainLib} from "src/traceability/libraries/SupplyChainLib.sol";
import {Roles} from "src/access/libraries/Roles.sol";

contract SupplyChainTest is MineNetFixture {
    function _cp(uint256 id, SupplyChainLib.CheckpointType t, uint128 qty)
        internal
        pure
        returns (SupplyChainLib.CheckpointInput memory)
    {
        return SupplyChainLib.CheckpointInput({
            tokenId: id,
            cpType: t,
            measuredQty: qty,
            condition: SupplyChainLib.Condition.Good,
            gradeBps: 0,
            evidenceHash: keccak256("ticket"),
            locationHash: keccak256("site")
        });
    }

    function _record(address who, uint256 id, SupplyChainLib.CheckpointType t, uint128 qty)
        internal
        returns (uint256 index, uint256 flagId)
    {
        vm.prank(who);
        return supplyChain.recordCheckpoint(_cp(id, t, qty));
    }

    /// Registered 10_000 g lot delivered (with exact weights) into the warehouse's custody.
    function _atWarehouse() internal returns (uint256 id) {
        id = _register(10_000);
        _deliver(id, miner, warehouse);
    }

    // ---------------------------------------------------------------- mass balance

    function test_WarehouseIn_WithinTolerance() public {
        uint256 id = _atWarehouse();
        (uint256 idx, uint256 flagId) = _record(warehouse, id, SupplyChainLib.CheckpointType.WarehouseIn, 9_900); // -1%

        assertEq(flagId, 0);
        SupplyChainLib.Checkpoint memory c = supplyChain.getCheckpoint(id, idx);
        assertTrue(c.withinTolerance);
        assertEq(c.measuredQty, 9_900);
        assertEq(c.referenceQty, 10_000);
        assertEq(c.hopDeviationBps, 100);
        assertEq(c.cumulativeDeviationBps, 100);
        assertEq(supplyChain.lastWeight(id), 9_900);
        assertFalse(passport.isFrozen(id));
    }

    function test_HopMismatch_FlagsAndFreezes() public {
        uint256 id = _atWarehouse();
        _record(warehouse, id, SupplyChainLib.CheckpointType.WarehouseIn, 9_900);

        // check-out 4% lighter than check-in: lot swapped or skimmed while stored
        vm.expectEmit(true, true, false, false, address(supplyChain));
        emit SupplyChainLib.MassBalanceMismatch(id, 3, 9_900, 9_500, 1);
        (, uint256 flagId) = _record(warehouse, id, SupplyChainLib.CheckpointType.WarehouseOut, 9_500);

        assertGt(flagId, 0);
        assertTrue(passport.isFrozen(id));
        assertEq(passport.getFlag(flagId).raisedBy, warehouse, "flag attributed to the signer, not the module");
        assertFalse(supplyChain.getCheckpoint(id, 3).withinTolerance);
    }

    function test_CumulativeDrift_CaughtEvenWhenEachHopIsSmall() public {
        uint256 id = _register(10_000);
        uint128[4] memory w = [uint128(9_850), 9_700, 9_550, 9_400]; // each hop ~1.5%, total 6%
        uint256 flagId;
        for (uint256 i; i < 4; ++i) {
            (, flagId) = _record(oracle, id, SupplyChainLib.CheckpointType.Weighing, w[i]);
            if (i < 3) assertEq(flagId, 0, "hops within tolerance");
        }
        assertGt(flagId, 0, "cumulative 6% > 5%");
        assertEq(supplyChain.getCheckpoint(id, 3).cumulativeDeviationBps, 600);
    }

    function test_WeightGain_AlsoMismatch() public {
        uint256 id = _register(10_000);
        (, uint256 flagId) = _record(oracle, id, SupplyChainLib.CheckpointType.Weighing, 10_300); // dilution
        assertGt(flagId, 0);
    }

    function test_PerMineralTolerance() public {
        vm.prank(admin);
        supplyChain.setMineralTolerance(TIN, 400); // wet cassiterite: 4% per hop
        assertEq(supplyChain.toleranceOf(TIN), 400);
        uint256 id = _register(10_000);
        (, uint256 flagId) = _record(oracle, id, SupplyChainLib.CheckpointType.Weighing, 9_650);
        assertEq(flagId, 0);
    }

    function test_ToleranceBounds() public {
        vm.startPrank(admin);
        vm.expectRevert(abi.encodeWithSelector(SupplyChainLib.SupplyChain__InvalidTolerance.selector, uint16(0)));
        supplyChain.setDefaultTolerances(0, 500);
        vm.expectRevert(abi.encodeWithSelector(SupplyChainLib.SupplyChain__InvalidTolerance.selector, uint16(100)));
        supplyChain.setDefaultTolerances(200, 100); // cumulative must be >= hop
        vm.expectRevert(abi.encodeWithSelector(SupplyChainLib.SupplyChain__InvalidTolerance.selector, uint16(2_001)));
        supplyChain.setMineralTolerance(TIN, 2_001);
        vm.stopPrank();

        vm.prank(outsider);
        vm.expectRevert(abi.encodeWithSelector(SupplyChainLib.SupplyChain__NotRegistryAdmin.selector, outsider));
        supplyChain.setDefaultTolerances(300, 600);
    }

    function test_DamagedCondition_Flags() public {
        uint256 id = _atWarehouse();
        SupplyChainLib.CheckpointInput memory c = _cp(id, SupplyChainLib.CheckpointType.WarehouseIn, 10_000);
        c.condition = SupplyChainLib.Condition.Damaged;
        vm.prank(warehouse);
        (, uint256 flagId) = supplyChain.recordCheckpoint(c);
        assertGt(flagId, 0);
        assertTrue(passport.isFrozen(id));
    }

    // ---------------------------------------------------------------- authorization

    function test_RequiresWeightAndEvidence() public {
        uint256 id = _atWarehouse();
        vm.startPrank(warehouse);
        vm.expectRevert(
            abi.encodeWithSelector(
                SupplyChainLib.SupplyChain__WeightRequired.selector, SupplyChainLib.CheckpointType.WarehouseIn
            )
        );
        supplyChain.recordCheckpoint(_cp(id, SupplyChainLib.CheckpointType.WarehouseIn, 0));

        SupplyChainLib.CheckpointInput memory c = _cp(id, SupplyChainLib.CheckpointType.WarehouseIn, 10_000);
        c.evidenceHash = bytes32(0);
        vm.expectRevert(SupplyChainLib.SupplyChain__EvidenceRequired.selector);
        supplyChain.recordCheckpoint(c);
        vm.stopPrank();
    }

    function test_RoleAndCustodyPerType() public {
        uint256 id = _register(10_000); // miner holds custody

        // a warehouse that does not hold the lot
        vm.expectRevert(
            abi.encodeWithSelector(
                SupplyChainLib.SupplyChain__Unauthorized.selector, warehouse, SupplyChainLib.CheckpointType.WarehouseIn
            )
        );
        _record(warehouse, id, SupplyChainLib.CheckpointType.WarehouseIn, 10_000);

        // the custodian, but without the warehouse role
        vm.expectRevert(
            abi.encodeWithSelector(
                SupplyChainLib.SupplyChain__Unauthorized.selector, miner, SupplyChainLib.CheckpointType.WarehouseIn
            )
        );
        _record(miner, id, SupplyChainLib.CheckpointType.WarehouseIn, 10_000);

        // weighing is for oracle devices only
        vm.expectRevert(
            abi.encodeWithSelector(
                SupplyChainLib.SupplyChain__Unauthorized.selector, miner, SupplyChainLib.CheckpointType.Weighing
            )
        );
        _record(miner, id, SupplyChainLib.CheckpointType.Weighing, 10_000);

        // pickup and arrival only through DeliveryManager
        vm.expectRevert(
            abi.encodeWithSelector(
                SupplyChainLib.SupplyChain__ModuleOnlyType.selector, SupplyChainLib.CheckpointType.Pickup
            )
        );
        _record(transporter, id, SupplyChainLib.CheckpointType.Pickup, 10_000);

        vm.prank(transporter);
        vm.expectRevert(abi.encodeWithSelector(SupplyChainLib.SupplyChain__NotModule.selector, transporter));
        supplyChain.recordFromModule(_cp(id, SupplyChainLib.CheckpointType.Pickup, 10_000), transporter);
    }

    function test_ProcessorIntake() public {
        uint256 id = _register(10_000);
        _deliver(id, miner, processor);
        (, uint256 flagId) = _record(processor, id, SupplyChainLib.CheckpointType.ProcessingIn, 9_950);
        assertEq(flagId, 0);
    }

    function test_OracleMustBeIndependentOfLotParties() public {
        address minersOwnNode = makeAddr("minersOwnNode");
        vm.prank(admin);
        registry.onboard(minersOwnNode, Roles.ORACLE, "org-miner", H, 0); // same org as the miner

        uint256 id = _register(10_000);
        vm.expectRevert(abi.encodeWithSelector(SupplyChainLib.SupplyChain__NotIndependent.selector, id, minersOwnNode));
        _record(minersOwnNode, id, SupplyChainLib.CheckpointType.Weighing, 10_000);
    }

    // ---------------------------------------------------------------- assignment & flags

    function test_InspectorNeedsAssignment() public {
        uint256 id = _register(10_000);
        vm.expectRevert(
            abi.encodeWithSelector(SupplyChainLib.SupplyChain__NotAssignedParticipant.selector, id, inspector)
        );
        _record(inspector, id, SupplyChainLib.CheckpointType.Inspection, 0);

        vm.prank(outsider);
        vm.expectRevert(abi.encodeWithSelector(SupplyChainLib.SupplyChain__NotOwnerOrCustodian.selector, id, outsider));
        supplyChain.assign(id, inspector);

        vm.prank(miner);
        vm.expectRevert(abi.encodeWithSelector(SupplyChainLib.SupplyChain__NotAssignable.selector, transporter));
        supplyChain.assign(id, transporter);

        vm.prank(miner); // the owner cannot choose its inspector
        vm.expectRevert(
            abi.encodeWithSelector(SupplyChainLib.SupplyChain__InspectorsArePlatformAssigned.selector, inspector)
        );
        supplyChain.assign(id, inspector);

        _assignTo(id, inspector); // the platform assigns one
        vm.prank(miner); // and the owner cannot remove it
        vm.expectRevert(
            abi.encodeWithSelector(SupplyChainLib.SupplyChain__InspectorsArePlatformAssigned.selector, inspector)
        );
        supplyChain.unassign(id, inspector);
        _record(inspector, id, SupplyChainLib.CheckpointType.Inspection, 10_000);
        assertEq(supplyChain.checkpointCount(id), 1);
    }

    function test_FlagLot_Authority() public {
        uint256 id = _register(10_000);

        vm.prank(inspector); // not assigned
        vm.expectRevert(abi.encodeWithSelector(SupplyChainLib.SupplyChain__NotFlagAuthority.selector, inspector));
        supplyChain.flagLot(id, H);

        vm.prank(auditor);
        uint256 flagId = supplyChain.flagLot(id, keccak256("finding"));
        assertEq(passport.getFlag(flagId).raisedBy, auditor);
        assertTrue(passport.isFrozen(id));

        vm.prank(miner);
        supplyChain.assign(id, customs);
        vm.prank(customs);
        supplyChain.flagLot(id, keccak256("border hold"));
    }

    // ---------------------------------------------------------------- customs

    function test_CustomsFlow_DeclareReleaseExit() public {
        bytes32[] memory req = new bytes32[](1);
        req[0] = EXPORT_PERMIT;
        vm.prank(admin);
        supplyChain.setCustomsRequiredCerts(req);

        uint256 id = _register(10_000);
        vm.prank(miner);
        supplyChain.assign(id, customs);

        // order enforced
        vm.expectRevert(
            abi.encodeWithSelector(
                SupplyChainLib.SupplyChain__InvalidCustomsStatus.selector, id, SupplyChainLib.CustomsStatus.None
            )
        );
        _record(customs, id, SupplyChainLib.CheckpointType.BorderExit, 0);

        // export permit must be attached before declaring
        vm.expectRevert(abi.encodeWithSelector(SupplyChainLib.SupplyChain__MissingCertificates.selector, id));
        _record(customs, id, SupplyChainLib.CheckpointType.CustomsDeclared, 10_000);

        vm.prank(regulator);
        certs.issue(id, EXPORT_PERMIT, uint64(block.timestamp + 30 days), H);
        _record(customs, id, SupplyChainLib.CheckpointType.CustomsDeclared, 10_000); // declared weight

        // release confirmed by an oracle against the RRA record
        _record(oracle, id, SupplyChainLib.CheckpointType.CustomsReleased, 0);
        _record(customs, id, SupplyChainLib.CheckpointType.BorderExit, 0);
        assertEq(uint8(supplyChain.customsStatus(id)), uint8(SupplyChainLib.CustomsStatus.Exited));
    }

    function test_Customs_DeclaredWeightMismatch_BlocksRelease() public {
        uint256 id = _register(10_000);
        vm.prank(miner);
        supplyChain.assign(id, customs);
        (, uint256 flagId) = _record(customs, id, SupplyChainLib.CheckpointType.CustomsDeclared, 9_000); // under-declared
        assertGt(flagId, 0);

        vm.expectRevert(abi.encodeWithSelector(SupplyChainLib.SupplyChain__LotFrozen.selector, id));
        _record(regulator, id, SupplyChainLib.CheckpointType.CustomsReleased, 0);
    }

    // ---------------------------------------------------------------- audits & oracle reports

    function test_Audit_CleanAndFinding() public {
        uint256 id = _register(10_000);
        vm.prank(auditor);
        (uint256 idx, uint256 none) = supplyChain.recordAudit(id, keccak256("clean"), true);
        assertEq(none, 0);
        assertTrue(supplyChain.getCheckpoint(id, idx).withinTolerance);

        vm.prank(auditor);
        (, uint256 flagId) = supplyChain.recordAudit(id, keccak256("finding"), false);
        assertGt(flagId, 0);
        assertTrue(passport.isFrozen(id));

        vm.prank(inspector);
        vm.expectRevert(
            abi.encodeWithSelector(
                SupplyChainLib.SupplyChain__Unauthorized.selector, inspector, SupplyChainLib.CheckpointType.Audit
            )
        );
        supplyChain.recordAudit(id, H, true);
    }

    function test_OracleReport_MismatchFreezes_AndIndependence() public {
        uint256 id = _register(10_000);
        vm.prank(oracle);
        (, uint256 flagId) = supplyChain.submitOracleReport(id, keccak256("rmb-register"), false);
        assertGt(flagId, 0);
        assertEq(passport.getFlag(flagId).raisedBy, oracle);

        address minersOwnNode = makeAddr("minersOwnNode");
        vm.prank(admin);
        registry.onboard(minersOwnNode, Roles.ORACLE, "org-miner", H, 0);
        vm.prank(minersOwnNode);
        vm.expectRevert(abi.encodeWithSelector(SupplyChainLib.SupplyChain__NotIndependent.selector, id, minersOwnNode));
        supplyChain.submitOracleReport(id, H, true);
    }

    function test_AttestationTypes_NotViaRecordCheckpoint() public {
        uint256 id = _register(10_000);
        vm.expectRevert(
            abi.encodeWithSelector(
                SupplyChainLib.SupplyChain__Unauthorized.selector, auditor, SupplyChainLib.CheckpointType.Audit
            )
        );
        _record(auditor, id, SupplyChainLib.CheckpointType.Audit, 0);
    }

    // ---------------------------------------------------------------- views

    function test_PaginatedCheckpoints() public {
        uint256 id = _register(10_000);
        for (uint256 i; i < 5; ++i) {
            _record(oracle, id, SupplyChainLib.CheckpointType.Weighing, 10_000);
        }
        assertEq(supplyChain.getCheckpoints(id, 0, 3).length, 3);
        assertEq(supplyChain.getCheckpoints(id, 3, 10).length, 2);
        assertEq(supplyChain.getCheckpoints(id, 9, 10).length, 0);
    }

    // ---------------------------------------------------------------- fuzz

    function testFuzz_ToleranceMath(uint128 qty, uint128 measured) public {
        qty = uint128(bound(qty, 1, type(uint64).max));
        measured = uint128(bound(measured, 1, type(uint64).max));
        uint256 id = _register(qty);
        (uint256 idx,) = _record(oracle, id, SupplyChainLib.CheckpointType.Weighing, measured);

        uint256 diff = measured > qty ? measured - qty : qty - measured;
        uint256 dev = (diff * 10_000) / qty;
        SupplyChainLib.Checkpoint memory c = supplyChain.getCheckpoint(id, idx);
        // first weighing: hop reference == registered quantity, so the 2% hop tolerance governs
        assertEq(c.withinTolerance, dev <= 200);
        assertEq(passport.isFrozen(id), dev > 200);
        assertEq(c.hopDeviationBps, dev > type(uint16).max ? type(uint16).max : dev);
    }
}
