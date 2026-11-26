// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {MineNetFixture} from "test/utils/MineNetFixture.sol";
import {RegistryLib} from "src/access/libraries/RegistryLib.sol";
import {Roles} from "src/access/libraries/Roles.sol";
import {Actions} from "src/access/libraries/Actions.sol";

/**
 * @title LicensingFuzzTest
 * @notice Stateless fuzz tests of the licensing workflow in {MineNetRegistry}.
 */
contract LicensingFuzzTest is MineNetFixture {
    function setUp() public override {
        super.setUp();
        vm.prank(admin);
        registry.setRoleAuthority(Roles.MINER, "org-rmb");
    }

    /// Any fresh account and organisation with an unexpired licence can be registered, and is then authorised.
    function testFuzz_RegisterCompany(address account, bytes32 orgId, bytes32 licence, uint64 validFor) public {
        vm.assume(account != address(0) && registry.participant(account).orgId == bytes32(0));
        vm.assume(orgId != bytes32(0) && !registry.orgRegistered(orgId));
        vm.assume(licence != bytes32(0));
        uint64 expiry = uint64(block.timestamp + bound(validFor, 1, 50 * 365 days));

        vm.prank(regulator);
        registry.registerCompany(account, Roles.MINER, orgId, licence, expiry);
        assertTrue(registry.isAuthorized(account, Actions.REGISTER_LOT));
        assertTrue(registry.orgRegistered(orgId));

        vm.warp(uint256(expiry) + 1); // licence expiry blocks the account everywhere
        assertFalse(registry.isAuthorized(account, Actions.REGISTER_LOT));
    }

    /// Nobody but a regulator of the licensing institution can register a company.
    function testFuzz_RegisterCompany_OnlyAuthority(address caller) public {
        vm.assume(caller != regulator);
        address fresh = makeAddr("fresh");
        uint64 expiry = uint64(block.timestamp + 1);
        vm.expectRevert(
            abi.encodeWithSelector(RegistryLib.MineNetRegistry__NotRoleAuthority.selector, caller, Roles.MINER)
        );
        vm.prank(caller);
        registry.registerCompany(fresh, Roles.MINER, "org-fresh", keccak256("l"), expiry);
    }

    /// Any evidence opens a request that only the authority can resolve, and the pending queue stays consistent.
    function testFuzz_RoleRequest_Lifecycle(bytes32 evidence, bool approve) public {
        vm.assume(evidence != bytes32(0));
        vm.prank(buyer);
        registry.requestRole(Roles.MINER, evidence);
        assertEq(registry.pendingRoleRequests("org-rmb").length, 1);
        assertEq(registry.getRoleRequest(buyer, Roles.MINER).evidenceHash, evidence);

        vm.prank(regulator);
        if (approve) registry.approveRoleRequest(buyer, Roles.MINER, evidence);
        else registry.rejectRoleRequest(buyer, Roles.MINER, evidence);

        assertEq(registry.pendingRoleRequests("org-rmb").length, 0);
        assertEq(registry.hasRole(Roles.MINER, buyer), approve);
    }
}
