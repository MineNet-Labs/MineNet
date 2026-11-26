// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import {IMineNetRegistry} from "src/access/interfaces/IMineNetRegistry.sol";
import {ICurrencyManager} from "src/finance/interfaces/ICurrencyManager.sol";
import {ISiteRegistry} from "src/compliance/interfaces/ISiteRegistry.sol";
import {IStaffDirectory} from "src/workforce/interfaces/IStaffDirectory.sol";
import {Actions} from "src/access/libraries/Actions.sol";
import {WorkforceLib} from "src/workforce/libraries/WorkforceLib.sol";
import {StaffLib} from "src/workforce/libraries/StaffLib.sol";

/**
 * @title WorkforceManager
 * @author 0xEmmyb2
 * @notice Workers of mining (and processing) companies: where they work, their attendance, and how they and the
 * company's other payees are paid.
 * @dev Workers: a company manager (`MANAGE_WORKFORCE`) registers each worker under an opaque id (a salted hash,
 * never a name or national id), optionally with a wallet, and assigns them to one of the company's mine sites.
 *
 * Attendance: a manager, or an attendance device (`REPORT_READING`, e.g. a biometric clock), records which
 * workers were present at a site on a day. Each worker counts once per day. Days up to
 * {MAX_ATTENDANCE_BACKDATE} in the past can be filed, for sites without connectivity.
 *
 * Payments: every payment the company makes (salaries, suppliers, contractors) is recorded with its method, so
 * management can see the whole picture:
 * - `MobileMoney` / `BankTransfer` / `Other`: recorded with the provider's receipt hash.
 * - `Stablecoin`: paid on-chain by this contract ({payStablecoin}, {payPayroll}) in a settlement token of
 *   {CurrencyManager}.
 * - `Cash`: waits for the payee to acknowledge it (with their wallet, or through an attendance / biometric
 *   device). Cash above {cashLimitUsd} is flagged, and cash not acknowledged within {ackWindow} is overdue
 *   ({isAckOverdue}). Both are cash-in-hand risks shown in the company report.
 * Payees with a wallet can dispute a payment they did not receive.
 *
 * Reports: {orgReport} gives each company its totals in USD (6 decimals) by method, its cash share, and its open
 * cash and dispute counts. Detailed reports come from the events.
 *
 * Staff roles (see {StaffLib}): the company account defines roles and assigns them to its workers, for the
 * worker's own site or for all sites. A worker with a role acts from their own wallet, within the role's
 * permissions and scope: e.g. a `SUPERVISOR` records attendance at their site, a `PAYROLL_OFFICER` records and
 * pays wages. Staff can never assign roles, change a role holder, or pay or record payments to themselves.
 * Other contracts ({MineSiteRegistry}) check staff permissions through {staffOrg}.
 */
