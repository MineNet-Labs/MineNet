// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SiteTeamFixture} from "test/utils/SiteTeamFixture.sol";
import {SiteOpsLib} from "src/workforce/libraries/SiteOpsLib.sol";
import {PayrollLib} from "src/workforce/libraries/PayrollLib.sol";
import {WorkforceLib} from "src/workforce/libraries/WorkforceLib.sol";

/**
 * @notice Day types (rest days, holidays, paid / excused leave, no-shows), the check-in gate and 1-in-7 fatigue lock,
 * overtime, daily-rate vs salaried pay, automatic settlement and the payment fallback. Day 60 is a Monday.
 */
contract PayrollEngineTest is SiteTeamFixture {
    uint256 constant MON_TO_SAT = 0x3F; // in a week starting on a Monday
    uint64 constant MON = 60;
    uint64 constant TUE = 61;
    uint64 constant WED = 62;

    function _weeklyDriller() internal returns (uint256) {
        return _hireDriller(SiteOpsLib.PayFrequency.Weekly, SiteOpsLib.PayBasis.Daily, RATE);
    }

    function _settle(uint256 hid) internal {
        vm.prank(outsider); // anyone: no approval needed
        payroll.settlePay(_one(hid));
    }

    /*//////////////////////////////////////////////////////////////
                         DAILY-RATE SHIFT MINERS
    //////////////////////////////////////////////////////////////*/

    function test_WeekWithScheduledRestDay() public {
        _policy(usdc, rwfCoin, 0, 0);
        uint256 hid = _weeklyDriller();
        _live(NEW1, 7, MON_TO_SAT);
        _settle(hid);
        assertEq(usdc.balanceOf(new1W), 6 * RATE); // Sunday: rest, 0 pay, no penalty
        assertEq(payroll.payStateOf(hid).absences, 0);
        assertEq(payroll.accruedPayroll(site, USD), 6 * RATE);
    }

    function test_NoShowIsPenalisedAndAlertsHr() public {
        _policy(usdc, rwfCoin, 0, 1);
        uint256 hid = _weeklyDriller();
        _live(NEW1, 7, 0x1F); // no-show on Saturday
        vm.expectEmit(address(payroll));
        emit PayrollLib.NoShowAlert(hid, 1, 1);
        _settle(hid);
        assertEq(usdc.balanceOf(new1W), 5 * RATE - RATE * PENALTY_BPS / 10_000);
        assertEq(payroll.payStateOf(hid).absences, 1);
    }

    function test_ExcusedLeaveIsUnpaidWithoutPenaltyAndBlocksCheckIn() public {
        _policy(usdc, rwfCoin, 0, 1);
        uint256 hid = _weeklyDriller();
        vm.prank(new1W);
        uint256 req = payroll.requestLeave(hid, PayrollLib.LeaveType.Excused, _days(WED), keccak256("family"));
        vm.prank(supW); // a supervisor approves excused leave
        payroll.decideLeave(req, true, H);

        _live(NEW1, 2, 0x3);
        vm.prank(supW);
        bytes32[] memory ids = new bytes32[](1);
        ids[0] = NEW1;
        vm.expectRevert(abi.encodeWithSelector(PayrollLib.PayrollEngine__OnLeave.selector, NEW1, WED));
        workforce.recordAttendance(site, WED, ids);
        _live(NEW1, 5, 0xE); // Wed (on leave), Thu, Fri, Sat, Sun (rest)

        _settle(hid);
        assertEq(usdc.balanceOf(new1W), 5 * RATE);
        assertEq(payroll.payStateOf(hid).absences, 0); // protected status: no alert
    }

    function test_PaidSickLeaveNeedsHr() public {
        _policy(usdc, rwfCoin, 0, 0);
        uint256 hid = _weeklyDriller();
        vm.prank(supW);
        vm.expectRevert(abi.encodeWithSelector(PayrollLib.PayrollEngine__NotAuthorized.selector, supW));
        payroll.grantLeave(hid, PayrollLib.LeaveType.Sick, _days(TUE), keccak256("medical certificate"));
        vm.prank(hrW);
        payroll.grantLeave(hid, PayrollLib.LeaveType.Sick, _days(TUE), keccak256("medical certificate"));

        _live(NEW1, 7, 0x3D); // all but Tuesday
        _settle(hid);
        assertEq(usdc.balanceOf(new1W), 6 * RATE); // 5 shifts + 1 day of paid sick leave
    }

    function test_AnnualLeaveComesFromAccruedBalance() public {
        _policy(usdc, rwfCoin, 0, 0);
        uint256 hid = _hireDriller(SiteOpsLib.PayFrequency.Monthly, SiteOpsLib.PayBasis.Daily, RATE);
        vm.prank(hrW);
        vm.expectRevert(abi.encodeWithSelector(PayrollLib.PayrollEngine__InsufficientLeave.selector, hid, 0, 1));
        payroll.grantLeave(hid, PayrollLib.LeaveType.Annual, _days(TUE), H);

        vm.warp(block.timestamp + 40 days); // 40 days employed: 2 days of annual leave (1.5 per 30)
        assertEq(payroll.annualLeaveBalance(hid), 2);
        uint64[] memory two = new uint64[](2);
        two[0] = MON + 42; // a Monday
        two[1] = MON + 43;
        vm.prank(hrW);
        payroll.grantLeave(hid, PayrollLib.LeaveType.Annual, two, H);
        assertEq(payroll.annualLeaveBalance(hid), 0);
    }

    function test_RevertWhen_WorkerApprovesOwnLeave() public {
        _policy(usdc, rwfCoin, 0, 0);
        uint256 hid = _weeklyDriller();
        vm.prank(new1W);
        uint256 req = payroll.requestLeave(hid, PayrollLib.LeaveType.Excused, _days(WED), H);
        vm.prank(new1W);
        vm.expectRevert(abi.encodeWithSelector(PayrollLib.PayrollEngine__NotAuthorized.selector, new1W));
        payroll.decideLeave(req, true, H);
    }

    /*//////////////////////////////////////////////////////////////
                  REST DAYS, HOLIDAYS, OVERTIME, FATIGUE
    //////////////////////////////////////////////////////////////*/

    function test_RestDayGateOvertimeAndFatigueLock() public {
        _policy(usdc, rwfCoin, 0, 0);
        uint256 hid = _weeklyDriller();
        _live(NEW1, 6, MON_TO_SAT); // now Sunday, after 6 days in a row
        uint64 sunday = _today();

        vm.prank(supW);
        bytes32[] memory ids = new bytes32[](1);
        ids[0] = NEW1;
        vm.expectRevert(abi.encodeWithSelector(PayrollLib.PayrollEngine__RestDay.selector, NEW1, sunday));
        workforce.recordAttendance(site, sunday, ids);

        // a 7th day in a row is an emergency: the supervisor cannot authorise it, the site manager can
        vm.prank(supW);
        vm.expectRevert(abi.encodeWithSelector(PayrollLib.PayrollEngine__NotAuthorized.selector, supW));
        payroll.authorizeOvertime(hid, _days(sunday), keccak256("emergency dewatering"));
        vm.prank(mgrW);
        payroll.authorizeOvertime(hid, _days(sunday), keccak256("emergency dewatering"));
        _live(NEW1, 1, 1);

        // Monday would be an 8th day in a row: locked
        vm.prank(supW);
        vm.expectRevert(abi.encodeWithSelector(PayrollLib.PayrollEngine__FatigueLock.selector, NEW1, _today()));
        workforce.recordAttendance(site, _today(), ids);

        _settle(hid);
        assertEq(usdc.balanceOf(new1W), 6 * RATE + RATE * REST_OT_BPS / 10_000);
    }

    function test_SupervisorAuthorisesOrdinaryRestDayOvertime() public {
        _policy(usdc, rwfCoin, 0, 0);
        uint256 hid = _weeklyDriller();
        _live(NEW1, 6, 0x1F); // Mon-Fri worked, Saturday off (a no-show), now Sunday
        vm.prank(supW);
        payroll.authorizeOvertime(hid, _days(_today()), keccak256("shaft repair"));
        _live(NEW1, 1, 1);
        _settle(hid);
        uint256 penalty = RATE * PENALTY_BPS / 10_000;
        assertEq(usdc.balanceOf(new1W), 5 * RATE + RATE * REST_OT_BPS / 10_000 - penalty);
    }

    function test_PublicHolidayFromHqCalendar() public {
        _policy(usdc, rwfCoin, 0, 0);
        uint256 hid = _weeklyDriller();
        vm.prank(miner); // HQ marks it for every site
        payroll.setHolidays(_days(WED), true);

        _live(NEW1, 2, 0x3);
        vm.prank(supW);
        bytes32[] memory ids = new bytes32[](1);
        ids[0] = NEW1;
        vm.expectRevert(abi.encodeWithSelector(PayrollLib.PayrollEngine__Holiday.selector, NEW1, WED));
        workforce.recordAttendance(site, WED, ids);
        _live(NEW1, 5, 0xE);

        _settle(hid);
        assertEq(usdc.balanceOf(new1W), 5 * RATE); // daily-rate: holiday unpaid, not an absence
        assertEq(payroll.payStateOf(hid).absences, 0);
    }

    function test_HolidayOvertimeRate() public {
        _policy(usdc, rwfCoin, 0, 0);
        uint256 hid = _weeklyDriller();
        vm.prank(miner);
        payroll.setHolidays(_days(WED), true);
        vm.prank(supW);
        payroll.authorizeOvertime(hid, _days(WED), keccak256("security"));
        _live(NEW1, 7, MON_TO_SAT);
        _settle(hid);
        assertEq(usdc.balanceOf(new1W), 5 * RATE + RATE * HOLIDAY_OT_BPS / 10_000);
    }

    function test_PersonalRosterMovesTheRestDay() public {
        _policy(usdc, rwfCoin, 0, 0);
        uint256 hid = _weeklyDriller();
        vm.prank(mgrW);
        payroll.setRoster(hid, 0x7E); // Tuesday to Sunday, Monday off
        vm.prank(supW);
        bytes32[] memory ids = new bytes32[](1);
        ids[0] = NEW1;
        vm.expectRevert(abi.encodeWithSelector(PayrollLib.PayrollEngine__RestDay.selector, NEW1, MON));
        workforce.recordAttendance(site, MON, ids);
    }

    function test_WorkersOutsideTheHiringFlowAreNotGated() public {
        _policy(usdc, rwfCoin, 0, 0);
        vm.warp(block.timestamp + 6 days); // Sunday
        bytes32[] memory ids = new bytes32[](1);
        ids[0] = MGR;
        vm.prank(miner);
        workforce.recordAttendance(site, _today(), ids);
    }

    /*//////////////////////////////////////////////////////////////
                             SALARIED STAFF
    //////////////////////////////////////////////////////////////*/

    function test_SalariedMonthDeductsUnpaidDays() public {
        _policy(usdc, rwfCoin, 0, 0);
        uint256 hid = _hireDriller(SiteOpsLib.PayFrequency.Monthly, SiteOpsLib.PayBasis.Monthly, SALARY);
        vm.prank(supW);
        payroll.grantLeave(hid, PayrollLib.LeaveType.Excused, _days(WED), H);

        uint256 mask;
        for (uint256 i; i < 30; ++i) {
            if (PayrollLib.isWorkday(MON_SAT, MON + uint64(i))) mask |= 1 << i;
        }
        mask &= ~(uint256(1) << 2); // Wednesday: excused leave
        mask &= ~(uint256(1) << 3); // Thursday: no-show
        _live(NEW1, 30, mask);
        _settle(hid);

        uint256 dayRate = SALARY / 26;
        assertEq(usdc.balanceOf(new1W), SALARY - 2 * dayRate - dayRate * PENALTY_BPS / 10_000);
    }

    /*//////////////////////////////////////////////////////////////
                        SETTLEMENT AND PAYMENT
    //////////////////////////////////////////////////////////////*/

    function test_GraceDaysWaitForLateAttendance() public {
        _policy(usdc, rwfCoin, 3, 0);
        uint256 hid = _hireDriller(SiteOpsLib.PayFrequency.Daily, SiteOpsLib.PayBasis.Daily, RATE);
        vm.warp(block.timestamp + 2 days);
        _settle(hid); // ended 1 day ago: still in grace
        assertEq(payroll.payStateOf(hid).settledPeriods, 0);

        bytes32[] memory ids = new bytes32[](1);
        ids[0] = NEW1;
        vm.prank(supW);
        workforce.recordAttendance(site, MON, ids); // filed late from an offline site
        vm.warp(block.timestamp + 2 days);
        _settle(hid);
        assertEq(usdc.balanceOf(new1W), RATE);
    }

    function test_SecondaryMethodWhenPrimaryFails() public {
        _policy(usdc, rwfCoin, 0, 0);
        vm.prank(miner);
        usdc.approve(address(payroll), 0);
        uint256 hid = _weeklyDriller();
        _live(NEW1, 7, MON_TO_SAT);
        vm.prank(oracle);
        rwfFeed.postRate(RWF_RATE);
        _settle(hid);
        assertEq(usdc.balanceOf(new1W), 0);
        assertEq(rwfCoin.balanceOf(new1W), currencies.toTokenAmount(6 * RATE, USD, rwfCoin, true));
    }

    function test_BothMethodsFailThenOwedIsPaidLater() public {
        _policy(usdc, rwfCoin, 0, 0);
        vm.startPrank(miner);
        usdc.approve(address(payroll), 0);
        rwfCoin.approve(address(payroll), 0);
        vm.stopPrank();
        uint256 hid = _weeklyDriller();
        _live(NEW1, 7, MON_TO_SAT);
        vm.expectEmit(address(payroll));
        emit PayrollLib.SalaryOwed(hid, 6 * RATE);
        _settle(hid);
        assertEq(payroll.payStateOf(hid).owed, 6 * RATE);

        vm.prank(miner);
        usdc.approve(address(payroll), type(uint256).max);
        _settle(hid);
        assertEq(usdc.balanceOf(new1W), 6 * RATE);
        assertEq(payroll.payStateOf(hid).owed, 0);
    }

    function test_EndedEmploymentSettlesFinalPartialPeriod() public {
        _policy(usdc, rwfCoin, 0, 0);
        uint256 hid = _hireDriller(SiteOpsLib.PayFrequency.Monthly, SiteOpsLib.PayBasis.Daily, RATE);
        _live(NEW1, 10, 0x3BF); // Mon-Sat, Sun off, Mon-Wed
        vm.prank(miner);
        siteOps.endEmployment(hid, H);
        _settle(hid);
        assertEq(usdc.balanceOf(new1W), 9 * RATE);
        assertEq(payroll.payStateOf(hid).settledPeriods, 1);
    }

    function test_PaymentIsBookedInWorkforce() public {
        _policy(usdc, rwfCoin, 0, 0);
        uint256 hid = _weeklyDriller();
        _live(NEW1, 7, MON_TO_SAT);
        _settle(hid);
        WorkforceLib.Payment memory p = workforce.getPayment(workforce.totalPayments());
        assertEq(p.payeeId, NEW1);
        assertEq(uint8(p.method), uint8(WorkforceLib.PaymentMethod.Stablecoin));
        assertEq(p.recordedBy, address(payroll));
    }

    function test_RevertWhen_PayPolicyInvalid() public {
        PayrollLib.PayPolicy memory p = PayrollLib.PayPolicy({
            payer: buyer, // not an account of the company
            workdays: MON_SAT,
            graceDays: 0,
            noShowAlert: 0,
            absencePenaltyBps: PENALTY_BPS,
            restDayOvertimeBps: REST_OT_BPS,
            holidayOvertimeBps: HOLIDAY_OT_BPS,
            primary: usdc,
            secondary: rwfCoin
        });
        vm.startPrank(miner);
        vm.expectRevert(PayrollLib.PayrollEngine__InvalidPolicy.selector);
        payroll.setPayPolicy(site, p);
        p.payer = miner;
        p.restDayOvertimeBps = 9_999; // overtime below a normal day
        vm.expectRevert(PayrollLib.PayrollEngine__InvalidPolicy.selector);
        payroll.setPayPolicy(site, p);
        p.restDayOvertimeBps = REST_OT_BPS;
        p.secondary = IERC20(address(usdc));
        vm.expectRevert(PayrollLib.PayrollEngine__InvalidPolicy.selector);
        payroll.setPayPolicy(site, p);
        vm.stopPrank();
    }

    function test_RevertWhen_OthersBookSalaries(address caller) public {
        vm.assume(caller != address(payroll));
        vm.prank(caller);
        vm.expectRevert();
        workforce.recordSiteSalary("org-miner", NEW1, usdc, 1, H);
    }
}
