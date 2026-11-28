// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import {IMineNetRegistry} from "src/access/interfaces/IMineNetRegistry.sol";
import {ICurrencyManager} from "src/finance/interfaces/ICurrencyManager.sol";
import {ISiteRegistry} from "src/compliance/interfaces/ISiteRegistry.sol";
import {IWorkforce} from "src/workforce/interfaces/IWorkforce.sol";
import {IAttendanceGate} from "src/workforce/interfaces/IAttendanceGate.sol";
import {ISiteOperations} from "src/workforce/interfaces/ISiteOperations.sol";
import {Actions} from "src/access/libraries/Actions.sol";
import {StaffLib} from "src/workforce/libraries/StaffLib.sol";
import {SiteOpsLib} from "src/workforce/libraries/SiteOpsLib.sol";
import {PayrollLib} from "src/workforce/libraries/PayrollLib.sol";

/**
 * @title PayrollEngine
 * @author 0xEmmyb2
 * @notice The attendance, leave and payroll engine of hires made through {SiteOperations}: it classifies every day,
 * guards check-ins like a gate terminal, and pays workers automatically from their verified attendance.
 * @dev Day types:
 * | Day | Set by | Daily-rate miner | Salaried staff | Penalty / alert |
 * |---|---|---|---|---|
 * | Shift worked (check-in, {WorkforceManager}) | gate / supervisor | 100% day rate | in salary | no |
 * | Scheduled rest day (site roster or personal roster) | company / site manager | 0 | in salary | no |
 * | Public holiday (company HQ calendar, all sites) | company | 0 | in salary | no |
 * | Paid statutory leave (annual 1.5 days/month, sick, maternity) | site HR / company | 100% base | in salary | no |
 * | Excused leave (unpaid personal leave) | supervisor, site admin, HR | 0 | salary / 26 deducted | no |
 * | Unexcused absence (no-show) | - | 0 | salary / 26 deducted | penalty, HR alert |
 * Authorised work on a rest day or holiday pays the site's overtime rate. Leave and unexcused absences reset the
 * consecutive-day streak.
 *
 * Gate ({checkAttendance}, called by {WorkforceManager-recordAttendance}): routine check-in is blocked on a rest
 * day, a holiday or a leave day, and on what would be a 7th consecutive working day (the 1-in-7 fatigue lock),
 * unless overtime was authorised ({authorizeOvertime}: a supervisor, and for the fatigue lock a site manager).
 *
 * Pay: once a period (daily, weekly, two-weekly or monthly) has ended and the site's grace days have passed,
 * anyone can settle it ({settlePay}), with no approval. The pay is pulled from the site's payer account in the
 * primary settlement token, else the secondary one, else it stays owed and is retried later. Every payment is
 * booked in {WorkforceManager}, and the site's accrued-to-date payroll is updated.
 */
