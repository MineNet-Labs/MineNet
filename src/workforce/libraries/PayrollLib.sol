// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title PayrollLib
 * @author 0xEmmyb2
 * @notice Shared types, events and custom errors of {PayrollEngine}: day types (rest days, public holidays, paid
 * and excused leave, unexcused absence), overtime, pay policies, settlement and payment.
 */
library PayrollLib {
    /*//////////////////////////////////////////////////////////////
                                  ENUMS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Leave recorded on a working day.
     */
    enum LeaveType {
        // No leave: a missed working day is an unexcused absence.
        None,
        // Approved personal / family leave: unpaid (salaried staff lose salary / 26), no penalty, no alert.
        Excused,
        // Statutory annual leave (1.5 days per month worked): paid at 100% base, deducted from the balance.
        Annual,
        // Certified sick leave: paid at 100% base.
        Sick,
        // Maternity (or paternity) leave: paid at 100% base.
        Maternity
    }

    /**
     * @notice State of a worker's leave request.
     */
    enum RequestStatus {
        None,
        Pending,
        Approved,
        Rejected
    }

    /*//////////////////////////////////////////////////////////////
                                 STRUCTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice How a site pays.
     * @param payer Company account wages are pulled from; it approves {PayrollEngine} for both tokens.
     * @param workdays Standard working days, bit 0 = Monday ... bit 6 = Sunday; the others are scheduled rest days.
     * @param graceDays Days a period stays open after it ends, for late (offline) attendance (at most
     * {MAX_GRACE_DAYS}).
     * @param noShowAlert Unexcused absences after which every further one raises an HR alert (0 = no alerts).
     * @param absencePenaltyBps Extra deduction per unexcused absence, in basis points of a day's pay (at most
     * {MAX_PENALTY_BPS}; 0 = unpaid only).
     * @param restDayOvertimeBps Pay for authorised work on a rest day, in basis points of a day's pay (e.g. 15_000
     * = 150%; {MIN_OVERTIME_BPS} to {MAX_OVERTIME_BPS}).
     * @param holidayOvertimeBps Pay for authorised work on a public holiday, in basis points of a day's pay.
     * @param primary Settlement token tried first.
     * @param secondary Settlement token used when the primary payment fails (zero = none).
     */
    struct PayPolicy {
        address payer;
        uint8 workdays;
        uint8 graceDays;
        uint8 noShowAlert;
        uint16 absencePenaltyBps;
        uint16 restDayOvertimeBps;
        uint16 holidayOvertimeBps;
        IERC20 primary;
        IERC20 secondary;
    }

    /**
     * @notice A hire's payroll state.
     * @param settledPeriods Pay periods settled.
     * @param absences Unexcused absences so far.
     * @param annualUsed Annual leave days taken.
     * @param roster Personal working-day mask (rotating rest days; 0 = the site's standard days).
     * @param owed Pay settled but not yet received (both payment methods failed), in the position's currency.
     */
    struct PayState {
        uint32 settledPeriods;
        uint32 absences;
        uint32 annualUsed;
        uint8 roster;
        uint256 owed;
    }

    /**
     * @notice A worker's leave request.
     * @param hireId Hire.
     * @param leaveType Type of leave.
     * @param status State.
     * @param requestedBy Worker wallet.
     * @param reasonHash Hash of the justification (medical certificate, leave form).
     * @param dayList Requested days (unix time / 1 day).
     */
    struct LeaveRequest {
        uint256 hireId;
        LeaveType leaveType;
        RequestStatus status;
        address requestedBy;
        bytes32 reasonHash;
        uint64[] dayList;
    }

    /**
     * @notice The outcome of one pay period.
     * @param worked Shifts worked on working days.
     * @param restOvertime Authorised shifts on rest days.
     * @param holidayOvertime Authorised shifts on public holidays.
     * @param paidLeave Days of paid statutory leave.
     * @param excused Days of excused (unpaid) leave.
     * @param unexcused Unexcused absences (no-shows).
     * @param gross Pay earned (base or shifts, paid leave, overtime).
     * @param deductions Unpaid days of salaried staff (excused and unexcused).
     * @param penalty Absence penalty.
     * @param net Paid: gross minus deductions and penalty, never below zero.
     */
    struct PeriodPay {
        uint32 worked;
        uint32 restOvertime;
        uint32 holidayOvertime;
        uint32 paidLeave;
        uint32 excused;
        uint32 unexcused;
        uint256 gross;
        uint256 deductions;
        uint256 penalty;
        uint256 net;
    }

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Maximum hires settled in one {PayrollEngine-settlePay} call.
     */
    uint256 internal constant MAX_PAY_BATCH = 100;

    /**
     * @notice Maximum pay periods settled per hire in one call (catch-up is spread over several calls).
     */
    uint256 internal constant MAX_PERIODS_PER_SETTLE = 31;

    /**
     * @notice Maximum days in one leave or overtime call.
     */
    uint256 internal constant MAX_DAYS = 31;

    /**
     * @notice Maximum absence penalty: one extra day's pay per unexcused absence.
     */
    uint16 internal constant MAX_PENALTY_BPS = 10_000;

    /**
     * @notice Overtime pays at least a normal day.
     */
    uint16 internal constant MIN_OVERTIME_BPS = 10_000;

    /**
     * @notice Overtime pays at most three days' pay.
     */
    uint16 internal constant MAX_OVERTIME_BPS = 30_000;

    /**
     * @notice Maximum grace before a period is settled: the attendance backdating window of {WorkforceManager}.
     */
    uint8 internal constant MAX_GRACE_DAYS = 7;

    /**
     * @notice Consecutive working days after which the next day is locked as rest (the 1-in-7 rule).
     */
    uint256 internal constant MAX_CONSECUTIVE_DAYS = 6;

    /**
     * @notice Annual leave accrues one day per this many days employed (1.5 days per 30 days).
     */
    uint64 internal constant DAYS_PER_ANNUAL_LEAVE_DAY = 20;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Emitted when the company sets how a site pays.
     * @param siteId Mine site.
     * @param policy The policy.
     */
    event PayPolicySet(uint256 indexed siteId, PayPolicy policy);

    /**
     * @notice Emitted when the company (HQ) marks or unmarks a public holiday for all its sites.
     * @param orgId Company.
     * @param day Day (unix time / 1 day).
     * @param holiday True if a holiday.
     */
    event HolidaySet(bytes32 indexed orgId, uint64 indexed day, bool holiday);

    /**
     * @notice Emitted when a hire's personal roster (working days) is set.
     * @param hireId Hire.
     * @param workdays Working-day mask (0 = site standard).
     * @param by Account that set it.
     */
    event RosterSet(uint256 indexed hireId, uint8 workdays, address indexed by);

    /**
     * @notice Emitted when a worker requests leave.
     * @param requestId New request id.
     * @param hireId Hire.
     * @param leaveType Type of leave.
     * @param dayList Requested days.
     * @param reasonHash Hash of the justification.
     */
    event LeaveRequested(
        uint256 indexed requestId, uint256 indexed hireId, LeaveType leaveType, uint64[] dayList, bytes32 reasonHash
    );

    /**
     * @notice Emitted when a leave request is decided.
     * @param requestId Request.
     * @param approved True if approved.
     * @param by Approver.
     * @param noteHash Hash of the decision note.
     */
    event LeaveDecided(uint256 indexed requestId, bool approved, address indexed by, bytes32 noteHash);

    /**
     * @notice Emitted per day of leave put on record.
     * @param hireId Hire.
     * @param day Day.
     * @param leaveType Type of leave.
     * @param by Approver.
     * @param reasonHash Hash of the justification.
     */
    event LeaveRecorded(
        uint256 indexed hireId, uint64 indexed day, LeaveType leaveType, address indexed by, bytes32 reasonHash
    );

    /**
     * @notice Emitted per day of authorised overtime (an override of the rest-day, holiday, leave or 1-in-7 lock).
     * @param hireId Hire.
     * @param day Day.
     * @param by Authorising supervisor or manager.
     * @param reasonHash Hash of the reason (emergency dewatering, shaft repair).
     */
    event OvertimeAuthorized(uint256 indexed hireId, uint64 indexed day, address indexed by, bytes32 reasonHash);

    /**
     * @notice Emitted for each pay period settled.
     * @param hireId Hire.
     * @param period Period index since the hire started.
     * @param pay The period's pay.
     */
    event PeriodSettled(uint256 indexed hireId, uint32 indexed period, PeriodPay pay);

    /**
     * @notice Emitted when a worker's unexcused absences reach the site's alert threshold (an HR alert).
     * @param hireId Hire.
     * @param inPeriod Unexcused absences in the period just settled.
     * @param total Unexcused absences so far.
     */
    event NoShowAlert(uint256 indexed hireId, uint32 inPeriod, uint32 total);

    /**
     * @notice Emitted when settled pay reaches the worker.
     * @param hireId Hire.
     * @param token Token paid.
     * @param amount Amount, in token units.
     * @param paymentId Payment id in {WorkforceManager}.
     * @param fallback_ True if the primary method failed and the secondary one paid.
     */
    event SalaryPaid(
        uint256 indexed hireId, address indexed token, uint256 amount, uint256 indexed paymentId, bool fallback_
    );

    /**
     * @notice Emitted when both payment methods failed; the amount stays owed and is retried at the next
     * settlement.
     * @param hireId Hire.
     * @param owed Total owed, in the position's currency.
     */
    event SalaryOwed(uint256 indexed hireId, uint256 owed);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice The caller is not the site's company account.
     * @param account The caller.
     */
    error PayrollEngine__NotCompany(address account);

    /**
     * @notice The caller does not hold the required staff permission at the site.
     * @param account The caller.
     */
    error PayrollEngine__NotAuthorized(address account);

    /**
     * @notice Invalid pay policy.
     */
    error PayrollEngine__InvalidPolicy();

    /**
     * @notice The site has no pay policy yet.
     * @param siteId The site.
     */
    error PayrollEngine__NoPayPolicy(uint256 siteId);

    /**
     * @notice The hire is not active (or, for settlement, not active or ended).
     * @param hireId The hire.
     */
    error PayrollEngine__HireNotActive(uint256 hireId);

    /**
     * @notice Empty or oversized batch, or an invalid leave type.
     */
    error PayrollEngine__InvalidInput();

    /**
     * @notice The day is already settled, before the hire started, not a working day, or already has leave.
     * @param hireId The hire.
     * @param day The day.
     */
    error PayrollEngine__InvalidDay(uint256 hireId, uint64 day);

    /**
     * @notice Not enough accrued annual leave.
     * @param hireId The hire.
     * @param available Days available.
     * @param requested Days requested.
     */
    error PayrollEngine__InsufficientLeave(uint256 hireId, uint256 available, uint256 requested);

    /**
     * @notice The leave request is not pending.
     * @param requestId The request.
     */
    error PayrollEngine__InvalidRequest(uint256 requestId);

    /**
     * @notice Check-in blocked: the worker is on a scheduled rest day; overtime authorisation required.
     * @param workerId The worker.
     * @param day The day.
     */
    error PayrollEngine__RestDay(bytes32 workerId, uint64 day);

    /**
     * @notice Check-in blocked: public holiday; overtime authorisation required.
     * @param workerId The worker.
     * @param day The day.
     */
    error PayrollEngine__Holiday(bytes32 workerId, uint64 day);

    /**
     * @notice Check-in blocked: the worker is on leave; overtime authorisation required.
     * @param workerId The worker.
     * @param day The day.
     */
    error PayrollEngine__OnLeave(bytes32 workerId, uint64 day);

    /**
     * @notice Check-in blocked: it would be a 7th consecutive working day (fatigue lock); a site manager's
     * emergency overtime authorisation is required.
     * @param workerId The worker.
     * @param day The day.
     */
    error PayrollEngine__FatigueLock(bytes32 workerId, uint64 day);

    /*//////////////////////////////////////////////////////////////
                                FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Whether `day` (unix time / 1 day) is a working day under `workdays`.
     * @dev Day 0 (1 January 1970) was a Thursday, so Monday-based weekday = (day + 3) % 7.
     * @param workdays Working-day mask, bit 0 = Monday.
     * @param day The day.
     * @return True for a working day.
     */
    function isWorkday(uint8 workdays, uint64 day) internal pure returns (bool) {
        return (workdays >> ((day + 3) % 7)) & 1 == 1;
    }

    /**
     * @notice Whether a leave type is paid.
     * @param t Leave type.
     * @return True for annual, sick and maternity leave.
     */
    function isPaid(LeaveType t) internal pure returns (bool) {
        return t == LeaveType.Annual || t == LeaveType.Sick || t == LeaveType.Maternity;
    }
}
