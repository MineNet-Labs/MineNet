// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {IMineNetRegistry} from "src/access/interfaces/IMineNetRegistry.sol";
import {ICurrencyManager} from "src/finance/interfaces/ICurrencyManager.sol";
import {ISiteRegistry} from "src/compliance/interfaces/ISiteRegistry.sol";
import {IWorkforce} from "src/workforce/interfaces/IWorkforce.sol";
import {ISiteOperations} from "src/workforce/interfaces/ISiteOperations.sol";
import {Actions} from "src/access/libraries/Actions.sol";
import {SiteLib} from "src/compliance/libraries/SiteLib.sol";
import {StaffLib} from "src/workforce/libraries/StaffLib.sol";
import {SiteOpsLib} from "src/workforce/libraries/SiteOpsLib.sol";
import {WorkforceLib} from "src/workforce/libraries/WorkforceLib.sol";

/**
 * @title SiteOperations
 * @author 0xEmmyb2
 * @notice How a mine site's supervisors, manager, HR and inspector work with the mining company: shift output is
 * verified by the company's internal inspector before it becomes official, the manager reports on the site, and HR
 * asks for staff and hires once the company approves.
 * @dev The company account (`MANAGE_WORKFORCE` of the site's organisation) appoints each site's manager, HR and
 * inspector in {WorkforceManager} ({WorkforceManager-appointSiteSeat}) and can remove or replace them at any
 * time. Permissions are read through {IStaffDirectory-staffOrg}.
 *
 * Reports (`SUBMIT_REPORTS`) are filed as Pending_Inspection and are informational only (dashboards show them as
 * "Estimated"):
 * - Shift reports: a shift supervisor's end-of-shift extraction log, with a unique shift reference.
 * - Period reports: the manager's site report (tunnels, headcount, incidents, output summary); periods never
 *   overlap.
 * The company's internal inspector (`INSPECT_REPORTS`: the site's traceability officer, or the site manager for
 * reports they did not file) is the maker-checker gate. Verifying a report marks it Approved_Official at once, with
 * no further company review, and records the inspector's employee id and time as the internal quality sign-off
 * (Verified_Internal, distinct from external audits or ITSCI / RMTS tag checks). For a shift report the inspector
 * enters the weighed quantities, which are recorded as the site's extraction
 * ({MineSiteRegistry-recordVerifiedExtraction}): they count toward the licensed ceiling and become official
 * inventory that lots can be registered and tagged from. For a period report the tunnel changes go on record.
 *
 * Hiring (`MANAGE_HIRING`, the HR, who deals with the company directly):
 * 1. HR files a staffing request: job title, workers available, people needed, daily rate or monthly salary, pay
 *    frequency and one-off onboarding cost per person.
 * 2. The company approves it (possibly for fewer people) or rejects it. HR cannot hire without this approval.
 * 3. HR opens the job advert, then submits each person hired with their signed contract.
 * 4. The company approves or rejects each hire: the worker is onboarded in {WorkforceManager} and the site's
 *    estimated monthly budget moves the pay from planned to committed.
 * 5. The company ends an employment (HR can ask it to); {PayrollEngine} settles the final period.
 * Nobody decides or inspects what they filed themselves. Pay itself is computed and paid by {PayrollEngine}.
 */