contract WorkforceManager is ReentrancyGuardTransient, IStaffDirectory {
    using SafeERC20 for IERC20;

    /**
     * @notice How many days in the past attendance may be filed.
     */
    uint64 public constant MAX_ATTENDANCE_BACKDATE = 7;

    /**
     * @notice Maximum number of workers paid in one {payPayroll} call.
     */
    uint256 public constant MAX_PAYROLL_BATCH = 200;

    /**
     * @notice Participant, role and permission registry.
     */
    IMineNetRegistry public immutable registry;

    /**
     * @notice Mine sites workers are assigned to.
     */
    ISiteRegistry public immutable sites;

    /**
     * @notice Currencies, settlement tokens and USD conversion.
     */
    ICurrencyManager public immutable currencies;

    /**
     * @notice Cash payments above this USD value (6 decimals) are flagged as a risk.
     */
    uint256 public cashLimitUsd = 500e6;

    /**
     * @notice Time a payee has to acknowledge a cash payment before it is overdue.
     */
    uint32 public ackWindow = 7 days;

    /**
     * @dev Worker id => worker.
     */
    mapping(bytes32 workerId => WorkforceLib.Worker) private _workers;

    /**
     * @dev Company => ids of its workers, in registration order.
     */
    mapping(bytes32 orgId => bytes32[]) private _workersOf;

    /**
     * @notice Whether a worker's attendance was recorded on a day (unix time / 1 day).
     */
    mapping(bytes32 workerId => mapping(uint64 day => bool)) public attendedOn;

    /**
     * @notice The worker a wallet belongs to (one wallet per worker).
     */
    mapping(address wallet => bytes32 workerId) public workerOfWallet;

    /**
     * @dev Worker id => staff role.
     */
    mapping(bytes32 workerId => StaffLib.StaffRole) private _staff;

    /**
     * @dev Company => role id => the company's definition of the role.
     */
    mapping(bytes32 orgId => mapping(bytes32 roleId => StaffLib.RoleDef)) private _roleDefs;

    /**
     * @dev Company => roles it has defined or redefined.
     */
    mapping(bytes32 orgId => bytes32[]) private _definedRoles;

    /**
     * @dev Next payment id; ids start at 1 so that 0 means "none".
     */
    uint256 private _nextPaymentId = 1;

    /**
     * @dev Payment id => payment.
     */
    mapping(uint256 paymentId => WorkforceLib.Payment) private _payments;

    /**
     * @dev Company => running payment totals.
     */
    mapping(bytes32 orgId => WorkforceLib.OrgReport) private _reports;

    /**
     * @param registry_ Participant, role and permission registry.
     * @param sites_ Mine site registry.
     * @param currencies_ Currency manager.
     */
    constructor(IMineNetRegistry registry_, ISiteRegistry sites_, ICurrencyManager currencies_) {
        registry = registry_;
        sites = sites_;
        currencies = currencies_;
    }

    /*//////////////////////////////////////////////////////////////
                                  ADMIN
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Sets the cash-risk limit and the acknowledgement window.
     * @dev Only a {MineNetRegistry} admin.
     * @param cashLimitUsd_ Cash amount above which a payment is flagged, USD with 6 decimals.
     * @param ackWindow_ Time a payee has to acknowledge a cash payment, in seconds; non-zero.
     * @custom:emits CashPolicySet
     */
    function setCashPolicy(uint256 cashLimitUsd_, uint32 ackWindow_) external {
        if (!registry.isAdmin(msg.sender)) {
            revert WorkforceLib.WorkforceManager__NotRegistryAdmin(msg.sender);
        }
        if (ackWindow_ == 0) revert WorkforceLib.WorkforceManager__InvalidPolicy();
        cashLimitUsd = cashLimitUsd_;
        ackWindow = ackWindow_;
        emit WorkforceLib.CashPolicySet(cashLimitUsd_, ackWindow_);
    }

    /*//////////////////////////////////////////////////////////////
                        MANAGER: WORKERS AND SITES
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Registers a worker of the caller's company, optionally assigned to a site.
     * @dev The company account, or staff with `MANAGE_WORKERS` for that site.
     * @param workerId Opaque, salted worker id; non-zero and unused.
     * @param wallet Worker wallet, or zero for none; not linked to another worker.
     * @param siteId One of the company's sites, or 0 for none yet.
     * @custom:emits WorkerRegistered
     */
    function registerWorker(bytes32 workerId, address wallet, uint256 siteId) external {
        (bytes32 orgId,) = _actor(StaffLib.MANAGE_WORKERS, siteId);
        if (workerId == bytes32(0)) revert WorkforceLib.WorkforceManager__InvalidWorkerId();
        if (_workers[workerId].orgId != bytes32(0)) revert WorkforceLib.WorkforceManager__WorkerExists(workerId);
        _requireOrgSite(orgId, siteId);
        _bindWallet(workerId, wallet);

        _workers[workerId] = WorkforceLib.Worker({
            orgId: orgId,
            wallet: wallet,
            siteId: siteId,
            registeredAt: uint64(block.timestamp),
            lastAttendanceDay: 0,
            daysWorked: 0,
            active: true
        });
        _workersOf[orgId].push(workerId);
        emit WorkforceLib.WorkerRegistered(workerId, orgId, wallet, siteId);
    }

    /**
     * @notice Moves a worker to another of the company's sites (0 = unassigned).
     * @dev The company account, or staff with `MANAGE_WORKERS` over both sites. Staff cannot move themselves or
     * another role holder.
     * @param workerId Worker id.
     * @param siteId New site, or 0.
     * @custom:emits WorkerAssigned
     */
    function assignSite(bytes32 workerId, uint256 siteId) external {
        (WorkforceLib.Worker storage w, bool byStaff) = _manageWorker(workerId);
        if (byStaff) _actor(StaffLib.MANAGE_WORKERS, siteId);
        _requireOrgSite(w.orgId, siteId);
        emit WorkforceLib.WorkerAssigned(workerId, w.siteId, siteId);
        w.siteId = siteId;
    }

    /**
     * @notice Changes (or removes, with zero) a worker's wallet.
     * @dev The company account, or staff with `MANAGE_WORKERS` over the worker's site.
     * @param workerId Worker id.
     * @param wallet New wallet, or zero; not linked to another worker.
     * @custom:emits WorkerWalletChanged
     */
    function setWorkerWallet(bytes32 workerId, address wallet) external {
        (WorkforceLib.Worker storage w,) = _manageWorker(workerId);
        delete workerOfWallet[w.wallet];
        _bindWallet(workerId, wallet);
        w.wallet = wallet;
        emit WorkforceLib.WorkerWalletChanged(workerId, wallet);
    }

    /**
     * @notice Deactivates a worker who left, or reactivates one who returned. History is kept.
     * @dev An inactive worker's staff role has no effect.
     * @param workerId Worker id.
     * @param active New state.
     * @custom:emits WorkerStatusChanged
     */
    function setWorkerActive(bytes32 workerId, bool active) external {
        (WorkforceLib.Worker storage w,) = _manageWorker(workerId);
        w.active = active;
        emit WorkforceLib.WorkerStatusChanged(workerId, active);
    }

    /*//////////////////////////////////////////////////////////////
                       COMPANY ACCOUNT: STAFF ROLES
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Creates a company role, or redefines one (including a built-in role) with new permissions.
     * @dev Only the company account (`MANAGE_WORKFORCE`).
     * @param roleId Role id; non-zero.
     * @param permissions Permission bit flags ({StaffLib}).
     * @custom:emits RoleDefined
     */
    function defineRole(bytes32 roleId, uint32 permissions) external {
        bytes32 orgId = _companyOrg();
        if (roleId == bytes32(0)) revert StaffLib.WorkforceManager__InvalidRole(roleId);
        if (permissions & ~StaffLib.ALL != 0) revert StaffLib.WorkforceManager__InvalidPermissions(permissions);
        StaffLib.RoleDef storage d = _roleDefs[orgId][roleId];
        if (!d.defined) _definedRoles[orgId].push(roleId);
        d.defined = true;
        d.permissions = permissions;
        emit StaffLib.RoleDefined(orgId, roleId, permissions);
    }

    /**
     * @notice Gives a worker a staff role, for their own site or for all of the company's sites.
     * @dev Only the company account. A zero `roleId` removes the worker's role.
     * @param workerId One of the company's workers.
     * @param roleId A built-in or company-defined role, or zero.
     * @param allSites Whether the role applies at every company site.
     * @custom:emits RoleAssigned
     */
    function assignRole(bytes32 workerId, bytes32 roleId, bool allSites) external {
        bytes32 orgId = _companyOrg();
        WorkforceLib.Worker storage w = _workers[workerId];
        if (w.orgId == bytes32(0)) revert WorkforceLib.WorkforceManager__UnknownWorker(workerId);
        if (w.orgId != orgId) revert WorkforceLib.WorkforceManager__NotYourWorker(workerId);
        if (roleId != bytes32(0) && !_roleDefs[orgId][roleId].defined && !StaffLib.isBuiltIn(roleId)) {
            revert StaffLib.WorkforceManager__InvalidRole(roleId);
        }
        _staff[workerId] = StaffLib.StaffRole({roleId: roleId, allSites: roleId != bytes32(0) && allSites});
        emit StaffLib.RoleAssigned(workerId, roleId, allSites, msg.sender);
    }

    /*//////////////////////////////////////////////////////////////
                                ATTENDANCE
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Records that workers were present at a site on a day.
     * @dev The site's company account, its staff with `RECORD_ATTENDANCE` there, or an attendance device
     * (`REPORT_READING`). Workers already marked for that day are skipped, so a retried submission is harmless.
     * @param siteId Site; every worker must be active and assigned to it.
     * @param day Day number (unix time / 1 day); not in the future and at most {MAX_ATTENDANCE_BACKDATE} days back.
     * @param workerIds Workers present.
     * @custom:emits AttendanceRecorded (per newly marked worker)
     */
    function recordAttendance(uint256 siteId, uint64 day, bytes32[] calldata workerIds) external {
        bytes32 orgId = sites.orgOfSite(siteId);
        if (!registry.isAuthorized(msg.sender, Actions.REPORT_READING)) {
            (bytes32 actorOrg,) = _actor(StaffLib.RECORD_ATTENDANCE, siteId);
            if (actorOrg != orgId) revert WorkforceLib.WorkforceManager__Unauthorized(msg.sender);
        }
        uint64 today = uint64(block.timestamp / 1 days);
        if (day > today || day + MAX_ATTENDANCE_BACKDATE < today) {
            revert WorkforceLib.WorkforceManager__InvalidDay(day);
        }

        for (uint256 i; i < workerIds.length; ++i) {
            bytes32 workerId = workerIds[i];
            WorkforceLib.Worker storage w = _workers[workerId];
            if (w.orgId != orgId || w.siteId != siteId || siteId == 0) {
                revert WorkforceLib.WorkforceManager__NotAtSite(workerId, siteId);
            }
            if (!w.active) revert WorkforceLib.WorkforceManager__WorkerInactive(workerId);
            if (attendedOn[workerId][day]) continue;
            attendedOn[workerId][day] = true;
            w.daysWorked += 1;
            if (day > w.lastAttendanceDay) w.lastAttendanceDay = day;
            emit WorkforceLib.AttendanceRecorded(workerId, siteId, day, msg.sender);
        }
    }

    /*//////////////////////////////////////////////////////////////
                                 PAYMENTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Records a payment made off-chain (mobile money, e-banking, cash, other).
     * @dev The company account or staff with `RECORD_PAYMENTS` (for salaries, at the worker's site). Cash payments
     * wait for acknowledgement; the USD value is 0 when no rate is available.
     * @param p The payment.
     * @return paymentId New payment id.
     * @custom:emits PaymentRecorded
     * @custom:emits CashRiskFlagged (for cash above the limit)
     */
    function recordPayment(WorkforceLib.PaymentInput calldata p) external returns (uint256 paymentId) {
        bytes32 orgId = _payer(StaffLib.RECORD_PAYMENTS, p.category, p.payeeId);
        if (p.method == WorkforceLib.PaymentMethod.Stablecoin) revert WorkforceLib.WorkforceManager__InvalidMethod();
        if (p.amount == 0) revert WorkforceLib.WorkforceManager__InvalidAmount();
        if (!currencies.isCurrency(p.currency)) revert WorkforceLib.WorkforceManager__UnknownCurrency(p.currency);
        address wallet = _payeeWallet(orgId, p.category, p.payeeId, p.payeeWallet);

        uint256 usdValue;
        try currencies.toUsd(p.amount, p.currency) returns (uint256 v) {
            usdValue = v;
        } catch {}

        paymentId = _record(orgId, p, wallet, p.currency, usdValue);
    }

    /**
     * @notice Pays a worker, supplier or contractor in a settlement stablecoin, from the caller's wallet.
     * @dev The company account or staff with `PAY_WAGES`. The caller must have approved this contract for `amount`.
     * Salaries go to the worker's registered wallet.
     * @param payeeId Worker id or opaque payee reference.
     * @param payeeWallet Payee wallet (ignored for salaries).
     * @param category What the payment is for.
     * @param token Settlement token.
     * @param amount Amount, in token units; non-zero.
     * @param paymentRef Hashed payment reference.
     * @return paymentId New payment id.
     * @custom:emits PaymentRecorded
     */
    function payStablecoin(
        bytes32 payeeId,
        address payeeWallet,
        WorkforceLib.PaymentCategory category,
        IERC20 token,
        uint256 amount,
        bytes32 paymentRef
    ) external nonReentrant returns (uint256 paymentId) {
        bytes32 orgId = _payer(StaffLib.PAY_WAGES, category, payeeId);
        paymentId = _payStablecoin(orgId, payeeId, payeeWallet, category, token, amount, paymentRef);
    }

    /**
     * @notice Pays salaries to many workers in one transaction.
     * @dev Same rules as {payStablecoin} for each worker. Payment ids are consecutive.
     * @param token Settlement token.
     * @param workerIds Workers to pay (1 to {MAX_PAYROLL_BATCH}).
     * @param amounts Amount per worker, in token units (same order).
     * @param paymentRef Hashed pay-period reference.
     * @return firstPaymentId Id of the first payment created.
     * @custom:emits PaymentRecorded (per worker)
     */
    function payPayroll(IERC20 token, bytes32[] calldata workerIds, uint256[] calldata amounts, bytes32 paymentRef)
        external
        nonReentrant
        returns (uint256 firstPaymentId)
    {
        if (workerIds.length != amounts.length || workerIds.length == 0 || workerIds.length > MAX_PAYROLL_BATCH) {
            revert WorkforceLib.WorkforceManager__LengthMismatch();
        }
        firstPaymentId = _nextPaymentId;
        for (uint256 i; i < workerIds.length; ++i) {
            bytes32 orgId = _payer(StaffLib.PAY_WAGES, WorkforceLib.PaymentCategory.Salary, workerIds[i]);
            _payStablecoin(
                orgId, workerIds[i], address(0), WorkforceLib.PaymentCategory.Salary, token, amounts[i], paymentRef
            );
        }
    }

    /**
     * @notice Confirms that a cash payment was received.
     * @dev The payee's wallet, or an attendance / biometric device (`REPORT_READING`).
     * @param paymentId Cash payment awaiting acknowledgement.
     * @param receiptHash Hash of the acknowledgement evidence (zero keeps the recorded receipt).
     * @custom:emits PaymentAcknowledged
     */
    function acknowledgePayment(uint256 paymentId, bytes32 receiptHash) external {
        WorkforceLib.Payment storage p = _requirePayment(paymentId);
        if (p.status != WorkforceLib.PaymentStatus.PendingAck) {
            revert WorkforceLib.WorkforceManager__InvalidPaymentStatus(paymentId, p.status);
        }
        if (msg.sender != p.payeeWallet || p.payeeWallet == address(0)) {
            if (!registry.isAuthorized(msg.sender, Actions.REPORT_READING)) {
                revert WorkforceLib.WorkforceManager__NotPayee(paymentId, msg.sender);
            }
        }
        p.status = WorkforceLib.PaymentStatus.Acknowledged;
        if (receiptHash != bytes32(0)) p.receiptHash = receiptHash;
        _reports[p.orgId].cashPendingAck -= 1;
        emit WorkforceLib.PaymentAcknowledged(paymentId, msg.sender, receiptHash);
    }

    /**
     * @notice The payee says a payment was not received, or was not what was recorded.
     * @dev Only the payee's wallet.
     * @param paymentId Payment id.
     * @param reasonHash Hash of the reason.
     * @custom:emits PaymentDisputed
     */
    function disputePayment(uint256 paymentId, bytes32 reasonHash) external {
        WorkforceLib.Payment storage p = _requirePayment(paymentId);
        if (msg.sender != p.payeeWallet || p.payeeWallet == address(0)) {
            revert WorkforceLib.WorkforceManager__NotPayee(paymentId, msg.sender);
        }
        if (p.status == WorkforceLib.PaymentStatus.Disputed) {
            revert WorkforceLib.WorkforceManager__InvalidPaymentStatus(paymentId, p.status);
        }
        WorkforceLib.OrgReport storage r = _reports[p.orgId];
        if (p.status == WorkforceLib.PaymentStatus.PendingAck) r.cashPendingAck -= 1;
        r.disputed += 1;
        p.status = WorkforceLib.PaymentStatus.Disputed;
        emit WorkforceLib.PaymentDisputed(paymentId, msg.sender, reasonHash);
    }

    /*//////////////////////////////////////////////////////////////
                                  VIEWS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns a worker.
     * @param workerId Worker id.
     * @return The worker (zero organisation if unknown).
     */
    function getWorker(bytes32 workerId) external view returns (WorkforceLib.Worker memory) {
        return _workers[workerId];
    }

    /**
     * @notice Returns all workers of a company, in registration order.
     * @param orgId Company.
     * @return Worker ids.
     */
    function workersOf(bytes32 orgId) external view returns (bytes32[] memory) {
        return _workersOf[orgId];
    }

    /**
     * @notice Returns a worker's staff role.
     * @param workerId Worker id.
     * @return The staff role (zero role id if none).
     */
    function staffRole(bytes32 workerId) external view returns (StaffLib.StaffRole memory) {
        return _staff[workerId];
    }

    /**
     * @notice Permissions of a role in a company: the company's own definition, else the built-in one.
     * @param orgId Company.
     * @param roleId Role id.
     * @return Permission bit flags.
     */
    function rolePermissions(bytes32 orgId, bytes32 roleId) public view returns (uint32) {
        StaffLib.RoleDef storage d = _roleDefs[orgId][roleId];
        return d.defined ? d.permissions : StaffLib.builtIn(roleId);
    }

    /**
     * @notice Roles the company has defined or redefined (built-in roles are always available).
     * @param orgId Company.
     * @return Role ids.
     */
    function definedRoles(bytes32 orgId) external view returns (bytes32[] memory) {
        return _definedRoles[orgId];
    }

    /**
     * @inheritdoc IStaffDirectory
     */
    function staffOrg(address account, uint256 siteId, uint32 permission) public view returns (bytes32) {
        bytes32 workerId = workerOfWallet[account];
        if (workerId == bytes32(0)) return bytes32(0);
        WorkforceLib.Worker storage w = _workers[workerId];
        StaffLib.StaffRole storage r = _staff[workerId];
        if (!w.active || r.roleId == bytes32(0)) return bytes32(0);
        if (permission == 0 || rolePermissions(w.orgId, r.roleId) & permission != permission) return bytes32(0);
        if (!r.allSites && (siteId == 0 || siteId != w.siteId)) return bytes32(0);
        return w.orgId;
    }

    /**
     * @notice Returns a payment.
     * @param paymentId Payment id.
     * @return The payment (status `None` if unknown).
     */
    function getPayment(uint256 paymentId) external view returns (WorkforceLib.Payment memory) {
        return _payments[paymentId];
    }

    /**
     * @notice Number of payments ever recorded.
     * @return Total payment count.
     */
    function totalPayments() external view returns (uint256) {
        return _nextPaymentId - 1;
    }

    /**
     * @notice A company's payment totals for management reports.
     * @param orgId Company.
     * @return The report.
     */
    function orgReport(bytes32 orgId) external view returns (WorkforceLib.OrgReport memory) {
        return _reports[orgId];
    }

    /**
     * @notice Share of the company's payments, by USD value, made in cash.
     * @param orgId Company.
     * @return Share in basis points (0 if no payments).
     */
    function cashShareBps(bytes32 orgId) external view returns (uint256) {
        WorkforceLib.OrgReport storage r = _reports[orgId];
        if (r.totalUsd == 0) return 0;
        return r.usdByMethod[uint8(WorkforceLib.PaymentMethod.Cash)] * 10_000 / r.totalUsd;
    }

    /**
     * @notice Whether a cash payment has waited longer than {ackWindow} for acknowledgement.
     * @param paymentId Payment id.
     * @return True if overdue.
     */
    function isAckOverdue(uint256 paymentId) external view returns (bool) {
        WorkforceLib.Payment storage p = _payments[paymentId];
        return p.status == WorkforceLib.PaymentStatus.PendingAck && block.timestamp > p.paidAt + ackWindow;
    }

    /*//////////////////////////////////////////////////////////////
                                 INTERNAL
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Records a stablecoin payment and transfers the tokens from the caller to the payee.
     * @param orgId Paying company.
     * @param payeeId Payee.
     * @param payeeWallet Payee wallet (ignored for salaries).
     * @param category What the payment is for.
     * @param token Settlement token.
     * @param amount Amount, in token units.
     * @param paymentRef Hashed payment reference.
     * @return paymentId New payment id.
     */
    function _payStablecoin(
        bytes32 orgId,
        bytes32 payeeId,
        address payeeWallet,
        WorkforceLib.PaymentCategory category,
        IERC20 token,
        uint256 amount,
        bytes32 paymentRef
    ) private returns (uint256 paymentId) {
        if (amount == 0) revert WorkforceLib.WorkforceManager__InvalidAmount();
        bytes32 currency = currencies.currencyOf(token); // reverts unless a settlement token
        address wallet = _payeeWallet(orgId, category, payeeId, payeeWallet);
        if (wallet == address(0)) revert WorkforceLib.WorkforceManager__NoWallet(payeeId);

        uint256 usdValue;
        try currencies.tokenToUsd(token, amount) returns (uint256 v) {
            usdValue = v;
        } catch {}

        WorkforceLib.PaymentInput memory p = WorkforceLib.PaymentInput({
            payeeId: payeeId,
            payeeWallet: wallet,
            category: category,
            method: WorkforceLib.PaymentMethod.Stablecoin,
            currency: currency,
            amount: amount,
            paymentRef: paymentRef,
            receiptHash: bytes32(0)
        });
        paymentId = _record(orgId, p, wallet, currency, usdValue);
        token.safeTransferFrom(msg.sender, wallet, amount);
    }

    /**
     * @dev Stores a payment, updates the company report and emits the events.
     * @param orgId Paying company.
     * @param p The payment.
     * @param wallet Payee wallet.
     * @param currency Currency code.
     * @param usdValue USD value, 6 decimals.
     * @return paymentId New payment id.
     */
    function _record(
        bytes32 orgId,
        WorkforceLib.PaymentInput memory p,
        address wallet,
        bytes32 currency,
        uint256 usdValue
    ) private returns (uint256 paymentId) {
        bool cash = p.method == WorkforceLib.PaymentMethod.Cash;
        bool cashRisk = cash && usdValue > cashLimitUsd;

        paymentId = _nextPaymentId++;
        _payments[paymentId] = WorkforceLib.Payment({
            orgId: orgId,
            payeeId: p.payeeId,
            payeeWallet: wallet,
            category: p.category,
            method: p.method,
            status: cash ? WorkforceLib.PaymentStatus.PendingAck : WorkforceLib.PaymentStatus.Confirmed,
            cashRisk: cashRisk,
            currency: currency,
            amount: p.amount,
            usdValue: usdValue,
            paymentRef: p.paymentRef,
            receiptHash: p.receiptHash,
            recordedBy: msg.sender,
            paidAt: uint64(block.timestamp)
        });

        WorkforceLib.OrgReport storage r = _reports[orgId];
        r.payments += 1;
        r.totalUsd += usdValue;
        r.usdByMethod[uint8(p.method)] += usdValue;
        if (cash) r.cashPendingAck += 1;
        if (cashRisk) r.cashRiskPayments += 1;

        emit WorkforceLib.PaymentRecorded(
            paymentId, orgId, p.payeeId, p.category, p.method, currency, p.amount, usdValue, p.paymentRef
        );
        if (cashRisk) emit WorkforceLib.CashRiskFlagged(paymentId, orgId, usdValue);
    }

    /**
     * @dev The wallet a payment goes to. Salaries go to a registered, active worker of the company and use the
     * worker's wallet; other payments use `given`.
     * @param orgId Paying company.
     * @param category What the payment is for.
     * @param payeeId Payee.
     * @param given Wallet supplied by the caller.
     * @return The payee wallet.
     */
    function _payeeWallet(bytes32 orgId, WorkforceLib.PaymentCategory category, bytes32 payeeId, address given)
        private
        view
        returns (address)
    {
        if (category != WorkforceLib.PaymentCategory.Salary) return given;
        WorkforceLib.Worker storage w = _workers[payeeId];
        if (w.orgId == bytes32(0)) revert WorkforceLib.WorkforceManager__UnknownWorker(payeeId);
        if (w.orgId != orgId) revert WorkforceLib.WorkforceManager__NotYourWorker(payeeId);
        if (!w.active) revert WorkforceLib.WorkforceManager__WorkerInactive(payeeId);
        return w.wallet;
    }

    /**
     * @dev Checks that the caller may change `workerId`: the company account, or staff with `MANAGE_WORKERS` over
     * the worker's site. Staff cannot change themselves or another role holder.
     * @param workerId Worker id.
     * @return w Storage pointer to the worker.
     * @return byStaff True if the caller acts as staff.
     */
    function _manageWorker(bytes32 workerId) private view returns (WorkforceLib.Worker storage w, bool byStaff) {
        w = _workers[workerId];
        if (w.orgId == bytes32(0)) revert WorkforceLib.WorkforceManager__UnknownWorker(workerId);
        bytes32 orgId;
        bytes32 actorWorker;
        (orgId, actorWorker) = _actor(StaffLib.MANAGE_WORKERS, w.siteId);
        if (w.orgId != orgId) revert WorkforceLib.WorkforceManager__NotYourWorker(workerId);
        byStaff = actorWorker != bytes32(0);
        if (byStaff && (actorWorker == workerId || _staff[workerId].roleId != bytes32(0))) {
            revert StaffLib.WorkforceManager__ProtectedWorker(workerId);
        }
    }

    /**
     * @dev The company paying, checking the caller may record or make the payment: for salaries the scope is the
     * worker's site, for other payees the whole company. Staff never pay themselves.
     * @param permission Required staff permission.
     * @param category What the payment is for.
     * @param payeeId Payee.
     * @return orgId Paying company.
     */
    function _payer(uint32 permission, WorkforceLib.PaymentCategory category, bytes32 payeeId)
        private
        view
        returns (bytes32 orgId)
    {
        bool salary = category == WorkforceLib.PaymentCategory.Salary;
        bytes32 actorWorker;
        (orgId, actorWorker) = _actor(permission, salary ? _workers[payeeId].siteId : 0);
        if (actorWorker != bytes32(0) && actorWorker == payeeId) {
            revert StaffLib.WorkforceManager__SelfPayment(payeeId);
        }
    }

    /**
     * @dev The company the caller acts for: the company account itself (`MANAGE_WORKFORCE`, any site), or a worker
     * whose staff role grants `permission` at `siteId` (0 = company-wide).
     * @param permission Required staff permission.
     * @param siteId Site, or 0 for company-wide.
     * @return orgId The company.
     * @return actorWorker The staff member's worker id, or zero for the company account.
     */
    function _actor(uint32 permission, uint256 siteId) private view returns (bytes32 orgId, bytes32 actorWorker) {
        if (registry.isAuthorized(msg.sender, Actions.MANAGE_WORKFORCE)) return (_orgOf(msg.sender), bytes32(0));
        actorWorker = workerOfWallet[msg.sender];
        if (actorWorker == bytes32(0)) revert WorkforceLib.WorkforceManager__Unauthorized(msg.sender);
        orgId = staffOrg(msg.sender, siteId, permission);
        if (orgId == bytes32(0)) revert StaffLib.WorkforceManager__OutOfScope(msg.sender, siteId);
    }

    /**
     * @dev Links a wallet to a worker (no-op for zero), reverting if it belongs to another worker.
     * @param workerId Worker id.
     * @param wallet Wallet.
     */
    function _bindWallet(bytes32 workerId, address wallet) private {
        if (wallet == address(0)) return;
        bytes32 existing = workerOfWallet[wallet];
        if (existing != bytes32(0) && existing != workerId) {
            revert StaffLib.WorkforceManager__WalletInUse(wallet, existing);
        }
        workerOfWallet[wallet] = workerId;
    }

    /**
     * @dev Reverts unless `siteId` is 0 or belongs to `orgId`.
     * @param orgId Company.
     * @param siteId Site.
     */
    function _requireOrgSite(bytes32 orgId, uint256 siteId) private view {
        if (siteId != 0 && sites.orgOfSite(siteId) != orgId) {
            revert WorkforceLib.WorkforceManager__SiteNotOfOrg(siteId);
        }
    }

    /**
     * @dev Returns the payment, reverting if it does not exist.
     * @param paymentId Payment id.
     * @return p Storage pointer to the payment.
     */
    function _requirePayment(uint256 paymentId) private view returns (WorkforceLib.Payment storage p) {
        p = _payments[paymentId];
        if (p.status == WorkforceLib.PaymentStatus.None) {
            revert WorkforceLib.WorkforceManager__UnknownPayment(paymentId);
        }
    }

    /**
     * @dev The caller's organisation, reverting unless it is a company account (`MANAGE_WORKFORCE`).
     * @return orgId The company.
     */
    function _companyOrg() private view returns (bytes32 orgId) {
        if (!registry.isAuthorized(msg.sender, Actions.MANAGE_WORKFORCE)) {
            revert WorkforceLib.WorkforceManager__Unauthorized(msg.sender);
        }
        orgId = _orgOf(msg.sender);
    }

    /**
     * @dev An account's organisation.
     * @param account The account.
     * @return Organisation id.
     */
    function _orgOf(address account) private view returns (bytes32) {
        return registry.participant(account).orgId;
    }
}