contract PayrollEngine is ReentrancyGuardTransient, IAttendanceGate {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                             STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Participant, role and permission registry.
     */
    IMineNetRegistry public immutable registry;

    /**
     * @notice Mine sites.
     */
    ISiteRegistry public immutable sites;

    /**
     * @notice Workers, attendance, staff permissions and payment records.
     */
    IWorkforce public immutable workforce;

    /**
     * @notice Currencies, settlement tokens and conversion.
     */
    ICurrencyManager public immutable currencies;

    /**
     * @notice Hires and positions.
     */
    ISiteOperations public immutable siteOps;

    /**
     * @dev Last leave request id; ids start at 1.
     */
    uint256 private _requestCount;

    /**
     * @dev Site => how it pays.
     */
    mapping(uint256 siteId => PayrollLib.PayPolicy) private _policies;

    /**
     * @dev Hire => payroll state.
     */
    mapping(uint256 hireId => PayrollLib.PayState) private _state;

    /**
     * @notice Leave recorded for a hire on a day.
     */
    mapping(uint256 hireId => mapping(uint64 day => PayrollLib.LeaveType)) public leaveOn;

    /**
     * @notice Whether overtime was authorised for a hire on a day.
     */
    mapping(uint256 hireId => mapping(uint64 day => bool)) public overtimeOn;

    /**
     * @notice Public holidays on a company's HQ calendar (apply to all its sites).
     */
    mapping(bytes32 orgId => mapping(uint64 day => bool)) public isHoliday;

    /**
     * @dev Request id => leave request.
     */
    mapping(uint256 requestId => PayrollLib.LeaveRequest) private _requests;

    /**
     * @notice Pay settled so far at a site, per currency (accrued-to-date payroll).
     */
    mapping(uint256 siteId => mapping(bytes32 currency => uint256)) public accruedPayroll;

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @param registry_ Participant, role and permission registry.
     * @param sites_ Mine site registry.
     * @param workforce_ Workforce manager.
     * @param currencies_ Currency manager.
     * @param siteOps_ Site operations (hires and positions).
     */
    constructor(
        IMineNetRegistry registry_,
        ISiteRegistry sites_,
        IWorkforce workforce_,
        ICurrencyManager currencies_,
        ISiteOperations siteOps_
    ) {
        registry = registry_;
        sites = sites_;
        workforce = workforce_;
        currencies = currencies_;
        siteOps = siteOps_;
    }

    /*//////////////////////////////////////////////////////////////
                          COMPANY: POLICY AND CALENDAR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Sets how a site pays: payer account, primary and secondary tokens, working days, grace, penalty,
     * no-show alert threshold and overtime rates.
     * @dev The site's company account. The payer must be an account of the same company. Applies to every period
     * settled from now on.
     * @param siteId Mine site.
     * @param policy The policy.
     * @custom:emits PayPolicySet
     */
    function setPayPolicy(uint256 siteId, PayrollLib.PayPolicy calldata policy) external {
        bytes32 orgId = _onlyCompany(siteId);
        if (
            policy.payer == address(0) || registry.participant(policy.payer).orgId != orgId
                || !currencies.isSettlementToken(policy.primary) || policy.workdays == 0 || policy.workdays > 0x7F
                || policy.graceDays > PayrollLib.MAX_GRACE_DAYS || policy.absencePenaltyBps > PayrollLib.MAX_PENALTY_BPS
                || policy.restDayOvertimeBps < PayrollLib.MIN_OVERTIME_BPS
                || policy.restDayOvertimeBps > PayrollLib.MAX_OVERTIME_BPS
                || policy.holidayOvertimeBps < PayrollLib.MIN_OVERTIME_BPS
                || policy.holidayOvertimeBps > PayrollLib.MAX_OVERTIME_BPS
                || address(policy.secondary) == address(policy.primary)
                || (address(policy.secondary) != address(0) && !currencies.isSettlementToken(policy.secondary))
        ) {
            revert PayrollLib.PayrollEngine__InvalidPolicy();
        }
        _policies[siteId] = policy;
        emit PayrollLib.PayPolicySet(siteId, policy);
    }

    /**
     * @notice Marks or unmarks public holidays on the company's HQ calendar, for all its sites.
     * @dev A company account (`MANAGE_WORKFORCE`). Only days not yet settled are affected.
     * @param days_ Days (1 to {PayrollLib-MAX_DAYS}).
     * @param holiday True to mark, false to unmark.
     * @custom:emits HolidaySet (per day)
     */
    function setHolidays(uint64[] calldata days_, bool holiday) external {
        if (!registry.isAuthorized(msg.sender, Actions.MANAGE_WORKFORCE)) {
            revert PayrollLib.PayrollEngine__NotCompany(msg.sender);
        }
        _checkBatch(days_.length);
        bytes32 orgId = registry.participant(msg.sender).orgId;
        for (uint256 i; i < days_.length; ++i) {
            isHoliday[orgId][days_[i]] = holiday;
            emit PayrollLib.HolidaySet(orgId, days_[i], holiday);
        }
    }

    /**
     * @notice Sets a hire's personal roster (e.g. a rotating rest day), replacing the site's standard working days.
     * @dev The company, or staff with `MANAGE_SITE` at the hire's site (the site manager).
     * @param hireId An active hire.
     * @param workdays Working-day mask, bit 0 = Monday (0 = back to the site standard); at least one rest day.
     * @custom:emits RosterSet
     */
    function setRoster(uint256 hireId, uint8 workdays) external {
        (, SiteOpsLib.Position memory pos) = _activeHire(hireId);
        if (!_isCompany(pos.siteId)) _onlyStaff(pos.siteId, StaffLib.MANAGE_SITE);
        if (workdays >= 0x7F) revert PayrollLib.PayrollEngine__InvalidInput();
        _state[hireId].roster = workdays;
        emit PayrollLib.RosterSet(hireId, workdays, msg.sender);
    }

    /*//////////////////////////////////////////////////////////////
                                  LEAVE
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice A worker asks for leave.
     * @dev Only the worker's wallet, for their active hire.
     * @param hireId The worker's hire.
     * @param leaveType Excused, annual, sick or maternity leave.
     * @param days_ Days (1 to {PayrollLib-MAX_DAYS}).
     * @param reasonHash Hash of the justification (medical certificate, leave form).
     * @return requestId New request id.
     * @custom:emits LeaveRequested
     */
    function requestLeave(uint256 hireId, PayrollLib.LeaveType leaveType, uint64[] calldata days_, bytes32 reasonHash)
        external
        returns (uint256 requestId)
    {
        if (leaveType == PayrollLib.LeaveType.None) revert PayrollLib.PayrollEngine__InvalidInput();
        _checkBatch(days_.length);
        (SiteOpsLib.Hire memory h,) = _activeHire(hireId);
        if (workforce.getWorker(h.workerId).wallet != msg.sender) {
            revert PayrollLib.PayrollEngine__NotAuthorized(msg.sender);
        }
        requestId = ++_requestCount;
        _requests[requestId] = PayrollLib.LeaveRequest({
            hireId: hireId,
            leaveType: leaveType,
            status: PayrollLib.RequestStatus.Pending,
            requestedBy: msg.sender,
            reasonHash: reasonHash,
            dayList: days_
        });
        emit PayrollLib.LeaveRequested(requestId, hireId, leaveType, days_, reasonHash);
    }

    /**
     * @notice Approves or rejects a leave request.
     * @dev Excused leave: staff with `RECORD_ATTENDANCE` at the site (supervisor, site admin, HR) or the company.
     * Paid leave: staff with `MANAGE_HIRING` (site HR) or the company. Never the worker themselves.
     * @param requestId A pending request.
     * @param approve True to approve.
     * @param noteHash Hash of the decision note.
     * @custom:emits LeaveDecided
     * @custom:emits LeaveRecorded (per day, on approval)
     */
    function decideLeave(uint256 requestId, bool approve, bytes32 noteHash) external {
        PayrollLib.LeaveRequest storage r = _requests[requestId];
        if (r.status != PayrollLib.RequestStatus.Pending) revert PayrollLib.PayrollEngine__InvalidRequest(requestId);
        if (msg.sender == r.requestedBy) revert PayrollLib.PayrollEngine__NotAuthorized(msg.sender);
        _authorizeLeave(r.hireId, r.leaveType);
        r.status = approve ? PayrollLib.RequestStatus.Approved : PayrollLib.RequestStatus.Rejected;
        emit PayrollLib.LeaveDecided(requestId, approve, msg.sender, noteHash);
        if (approve) _applyLeave(r.hireId, r.leaveType, r.dayList, r.reasonHash);
    }

    /**
     * @notice Records approved leave directly (e.g. from a paper leave form).
     * @dev Same approvers as {decideLeave}; never the worker themselves.
     * @param hireId An active hire.
     * @param leaveType Excused, annual, sick or maternity leave.
     * @param days_ Days (1 to {PayrollLib-MAX_DAYS}).
     * @param reasonHash Hash of the justification.
     * @custom:emits LeaveRecorded (per day)
     */
    function grantLeave(uint256 hireId, PayrollLib.LeaveType leaveType, uint64[] calldata days_, bytes32 reasonHash)
        external
    {
        if (leaveType == PayrollLib.LeaveType.None) revert PayrollLib.PayrollEngine__InvalidInput();
        _checkBatch(days_.length);
        _applyLeave(hireId, leaveType, days_, reasonHash);
    }

    /**
     * @notice Authorises overtime: the worker may check in on a rest day, holiday or leave day, at the overtime
     * rate on rest days and holidays. Overriding the 1-in-7 fatigue lock is an emergency decision of the site
     * manager.
     * @dev Staff with `AUTHORIZE_OVERTIME` at the hire's site (shift supervisor, manager); a day that is
     * fatigue-locked also needs `MANAGE_SITE` (site manager). Only days not yet settled.
     * @param hireId An active hire.
     * @param days_ Days (1 to {PayrollLib-MAX_DAYS}).
     * @param reasonHash Hash of the reason (emergency dewatering, shaft repair, security).
     * @custom:emits OvertimeAuthorized (per day)
     */
    function authorizeOvertime(uint256 hireId, uint64[] calldata days_, bytes32 reasonHash) external {
        _checkBatch(days_.length);
        (SiteOpsLib.Hire memory h, SiteOpsLib.Position memory pos) = _activeHire(hireId);
        _onlyStaff(pos.siteId, StaffLib.AUTHORIZE_OVERTIME);
        uint64 open = _openDay(hireId, h, pos);
        for (uint256 i; i < days_.length; ++i) {
            uint64 day = days_[i];
            if (day < open) revert PayrollLib.PayrollEngine__InvalidDay(hireId, day);
            if (_fatigueLocked(h.workerId, day)) _onlyStaff(pos.siteId, StaffLib.MANAGE_SITE);
            overtimeOn[hireId][day] = true;
            emit PayrollLib.OvertimeAuthorized(hireId, day, msg.sender, reasonHash);
        }
    }

    /*//////////////////////////////////////////////////////////////
                         PAY: NO APPROVAL NEEDED
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Settles and pays every finished pay period of the hires, plus anything owed.
     * @dev Anyone: the worker, HR or a keeper bot. An active hire's period is settled once it ended at least the
     * policy's `graceDays` ago; an ended hire's last period runs to its end day. At most
     * {PayrollLib-MAX_PERIODS_PER_SETTLE} periods per hire per call.
     * @param hireIds Hires (1 to {PayrollLib-MAX_PAY_BATCH}).
     * @custom:emits PeriodSettled (per period)
     * @custom:emits NoShowAlert (when the threshold is reached)
     * @custom:emits SalaryPaid or SalaryOwed (per hire with pay due)
     * @custom:emits PaymentRecorded in {WorkforceManager} (per payment)
     */
    function settlePay(uint256[] calldata hireIds) external nonReentrant {
        if (hireIds.length == 0 || hireIds.length > PayrollLib.MAX_PAY_BATCH) {
            revert PayrollLib.PayrollEngine__InvalidInput();
        }
        uint64 today = uint64(block.timestamp / 1 days);
        for (uint256 i; i < hireIds.length; ++i) {
            uint256 hireId = hireIds[i];
            SiteOpsLib.Hire memory h = siteOps.getHire(hireId);
            bool active = h.status == SiteOpsLib.HireStatus.Active;
            if (!active && h.status != SiteOpsLib.HireStatus.Ended) {
                revert PayrollLib.PayrollEngine__HireNotActive(hireId);
            }
            SiteOpsLib.Position memory pos = siteOps.getPosition(h.positionId);
            PayrollLib.PayPolicy memory pol = _policies[pos.siteId];
            if (pol.payer == address(0)) revert PayrollLib.PayrollEngine__NoPayPolicy(pos.siteId);
            uint64 until = active ? (today > pol.graceDays ? today - pol.graceDays : 0) : h.endDay;
            _settle(hireId, h, pos, pol, until, !active);
        }
    }

    /*//////////////////////////////////////////////////////////////
                                  VIEWS
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc IAttendanceGate
     * @dev Only hires made through {SiteOperations} are gated. Authorised overtime lifts every block.
     */
    function checkAttendance(bytes32 workerId, uint256, uint64 day) external view {
        uint256 hireId = siteOps.hireOf(workerId);
        if (hireId == 0 || overtimeOn[hireId][day]) return;
        SiteOpsLib.Hire memory h = siteOps.getHire(hireId);
        if (h.status != SiteOpsLib.HireStatus.Active) return;
        uint256 site = siteOps.getPosition(h.positionId).siteId;
        if (isHoliday[sites.orgOfSite(site)][day]) revert PayrollLib.PayrollEngine__Holiday(workerId, day);
        uint8 roster = _roster(hireId, site); // 0 until the site has a pay policy: no rest days to enforce yet
        if (roster != 0 && !PayrollLib.isWorkday(roster, day)) revert PayrollLib.PayrollEngine__RestDay(workerId, day);
        if (leaveOn[hireId][day] != PayrollLib.LeaveType.None) revert PayrollLib.PayrollEngine__OnLeave(workerId, day);
        if (_fatigueLocked(workerId, day)) revert PayrollLib.PayrollEngine__FatigueLock(workerId, day);
    }

    /**
     * @notice How a site pays.
     * @param siteId Site.
     * @return The policy (zero payer = not set).
     */
    function payPolicyOf(uint256 siteId) external view returns (PayrollLib.PayPolicy memory) {
        return _policies[siteId];
    }

    /**
     * @notice A hire's payroll state.
     * @param hireId Hire.
     * @return The state.
     */
    function payStateOf(uint256 hireId) external view returns (PayrollLib.PayState memory) {
        return _state[hireId];
    }

    /**
     * @notice Returns a leave request.
     * @param requestId Request id.
     * @return The request (status `None` if unknown).
     */
    function getLeaveRequest(uint256 requestId) external view returns (PayrollLib.LeaveRequest memory) {
        return _requests[requestId];
    }

    /**
     * @notice Annual leave a hire has accrued and not yet taken (1.5 days per 30 days employed).
     * @param hireId Hire.
     * @return Days available.
     */
    function annualLeaveBalance(uint256 hireId) public view returns (uint256) {
        SiteOpsLib.Hire memory h = siteOps.getHire(hireId);
        uint64 today = uint64(block.timestamp / 1 days);
        uint256 accrued = today > h.startDay ? (today - h.startDay) / PayrollLib.DAYS_PER_ANNUAL_LEAVE_DAY : 0;
        uint256 used = _state[hireId].annualUsed;
        return accrued > used ? accrued - used : 0;
    }

    /**
     * @notice The first day after a hire's next unsettled pay period (before grace days).
     * @param hireId Hire.
     * @return Day number (unix time / 1 day).
     */
    function nextPayDay(uint256 hireId) external view returns (uint64) {
        SiteOpsLib.Hire memory h = siteOps.getHire(hireId);
        SiteOpsLib.Position memory pos = siteOps.getPosition(h.positionId);
        return _openDay(hireId, h, pos) + SiteOpsLib.periodDays(pos.frequency);
    }

    /**
     * @notice What a hire earns for one pay period from what is recorded so far (a preview; settled periods are
     * final).
     * @param hireId Hire.
     * @param period Period index since the hire started.
     * @return The period's pay.
     */
    function previewPeriod(uint256 hireId, uint32 period) external view returns (PayrollLib.PeriodPay memory) {
        SiteOpsLib.Hire memory h = siteOps.getHire(hireId);
        SiteOpsLib.Position memory pos = siteOps.getPosition(h.positionId);
        uint64 len = SiteOpsLib.periodDays(pos.frequency);
        uint64 from = h.startDay + uint64(period) * len;
        return _periodPay(hireId, h, pos, _policies[pos.siteId], from, from + len);
    }

    /*//////////////////////////////////////////////////////////////
                    INTERNAL STATE-CHANGING FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Records leave on unsettled working days, after checking the approver and the annual balance.
     * @param hireId Hire.
     * @param leaveType Type of leave.
     * @param days_ Days.
     * @param reasonHash Hash of the justification.
     */
    function _applyLeave(uint256 hireId, PayrollLib.LeaveType leaveType, uint64[] memory days_, bytes32 reasonHash)
        private
    {
        (SiteOpsLib.Hire memory h, SiteOpsLib.Position memory pos) = _activeHire(hireId);
        _authorizeLeave(hireId, leaveType);
        if (workforce.getWorker(h.workerId).wallet == msg.sender) {
            revert PayrollLib.PayrollEngine__NotAuthorized(msg.sender);
        }
        if (leaveType == PayrollLib.LeaveType.Annual) {
            uint256 available = annualLeaveBalance(hireId);
            if (days_.length > available) {
                revert PayrollLib.PayrollEngine__InsufficientLeave(hireId, available, days_.length);
            }
            _state[hireId].annualUsed += uint32(days_.length);
        }
        uint64 open = _openDay(hireId, h, pos);
        uint8 roster = _roster(hireId, pos.siteId);
        bytes32 orgId = sites.orgOfSite(pos.siteId);
        for (uint256 i; i < days_.length; ++i) {
            uint64 day = days_[i];
            if (
                day < open || !PayrollLib.isWorkday(roster, day) || isHoliday[orgId][day]
                    || leaveOn[hireId][day] != PayrollLib.LeaveType.None
            ) revert PayrollLib.PayrollEngine__InvalidDay(hireId, day);
            leaveOn[hireId][day] = leaveType;
            emit PayrollLib.LeaveRecorded(hireId, day, leaveType, msg.sender, reasonHash);
        }
    }

    /**
     * @dev Settles a hire's periods ending on or before `untilDay` (and, if `partialLast`, the period running on it,
     * cut there), then pays the total plus anything owed.
     * @param hireId Hire id.
     * @param h The hire.
     * @param pos Its position.
     * @param pol The site's pay policy.
     * @param untilDay Settle up to this day (exclusive).
     * @param partialLast Whether to settle a final, partial period.
     */
    function _settle(
        uint256 hireId,
        SiteOpsLib.Hire memory h,
        SiteOpsLib.Position memory pos,
        PayrollLib.PayPolicy memory pol,
        uint64 untilDay,
        bool partialLast
    ) private {
        PayrollLib.PayState storage st = _state[hireId];
        uint64 len = SiteOpsLib.periodDays(pos.frequency);
        uint32 k = st.settledPeriods;
        uint256 due;
        for (uint256 n; n < PayrollLib.MAX_PERIODS_PER_SETTLE; ++n) {
            uint64 from = h.startDay + uint64(k) * len;
            uint64 to = from + len;
            if (to > untilDay) {
                if (!partialLast || from >= untilDay) break;
                to = untilDay;
            }
            PayrollLib.PeriodPay memory pp = _periodPay(hireId, h, pos, pol, from, to);
            emit PayrollLib.PeriodSettled(hireId, k, pp);
            due += pp.net;
            if (pp.unexcused != 0) {
                uint32 total = st.absences + pp.unexcused;
                st.absences = total;
                if (pol.noShowAlert != 0 && total >= pol.noShowAlert) {
                    emit PayrollLib.NoShowAlert(hireId, pp.unexcused, total);
                }
            }
            ++k;
            if (to == untilDay) break;
        }
        st.settledPeriods = k;
        accruedPayroll[pos.siteId][pos.currency] += due;
        _pay(hireId, h, pos, pol, due + st.owed);
    }

    /**
     * @dev Pays `amount` (in the position's currency) from the payer: primary token, else secondary, else owed.
     * @param hireId Hire id.
     * @param h The hire.
     * @param pos Its position.
     * @param pol The site's pay policy.
     * @param amount Amount due.
     */
    function _pay(
        uint256 hireId,
        SiteOpsLib.Hire memory h,
        SiteOpsLib.Position memory pos,
        PayrollLib.PayPolicy memory pol,
        uint256 amount
    ) private {
        if (amount == 0) return;
        PayrollLib.PayState storage st = _state[hireId];
        address wallet = workforce.getWorker(h.workerId).wallet;
        IERC20 token = pol.primary;
        (bool ok, uint256 tokenAmount) = _tryPay(token, pos.currency, amount, pol.payer, wallet);
        bool fallback_;
        if (!ok) {
            token = pol.secondary;
            (ok, tokenAmount) = _tryPay(token, pos.currency, amount, pol.payer, wallet);
            fallback_ = true;
        }
        if (!ok) {
            st.owed = amount;
            emit PayrollLib.SalaryOwed(hireId, amount);
            return;
        }
        st.owed = 0;
        (uint256 paymentId,) = workforce.recordSiteSalary(
            sites.orgOfSite(pos.siteId),
            h.workerId,
            token,
            tokenAmount,
            keccak256(abi.encode("MINENET_PAY", hireId, st.settledPeriods))
        );
        emit PayrollLib.SalaryPaid(hireId, address(token), tokenAmount, paymentId, fallback_);
    }

    /**
     * @dev Tries to pull `amount` (in `currency`) from `payer` to `wallet` in `token` at the live rate, rounded up.
     * @param token Settlement token (zero = no such method).
     * @param currency Currency `amount` is in.
     * @param amount Amount due.
     * @param payer Account paying.
     * @param wallet Worker wallet.
     * @return ok True if the transfer succeeded.
     * @return tokenAmount Amount sent, in token units.
     */
    function _tryPay(IERC20 token, bytes32 currency, uint256 amount, address payer, address wallet)
        private
        returns (bool ok, uint256 tokenAmount)
    {
        if (address(token) == address(0) || wallet == address(0)) return (false, 0);
        try currencies.toTokenAmount(amount, currency, token, true) returns (uint256 t) {
            tokenAmount = t;
        } catch {
            return (false, 0);
        }
        if (tokenAmount == 0) return (false, 0);
        ok = token.trySafeTransferFrom(payer, wallet, tokenAmount);
    }

    /*//////////////////////////////////////////////////////////////
                     INTERNAL READ-ONLY FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Classifies every day of `[from, to)` and prices the period (see the table in the contract notice).
     * @param hireId Hire id.
     * @param h The hire.
     * @param pos Its position.
     * @param pol The site's pay policy.
     * @param from First day.
     * @param to Day after the last day (at most 256 days after `from`).
     * @return pp The period's pay.
     */
    function _periodPay(
        uint256 hireId,
        SiteOpsLib.Hire memory h,
        SiteOpsLib.Position memory pos,
        PayrollLib.PayPolicy memory pol,
        uint64 from,
        uint64 to
    ) private view returns (PayrollLib.PeriodPay memory pp) {
        uint256 mask = workforce.attendanceMask(h.workerId, from, to - from);
        uint8 roster = _state[hireId].roster;
        if (roster == 0) roster = pol.workdays;
        bytes32 orgId = sites.orgOfSite(pos.siteId);
        for (uint64 day = from; day < to; ++day) {
            bool holiday = isHoliday[orgId][day];
            bool workday = PayrollLib.isWorkday(roster, day);
            if ((mask >> (day - from)) & 1 == 1) {
                if (holiday) ++pp.holidayOvertime;
                else if (!workday) ++pp.restOvertime;
                else ++pp.worked;
            } else if (workday && !holiday) {
                PayrollLib.LeaveType lt = leaveOn[hireId][day];
                if (PayrollLib.isPaid(lt)) ++pp.paidLeave;
                else if (lt == PayrollLib.LeaveType.Excused) ++pp.excused;
                else ++pp.unexcused;
            }
        }
        bool salaried = pos.basis == SiteOpsLib.PayBasis.Monthly;
        uint256 dayRate = salaried ? pos.rate / SiteOpsLib.WORKDAYS_PER_MONTH : pos.rate;
        uint256 overtime =
            (uint256(pp.restOvertime) * pol.restDayOvertimeBps + uint256(pp.holidayOvertime) * pol.holidayOvertimeBps)
                * dayRate / 10_000;
        if (salaried) {
            pp.gross = uint256(pos.rate) * (to - from) / 30 + overtime;
            pp.deductions = uint256(pp.excused + pp.unexcused) * dayRate;
        } else {
            pp.gross = uint256(pp.worked + pp.paidLeave) * dayRate + overtime;
        }
        pp.penalty = uint256(pp.unexcused) * dayRate * pol.absencePenaltyBps / 10_000;
        uint256 cut = pp.deductions + pp.penalty;
        pp.net = pp.gross > cut ? pp.gross - cut : 0;
    }

    /**
     * @dev Whether checking `workerId` in on `day` would make 7 consecutive days of attendance.
     * @param workerId Worker.
     * @param day Day.
     * @return True if the day is fatigue-locked.
     */
    function _fatigueLocked(bytes32 workerId, uint64 day) private view returns (bool) {
        uint256 limit = PayrollLib.MAX_CONSECUTIVE_DAYS;
        uint64 from = day > limit ? day - uint64(limit) : 0;
        uint256 offset = day - from; // bit of `day`
        uint256 mask = workforce.attendanceMask(workerId, from, offset + limit + 1);
        uint256 run;
        for (uint256 i = offset; i > 0 && (mask >> (i - 1)) & 1 == 1; --i) {
            ++run;
        }
        for (uint256 i = offset + 1; i <= offset + limit && (mask >> i) & 1 == 1; ++i) {
            ++run;
        }
        return run >= limit;
    }

    /**
     * @dev Reverts unless the caller may approve `leaveType` for the hire's site.
     * @param hireId Hire.
     * @param leaveType Type of leave.
     */
    function _authorizeLeave(uint256 hireId, PayrollLib.LeaveType leaveType) private view {
        uint256 siteId = siteOps.getPosition(siteOps.getHire(hireId).positionId).siteId;
        if (_isCompany(siteId)) return;
        _onlyStaff(
            siteId, leaveType == PayrollLib.LeaveType.Excused ? StaffLib.RECORD_ATTENDANCE : StaffLib.MANAGE_HIRING
        );
    }

    /**
     * @dev Returns an active hire and its position.
     * @param hireId Hire id.
     * @return h The hire.
     * @return pos Its position.
     */
    function _activeHire(uint256 hireId)
        private
        view
        returns (SiteOpsLib.Hire memory h, SiteOpsLib.Position memory pos)
    {
        h = siteOps.getHire(hireId);
        if (h.status != SiteOpsLib.HireStatus.Active) revert PayrollLib.PayrollEngine__HireNotActive(hireId);
        pos = siteOps.getPosition(h.positionId);
    }

    /**
     * @dev First day not yet settled.
     * @param hireId Hire id.
     * @param h The hire.
     * @param pos Its position.
     * @return The day.
     */
    function _openDay(uint256 hireId, SiteOpsLib.Hire memory h, SiteOpsLib.Position memory pos)
        private
        view
        returns (uint64)
    {
        return h.startDay + uint64(_state[hireId].settledPeriods) * SiteOpsLib.periodDays(pos.frequency);
    }

    /**
     * @dev A hire's working days: their personal roster, else the site's standard.
     * @param hireId Hire.
     * @param siteId Site.
     * @return Working-day mask.
     */
    function _roster(uint256 hireId, uint256 siteId) private view returns (uint8) {
        uint8 r = _state[hireId].roster;
        return r != 0 ? r : _policies[siteId].workdays;
    }

    /**
     * @dev Reverts on an empty or oversized day list.
     * @param n Length.
     */
    function _checkBatch(uint256 n) private pure {
        if (n == 0 || n > PayrollLib.MAX_DAYS) revert PayrollLib.PayrollEngine__InvalidInput();
    }

    /**
     * @dev The site's company, reverting unless the caller is its company account.
     * @param siteId Site.
     * @return orgId The company.
     */
    function _onlyCompany(uint256 siteId) private view returns (bytes32 orgId) {
        if (!_isCompany(siteId)) revert PayrollLib.PayrollEngine__NotCompany(msg.sender);
        orgId = sites.orgOfSite(siteId);
    }

    /**
     * @dev Reverts unless the caller is the site's staff holding `permission` there.
     * @param siteId Site.
     * @param permission Required staff permission ({StaffLib}).
     */
    function _onlyStaff(uint256 siteId, uint32 permission) private view {
        bytes32 orgId = sites.orgOfSite(siteId);
        if (orgId == bytes32(0) || workforce.staffOrg(msg.sender, siteId, permission) != orgId) {
            revert PayrollLib.PayrollEngine__NotAuthorized(msg.sender);
        }
    }

    /**
     * @dev Whether the caller is a company account (`MANAGE_WORKFORCE`) of the site's organisation.
     * @param siteId Site.
     * @return True if so.
     */
    function _isCompany(uint256 siteId) private view returns (bool) {
        bytes32 orgId = sites.orgOfSite(siteId);
        return orgId != bytes32(0) && registry.isAuthorized(msg.sender, Actions.MANAGE_WORKFORCE)
            && registry.participant(msg.sender).orgId == orgId;
    }
}