contract SiteOperations is ISiteOperations {
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
     * @dev Last report id; ids start at 1.
     */
    uint256 private _reportCount;

    /**
     * @dev Last position id; ids start at 1.
     */
    uint256 private _positionCount;

    /**
     * @dev Last hire id; ids start at 1.
     */
    uint256 private _hireCount;

    /**
     * @dev Report id => report.
     */
    mapping(uint256 reportId => SiteOpsLib.Report) private _reports;

    /**
     * @dev Report id => output per mineral.
     */
    mapping(uint256 reportId => SiteOpsLib.MineralOutput[]) private _outputs;

    /**
     * @dev Report id => tunnel updates.
     */
    mapping(uint256 reportId => SiteOpsLib.TunnelUpdate[]) private _tunnelUpdates;

    /**
     * @dev Site => its report ids, in filing order.
     */
    mapping(uint256 siteId => uint256[]) private _reportsOf;

    /**
     * @notice End of the latest accepted period report of a site; new period reports start at or after it.
     */
    mapping(uint256 siteId => uint64) public reportedUntil;

    /**
     * @notice Output of a mineral at a site, summed over accepted period reports, in grams (summary).
     */
    mapping(uint256 siteId => mapping(bytes32 mineralType => uint256)) public reportedOutput;

    /**
     * @dev Site => tunnel id => confirmed state.
     */
    mapping(uint256 siteId => mapping(bytes32 tunnelId => SiteOpsLib.Tunnel)) private _tunnels;

    /**
     * @dev Site => its tunnel ids, in order of first acceptance.
     */
    mapping(uint256 siteId => bytes32[]) private _tunnelsOf;

    /**
     * @dev Site => tunnel state => number of tunnels in it.
     */
    mapping(uint256 siteId => mapping(SiteOpsLib.TunnelStatus => uint256)) private _tunnelCount;

    /**
     * @dev Position id => position.
     */
    mapping(uint256 positionId => SiteOpsLib.Position) private _positions;

    /**
     * @dev Site => its position ids.
     */
    mapping(uint256 siteId => uint256[]) private _positionsOf;

    /**
     * @dev Hire id => hire.
     */
    mapping(uint256 hireId => SiteOpsLib.Hire) private _hires;

    /**
     * @dev Position id => its hire ids.
     */
    mapping(uint256 positionId => uint256[]) private _hiresOf;

    /**
     * @notice A worker's latest hire (pending, active or finished; zero = none).
     */
    mapping(bytes32 workerId => uint256 hireId) public override hireOf;

    /**
     * @dev Site => currency => budget.
     */
    mapping(uint256 siteId => mapping(bytes32 currency => SiteOpsLib.Budget)) private _budgets;

    /**
     * @dev Site => currencies its budget uses.
     */
    mapping(uint256 siteId => bytes32[]) private _budgetCurrencies;

    /**
     * @notice Whether a shift reference was already reported at a site.
     */
    mapping(uint256 siteId => mapping(bytes32 shiftRef => bool)) public shiftReported;

    /**
     * @notice Inspector-verified output of a mineral at a site from shift reports, in grams (official).
     */
    mapping(uint256 siteId => mapping(bytes32 mineralType => uint256)) public verifiedOutput;

    /**
     * @dev Report id => verified weight per output (shift reports).
     */
    mapping(uint256 reportId => uint128[]) private _verified;

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @param registry_ Participant, role and permission registry.
     * @param sites_ Mine site registry.
     * @param workforce_ Workforce manager.
     * @param currencies_ Currency manager.
     */
    constructor(IMineNetRegistry registry_, ISiteRegistry sites_, IWorkforce workforce_, ICurrencyManager currencies_) {
        registry = registry_;
        sites = sites_;
        workforce = workforce_;
        currencies = currencies_;
    }

    /*//////////////////////////////////////////////////////////////
                    FILERS AND INSPECTOR: REPORTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Files a shift or period report, Pending_Inspection (informational only).
     * @dev Staff with `SUBMIT_REPORTS` at the site (shift supervisors, the manager). The site must be active or
     * dormant. A shift report needs a new shift reference and no tunnel changes; a period report must start at or
     * after {reportedUntil}. The end is never in the future.
     * @param siteId Mine site.
     * @param r The report.
     * @return reportId New report id.
     * @custom:emits ReportSubmitted
     */
    function submitReport(uint256 siteId, SiteOpsLib.ReportInput calldata r) external returns (uint256 reportId) {
        if (r.periodEnd <= r.periodStart || r.periodEnd > block.timestamp) {
            revert SiteOpsLib.SiteOperations__InvalidPeriod();
        }
        if (r.outputs.length > SiteOpsLib.MAX_REPORT_ITEMS || r.tunnels.length > SiteOpsLib.MAX_REPORT_ITEMS) {
            revert SiteOpsLib.SiteOperations__InvalidReportItems();
        }
        bool shift = r.kind == SiteOpsLib.ReportKind.Shift;
        if (shift && (r.shiftRef == bytes32(0) || r.tunnels.length != 0)) {
            revert SiteOpsLib.SiteOperations__InvalidReportItems();
        }
        _onlyStaff(siteId, StaffLib.SUBMIT_REPORTS);
        SiteLib.SiteStatus status = sites.getSite(siteId).status;
        if (status != SiteLib.SiteStatus.Active && status != SiteLib.SiteStatus.Dormant) {
            revert SiteOpsLib.SiteOperations__SiteNotOperating(siteId);
        }
        if (shift) {
            if (shiftReported[siteId][r.shiftRef]) revert SiteOpsLib.SiteOperations__DuplicateShift(r.shiftRef);
            shiftReported[siteId][r.shiftRef] = true;
        } else if (r.periodStart < reportedUntil[siteId]) {
            revert SiteOpsLib.SiteOperations__InvalidPeriod();
        }

        reportId = ++_reportCount;
        SiteOpsLib.Report storage rep = _reports[reportId];
        rep.siteId = siteId;
        rep.submittedBy = msg.sender;
        rep.periodStart = r.periodStart;
        rep.status = SiteOpsLib.ReportStatus.Submitted;
        rep.kind = r.kind;
        rep.periodEnd = r.periodEnd;
        rep.submittedAt = uint64(block.timestamp);
        rep.workersOnSite = r.workersOnSite;
        rep.incidents = r.incidents;
        rep.shiftRef = r.shiftRef;
        rep.reportHash = r.reportHash;
        for (uint256 i; i < r.outputs.length; ++i) {
            if (r.outputs[i].mineralType == bytes32(0)) revert SiteOpsLib.SiteOperations__InvalidReportItems();
            _outputs[reportId].push(r.outputs[i]);
        }
        for (uint256 i; i < r.tunnels.length; ++i) {
            SiteOpsLib.TunnelUpdate calldata u = r.tunnels[i];
            if (u.tunnelId == bytes32(0) || u.status == SiteOpsLib.TunnelStatus.None) {
                revert SiteOpsLib.SiteOperations__InvalidReportItems();
            }
            _tunnelUpdates[reportId].push(u);
        }
        _reportsOf[siteId].push(reportId);
        emit SiteOpsLib.ReportSubmitted(reportId, siteId, msg.sender, r.kind, r.periodStart, r.periodEnd, r.reportHash);
    }

    /**
     * @notice The company's internal inspector checks a report. Verifying it marks it Approved_Official at once,
     * with no further company review: for a shift report the weighed quantities become the site's recorded
     * extraction (counting toward the licensed ceiling) and official inventory; for a period report the tunnel
     * changes go on record. A report found inaccurate is rejected.
     * @dev Staff with `INSPECT_REPORTS` at the site (its inspector, or the manager), not the report's filer. The
     * inspector's wallet, employee id and the time are stored as the internal quality sign-off. Verifying reverts
     * if the site cannot produce, the ceiling would be exceeded, a tunnel is already closed or a period report now
     * overlaps an accepted one (reject it instead).
     * @param reportId A submitted report.
     * @param truthful True if the information is verified.
     * @param verifiedQuantities Weighed quantity per output, in report order (shift reports when verified; empty
     * otherwise).
     * @param findingsHash Hash of the inspection findings (weighbridge tickets, photos, notes).
     * @custom:emits ReportInspected
     * @custom:emits OutputVerified and ExtractionRecorded in {MineSiteRegistry} (verified shift report)
     * @custom:emits TunnelStatusChanged (verified period report)
     */
    function inspectReport(uint256 reportId, bool truthful, uint128[] calldata verifiedQuantities, bytes32 findingsHash)
        external
    {
        SiteOpsLib.Report storage rep = _reports[reportId];
        if (rep.status != SiteOpsLib.ReportStatus.Submitted) revert SiteOpsLib.SiteOperations__InvalidReport(reportId);
        uint256 siteId = rep.siteId;
        _onlyStaff(siteId, StaffLib.INSPECT_REPORTS);
        if (msg.sender == rep.submittedBy) revert SiteOpsLib.SiteOperations__SelfApproval(msg.sender);
        bool shift = rep.kind == SiteOpsLib.ReportKind.Shift;
        SiteOpsLib.MineralOutput[] storage outs = _outputs[reportId];
        if (verifiedQuantities.length != (truthful && shift ? outs.length : 0)) {
            revert SiteOpsLib.SiteOperations__InvalidReportItems();
        }

        bytes32 inspectorId = workforce.workerOfWallet(msg.sender);
        rep.inspectedAt = uint64(block.timestamp);
        rep.inspectedBy = msg.sender;
        rep.inspectorId = inspectorId;
        rep.findingsHash = findingsHash;
        emit SiteOpsLib.ReportInspected(reportId, truthful, msg.sender, inspectorId, findingsHash);
        if (!truthful) {
            rep.status = SiteOpsLib.ReportStatus.Rejected;
            return;
        }
        rep.status = SiteOpsLib.ReportStatus.Accepted;

        if (shift) {
            bytes32 evidence = keccak256(abi.encode(reportId, findingsHash));
            for (uint256 i; i < outs.length; ++i) {
                uint128 qty = verifiedQuantities[i];
                bytes32 mineral = outs[i].mineralType;
                _verified[reportId].push(qty);
                emit SiteOpsLib.OutputVerified(reportId, siteId, mineral, outs[i].quantity, qty);
                if (qty == 0) continue;
                verifiedOutput[siteId][mineral] += qty;
                sites.recordVerifiedExtraction(siteId, mineral, qty, evidence, msg.sender);
            }
            return;
        }
        if (rep.periodStart < reportedUntil[siteId]) revert SiteOpsLib.SiteOperations__InvalidPeriod();
        reportedUntil[siteId] = rep.periodEnd;
        for (uint256 i; i < outs.length; ++i) {
            reportedOutput[siteId][outs[i].mineralType] += outs[i].quantity;
        }
        SiteOpsLib.TunnelUpdate[] storage ups = _tunnelUpdates[reportId];
        for (uint256 i; i < ups.length; ++i) {
            _applyTunnel(siteId, reportId, ups[i].tunnelId, ups[i].status);
        }
    }

    /*//////////////////////////////////////////////////////////////
                             SITE HR: HIRING
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Files a staffing request with the company: workers available and needed for a job, and its pay.
     * @dev Staff with `MANAGE_HIRING` at the site (its HR), directly to the company. The site must be active.
     * @param siteId Mine site.
     * @param p The request.
     * @return positionId New position id.
     * @custom:emits PositionRequested
     */
    function requestPosition(uint256 siteId, SiteOpsLib.PositionInput calldata p)
        external
        returns (uint256 positionId)
    {
        if (p.title == bytes32(0) || p.headcount == 0 || p.headcount > SiteOpsLib.MAX_HEADCOUNT || p.rate == 0) {
            revert SiteOpsLib.SiteOperations__InvalidPosition();
        }
        _onlyStaff(siteId, StaffLib.MANAGE_HIRING);
        _requireActiveSite(siteId);
        if (!currencies.isCurrency(p.currency)) revert SiteOpsLib.SiteOperations__InvalidPosition();

        positionId = ++_positionCount;
        _positions[positionId] = SiteOpsLib.Position({
            siteId: siteId,
            title: p.title,
            currency: p.currency,
            rate: p.rate,
            onboardingCost: p.onboardingCost,
            requestedBy: msg.sender,
            available: p.available,
            headcount: p.headcount,
            filled: 0,
            pending: 0,
            status: SiteOpsLib.PositionStatus.Requested,
            basis: p.basis,
            frequency: p.frequency,
            advertClosesAt: 0,
            requirementsHash: p.requirementsHash,
            advertHash: bytes32(0)
        });
        _positionsOf[siteId].push(positionId);
        emit SiteOpsLib.PositionRequested(positionId, siteId, p.title, p.available, p.headcount, p.basis, p.rate);
    }

    /**
     * @notice Opens the job advert of an approved position, so hires can be submitted.
     * @dev Staff with `MANAGE_HIRING` at the position's site.
     * @param positionId An approved position.
     * @param closesAt Closing date shown to candidates; 0 for open-ended, otherwise in the future.
     * @param advertHash Hash of the published advert.
     * @custom:emits VacancyOpened
     */
    function openVacancy(uint256 positionId, uint64 closesAt, bytes32 advertHash) external {
        SiteOpsLib.Position storage pos = _requirePosition(positionId, SiteOpsLib.PositionStatus.Approved);
        _onlyStaff(pos.siteId, StaffLib.MANAGE_HIRING);
        if (closesAt != 0 && closesAt <= block.timestamp) revert SiteOpsLib.SiteOperations__InvalidPeriod();
        pos.status = SiteOpsLib.PositionStatus.Open;
        pos.advertClosesAt = closesAt;
        pos.advertHash = advertHash;
        emit SiteOpsLib.VacancyOpened(positionId, closesAt, advertHash);
    }

    /**
     * @notice Submits a person hired for an open position, for the company's approval.
     * @dev Staff with `MANAGE_HIRING` at the position's site. The worker is new (with a wallet to be paid in),
     * or an existing worker of the company with a wallet and no pending or active hire.
     * @param positionId An open position with a free slot.
     * @param workerId Opaque, salted worker id; non-zero.
     * @param wallet Wallet of a new worker (ignored for an existing worker, who keeps theirs).
     * @param contractHash Hash of the signed employment contract.
     * @return hireId New hire id.
     * @custom:emits HireSubmitted
     */
    function submitHire(uint256 positionId, bytes32 workerId, address wallet, bytes32 contractHash)
        external
        returns (uint256 hireId)
    {
        if (workerId == bytes32(0)) revert SiteOpsLib.SiteOperations__InvalidWorker(workerId);
        SiteOpsLib.Position storage pos = _requirePosition(positionId, SiteOpsLib.PositionStatus.Open);
        bytes32 orgId = _onlyStaff(pos.siteId, StaffLib.MANAGE_HIRING);
        if (pos.filled + pos.pending >= pos.headcount) revert SiteOpsLib.SiteOperations__NoOpenSlot(positionId);
        WorkforceLib.Worker memory existing = workforce.getWorker(workerId);
        if (existing.orgId != bytes32(0)) {
            if (existing.orgId != orgId) revert SiteOpsLib.SiteOperations__InvalidWorker(workerId);
            wallet = existing.wallet;
        }
        if (wallet == address(0)) revert SiteOpsLib.SiteOperations__InvalidWorker(workerId);
        uint256 previous = hireOf[workerId];
        if (previous != 0) {
            SiteOpsLib.HireStatus s = _hires[previous].status;
            if (s == SiteOpsLib.HireStatus.Pending || s == SiteOpsLib.HireStatus.Active) {
                revert SiteOpsLib.SiteOperations__AlreadyHired(workerId, previous);
            }
        }

        pos.pending += 1;
        hireId = ++_hireCount;
        SiteOpsLib.Hire storage h = _hires[hireId];
        h.positionId = positionId;
        h.workerId = workerId;
        h.wallet = wallet;
        h.status = SiteOpsLib.HireStatus.Pending;
        h.submittedBy = msg.sender;
        h.contractHash = contractHash;
        _hiresOf[positionId].push(hireId);
        hireOf[workerId] = hireId;
        emit SiteOpsLib.HireSubmitted(hireId, positionId, workerId, msg.sender, contractHash);
    }

    /**
     * @notice Asks the company to end an employment.
     * @dev Staff with `MANAGE_HIRING` at the hire's site. The company ends it with {endEmployment}.
     * @param hireId An active hire.
     * @param reasonHash Hash of the reason.
     * @custom:emits TerminationRequested
     */
    function requestTermination(uint256 hireId, bytes32 reasonHash) external {
        (, SiteOpsLib.Position storage pos) = _requireHire(hireId, SiteOpsLib.HireStatus.Active);
        _onlyStaff(pos.siteId, StaffLib.MANAGE_HIRING);
        emit SiteOpsLib.TerminationRequested(hireId, msg.sender, reasonHash);
    }

    /**
     * @notice Closes a position before it is filled, releasing its unfilled slots from the planned budget.
     * @dev The company, or staff with `MANAGE_HIRING` at the site. No hire may be waiting for approval.
     * @param positionId An approved or open position.
     * @param reasonHash Hash of the reason.
     * @custom:emits PositionClosed
     * @custom:emits BudgetUpdated
     */
    function closePosition(uint256 positionId, bytes32 reasonHash) external {
        SiteOpsLib.Position storage pos = _positions[positionId];
        SiteOpsLib.PositionStatus status = pos.status;
        if (status != SiteOpsLib.PositionStatus.Approved && status != SiteOpsLib.PositionStatus.Open) {
            revert SiteOpsLib.SiteOperations__InvalidPositionStatus(positionId, status);
        }
        uint256 siteId = pos.siteId;
        if (!_isCompany(siteId)) _onlyStaff(siteId, StaffLib.MANAGE_HIRING);
        if (pos.pending != 0) revert SiteOpsLib.SiteOperations__HiresPending(positionId);

        uint32 released = pos.headcount - pos.filled;
        pos.status = SiteOpsLib.PositionStatus.Closed;
        SiteOpsLib.Budget storage b = _budgets[siteId][pos.currency];
        b.plannedMonthlyPayroll -= uint128(released) * SiteOpsLib.monthlyCost(pos.basis, pos.rate);
        emit SiteOpsLib.PositionClosed(positionId, released, msg.sender, reasonHash);
        _emitBudget(siteId, pos.currency, b);
    }

    /*//////////////////////////////////////////////////////////////
                           COMPANY: DECISIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Approves a staffing request (possibly for fewer people) or rejects it. Without approval HR cannot
     * advertise or hire.
     * @dev The site's company account, not the requester. Approved slots enter the site's planned payroll.
     * @param positionId A requested position.
     * @param approvedHeadcount People approved, at most the requested headcount; 0 rejects the request.
     * @param noteHash Hash of the decision note.
     * @custom:emits PositionDecided
     * @custom:emits BudgetUpdated (on approval)
     */
    function decidePosition(uint256 positionId, uint32 approvedHeadcount, bytes32 noteHash) external {
        SiteOpsLib.Position storage pos = _requirePosition(positionId, SiteOpsLib.PositionStatus.Requested);
        uint256 siteId = pos.siteId;
        _onlyCompany(siteId, pos.requestedBy);
        if (approvedHeadcount > pos.headcount) revert SiteOpsLib.SiteOperations__InvalidPosition();
        emit SiteOpsLib.PositionDecided(positionId, approvedHeadcount, msg.sender, noteHash);
        if (approvedHeadcount == 0) {
            pos.status = SiteOpsLib.PositionStatus.Rejected;
            return;
        }
        pos.status = SiteOpsLib.PositionStatus.Approved;
        pos.headcount = approvedHeadcount;
        bytes32 currency = pos.currency;
        SiteOpsLib.Budget storage b = _budget(siteId, currency);
        b.plannedMonthlyPayroll += uint128(approvedHeadcount) * SiteOpsLib.monthlyCost(pos.basis, pos.rate);
        _emitBudget(siteId, currency, b);
    }

    /**
     * @notice Approves or rejects a hire. On approval the worker is onboarded in {WorkforceManager} and the site
     * budget is updated automatically: the wage moves from planned to committed and the onboarding cost is added.
     * @dev The site's company account, not the hire's submitter. Pay starts today. The position becomes `Filled`
     * with its last slot.
     * @param hireId A pending hire.
     * @param approve True to approve.
     * @param noteHash Hash of the decision note.
     * @custom:emits HireDecided
     * @custom:emits BudgetUpdated (on approval)
     * @custom:emits WorkerRegistered or WorkerStatusChanged / WorkerAssigned in {WorkforceManager} (on approval)
     */
    function decideHire(uint256 hireId, bool approve, bytes32 noteHash) external {
        (SiteOpsLib.Hire storage h, SiteOpsLib.Position storage pos) =
            _requireHire(hireId, SiteOpsLib.HireStatus.Pending);
        uint256 siteId = pos.siteId;
        bytes32 orgId = _onlyCompany(siteId, h.submittedBy);
        pos.pending -= 1;
        emit SiteOpsLib.HireDecided(hireId, approve, msg.sender, noteHash);
        if (!approve) {
            h.status = SiteOpsLib.HireStatus.Rejected;
            return;
        }

        h.status = SiteOpsLib.HireStatus.Active;
        h.startDay = uint64(block.timestamp / 1 days);
        pos.filled += 1;
        if (pos.filled == pos.headcount) pos.status = SiteOpsLib.PositionStatus.Filled;

        bytes32 currency = pos.currency;
        uint128 monthly = SiteOpsLib.monthlyCost(pos.basis, pos.rate);
        SiteOpsLib.Budget storage b = _budgets[siteId][currency];
        b.headcount += 1;
        b.monthlyPayroll += monthly;
        b.plannedMonthlyPayroll -= monthly;
        b.onboardingCosts += pos.onboardingCost;
        _emitBudget(siteId, currency, b);

        workforce.onboardWorker(orgId, h.workerId, h.wallet, siteId);
    }

    /**
     * @notice Ends an employment: the pay leaves the site budget and the worker is deactivated. {PayrollEngine}
     * settles the final, partial period up to today.
     * @dev The site's company account.
     * @param hireId An active hire.
     * @param reasonHash Hash of the reason.
     * @custom:emits EmploymentEnded
     * @custom:emits BudgetUpdated
     * @custom:emits WorkerStatusChanged in {WorkforceManager}
     */
    function endEmployment(uint256 hireId, bytes32 reasonHash) external {
        (SiteOpsLib.Hire storage h, SiteOpsLib.Position storage pos) =
            _requireHire(hireId, SiteOpsLib.HireStatus.Active);
        uint256 siteId = pos.siteId;
        _onlyCompany(siteId, address(0));

        h.status = SiteOpsLib.HireStatus.Ended;
        h.endDay = uint64(block.timestamp / 1 days);
        bytes32 currency = pos.currency;
        SiteOpsLib.Budget storage b = _budgets[siteId][currency];
        b.headcount -= 1;
        b.monthlyPayroll -= SiteOpsLib.monthlyCost(pos.basis, pos.rate);
        emit SiteOpsLib.EmploymentEnded(hireId, msg.sender, reasonHash);
        _emitBudget(siteId, currency, b);

        workforce.offboardWorker(h.workerId);
    }

    /*//////////////////////////////////////////////////////////////
                                  VIEWS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns a report.
     * @param reportId Report id.
     * @return The report (status `None` if unknown).
     */
    function getReport(uint256 reportId) external view returns (SiteOpsLib.Report memory) {
        return _reports[reportId];
    }

    /**
     * @notice Output per mineral filed in a report.
     * @param reportId Report id.
     * @return The outputs.
     */
    function reportOutputs(uint256 reportId) external view returns (SiteOpsLib.MineralOutput[] memory) {
        return _outputs[reportId];
    }

    /**
     * @notice Weighed quantity per output of a verified shift report, in output order.
     * @param reportId Report id.
     * @return Verified quantities (empty unless a verified shift report).
     */
    function reportVerified(uint256 reportId) external view returns (uint128[] memory) {
        return _verified[reportId];
    }

    /**
     * @notice Tunnel updates filed in a report.
     * @param reportId Report id.
     * @return The updates.
     */
    function reportTunnels(uint256 reportId) external view returns (SiteOpsLib.TunnelUpdate[] memory) {
        return _tunnelUpdates[reportId];
    }

    /**
     * @notice A site's reports, in filing order.
     * @param siteId Site.
     * @return Report ids.
     */
    function reportsOf(uint256 siteId) external view returns (uint256[] memory) {
        return _reportsOf[siteId];
    }

    /**
     * @notice A tunnel's confirmed state.
     * @param siteId Site.
     * @param tunnelId Tunnel id.
     * @return The tunnel (status `None` if never reported).
     */
    function getTunnel(uint256 siteId, bytes32 tunnelId) external view returns (SiteOpsLib.Tunnel memory) {
        return _tunnels[siteId][tunnelId];
    }

    /**
     * @notice A site's tunnels, in order of first acceptance.
     * @param siteId Site.
     * @return Tunnel ids.
     */
    function tunnelsOf(uint256 siteId) external view returns (bytes32[] memory) {
        return _tunnelsOf[siteId];
    }

    /**
     * @notice How many of a site's tunnels are active, inactive and closed.
     * @param siteId Site.
     * @return active Active tunnels.
     * @return inactive Inactive tunnels.
     * @return closed Closed tunnels.
     */
    function tunnelCounts(uint256 siteId) external view returns (uint256 active, uint256 inactive, uint256 closed) {
        active = _tunnelCount[siteId][SiteOpsLib.TunnelStatus.Active];
        inactive = _tunnelCount[siteId][SiteOpsLib.TunnelStatus.Inactive];
        closed = _tunnelCount[siteId][SiteOpsLib.TunnelStatus.Closed];
    }

    /**
     * @notice Returns a position.
     * @param positionId Position id.
     * @return The position (status `None` if unknown).
     */
    function getPosition(uint256 positionId) external view override returns (SiteOpsLib.Position memory) {
        return _positions[positionId];
    }

    /**
     * @notice A site's positions, in request order.
     * @param siteId Site.
     * @return Position ids.
     */
    function positionsOf(uint256 siteId) external view returns (uint256[] memory) {
        return _positionsOf[siteId];
    }

    /**
     * @notice Returns a hire.
     * @param hireId Hire id.
     * @return The hire (status `None` if unknown).
     */
    function getHire(uint256 hireId) external view override returns (SiteOpsLib.Hire memory) {
        return _hires[hireId];
    }

    /**
     * @notice A position's hires, in submission order.
     * @param positionId Position id.
     * @return Hire ids.
     */
    function hiresOf(uint256 positionId) external view returns (uint256[] memory) {
        return _hiresOf[positionId];
    }

    /**
     * @notice A site's budget in one currency.
     * @param siteId Site.
     * @param currency Currency code.
     * @return The budget.
     */
    function budgetOf(uint256 siteId, bytes32 currency) external view returns (SiteOpsLib.Budget memory) {
        return _budgets[siteId][currency];
    }

    /**
     * @notice Currencies a site's budget uses.
     * @param siteId Site.
     * @return Currency codes.
     */
    function budgetCurrencies(uint256 siteId) external view returns (bytes32[] memory) {
        return _budgetCurrencies[siteId];
    }

    /*//////////////////////////////////////////////////////////////
                    INTERNAL STATE-CHANGING FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Applies one accepted tunnel update and keeps the per-state counts.
     * @param siteId Site.
     * @param reportId Accepted report.
     * @param tunnelId Tunnel.
     * @param to New state.
     */
    function _applyTunnel(uint256 siteId, uint256 reportId, bytes32 tunnelId, SiteOpsLib.TunnelStatus to) private {
        SiteOpsLib.Tunnel storage t = _tunnels[siteId][tunnelId];
        SiteOpsLib.TunnelStatus from = t.status;
        if (from == SiteOpsLib.TunnelStatus.Closed) revert SiteOpsLib.SiteOperations__TunnelClosed(tunnelId);
        if (from == SiteOpsLib.TunnelStatus.None) _tunnelsOf[siteId].push(tunnelId);
        else _tunnelCount[siteId][from] -= 1;
        _tunnelCount[siteId][to] += 1;
        t.status = to;
        t.updatedAt = uint64(block.timestamp);
        t.reportId = reportId;
        emit SiteOpsLib.TunnelStatusChanged(siteId, tunnelId, from, to, reportId);
    }

    /**
     * @dev A site's budget in `currency`, registering the currency on first use.
     * @param siteId Site.
     * @param currency Currency code.
     * @return b Storage pointer to the budget.
     */
    function _budget(uint256 siteId, bytes32 currency) private returns (SiteOpsLib.Budget storage b) {
        b = _budgets[siteId][currency];
        if (b.headcount == 0 && b.monthlyPayroll == 0 && b.plannedMonthlyPayroll == 0 && b.onboardingCosts == 0) {
            bytes32[] storage list = _budgetCurrencies[siteId];
            for (uint256 i; i < list.length; ++i) {
                if (list[i] == currency) return b;
            }
            list.push(currency);
        }
    }

    /**
     * @dev Emits the current state of a budget.
     * @param siteId Site.
     * @param currency Currency code.
     * @param b The budget.
     */
    function _emitBudget(uint256 siteId, bytes32 currency, SiteOpsLib.Budget storage b) private {
        emit SiteOpsLib.BudgetUpdated(
            siteId, currency, b.headcount, b.monthlyPayroll, b.plannedMonthlyPayroll, b.onboardingCosts
        );
    }

    /*//////////////////////////////////////////////////////////////
                     INTERNAL READ-ONLY FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Returns a position, reverting unless it is in `expected` state.
     * @param positionId Position id.
     * @param expected Required state.
     * @return pos Storage pointer to the position.
     */
    function _requirePosition(uint256 positionId, SiteOpsLib.PositionStatus expected)
        private
        view
        returns (SiteOpsLib.Position storage pos)
    {
        pos = _positions[positionId];
        if (pos.status != expected) revert SiteOpsLib.SiteOperations__InvalidPositionStatus(positionId, pos.status);
    }

    /**
     * @dev Returns a hire and its position, reverting unless the hire is in `expected` state.
     * @param hireId Hire id.
     * @param expected Required state.
     * @return h Storage pointer to the hire.
     * @return pos Storage pointer to its position.
     */
    function _requireHire(uint256 hireId, SiteOpsLib.HireStatus expected)
        private
        view
        returns (SiteOpsLib.Hire storage h, SiteOpsLib.Position storage pos)
    {
        h = _hires[hireId];
        if (h.status != expected) revert SiteOpsLib.SiteOperations__InvalidHireStatus(hireId, h.status);
        pos = _positions[h.positionId];
    }

    /**
     * @dev Reverts unless the site is active.
     * @param siteId Site.
     */
    function _requireActiveSite(uint256 siteId) private view {
        if (sites.getSite(siteId).status != SiteLib.SiteStatus.Active) {
            revert SiteOpsLib.SiteOperations__SiteNotOperating(siteId);
        }
    }

    /**
     * @dev The site's company, reverting unless the caller is its company account and not `filer`.
     * @param siteId Site.
     * @param filer Account that filed the request being decided (zero = none).
     * @return orgId The company.
     */
    function _onlyCompany(uint256 siteId, address filer) private view returns (bytes32 orgId) {
        if (!_isCompany(siteId)) revert SiteOpsLib.SiteOperations__NotCompany(msg.sender, siteId);
        if (msg.sender == filer) revert SiteOpsLib.SiteOperations__SelfApproval(msg.sender);
        orgId = sites.orgOfSite(siteId);
    }

    /**
     * @dev The site's company, reverting unless the caller is its staff holding `permission` there.
     * @param siteId Site.
     * @param permission Required staff permission ({StaffLib}).
     * @return orgId The company.
     */
    function _onlyStaff(uint256 siteId, uint32 permission) private view returns (bytes32 orgId) {
        orgId = sites.orgOfSite(siteId);
        if (orgId == bytes32(0) || workforce.staffOrg(msg.sender, siteId, permission) != orgId) {
            revert SiteOpsLib.SiteOperations__NotSiteStaff(msg.sender, siteId);
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
