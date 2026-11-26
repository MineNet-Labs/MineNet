// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {MineNetFixture} from "test/utils/MineNetFixture.sol";
import {RegistryLib} from "src/access/libraries/RegistryLib.sol";
import {Roles} from "src/access/libraries/Roles.sol";
import {Actions} from "src/access/libraries/Actions.sol";

contract LicensingTest is MineNetFixture {
    address rra = makeAddr("rraRegulator"); // Rwanda Revenue Authority regulator
    address rmb2 = makeAddr("rmbRegulator2"); // a second RMB regulator
    address newMine = makeAddr("newMine");
    bytes32 constant LICENCE = keccak256("ML-2026-077");

    function setUp() public override {
        super.setUp();
        vm.startPrank(admin);
        registry.onboard(rra, Roles.REGULATOR, "org-rra", H, 0);
        registry.onboard(rmb2, Roles.REGULATOR, "org-rmb", H, 0);
        registry.setRoleAuthority(Roles.MINER, "org-rmb");
        registry.setRoleAuthority(Roles.REFINERY, "org-rmb");
        registry.setRoleAuthority(Roles.CUSTOMS, "org-rra");
        vm.stopPrank();
    }

    function _exp() internal view returns (uint64) {
        return uint64(block.timestamp + 5 * 365 days);
    }

    // ---------------------------------------------------------------- role authorities

    function test_SetRoleAuthority_AdminOnly_RegulatorRoleReserved() public {
        vm.prank(regulator);
        vm.expectRevert();
        registry.setRoleAuthority(Roles.BUYER, "org-rmb");

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(RegistryLib.MineNetRegistry__ReservedRole.selector, Roles.REGULATOR));
        registry.setRoleAuthority(Roles.REGULATOR, "org-rmb");

        assertEq(registry.roleAuthority(Roles.MINER), bytes32("org-rmb"));
    }

    // ---------------------------------------------------------------- registering new companies

    function test_RegisterCompany_NewMiningCompany() public {
        vm.expectEmit(address(registry));
        emit RegistryLib.CompanyRegistered("org-newmine", newMine, Roles.MINER, regulator);
        vm.prank(regulator);
        registry.registerCompany(newMine, Roles.MINER, "org-newmine", LICENCE, _exp());

        assertTrue(registry.hasRole(Roles.MINER, newMine));
        assertTrue(registry.orgRegistered("org-newmine"));
        assertTrue(registry.isAuthorized(newMine, Actions.REGISTER_LOT));
        assertEq(registry.participant(newMine).licenceHash, LICENCE);
    }

    function test_RegisterCompany_OnlyTheLicensingAuthority() public {
        vm.prank(rra); // RRA does not license miners
        vm.expectRevert(
            abi.encodeWithSelector(RegistryLib.MineNetRegistry__NotRoleAuthority.selector, rra, Roles.MINER)
        );
        registry.registerCompany(newMine, Roles.MINER, "org-newmine", LICENCE, _exp());

        vm.prank(miner); // not a regulator
        vm.expectRevert(
            abi.encodeWithSelector(RegistryLib.MineNetRegistry__NotRoleAuthority.selector, miner, Roles.MINER)
        );
        registry.registerCompany(newMine, Roles.MINER, "org-newmine", LICENCE, _exp());

        vm.prank(regulator); // no authority set for BUYER: admin only
        vm.expectRevert(abi.encodeWithSelector(RegistryLib.MineNetRegistry__NoAuthority.selector, Roles.BUYER));
        registry.registerCompany(newMine, Roles.BUYER, "org-newmine", LICENCE, _exp());

        vm.prank(rra); // RRA registers a customs agency
        registry.registerCompany(newMine, Roles.CUSTOMS, "org-newcustoms", LICENCE, _exp());
        assertTrue(registry.hasRole(Roles.CUSTOMS, newMine));
    }

    function test_RegisterCompany_OnlyNewCompaniesWithValidLicence() public {
        vm.startPrank(regulator);
        vm.expectRevert(abi.encodeWithSelector(RegistryLib.MineNetRegistry__OrgExists.selector, bytes32("org-miner")));
        registry.registerCompany(newMine, Roles.MINER, "org-miner", LICENCE, _exp());

        vm.expectRevert(abi.encodeWithSelector(RegistryLib.MineNetRegistry__AccountExists.selector, buyer));
        registry.registerCompany(buyer, Roles.MINER, "org-newmine", LICENCE, _exp());

        vm.expectRevert(RegistryLib.MineNetRegistry__InvalidRegistration.selector);
        registry.registerCompany(newMine, Roles.MINER, "org-newmine", bytes32(0), _exp());

        vm.expectRevert(RegistryLib.MineNetRegistry__InvalidRegistration.selector);
        registry.registerCompany(newMine, Roles.MINER, "org-newmine", LICENCE, uint64(block.timestamp));
        vm.stopPrank();
    }

    // ---------------------------------------------------------------- role requests

    function test_RoleRequest_ApprovedByAuthority() public {
        vm.prank(buyer); // a trader applies to become a refinery
        registry.requestRole(Roles.REFINERY, keccak256("refinery-licence-application"));

        RegistryLib.RoleRequest[] memory pending = registry.pendingRoleRequests("org-rmb");
        assertEq(pending.length, 1);
        assertEq(pending[0].account, buyer);
        assertEq(pending[0].orgId, bytes32("org-buyer"));
        assertFalse(registry.isAuthorized(buyer, Actions.PROCESS_LOTS));

        vm.prank(rra); // not the licensing authority for refineries
        vm.expectRevert(
            abi.encodeWithSelector(RegistryLib.MineNetRegistry__NotRoleAuthority.selector, rra, Roles.REFINERY)
        );
        registry.approveRoleRequest(buyer, Roles.REFINERY, H);

        vm.prank(regulator);
        registry.approveRoleRequest(buyer, Roles.REFINERY, keccak256("RL-2026-009"));
        assertTrue(registry.hasRole(Roles.REFINERY, buyer));
        assertTrue(registry.isAuthorized(buyer, Actions.PROCESS_LOTS));
        assertEq(registry.pendingRoleRequests("org-rmb").length, 0);
        assertEq(registry.getRoleRequest(buyer, Roles.REFINERY).requestedAt, 0);
    }

    function test_RoleRequest_RejectAndCancel() public {
        vm.prank(buyer);
        registry.requestRole(Roles.REFINERY, H);
        vm.prank(regulator);
        registry.rejectRoleRequest(buyer, Roles.REFINERY, keccak256("missing EIA"));
        assertFalse(registry.hasRole(Roles.REFINERY, buyer));

        vm.prank(buyer); // can apply again
        registry.requestRole(Roles.REFINERY, H);
        vm.prank(buyer);
        registry.cancelRoleRequest(Roles.REFINERY);
        assertEq(registry.pendingRoleRequests("org-rmb").length, 0);

        vm.prank(regulator);
        vm.expectRevert(abi.encodeWithSelector(RegistryLib.MineNetRegistry__NoRequest.selector, buyer, Roles.REFINERY));
        registry.approveRoleRequest(buyer, Roles.REFINERY, H);
    }

    function test_RoleRequest_Validation() public {
        vm.startPrank(buyer);
        vm.expectRevert(RegistryLib.MineNetRegistry__MissingEvidence.selector);
        registry.requestRole(Roles.REFINERY, bytes32(0));

        vm.expectRevert(abi.encodeWithSelector(RegistryLib.MineNetRegistry__NoAuthority.selector, Roles.WAREHOUSE));
        registry.requestRole(Roles.WAREHOUSE, H);

        registry.requestRole(Roles.REFINERY, H);
        vm.expectRevert(
            abi.encodeWithSelector(RegistryLib.MineNetRegistry__RequestPending.selector, buyer, Roles.REFINERY)
        );
        registry.requestRole(Roles.REFINERY, H);
        vm.stopPrank();

        vm.prank(miner);
        vm.expectRevert(
            abi.encodeWithSelector(RegistryLib.MineNetRegistry__RoleAlreadyHeld.selector, miner, Roles.MINER)
        );
        registry.requestRole(Roles.MINER, H);

        vm.prank(outsider); // not a participant: new companies are registered by the regulator
        vm.expectRevert(abi.encodeWithSelector(RegistryLib.MineNetRegistry__NotInGoodStanding.selector, outsider));
        registry.requestRole(Roles.MINER, H);
    }

    function test_RoleRequest_SuspendedRequesterCannotBeApproved() public {
        vm.prank(buyer);
        registry.requestRole(Roles.REFINERY, H);
        vm.prank(rra);
        registry.suspend(buyer, H);

        vm.prank(regulator);
        vm.expectRevert(abi.encodeWithSelector(RegistryLib.MineNetRegistry__NotInGoodStanding.selector, buyer));
        registry.approveRoleRequest(buyer, Roles.REFINERY, H);

        vm.prank(regulator); // it can still be rejected
        registry.rejectRoleRequest(buyer, Roles.REFINERY, H);
    }

    function test_RoleRequest_NoConflictOfInterest() public {
        vm.prank(rmb2); // an RMB regulator asks RMB for a miner role
        registry.requestRole(Roles.MINER, H);
        vm.prank(regulator);
        vm.expectRevert(abi.encodeWithSelector(RegistryLib.MineNetRegistry__ConflictOfInterest.selector, rmb2));
        registry.approveRoleRequest(rmb2, Roles.MINER, H);
    }

    function test_RevokeRoleByAuthority() public {
        vm.prank(rra);
        vm.expectRevert(
            abi.encodeWithSelector(RegistryLib.MineNetRegistry__NotRoleAuthority.selector, rra, Roles.MINER)
        );
        registry.revokeRoleByAuthority(miner, Roles.MINER, H);

        vm.prank(regulator);
        registry.revokeRoleByAuthority(miner, Roles.MINER, keccak256("licence revoked"));
        assertFalse(registry.isAuthorized(miner, Actions.REGISTER_LOT));

        vm.prank(regulator);
        vm.expectRevert(abi.encodeWithSelector(RegistryLib.MineNetRegistry__RoleNotHeld.selector, miner, Roles.MINER));
        registry.revokeRoleByAuthority(miner, Roles.MINER, H);
    }
}
