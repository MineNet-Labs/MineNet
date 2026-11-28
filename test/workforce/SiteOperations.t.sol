// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {SiteTeamFixture} from "test/utils/SiteTeamFixture.sol";
import {StaffLib} from "src/workforce/libraries/StaffLib.sol";
import {SiteOpsLib} from "src/workforce/libraries/SiteOpsLib.sol";
import {WorkforceLib} from "src/workforce/libraries/WorkforceLib.sol";
import {SiteLib} from "src/compliance/libraries/SiteLib.sol";

/**
 * @notice Site seats, shift and period reports with the internal inspection gate, staffing requests, hires and the
 * estimated monthly budget.
 */
contract SiteOperationsTest is SiteTeamFixture {
    bytes32 constant SHAFT1 = "SHAFT-1";
    bytes32 constant SHAFT2 = "SHAFT-2";
    bytes32 constant GOLD = keccak256("GOLD");

    /*//////////////////////////////////////////////////////////////
                                 HELPERS
    //////////////////////////////////////////////////////////////*/

    function _period(uint64 start, uint64 end, bytes32 tunnel, SiteOpsLib.TunnelStatus status)
        internal
        pure
        returns (SiteOpsLib.ReportInput memory r)
    {
        r.kind = SiteOpsLib.ReportKind.Period;
        r.periodStart = start;
        r.periodEnd = end;
        r.workersOnSite = 42;
        r.incidents = 1;
        r.reportHash = keccak256("report");
        r.outputs = new SiteOpsLib.MineralOutput[](1);
        r.outputs[0] = SiteOpsLib.MineralOutput({mineralType: TIN, quantity: 1_200_000});
        r.tunnels = new SiteOpsLib.TunnelUpdate[](1);
        r.tunnels[0] = SiteOpsLib.TunnelUpdate({tunnelId: tunnel, status: status});
    }

    function _shift(bytes32 ref, uint128 estimated) internal view returns (SiteOpsLib.ReportInput memory r) {
        r.kind = SiteOpsLib.ReportKind.Shift;
        r.shiftRef = ref;
        r.periodStart = uint64(block.timestamp - 8 hours);
        r.periodEnd = uint64(block.timestamp);
        r.workersOnSite = 18;
        r.reportHash = keccak256(abi.encode("shift-log", ref));
        r.outputs = new SiteOpsLib.MineralOutput[](1);
        r.outputs[0] = SiteOpsLib.MineralOutput({mineralType: GOLD, quantity: estimated});
    }

    function _filePeriod(uint64 start, uint64 end, bytes32 tunnel, SiteOpsLib.TunnelStatus status)
        internal
        returns (uint256 id)
    {
        vm.prank(mgrW);
        id = siteOps.submitReport(site, _period(start, end, tunnel, status));
    }

    function _qty(uint128 q) internal pure returns (uint128[] memory a) {
        a = new uint128[](1);
        a[0] = q;
    }

    function _none() internal pure returns (uint128[] memory a) {}

    /*//////////////////////////////////////////////////////////////
                              SITE SEATS
    //////////////////////////////////////////////////////////////*/

    function test_SeatHoldersGetSitePermissions() public view {
        StaffLib.SiteTeam memory t = workforce.siteTeam(site);
        assertEq(t.manager, MGR);
        assertEq(t.hr, HR);
        assertEq(t.inspector, INSP);
        assertEq(workforce.staffOrg(mgrW, site, StaffLib.SUBMIT_REPORTS | StaffLib.DISPATCH_LOTS), "org-miner");
        assertEq(workforce.staffOrg(mgrW, site, StaffLib.INSPECT_REPORTS), "org-miner");
        assertEq(workforce.staffOrg(mgrW, site, StaffLib.MANAGE_WORKERS), bytes32(0));
        assertEq(workforce.staffOrg(mgrW, site, StaffLib.RECORD_PRODUCTION), bytes32(0));
        assertEq(workforce.staffOrg(mgrW, site2, StaffLib.SUBMIT_REPORTS), bytes32(0));
        assertEq(workforce.staffOrg(hrW, site, StaffLib.MANAGE_HIRING), "org-miner");
        assertEq(workforce.staffOrg(inspW, site, StaffLib.INSPECT_REPORTS), "org-miner");
        assertEq(workforce.staffOrg(supW, site, StaffLib.SUBMIT_REPORTS | StaffLib.AUTHORIZE_OVERTIME), "org-miner");
    }

    function test_RevertWhen_ManagerRegistersWorkerDirectly() public {
        vm.prank(mgrW);
        vm.expectRevert(abi.encodeWithSelector(StaffLib.WorkforceManager__OutOfScope.selector, mgrW, site));
        workforce.registerWorker(NEW1, new1W, site);
    }

    function test_CompanyReassignsAndRevokesSeats() public {
        vm.startPrank(miner);
        vm.expectEmit(address(workforce));
        emit StaffLib.SiteSeatAssigned(site, StaffLib.SiteSeat.Manager, MGR2, MGR, miner);
        workforce.appointSiteSeat(site, StaffLib.SiteSeat.Manager, MGR2);
        workforce.appointSiteSeat(site, StaffLib.SiteSeat.Hr, bytes32(0));
        vm.stopPrank();
        assertEq(workforce.staffOrg(mgrW, site, StaffLib.SUBMIT_REPORTS), bytes32(0));
        assertEq(workforce.staffOrg(mgr2W, site, StaffLib.SUBMIT_REPORTS), "org-miner");
        assertEq(workforce.staffOrg(hrW, site, StaffLib.MANAGE_HIRING), bytes32(0));
    }

    function test_RevertWhen_NonCompanyAppoints(address caller) public {
        vm.assume(caller != miner);
        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(WorkforceLib.WorkforceManager__Unauthorized.selector, caller));
        workforce.appointSiteSeat(site, StaffLib.SiteSeat.Manager, MGR2);
    }

    function test_RevertWhen_OneWorkerHoldsTwoSeats() public {
        vm.startPrank(miner);
        vm.expectRevert(abi.encodeWithSelector(StaffLib.WorkforceManager__SeatConflict.selector, site, MGR));
        workforce.appointSiteSeat(site, StaffLib.SiteSeat.Inspector, MGR);
        workforce.appointSiteSeat(site, StaffLib.SiteSeat.Inspector, INSP); // same holder, same seat: fine
        vm.stopPrank();
        assertEq(workforce.seatsHeld(INSP), 1);
    }

    /*//////////////////////////////////////////////////////////////
                     SHIFT REPORTS: INSPECTION GATE
    //////////////////////////////////////////////////////////////*/

    function test_ShiftReportIsInformationalUntilInspected() public {
        vm.prank(supW);
        uint256 id = siteOps.submitReport(site, _shift("2026-11-28-A", 5_000));
        SiteOpsLib.Report memory r = siteOps.getReport(id);
        assertEq(uint8(r.status), uint8(SiteOpsLib.ReportStatus.Submitted)); // Pending_Inspection
        assertEq(uint8(r.kind), uint8(SiteOpsLib.ReportKind.Shift));
        assertEq(sites.productionOf(site, GOLD).extracted, 0); // the extraction cap is untouched
        assertEq(siteOps.verifiedOutput(site, GOLD), 0);
    }

    function test_InspectedShiftWeightCountsTowardExtraction(uint128 estimated, uint128 weighed) public {
        estimated = uint128(bound(estimated, 1, 1e9));
        weighed = uint128(bound(weighed, 1, 1e9));
        vm.prank(supW);
        uint256 id = siteOps.submitReport(site, _shift("2026-11-28-A", estimated));

        vm.expectEmit(address(siteOps));
        emit SiteOpsLib.OutputVerified(id, site, GOLD, estimated, weighed);
        vm.prank(inspW);
        siteOps.inspectReport(id, true, _qty(weighed), keccak256("weighbridge ticket"));

        // Approved_Official at once: verified weight is the site's extraction and lot-able inventory
        SiteOpsLib.Report memory r = siteOps.getReport(id);
        assertEq(uint8(r.status), uint8(SiteOpsLib.ReportStatus.Accepted));
        assertEq(r.inspectedBy, inspW);
        assertEq(r.inspectorId, INSP); // the internal sign-off: employee id and time
        assertEq(r.inspectedAt, block.timestamp);
        assertEq(sites.productionOf(site, GOLD).extracted, weighed);
        assertEq(siteOps.verifiedOutput(site, GOLD), weighed);
        assertEq(siteOps.reportVerified(id)[0], weighed);

        // the company can now register a lot from it
        vm.prank(miner);
        passport.registerLot(keccak256("gold-lot"), GOLD, weighed, site, H);
    }

    function test_ManagerCanInspectSupervisorShift() public {
        vm.prank(supW);
        uint256 id = siteOps.submitReport(site, _shift("A", 5_000));
        vm.prank(mgrW);
        siteOps.inspectReport(id, true, _qty(4_900), H);
        assertEq(siteOps.getReport(id).inspectorId, MGR);
        assertEq(sites.productionOf(site, GOLD).extracted, 4_900);
    }

    function test_RevertWhen_InspectedShiftExceedsLicensedCeiling() public {
        vm.prank(regulator);
        sites.setExtractionCeiling(site, GOLD, 4_000, H);
        vm.prank(supW);
        uint256 id = siteOps.submitReport(site, _shift("A", 5_000));
        vm.prank(inspW);
        vm.expectRevert(
            abi.encodeWithSelector(SiteLib.MineSiteRegistry__CeilingExceeded.selector, site, GOLD, 4_000, 5_000)
        );
        siteOps.inspectReport(id, true, _qty(5_000), H);
    }

    function test_RejectedShiftChangesNothing() public {
        vm.prank(supW);
        uint256 id = siteOps.submitReport(site, _shift("A", 5_000));
        vm.prank(inspW);
        siteOps.inspectReport(id, false, _none(), keccak256("does not match the washed concentrate"));
        assertEq(uint8(siteOps.getReport(id).status), uint8(SiteOpsLib.ReportStatus.Rejected));
        assertEq(sites.productionOf(site, GOLD).extracted, 0);
    }

    function test_RevertWhen_ShiftReportedTwice() public {
        vm.startPrank(supW);
        siteOps.submitReport(site, _shift("A", 5_000));
        vm.expectRevert(abi.encodeWithSelector(SiteOpsLib.SiteOperations__DuplicateShift.selector, bytes32("A")));
        siteOps.submitReport(site, _shift("A", 5_000));
        vm.stopPrank();
    }

    function test_RevertWhen_FilerInspectsOwnReport() public {
        vm.prank(mgrW);
        uint256 id = siteOps.submitReport(site, _shift("A", 5_000));
        vm.prank(mgrW);
        vm.expectRevert(abi.encodeWithSelector(SiteOpsLib.SiteOperations__SelfApproval.selector, mgrW));
        siteOps.inspectReport(id, true, _qty(5_000), H);
    }

    function test_RevertWhen_NonInspectorReviews() public {
        vm.prank(supW);
        uint256 id = siteOps.submitReport(site, _shift("A", 5_000));
        address[2] memory others = [miner, hrW];
        for (uint256 i; i < 2; ++i) {
            vm.prank(others[i]);
            vm.expectRevert(abi.encodeWithSelector(SiteOpsLib.SiteOperations__NotSiteStaff.selector, others[i], site));
            siteOps.inspectReport(id, true, _qty(5_000), H);
        }
    }

    function test_RevertWhen_VerifiedWeightsMissing() public {
        vm.prank(supW);
        uint256 id = siteOps.submitReport(site, _shift("A", 5_000));
        vm.prank(inspW);
        vm.expectRevert(SiteOpsLib.SiteOperations__InvalidReportItems.selector);
        siteOps.inspectReport(id, true, _none(), H);
    }

    /*//////////////////////////////////////////////////////////////
                             PERIOD REPORTS
    //////////////////////////////////////////////////////////////*/

    function test_VerifiedPeriodReportUpdatesTunnelsNotExtraction() public {
        uint64 t0 = uint64(block.timestamp - 7 days);
        uint256 id = _filePeriod(t0, t0 + 7 days, SHAFT1, SiteOpsLib.TunnelStatus.Active);
        vm.prank(inspW);
        siteOps.inspectReport(id, true, _none(), keccak256("site visit"));
        assertEq(uint8(siteOps.getTunnel(site, SHAFT1).status), uint8(SiteOpsLib.TunnelStatus.Active));
        assertEq(siteOps.reportedOutput(site, TIN), 1_200_000); // summary only
        assertEq(siteOps.reportedUntil(site), t0 + 7 days);
        assertEq(sites.productionOf(site, TIN).extracted, EXTRACTED); // unchanged
    }

    function test_TunnelLifecycleAcrossReports() public {
        uint64 t0 = uint64(block.timestamp - 21 days);
        SiteOpsLib.TunnelStatus[3] memory steps =
            [SiteOpsLib.TunnelStatus.Active, SiteOpsLib.TunnelStatus.Inactive, SiteOpsLib.TunnelStatus.Closed];
        for (uint256 i; i < 3; ++i) {
            uint64 start = t0 + uint64(i) * 7 days;
            uint256 id = _filePeriod(start, start + 7 days, SHAFT2, steps[i]);
            vm.prank(inspW);
            siteOps.inspectReport(id, true, _none(), H);
        }
        (uint256 active, uint256 inactive, uint256 closed) = siteOps.tunnelCounts(site);
        assertEq(active + inactive, 0);
        assertEq(closed, 1);
    }

    function test_RevertWhen_PeriodOverlapsAcceptedReport() public {
        uint64 t0 = uint64(block.timestamp - 7 days);
        uint256 id = _filePeriod(t0, t0 + 7 days, SHAFT1, SiteOpsLib.TunnelStatus.Active);
        vm.prank(inspW);
        siteOps.inspectReport(id, true, _none(), H);
        vm.prank(mgrW);
        vm.expectRevert(SiteOpsLib.SiteOperations__InvalidPeriod.selector);
        siteOps.submitReport(site, _period(t0 + 1 days, t0 + 7 days, SHAFT1, SiteOpsLib.TunnelStatus.Inactive));
    }

    /*//////////////////////////////////////////////////////////////
                      STAFFING REQUESTS AND HIRES
    //////////////////////////////////////////////////////////////*/

    function test_StaffingRequestBudgetsMonthlyCost(uint32 requested, uint32 approved, bool salaried) public {
        requested = uint32(bound(requested, 1, 1000));
        approved = uint32(bound(approved, 1, requested));
        SiteOpsLib.PayBasis basis = salaried ? SiteOpsLib.PayBasis.Monthly : SiteOpsLib.PayBasis.Daily;
        uint128 rate = salaried ? SALARY : RATE;
        vm.prank(hrW);
        uint256 id = siteOps.requestPosition(site, _position(requested, SiteOpsLib.PayFrequency.Monthly, basis, rate));
        vm.prank(miner);
        siteOps.decidePosition(id, approved, H);

        assertEq(siteOps.getPosition(id).available, 4);
        uint128 monthly = salaried ? SALARY : RATE * 26; // a standard 26-day month
        assertEq(siteOps.budgetOf(site, USD).plannedMonthlyPayroll, uint128(approved) * monthly);
    }

    function test_RevertWhen_HrHiresWithoutCompanyApproval() public {
        vm.prank(hrW);
        uint256 pid = siteOps.requestPosition(
            site, _position(2, SiteOpsLib.PayFrequency.Weekly, SiteOpsLib.PayBasis.Daily, RATE)
        );
        vm.startPrank(hrW);
        vm.expectRevert(
            abi.encodeWithSelector(
                SiteOpsLib.SiteOperations__InvalidPositionStatus.selector, pid, SiteOpsLib.PositionStatus.Requested
            )
        );
        siteOps.submitHire(pid, NEW1, new1W, H);
        vm.expectRevert(abi.encodeWithSelector(SiteOpsLib.SiteOperations__NotCompany.selector, hrW, site));
        siteOps.decidePosition(pid, 2, H);
        vm.stopPrank();
    }

    function test_ApprovedHireOnboardsWorkerAndCommitsBudget() public {
        uint256 pid = _openPosition(_position(2, SiteOpsLib.PayFrequency.Weekly, SiteOpsLib.PayBasis.Daily, RATE));
        uint256 hid = _hire(pid, NEW1, new1W);
        assertTrue(workforce.getWorker(NEW1).active);
        assertEq(siteOps.getHire(hid).startDay, _today());
        SiteOpsLib.Budget memory b = siteOps.budgetOf(site, USD);
        assertEq(b.headcount, 1);
        assertEq(b.monthlyPayroll, RATE * 26);
        assertEq(b.plannedMonthlyPayroll, RATE * 26);
        assertEq(b.onboardingCosts, ONBOARD);

        vm.prank(miner);
        siteOps.endEmployment(hid, H);
        b = siteOps.budgetOf(site, USD);
        assertEq(b.headcount, 0);
        assertEq(b.monthlyPayroll, 0);
        assertFalse(workforce.getWorker(NEW1).active);
    }

    function test_RevertWhen_HireHasNoWallet() public {
        uint256 pid = _openPosition(_position(1, SiteOpsLib.PayFrequency.Weekly, SiteOpsLib.PayBasis.Daily, RATE));
        vm.prank(hrW);
        vm.expectRevert(abi.encodeWithSelector(SiteOpsLib.SiteOperations__InvalidWorker.selector, NEW1));
        siteOps.submitHire(pid, NEW1, address(0), H);
    }

    function test_ClosePositionReleasesPlannedSlots() public {
        uint256 pid = _openPosition(_position(3, SiteOpsLib.PayFrequency.Weekly, SiteOpsLib.PayBasis.Daily, RATE));
        _hire(pid, NEW1, new1W);
        vm.prank(hrW);
        siteOps.closePosition(pid, H);
        assertEq(siteOps.budgetOf(site, USD).plannedMonthlyPayroll, 0);
        assertEq(siteOps.budgetOf(site, USD).monthlyPayroll, RATE * 26);
    }
}
