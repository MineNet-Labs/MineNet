// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {MineNetFixture} from "test/utils/MineNetFixture.sol";
import {Vm} from "forge-std/Vm.sol";
import {SiteLib} from "src/compliance/libraries/SiteLib.sol";
import {StaffLib} from "src/workforce/libraries/StaffLib.sol";
import {SupplyChainLib} from "src/traceability/libraries/SupplyChainLib.sol";

/// The production ledger: a site can never lot more than it recorded extracting.
contract ExtractionTest is MineNetFixture {
    bytes32 constant GOLD = keccak256("GOLD");

    function _registerGold(bytes32 lotId, uint128 qty) internal returns (uint256 id) {
        vm.prank(miner);
        id = passport.registerLot(lotId, GOLD, qty, site, H);
    }

    function testFuzz_RegisterLot_CappedByRecordedExtraction(uint128 extracted, uint128 first, uint128 second) public {
        extracted = uint128(bound(extracted, 1, 1e24));
        first = uint128(bound(first, 1, extracted));
        second = uint128(bound(second, 1, 1e24));
        _extract(site, GOLD, extracted);

        _registerGold("gold-1", first);
        SiteLib.Production memory p = sites.productionOf(site, GOLD);
        assertEq(p.extracted, extracted);
        assertEq(p.lotted, first);

        uint128 left = extracted - first;
        if (second > left) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    SiteLib.MineSiteRegistry__InsufficientExtraction.selector, site, GOLD, left, second
                )
            );
            _registerGold("gold-2", second);
        } else {
            _registerGold("gold-2", second);
            assertEq(sites.productionOf(site, GOLD).lotted, first + second);
        }
        assertLe(sites.productionOf(site, GOLD).lotted, sites.productionOf(site, GOLD).extracted);
    }

    function test_RegisterLot_WithoutExtraction_Reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(SiteLib.MineSiteRegistry__InsufficientExtraction.selector, site, GOLD, 0, 1)
        );
        _registerGold("gold-1", 1);
    }

    function test_RecordExtraction_OnlyTheSiteHolder() public {
        vm.prank(outsider);
        vm.expectRevert(
            abi.encodeWithSelector(SiteLib.MineSiteRegistry__NotOrgMember.selector, outsider, bytes32("org-miner"))
        );
        sites.recordExtraction(site, GOLD, 1_000, H);

        vm.prank(miner);
        vm.expectRevert(SiteLib.MineSiteRegistry__InvalidQuantity.selector);
        sites.recordExtraction(site, GOLD, 0, H);
    }

    function test_RecordExtraction_OnlyWhileTheSiteProduces() public {
        vm.prank(miner);
        sites.declareDormant(site, H);
        vm.prank(miner);
        vm.expectRevert(abi.encodeWithSelector(SiteLib.MineSiteRegistry__SiteNotProducing.selector, site));
        sites.recordExtraction(site, GOLD, 1_000, H);
    }

    /// Site output becomes official only through inspected shift reports, so no built-in site role records it.
    function test_NoBuiltInSiteRoleRecordsProduction() public pure {
        assertEq(StaffLib.builtIn(StaffLib.SITE_MANAGER) & StaffLib.RECORD_PRODUCTION, 0);
        assertEq(StaffLib.builtIn(StaffLib.SUPERVISOR) & StaffLib.RECORD_PRODUCTION, 0);
        assertEq(StaffLib.builtIn(StaffLib.PAYROLL_OFFICER) & StaffLib.RECORD_PRODUCTION, 0);
    }

    function test_ExtractionNeverExceedsLicensedCeiling(uint128 ceiling) public {
        ceiling = uint128(bound(ceiling, 1, 1e12));
        vm.prank(regulator);
        sites.setExtractionCeiling(site, GOLD, ceiling, H);
        _extract(site, GOLD, ceiling);
        vm.prank(miner);
        vm.expectRevert(
            abi.encodeWithSelector(SiteLib.MineSiteRegistry__CeilingExceeded.selector, site, GOLD, ceiling, ceiling + 1)
        );
        sites.recordExtraction(site, GOLD, 1, H);
    }

    function test_RevertWhen_NonRegulatorSetsCeiling() public {
        vm.prank(miner);
        vm.expectRevert(abi.encodeWithSelector(SiteLib.MineSiteRegistry__NotRegulator.selector, miner));
        sites.setExtractionCeiling(site, GOLD, 1, H);
    }

    function test_RevertWhen_OthersRecordVerifiedExtraction(address caller) public {
        vm.assume(caller != address(siteOps));
        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(SiteLib.MineSiteRegistry__NotSiteOperations.selector, caller));
        sites.recordVerifiedExtraction(site, GOLD, 1, H, caller);
    }

    function test_ReduceExtraction_NeverBelowLotted() public {
        _extract(site, GOLD, 1_000);
        _registerGold("gold-1", 600);

        vm.prank(regulator);
        vm.expectRevert(
            abi.encodeWithSelector(SiteLib.MineSiteRegistry__InsufficientExtraction.selector, site, GOLD, 400, 401)
        );
        sites.reduceExtraction(site, GOLD, 401, H);

        vm.prank(regulator); // a regulator finding: production was overstated
        sites.reduceExtraction(site, GOLD, 400, keccak256("audit finding"));
        SiteLib.Production memory p = sites.productionOf(site, GOLD);
        assertEq(p.extracted, 600);
        assertEq(p.lotted, 600);

        vm.prank(outsider);
        vm.expectRevert(
            abi.encodeWithSelector(SiteLib.MineSiteRegistry__NotOrgMember.selector, outsider, bytes32("org-miner"))
        );
        sites.reduceExtraction(site, GOLD, 1, H);
    }

    function test_ConsumeExtraction_OnlyPassport() public {
        _extract(site, GOLD, 1_000);
        vm.prank(miner);
        vm.expectRevert(abi.encodeWithSelector(SiteLib.MineSiteRegistry__NotPassport.selector, miner));
        sites.consumeExtraction(site, GOLD, 1_000);
    }

    // ================================================================ declared grade (SupplyChain)

    function test_DeclareGrade_OnceByOwnerBeforeInspection() public {
        uint256 id = _register(1_000);
        vm.prank(outsider);
        vm.expectRevert(abi.encodeWithSelector(SupplyChainLib.SupplyChain__CannotDeclareGrade.selector, id));
        supplyChain.declareGrade(id, 6_500);

        vm.prank(miner);
        supplyChain.declareGrade(id, 6_500);
        assertEq(supplyChain.declaredGradeOf(id), 6_500);

        vm.prank(miner);
        vm.expectRevert(abi.encodeWithSelector(SupplyChainLib.SupplyChain__CannotDeclareGrade.selector, id));
        supplyChain.declareGrade(id, 7_000); // declared once

        uint256 inspected = _inspected(1_000);
        vm.prank(miner);
        vm.expectRevert(abi.encodeWithSelector(SupplyChainLib.SupplyChain__CannotDeclareGrade.selector, inspected));
        supplyChain.declareGrade(inspected, 6_500); // too late: already inspected

        vm.prank(miner);
        vm.expectRevert(abi.encodeWithSelector(SupplyChainLib.SupplyChain__InvalidGrade.selector, uint16(10_001)));
        supplyChain.declareGrade(id, 10_001);
    }

    function testFuzz_GradeDiscrepancy_EmittedBeyondThreshold(uint16 declared, uint16 attested) public {
        declared = uint16(bound(declared, 1, 10_000));
        attested = uint16(bound(attested, 1, 10_000));
        uint256 id = _register(1_000);
        vm.prank(miner);
        supplyChain.declareGrade(id, declared);

        bool expected =
            (declared > attested ? declared - attested : attested - declared) > supplyChain.gradeDiscrepancyBps();
        vm.recordLogs();
        _grade(id, attested);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool seen;
        for (uint256 i; i < logs.length; ++i) {
            if (
                logs[i].emitter == address(supplyChain) && logs[i].topics[0] == SupplyChainLib.GradeDiscrepancy.selector
            ) {
                seen = true;
                (uint16 d, uint16 a) = abi.decode(logs[i].data, (uint16, uint16));
                assertEq(d, declared);
                assertEq(a, attested);
            }
        }
        assertEq(seen, expected, "discrepancy reported exactly when beyond the threshold");
    }
}
