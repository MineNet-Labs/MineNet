// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {MineNetFixture} from "test/utils/MineNetFixture.sol";
import {LicenceLib} from "src/compliance/libraries/LicenceLib.sol";

contract LicencesTest is MineNetFixture {
    bytes32 constant TRANSPORT_LICENCE = keccak256("TRANSPORT_LICENCE");

    function _issue(uint64 duration) internal returns (uint256 id) {
        vm.prank(regulator);
        id = licences.issueLicence(
            "org-transport", TRANSPORT_LICENCE, keccak256("TL-1"), 0, uint64(block.timestamp) + duration, H
        );
    }

    function test_Issue_RecordsAuthorityAndPeriod() public {
        uint256 id = _issue(365 days);
        LicenceLib.Licence memory l = licences.getLicence(id);
        assertEq(l.orgId, bytes32("org-transport"));
        assertEq(l.authority, bytes32("org-rmb")); // the regulator's own organisation
        assertEq(l.issuedBy, regulator);
        assertEq(l.validUntil, block.timestamp + 365 days);
        assertEq(uint8(licences.status(id)), uint8(LicenceLib.Status.Valid));
        assertTrue(licences.isValid(id));
        assertEq(licences.licencesOf("org-transport").length, 1);
    }

    function test_Issue_OnlyRegulator() public {
        vm.prank(miner);
        vm.expectRevert(abi.encodeWithSelector(LicenceLib.LicenceRegistry__NotRegulator.selector, miner));
        licences.issueLicence("org-miner", TRANSPORT_LICENCE, H, 0, uint64(block.timestamp + 1 days), H);
    }

    function test_Issue_RejectsBadPeriod() public {
        vm.startPrank(regulator);
        vm.expectRevert();
        licences.issueLicence("org-x", TRANSPORT_LICENCE, H, 0, uint64(block.timestamp), H);
        vm.expectRevert(LicenceLib.LicenceRegistry__InvalidOrg.selector);
        licences.issueLicence(bytes32(0), TRANSPORT_LICENCE, H, 0, uint64(block.timestamp + 1 days), H);
        vm.stopPrank();
    }

    function test_NotYetStarted_IsNotValid() public {
        vm.prank(regulator);
        uint256 id = licences.issueLicence(
            "org-x", TRANSPORT_LICENCE, H, uint64(block.timestamp + 10 days), uint64(block.timestamp + 100 days), H
        );
        assertFalse(licences.isValid(id));
        vm.warp(block.timestamp + 10 days);
        assertTrue(licences.isValid(id));
    }

    // ---------------------------------------------------------------- reminders

    function test_Reminders_OnePerThresholdThenExpiry() public {
        uint256 id = _issue(365 days);
        vm.expectRevert(abi.encodeWithSelector(LicenceLib.LicenceRegistry__NoNoticeDue.selector, id));
        licences.sendNotice(id);

        vm.warp(block.timestamp + 365 days - 90 days); // 90 days left
        assertEq(uint8(licences.status(id)), uint8(LicenceLib.Status.ExpiringSoon));
        vm.expectEmit(true, true, false, true);
        emit LicenceLib.LicenceExpiryReminder(id, "org-transport", licences.getLicence(id).validUntil, 90 days);
        licences.sendNotice(id);
        vm.expectRevert(abi.encodeWithSelector(LicenceLib.LicenceRegistry__NoNoticeDue.selector, id));
        licences.sendNotice(id); // once per threshold

        vm.warp(block.timestamp + 60 days); // 30 days left
        licences.sendNotice(id);
        vm.warp(block.timestamp + 23 days); // 7 days left
        licences.sendNotice(id);
        assertEq(licences.getLicence(id).noticesSent, 3);

        vm.warp(block.timestamp + 7 days + 1);
        assertEq(uint8(licences.status(id)), uint8(LicenceLib.Status.Expired));
        assertFalse(licences.isValid(id));
        vm.expectEmit(true, true, false, true);
        emit LicenceLib.LicenceExpired(id, "org-transport", licences.getLicence(id).validUntil);
        licences.sendNotice(id);
    }

    function test_Reminders_MissedOnesCollapseIntoOne() public {
        uint256 id = _issue(365 days);
        vm.warp(block.timestamp + 360 days); // 5 days left: all three thresholds crossed
        licences.sendNotice(id);
        assertEq(licences.getLicence(id).noticesSent, 3);
        vm.expectRevert(abi.encodeWithSelector(LicenceLib.LicenceRegistry__NoNoticeDue.selector, id));
        licences.sendNotice(id);
    }

    function test_Renewal_ResetsReminders() public {
        uint256 id = _issue(100 days);
        vm.warp(block.timestamp + 20 days);
        licences.sendNotice(id);
        vm.prank(regulator);
        licences.renewLicence(id, uint64(block.timestamp + 365 days), keccak256("renewed"));
        assertEq(licences.getLicence(id).noticesSent, 0);
        assertEq(uint8(licences.status(id)), uint8(LicenceLib.Status.Valid));
    }

    function test_Automation_CheckAndPerformUpkeep() public {
        uint256 a = _issue(60 days); // inside the 90-day window at once
        _issue(365 days); // not due
        uint256 c = _issue(20 days);

        (bool needed, bytes memory data) = licences.checkUpkeep("");
        assertTrue(needed);
        uint256[] memory ids = abi.decode(data, (uint256[]));
        assertEq(ids.length, 2);
        assertEq(ids[0], a);
        assertEq(ids[1], c);

        licences.performUpkeep(data);
        (needed,) = licences.checkUpkeep("");
        assertFalse(needed);

        // replaying stale perform data is harmless: nothing is due, nothing is sent
        licences.performUpkeep(data);
        assertEq(licences.getLicence(a).noticesSent, 1);
    }

    function test_Automation_ScansARange() public {
        _issue(60 days); // id 2 (id 1 is the fixture's mining licence)
        uint256 b = _issue(60 days); // id 3
        (bool needed, bytes memory data) = licences.checkUpkeep(abi.encode(b, uint256(1)));
        assertTrue(needed);
        uint256[] memory ids = abi.decode(data, (uint256[]));
        assertEq(ids.length, 1);
        assertEq(ids[0], b);
    }

    function test_AttentionNeeded() public {
        uint256 soon = _issue(30 days);
        _issue(365 days);
        uint256[] memory ids = licences.attentionNeeded("org-transport");
        assertEq(ids.length, 1);
        assertEq(ids[0], soon);
    }

    // ---------------------------------------------------------------- suspension and revocation

    function test_SuspendReinstateRevoke() public {
        uint256 id = _issue(365 days);
        vm.startPrank(regulator);
        licences.suspendLicence(id, H);
        assertEq(uint8(licences.status(id)), uint8(LicenceLib.Status.Suspended));
        assertFalse(licences.isValid(id));
        vm.expectRevert(abi.encodeWithSelector(LicenceLib.LicenceRegistry__AlreadySuspended.selector, id));
        licences.suspendLicence(id, H);
        licences.reinstateLicence(id, H);
        assertTrue(licences.isValid(id));

        licences.revokeLicence(id, H);
        assertEq(uint8(licences.status(id)), uint8(LicenceLib.Status.Revoked));
        vm.expectRevert(abi.encodeWithSelector(LicenceLib.LicenceRegistry__Revoked.selector, id));
        licences.renewLicence(id, uint64(block.timestamp + 800 days), H);
        vm.stopPrank();

        vm.warp(block.timestamp + 364 days);
        vm.expectRevert(abi.encodeWithSelector(LicenceLib.LicenceRegistry__NoNoticeDue.selector, id));
        licences.sendNotice(id); // revoked licences get no reminders
    }

    function test_SetReminderThresholds() public {
        uint32[] memory t = new uint32[](2);
        t[0] = 60 days;
        t[1] = 60 days; // not strictly decreasing
        vm.startPrank(admin);
        vm.expectRevert(LicenceLib.LicenceRegistry__InvalidThresholds.selector);
        licences.setReminderThresholds(t);
        t[1] = 14 days;
        licences.setReminderThresholds(t);
        vm.stopPrank();
        assertEq(licences.reminderThresholds().length, 2);

        vm.prank(outsider);
        vm.expectRevert(abi.encodeWithSelector(LicenceLib.LicenceRegistry__NotRegistryAdmin.selector, outsider));
        licences.setReminderThresholds(t);
    }
}
