// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {MineNetFixture} from "test/utils/MineNetFixture.sol";
import {InspectionLib} from "src/compliance/libraries/InspectionLib.sol";
import {PassportLib} from "src/traceability/libraries/PassportLib.sol";
import {SiteLib} from "src/compliance/libraries/SiteLib.sol";
import {Roles} from "src/access/libraries/Roles.sol";

/**
 * @title InspectionsTest
 * @notice The inspector roster and platform assignment: operators never choose who inspects their lots or sites.
 */
contract InspectionsTest is MineNetFixture {
    address itsciAgent = makeAddr("itsciAgent"); // traceability field agent (ITSCI)
    address huyeInspector = makeAddr("huyeInspector"); // RMB inspector deployed to another district
    address inHouse = makeAddr("inHouseInspector"); // an inspector employed by the miner itself

    function setUp() public override {
        super.setUp();
        vm.startPrank(admin);
        registry.onboard(itsciAgent, Roles.INSPECTOR, "org-itsci", H, 0);
        registry.onboard(huyeInspector, Roles.INSPECTOR, "org-inspect", H, 0);
        registry.onboard(inHouse, Roles.INSPECTOR, "org-miner", H, 0);
        vm.stopPrank();
        vm.prank(regulator);
        inspections.setInspectorate("org-itsci", InspectionLib.InspectorateKind.TraceabilityOperator);
    }

    function _deployTo(address who, string memory district) internal {
        bytes32[] memory coverage = new bytes32[](1);
        coverage[0] = InspectionLib.districtKey(district);
        vm.prank(regulator);
        inspections.deployInspector(who, coverage);
    }

    // ---------------------------------------------------------------- roster

    function test_Roster_OnlyTheInspectorAuthority() public {
        bytes32[] memory coverage = new bytes32[](1);
        coverage[0] = InspectionLib.NATIONAL;
        vm.prank(miner);
        vm.expectRevert(abi.encodeWithSelector(InspectionLib.InspectionRegistry__NotInspectorAuthority.selector, miner));
        inspections.deployInspector(itsciAgent, coverage);

        vm.prank(regulator); // an inspector of an unapproved organisation cannot be deployed
        vm.expectRevert(abi.encodeWithSelector(InspectionLib.InspectionRegistry__InvalidInspector.selector, inHouse));
        inspections.deployInspector(inHouse, coverage);

        vm.prank(regulator); // nor a non-inspector
        vm.expectRevert(abi.encodeWithSelector(InspectionLib.InspectionRegistry__InvalidInspector.selector, buyer));
        inspections.deployInspector(buyer, coverage);

        vm.prank(regulator);
        inspections.deployInspector(itsciAgent, coverage);
        assertTrue(inspections.getInspector(itsciAgent).enrolled);
        assertEq(inspections.inspectorsIn(InspectionLib.NATIONAL).length, 2);
    }

    // ---------------------------------------------------------------- assignment

    function test_Assignment_PlatformPicksAndOnlyItMayInspect() public {
        _deployTo(huyeInspector, "Huye"); // covers another district: never drawn for a Rutsiro lot
        uint256 id = _register(1_000);
        vm.prank(miner);
        address assigned = inspections.requestInspection(id);
        assertEq(assigned, inspector);
        assertEq(inspections.getAssignment(id).coverage, InspectionLib.districtKey("Rutsiro"));
        assertTrue(supplyChain.isAssigned(id, inspector));

        vm.prank(huyeInspector); // any other inspector is refused by the passport
        vm.expectRevert(
            abi.encodeWithSelector(PassportLib.LotPassport__NotAssignedInspector.selector, id, huyeInspector)
        );
        passport.submitInspection(id, true, H);

        vm.prank(inspector);
        passport.submitInspection(id, true, H);
        assertEq(uint8(passport.getLot(id).status), uint8(PassportLib.LotStatus.Inspected));
    }

    function test_Assignment_FallsBackToNationalPool() public {
        vm.prank(regulator);
        inspections.removeInspector(inspector, H);
        bytes32[] memory national = new bytes32[](1);
        national[0] = InspectionLib.NATIONAL;
        vm.prank(regulator);
        inspections.deployInspector(itsciAgent, national);

        uint256 id = _register(1_000);
        vm.prank(miner);
        assertEq(inspections.requestInspection(id), itsciAgent);
        assertEq(inspections.getAssignment(id).coverage, InspectionLib.NATIONAL);
    }

    function test_Assignment_NoInspectorAvailable() public {
        vm.prank(inspector);
        inspections.setAvailability(false);
        uint256 id = _register(1_000);
        vm.prank(miner);
        vm.expectRevert(abi.encodeWithSelector(InspectionLib.InspectionRegistry__NoInspectorAvailable.selector, id));
        inspections.requestInspection(id);
    }

    function test_Assignment_WhoMayRequest() public {
        uint256 id = _register(1_000);
        vm.prank(buyer);
        vm.expectRevert(
            abi.encodeWithSelector(InspectionLib.InspectionRegistry__NotAllowedToRequest.selector, id, buyer)
        );
        inspections.requestInspection(id);

        vm.prank(regulator); // an unannounced inspection ordered by RMB
        inspections.requestInspection(id);
        assertEq(inspections.getAssignment(id).requestedBy, regulator);
    }

    function test_Assignment_DeclineAndExpiryReassignToAnotherInspector() public {
        _deployTo(itsciAgent, "Rutsiro");
        uint256 id = _register(1_000);
        vm.prank(miner);
        address first = inspections.requestInspection(id);

        uint64 dueBy = inspections.getAssignment(id).dueBy;
        vm.prank(miner);
        vm.expectRevert(abi.encodeWithSelector(InspectionLib.InspectionRegistry__AssignmentOpen.selector, id, dueBy));
        inspections.requestInspection(id);

        vm.prank(first); // conflict of interest: declines, the other inspector is assigned at once
        address second = inspections.declineInspection(id, keccak256("conflict"));
        assertTrue(second != first);
        assertFalse(supplyChain.isAssigned(id, first));
        assertTrue(supplyChain.isAssigned(id, second));

        vm.warp(block.timestamp + 7 days + 1); // the second never inspected: reassigned after the window
        vm.prank(miner);
        assertEq(inspections.requestInspection(id), first);
        assertEq(inspections.getAssignment(id).round, 3);
    }

    /// Whatever the randomness, the drawn inspector is never from the owner's (or custodian's) organisation.
    function testFuzz_Assignment_NeverFromOwnersOrganisation(uint256 randomness) public {
        vm.prank(regulator);
        inspections.setInspectorate("org-miner", InspectionLib.InspectorateKind.TraceabilityOperator);
        _deployTo(inHouse, "Rutsiro");
        _deployTo(itsciAgent, "Rutsiro");

        uint256 id = _register(1_000);
        vm.prevrandao(bytes32(randomness));
        vm.prank(miner);
        address assigned = inspections.requestInspection(id);
        assertTrue(assigned != inHouse);
        assertTrue(assigned == inspector || assigned == itsciAgent);
    }

    // ---------------------------------------------------------------- mine sites

    function test_SiteInspection_OnlyInspectorsDeployedToTheDistrict() public {
        _deployTo(huyeInspector, "Huye");
        vm.prank(miner);
        sites.declareDormant(site, keccak256("safety-plan"));

        vm.prank(huyeInspector);
        vm.expectRevert(
            abi.encodeWithSelector(SiteLib.MineSiteRegistry__NotDeployedToSite.selector, huyeInspector, site)
        );
        sites.inspectSafety(site, true, H);

        vm.prank(inspector); // deployed to Rutsiro
        sites.inspectSafety(site, true, H);
        assertTrue(sites.getSite(site).safetyPassed);
    }
}
