// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {MineNetFixture} from "test/utils/MineNetFixture.sol";
import {AuditLib} from "src/compliance/libraries/AuditLib.sol";
import {Roles} from "src/access/libraries/Roles.sol";

/**
 * @title AuditsTest
 * @notice Accredited auditor roster, exporter's choice, independence, rotation and IMCA review.
 */
contract AuditsTest is MineNetFixture {
    address icglr = makeAddr("icglrAuditCommittee"); // ICGLR Audit Committee / IMCA
    address rmi = makeAddr("rmi"); // Responsible Minerals Initiative
    address auditor2 = makeAddr("auditor2");
    bytes32 constant ICGLR = AuditLib.ICGLR_THIRD_PARTY_AUDIT;
    bytes32 constant RMAP = AuditLib.RMI_RMAP_AUDIT;

    function setUp() public override {
        super.setUp();
        vm.startPrank(admin);
        registry.onboard(icglr, Roles.ACCREDITOR, "org-icglr", H, 0);
        registry.onboard(rmi, Roles.ACCREDITOR, "org-rmi", H, 0);
        registry.onboard(auditor2, Roles.AUDITOR, "org-audit-2", H, uint64(block.timestamp + 10 * 365 days));
        audits.setScheme(
            ICGLR,
            AuditLib.Scheme({
                enabled: true,
                reviewRequired: true,
                maxConsecutive: 2,
                accreditorOrg: "org-icglr",
                validity: 365 days,
                coolingOff: 365 days
            })
        );
        audits.setScheme(
            RMAP,
            AuditLib.Scheme({
                enabled: true,
                reviewRequired: false,
                maxConsecutive: 3,
                accreditorOrg: "org-rmi",
                validity: 3 * 365 days,
                coolingOff: 365 days
            })
        );
        vm.stopPrank();

        vm.startPrank(icglr);
        audits.accredit("org-audit", ICGLR, uint64(block.timestamp + 5 * 365 days), keccak256("accreditation-1"));
        audits.accredit("org-audit-2", ICGLR, uint64(block.timestamp + 5 * 365 days), keccak256("accreditation-2"));
        vm.stopPrank();
    }

    /// Exporter (the miner) audited by `firm` under ICGLR: request, fieldwork, report, IMCA review.
    function _auditCycle(bytes32 firm, address firmAuditor, bool passed, bool approved) internal returns (uint256 id) {
        vm.prank(miner);
        id = audits.requestAudit(ICGLR, "org-miner", firm, keccak256("scope"));
        vm.prank(firmAuditor);
        audits.acceptAudit(id);
        vm.prank(firmAuditor);
        audits.submitReport(id, passed, keccak256("report"), bytes32(0));
        vm.prank(icglr);
        audits.reviewReport(id, approved, keccak256("executive-summary"));
    }

    // ---------------------------------------------------------------- accreditation

    function test_Accreditation_OnlyTheSchemesBody() public {
        vm.prank(rmi); // RMI does not govern ICGLR audits
        vm.expectRevert(abi.encodeWithSelector(AuditLib.AuditRegistry__NotAccreditor.selector, rmi, ICGLR));
        audits.accredit("org-buyer", ICGLR, uint64(block.timestamp + 365 days), H);

        vm.prank(auditor); // auditors cannot accredit themselves
        vm.expectRevert(abi.encodeWithSelector(AuditLib.AuditRegistry__NotAccreditor.selector, auditor, ICGLR));
        audits.accredit("org-audit", ICGLR, uint64(block.timestamp + 365 days), H);

        vm.prank(icglr); // unregistered firm
        vm.expectRevert(AuditLib.AuditRegistry__InvalidAccreditation.selector);
        audits.accredit("org-ghost", ICGLR, uint64(block.timestamp + 365 days), H);

        assertEq(audits.accreditedFirms(ICGLR).length, 2);
        vm.prank(icglr);
        audits.setAccreditationSuspended("org-audit-2", ICGLR, true, keccak256("vetting failed"));
        assertFalse(audits.isAccredited("org-audit-2", ICGLR));
        assertEq(audits.accreditedFirms(ICGLR).length, 1);
    }

    // ---------------------------------------------------------------- selection & independence

    function test_Request_OnlyFromTheAccreditedRoster() public {
        vm.prank(miner); // not accredited for RMAP
        vm.expectRevert(
            abi.encodeWithSelector(AuditLib.AuditRegistry__NotAccredited.selector, bytes32("org-audit"), RMAP)
        );
        audits.requestAudit(RMAP, "org-miner", "org-audit", keccak256("scope"));

        vm.prank(miner); // nor a firm that was never vetted
        vm.expectRevert(
            abi.encodeWithSelector(AuditLib.AuditRegistry__NotAccredited.selector, bytes32("org-buyer"), ICGLR)
        );
        audits.requestAudit(ICGLR, "org-miner", "org-buyer", keccak256("scope"));
    }

    function test_Request_ConflictOfInterestBlocks() public {
        vm.prank(auditor); // the firm discloses consulting ties with the exporter
        audits.setConflict("org-audit", "org-miner", true, keccak256("consulting contract 2025"));

        vm.prank(miner);
        vm.expectRevert(
            abi.encodeWithSelector(
                AuditLib.AuditRegistry__NotIndependent.selector, bytes32("org-audit"), bytes32("org-miner")
            )
        );
        audits.requestAudit(ICGLR, "org-miner", "org-audit", keccak256("scope"));

        vm.prank(miner); // the company cannot clear it; only an accreditation body can
        vm.expectRevert(abi.encodeWithSelector(AuditLib.AuditRegistry__Unauthorized.selector, miner));
        audits.setConflict("org-audit", "org-miner", false, keccak256("ended"));
        vm.prank(icglr);
        audits.setConflict("org-audit", "org-miner", false, keccak256("ties ended, verified"));
        vm.prank(miner);
        audits.requestAudit(ICGLR, "org-miner", "org-audit", keccak256("scope"));
    }

    function test_Request_NoOpinionShopping() public {
        vm.prank(miner);
        uint256 first = audits.requestAudit(ICGLR, "org-miner", "org-audit", keccak256("scope"));
        vm.prank(miner);
        vm.expectRevert(abi.encodeWithSelector(AuditLib.AuditRegistry__EngagementOpen.selector, first));
        audits.requestAudit(ICGLR, "org-miner", "org-audit-2", keccak256("scope"));
    }

    function test_BuyerRequestedAudit_NeedsSupplierConsent() public {
        vm.prank(refinery); // a refinery wants its supplier audited
        uint256 id = audits.requestAudit(ICGLR, "org-miner", "org-audit-2", keccak256("scope"));
        vm.prank(auditor2);
        vm.expectRevert(abi.encodeWithSelector(AuditLib.AuditRegistry__ConsentRequired.selector, id));
        audits.acceptAudit(id);

        vm.prank(miner);
        audits.consentAudit(id);
        vm.prank(auditor2);
        audits.acceptAudit(id);
        assertEq(uint8(audits.getEngagement(id).status), uint8(AuditLib.EngagementStatus.Fieldwork));
    }

    // ---------------------------------------------------------------- review & certification

    function test_Certification_RequiresIMCAReview() public {
        vm.prank(miner);
        uint256 id = audits.requestAudit(ICGLR, "org-miner", "org-audit", keccak256("scope"));
        vm.prank(auditor);
        audits.acceptAudit(id);
        vm.prank(auditor);
        audits.submitReport(id, true, keccak256("report"), bytes32(0));
        assertEq(uint8(audits.getEngagement(id).status), uint8(AuditLib.EngagementStatus.InReview));
        assertFalse(audits.isCertified("org-miner", ICGLR)); // no rubber-stamping before review

        vm.prank(icglr);
        audits.reviewReport(id, true, keccak256("executive-summary"));
        assertTrue(audits.isCertified("org-miner", ICGLR));
        assertEq(audits.getEngagement(id).summaryHash, keccak256("executive-summary"));

        vm.warp(block.timestamp + 365 days + 1); // certification lapses after the validity period
        assertFalse(audits.isCertified("org-miner", ICGLR));
    }

    function test_Certification_RejectedReviewOrFailedAuditEndsIt() public {
        _auditCycle("org-audit", auditor, true, true);
        assertTrue(audits.isCertified("org-miner", ICGLR));
        _auditCycle("org-audit-2", auditor2, true, false); // IMCA rejects the report
        assertFalse(audits.isCertified("org-miner", ICGLR));
    }

    function test_SchemeWithoutReview_CompletesOnReport() public {
        vm.prank(rmi);
        audits.accredit("org-audit", RMAP, uint64(block.timestamp + 365 days), H);
        vm.prank(refinery); // a refiner orders its own RMAP audit
        uint256 id = audits.requestAudit(RMAP, "org-refinery", "org-audit", keccak256("scope"));
        vm.prank(auditor);
        audits.acceptAudit(id);
        vm.prank(auditor);
        audits.submitReport(id, true, keccak256("report"), keccak256("summary"));
        assertTrue(audits.isCertified("org-refinery", RMAP));
    }

    // ---------------------------------------------------------------- rotation

    function test_Rotation_SameFirmLimitedThenCoolingOff() public {
        _auditCycle("org-audit", auditor, true, true);
        _auditCycle("org-audit", auditor, true, true); // second consecutive: the limit
        assertEq(audits.rotationOf("org-miner", ICGLR).consecutive, 2);

        uint64 availableAt = uint64(block.timestamp + 365 days);
        vm.prank(miner);
        vm.expectRevert(
            abi.encodeWithSelector(AuditLib.AuditRegistry__RotationRequired.selector, bytes32("org-audit"), availableAt)
        );
        audits.requestAudit(ICGLR, "org-miner", "org-audit", keccak256("scope"));

        _auditCycle("org-audit-2", auditor2, true, true); // another firm is fine
        assertEq(audits.rotationOf("org-miner", ICGLR).consecutive, 1);
        _auditCycle("org-audit", auditor, true, true); // and the first firm may return
    }

    /// Whatever the timing, the same firm never completes more than `maxConsecutive` audits in a row.
    function testFuzz_Rotation_NeverMoreThanMaxConsecutive(uint8 attempts, uint256 gap) public {
        attempts = uint8(bound(attempts, 1, 6));
        gap = bound(gap, 0, 300 days); // up to ~5 years in total: inside the firm's accreditation
        vm.prank(admin); // keep the auditor licensed for the whole campaign
        registry.updateLicence(auditor, H, uint64(block.timestamp + 10 * 365 days));
        for (uint256 i; i < attempts; ++i) {
            vm.warp(block.timestamp + gap);
            vm.prank(miner);
            try audits.requestAudit(ICGLR, "org-miner", "org-audit", keccak256(abi.encode(i))) returns (uint256 id) {
                vm.prank(auditor);
                audits.acceptAudit(id);
                vm.prank(auditor);
                audits.submitReport(id, true, keccak256("report"), bytes32(0));
                vm.prank(icglr);
                audits.reviewReport(id, true, keccak256("summary"));
            } catch {}
            assertLe(audits.rotationOf("org-miner", ICGLR).consecutive, 2);
        }
    }
}
