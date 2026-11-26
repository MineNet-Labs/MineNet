// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {MineNetFixture} from "test/utils/MineNetFixture.sol";
import {CertificateRegistry} from "src/compliance/CertificateRegistry.sol";
import {LotPassport} from "src/traceability/LotPassport.sol";
import {CertificateLib} from "src/compliance/libraries/CertificateLib.sol";
import {PassportLib} from "src/traceability/libraries/PassportLib.sol";
import {Roles} from "src/access/libraries/Roles.sol";

contract CertificateRegistryTest is MineNetFixture {
    function test_IssueByConfiguredRoleOnly() public {
        uint256 id = _register(1000);
        vm.prank(inspector);
        vm.expectRevert(
            abi.encodeWithSelector(
                CertificateLib.CertificateRegistry__Unauthorized.selector, inspector, Roles.REGULATOR
            )
        );
        certs.issue(id, EXPORT_PERMIT, 0, H);

        vm.prank(auditor);
        uint256 certId = certs.issue(id, CONFLICT_FREE, 0, H);
        assertTrue(certs.hasValidCertificate(id, CONFLICT_FREE));
        assertEq(certs.latestCertificate(id, CONFLICT_FREE), certId);
    }

    function test_ExpiryAndRevocation() public {
        uint256 id = _register(1000);
        vm.prank(regulator);
        uint256 certId = certs.issue(id, EXPORT_PERMIT, uint64(block.timestamp + 10 days), H);
        assertTrue(certs.isValid(certId));
        vm.warp(block.timestamp + 10 days);
        assertFalse(certs.isValid(certId));

        vm.prank(auditor);
        uint256 cf = certs.issue(id, CONFLICT_FREE, 0, H);
        vm.prank(buyer);
        vm.expectRevert(
            abi.encodeWithSelector(CertificateLib.CertificateRegistry__NotIssuerOrRegulator.selector, buyer)
        );
        certs.revoke(cf, H);
        vm.prank(regulator);
        certs.revoke(cf, H);
        assertFalse(certs.hasValidCertificate(id, CONFLICT_FREE));
    }

    function test_Guards() public {
        uint256 id = _register(1000);
        vm.startPrank(regulator);
        vm.expectRevert(
            abi.encodeWithSelector(CertificateLib.CertificateRegistry__UnknownCertType.selector, bytes32("NOPE"))
        );
        certs.issue(id, bytes32("NOPE"), 0, H);
        vm.expectRevert(abi.encodeWithSelector(PassportLib.LotPassport__UnknownLot.selector, 999));
        certs.issue(999, EXPORT_PERMIT, 0, H);
        vm.expectRevert(
            abi.encodeWithSelector(CertificateLib.CertificateRegistry__InvalidExpiry.selector, uint64(block.timestamp))
        );
        certs.issue(id, EXPORT_PERMIT, uint64(block.timestamp), H);
        vm.stopPrank();

        vm.prank(outsider);
        vm.expectRevert(abi.encodeWithSelector(CertificateLib.CertificateRegistry__NotRegistryAdmin.selector, outsider));
        certs.configureCertType(EXPORT_PERMIT, Roles.INSPECTOR);
    }
}
