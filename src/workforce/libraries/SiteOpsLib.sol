// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

/**
 * @title SiteOpsLib
 * @author 0xEmmyb2
 * @notice Shared types, events and custom errors of {SiteOperations}: shift and period reports with their internal
 * inspection, tunnels, staffing requests, job adverts, hires and the site budget.
 */
library SiteOpsLib {
    /*//////////////////////////////////////////////////////////////
                                  ENUMS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice State of a site report.
     */
    enum ReportStatus {
        // Unknown report id.
        None,
        // Pending_Inspection: filed, informational only (shown as "Estimated"); nothing is official yet.
        Submitted,
        // Approved_Official: verified by the company's inspector (Verified_Internal) and on record.
        Accepted,
        // Found inaccurate by the inspector; a corrected report is filed.
        Rejected
    }

    /**
     * @notice What a report covers.
     */
    enum ReportKind {
        // The manager's site report for a period: tunnels, headcount, incidents, output summary.
        Period,
        // A shift supervisor's end-of-shift extraction log. Once inspected and weighed, its verified output counts
        // toward the site's extraction (and licensed ceiling) and becomes official inventory.
        Shift
    }

    /**
     * @notice State of a tunnel (shaft, adit or pit) at a site.
     */
    enum TunnelStatus {
        // Unknown tunnel.
        None,
        // Being worked.
        Active,
        // Temporarily not worked (flooded, unsafe, exhausted for now); can be reactivated.
        Inactive,
        // Permanently closed and sealed. Terminal.
        Closed
    }

    /**
     * @notice Lifecycle of a position (a job the site needs filled).
     */
    enum PositionStatus {
        // Unknown position id.
        None,
        // Requested by HR, waiting for the company.
        Requested,
        // Approved by the company (possibly for fewer people); no advert yet.
        Approved,
        // Rejected by the company. Terminal.
        Rejected,
        // Job advert open; HR may submit hires.
        Open,
        // Every approved slot is filled. Terminal.
        Filled,
        // Closed before being filled; remaining slots released. Terminal.
        Closed
    }

    /**
     * @notice Lifecycle of a hire (one person for one position).
     */
    enum HireStatus {
        // Unknown hire id.
        None,
        // Submitted by HR, waiting for the company.
        Pending,
        // Approved: the worker is onboarded, budgeted and paid by {PayrollEngine}.
        Active,
        // Rejected by the company. Terminal.
        Rejected,
        // Employment ended by the company; the final period is still settled by {PayrollEngine}. Terminal.
        Ended
    }

    /**
     * @notice How often a position is paid.
     */
    enum PayFrequency {
        Daily,
        Weekly,
        Biweekly,
        Monthly
    }

    /**
     * @notice How a position's pay is set.
     */
    enum PayBasis {
        // Shift miners (drillers, muckers, timbermen, washers): paid per verified shift at a daily rate.
        Daily,
        // Salaried staff (managers, engineers, geologists, HSE): a fixed monthly salary covering working and rest
        // days; a day of unpaid leave or unexcused absence deducts salary / {WORKDAYS_PER_MONTH}.
        Monthly
    }

    /*//////////////////////////////////////////////////////////////
                                 STRUCTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Output of one mineral.
     * @param mineralType Mineral code (e.g. "CASSITERITE").
     * @param quantity Quantity, in grams (estimated by the filer; the inspector supplies the verified weight).
     */
    struct MineralOutput {
        bytes32 mineralType;
        uint128 quantity;
    }

    /**
     * @notice A tunnel's state as reported (a new tunnel id opens it).
     * @param tunnelId Site-internal tunnel id (e.g. "SHAFT-3").
     * @param status New state; not `None`.
     */
    struct TunnelUpdate {
        bytes32 tunnelId;
        TunnelStatus status;
    }

    /**
     * @notice What a filer submits.
     * @param kind Shift log or period report.
     * @param shiftRef Unique reference of the shift (shift reports; zero for period reports).
     * @param periodStart Start of the shift or period (unix time).
     * @param periodEnd End (unix time); after `periodStart`, not in the future.
     * @param workersOnSite Headcount over the shift or period.
     * @param incidents Safety incidents.
     * @param reportHash Hash of the full off-chain report (shift log, photos, geology notes).
     * @param outputs Output per mineral (at most {MAX_REPORT_ITEMS}).
     * @param tunnels Tunnel changes (period reports only; at most {MAX_REPORT_ITEMS}).
     */
    struct ReportInput {
        ReportKind kind;
        bytes32 shiftRef;
        uint64 periodStart;
        uint64 periodEnd;
        uint32 workersOnSite;
        uint32 incidents;
        bytes32 reportHash;
        MineralOutput[] outputs;
        TunnelUpdate[] tunnels;
    }

    /**
     * @notice A filed report and its internal quality sign-off.
     * @param siteId Mine site.
     * @param submittedBy Supervisor or manager who filed it.
     * @param periodStart Start of the shift or period.
     * @param status Review state.
     * @param kind Shift log or period report.
     * @param periodEnd End of the shift or period.
     * @param submittedAt When it was filed.
     * @param inspectedAt When the inspector signed off (0 = pending).
     * @param workersOnSite Headcount.
     * @param incidents Safety incidents.
     * @param inspectedBy Inspector's wallet (zero = pending).
     * @param inspectorId Inspector's employee (worker) id, for the company's accountability.
     * @param shiftRef Shift reference (shift reports).
     * @param reportHash Hash of the full report.
     * @param findingsHash Hash of the inspector's findings (weighbridge tickets, photos).
     */
    struct Report {
        uint256 siteId;
        address submittedBy;
        uint64 periodStart;
        ReportStatus status;
        ReportKind kind;
        uint64 periodEnd;
        uint64 submittedAt;
        uint64 inspectedAt;
        uint32 workersOnSite;
        uint32 incidents;
        address inspectedBy;
        bytes32 inspectorId;
        bytes32 shiftRef;
        bytes32 reportHash;
        bytes32 findingsHash;
    }

    /**
     * @notice A tunnel's confirmed state.
     * @param status Current state.
     * @param updatedAt When an accepted report last changed it.
     * @param reportId Accepted report that last changed it.
     */
    struct Tunnel {
        TunnelStatus status;
        uint64 updatedAt;
        uint256 reportId;
    }

    /**
     * @notice A staffing request from HR: how many people the site has for a job, how many it needs, and on what
     * terms. The company must approve it before HR can hire.
     * @param title Job title (e.g. "DRILLER"); any title, existing or new.
     * @param available Workers the site already has in this job.
     * @param headcount Additional people needed (1 to {MAX_HEADCOUNT}).
     * @param currency Pricing currency of the pay ({CurrencyManager} code).
     * @param basis Daily rate or monthly salary.
     * @param rate Daily rate or monthly salary, in `currency` units; non-zero.
     * @param onboardingCost One-off cost per person (protective gear, tools, training, medical).
     * @param frequency How often the position is paid.
     * @param requirementsHash Hash of the job description and the staffing report.
     */
    struct PositionInput {
        bytes32 title;
        uint32 available;
        uint32 headcount;
        bytes32 currency;
        PayBasis basis;
        uint128 rate;
        uint128 onboardingCost;
        PayFrequency frequency;
        bytes32 requirementsHash;
    }

    /**
     * @notice A position and how far it is filled.
     * @param siteId Mine site.
     * @param title Job title.
     * @param currency Pricing currency of the pay.
     * @param rate Daily rate or monthly salary.
     * @param onboardingCost One-off cost per person.
     * @param requestedBy HR account that requested it.
     * @param available Workers the site already had in this job when requested.
     * @param headcount Requested headcount, then the approved one.
     * @param filled Approved hires.
     * @param pending Hires waiting for the company.
     * @param status Lifecycle state.
     * @param basis Daily rate or monthly salary.
     * @param frequency How often it is paid.
     * @param advertClosesAt Advert closing date shown to candidates (0 = open-ended).
     * @param requirementsHash Hash of the job description and staffing report.
     * @param advertHash Hash of the published job advert.
     */
    struct Position {
        uint256 siteId;
        bytes32 title;
        bytes32 currency;
        uint128 rate;
        uint128 onboardingCost;
        address requestedBy;
        uint32 available;
        uint32 headcount;
        uint32 filled;
        uint32 pending;
        PositionStatus status;
        PayBasis basis;
        PayFrequency frequency;
        uint64 advertClosesAt;
        bytes32 requirementsHash;
        bytes32 advertHash;
    }

    /**
     * @notice One person hired (or proposed) for a position.
     * @param positionId Position.
     * @param workerId Opaque worker id.
     * @param wallet Wallet given for a new worker.
     * @param status Lifecycle state.
     * @param startDay First day of pay (day of approval; unix time / 1 day).
     * @param endDay Day the employment ended (0 while active); pay runs up to, not including, it.
     * @param submittedBy HR account that submitted the hire.
     * @param contractHash Hash of the signed employment contract.
     */
    struct Hire {
        uint256 positionId;
        bytes32 workerId;
        address wallet;
        HireStatus status;
        uint64 startDay;
        uint64 endDay;
        address submittedBy;
        bytes32 contractHash;
    }

    /**
     * @notice A site's estimated monthly budget in one currency (standard {WORKDAYS_PER_MONTH}-day month), kept up
     * to date automatically as positions and hires are decided. Accrued-to-date pay is in {PayrollEngine}.
     * @param headcount Active hires.
     * @param monthlyPayroll Committed monthly pay of active hires.
     * @param plannedMonthlyPayroll Monthly pay of approved but still unfilled slots.
     * @param onboardingCosts One-off costs of every approved hire so far.
     */
    struct Budget {
        uint32 headcount;
        uint128 monthlyPayroll;
        uint128 plannedMonthlyPayroll;
        uint128 onboardingCosts;
    }

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Maximum outputs or tunnel updates in one report.
     */
    uint256 internal constant MAX_REPORT_ITEMS = 32;

    /**
     * @notice Maximum headcount of one position.
     */
    uint32 internal constant MAX_HEADCOUNT = 1000;

    /**
     * @notice Standard working days in a month, for budgets and salaried day rates.
     */
    uint128 internal constant WORKDAYS_PER_MONTH = 26;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Emitted when a report is filed (Pending_Inspection).
     * @param reportId New report id.
     * @param siteId Mine site.
     * @param by Filer.
     * @param kind Shift log or period report.
     * @param periodStart Start of the shift or period.
     * @param periodEnd End of the shift or period.
     * @param reportHash Hash of the full report.
     */
    event ReportSubmitted(
        uint256 indexed reportId,
        uint256 indexed siteId,
        address indexed by,
        ReportKind kind,
        uint64 periodStart,
        uint64 periodEnd,
        bytes32 reportHash
    );

    /**
     * @notice Emitted when the company's inspector signs a report off (Verified_Internal, distinct from any
     * external regulatory audit or ITSCI / RMTS tag verification) or rejects it.
     * @param reportId Report.
     * @param truthful True if verified (and so Approved_Official).
     * @param inspector Inspector's wallet.
     * @param inspectorId Inspector's employee id.
     * @param findingsHash Hash of the findings.
     */
    event ReportInspected(
        uint256 indexed reportId,
        bool truthful,
        address indexed inspector,
        bytes32 indexed inspectorId,
        bytes32 findingsHash
    );

    /**
     * @notice Emitted per mineral when an inspected shift report's verified weight is put on record as official
     * site output.
     * @param reportId Report.
     * @param siteId Mine site.
     * @param mineralType Mineral.
     * @param estimated Quantity the filer estimated, in grams.
     * @param verified Quantity the inspector weighed, in grams.
     */
    event OutputVerified(
        uint256 indexed reportId,
        uint256 indexed siteId,
        bytes32 indexed mineralType,
        uint128 estimated,
        uint128 verified
    );

    /**
     * @notice Emitted when an accepted report changes a tunnel's state.
     * @param siteId Mine site.
     * @param tunnelId Tunnel.
     * @param from Previous state (`None` = new tunnel).
     * @param to New state.
     * @param reportId Accepted report.
     */
    event TunnelStatusChanged(
        uint256 indexed siteId, bytes32 indexed tunnelId, TunnelStatus from, TunnelStatus to, uint256 indexed reportId
    );

    /**
     * @notice Emitted when HR files a staffing request (a position).
     * @param positionId New position id.
     * @param siteId Mine site.
     * @param title Job title.
     * @param available Workers already in the job.
     * @param headcount People needed.
     * @param basis Daily rate or monthly salary.
     * @param rate The rate.
     */
    event PositionRequested(
        uint256 indexed positionId,
        uint256 indexed siteId,
        bytes32 indexed title,
        uint32 available,
        uint32 headcount,
        PayBasis basis,
        uint128 rate
    );

    /**
     * @notice Emitted when the company decides a staffing request.
     * @param positionId Position.
     * @param approvedHeadcount Headcount approved (0 = rejected).
     * @param by Company account.
     * @param noteHash Hash of the decision note.
     */
    event PositionDecided(uint256 indexed positionId, uint32 approvedHeadcount, address indexed by, bytes32 noteHash);

    /**
     * @notice Emitted when HR opens the job advert of an approved position.
     * @param positionId Position.
     * @param closesAt Closing date shown to candidates (0 = open-ended).
     * @param advertHash Hash of the advert.
     */
    event VacancyOpened(uint256 indexed positionId, uint64 closesAt, bytes32 advertHash);

    /**
     * @notice Emitted when a position is closed before being filled.
     * @param positionId Position.
     * @param releasedSlots Unfilled slots released from the planned budget.
     * @param by HR or company account.
     * @param reasonHash Hash of the reason.
     */
    event PositionClosed(uint256 indexed positionId, uint32 releasedSlots, address indexed by, bytes32 reasonHash);

    /**
     * @notice Emitted when HR submits a hire for approval.
     * @param hireId New hire id.
     * @param positionId Position.
     * @param workerId Worker id.
     * @param by HR account.
     * @param contractHash Hash of the employment contract.
     */
    event HireSubmitted(
        uint256 indexed hireId, uint256 indexed positionId, bytes32 indexed workerId, address by, bytes32 contractHash
    );

    /**
     * @notice Emitted when the company approves or rejects a hire.
     * @param hireId Hire.
     * @param approved True if approved.
     * @param by Company account.
     * @param noteHash Hash of the decision note.
     */
    event HireDecided(uint256 indexed hireId, bool approved, address indexed by, bytes32 noteHash);

    /**
     * @notice Emitted when HR asks the company to end an employment.
     * @param hireId Hire.
     * @param by HR account.
     * @param reasonHash Hash of the reason.
     */
    event TerminationRequested(uint256 indexed hireId, address indexed by, bytes32 reasonHash);

    /**
     * @notice Emitted when the company ends an employment.
     * @param hireId Hire.
     * @param by Company account.
     * @param reasonHash Hash of the reason.
     */
    event EmploymentEnded(uint256 indexed hireId, address indexed by, bytes32 reasonHash);

    /**
     * @notice Emitted whenever a site budget changes.
     * @param siteId Mine site.
     * @param currency Budget currency.
     * @param headcount Active hires.
     * @param monthlyPayroll Committed monthly pay.
     * @param plannedMonthlyPayroll Monthly pay of approved, unfilled slots.
     * @param onboardingCosts One-off costs of approved hires so far.
     */
    event BudgetUpdated(
        uint256 indexed siteId,
        bytes32 indexed currency,
        uint32 headcount,
        uint128 monthlyPayroll,
        uint128 plannedMonthlyPayroll,
        uint128 onboardingCosts
    );

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice The caller is not the site's company account.
     * @param account The caller.
     * @param siteId The site.
     */
    error SiteOperations__NotCompany(address account, uint256 siteId);

    /**
     * @notice The caller does not hold the required staff permission at the site.
     * @param account The caller.
     * @param siteId The site.
     */
    error SiteOperations__NotSiteStaff(address account, uint256 siteId);

    /**
     * @notice The account would decide or inspect something it filed itself.
     * @param account The account.
     */
    error SiteOperations__SelfApproval(address account);

    /**
     * @notice The site is not in a state that allows this.
     * @param siteId The site.
     */
    error SiteOperations__SiteNotOperating(uint256 siteId);

    /**
     * @notice The report period is invalid or overlaps an accepted period report.
     */
    error SiteOperations__InvalidPeriod();

    /**
     * @notice Too many or invalid report items, a shift report without a reference or with tunnel changes, or
     * verified weights that do not match the outputs.
     */
    error SiteOperations__InvalidReportItems();

    /**
     * @notice The shift was already reported at the site.
     * @param shiftRef The shift reference.
     */
    error SiteOperations__DuplicateShift(bytes32 shiftRef);

    /**
     * @notice Unknown report, or not waiting for inspection.
     * @param reportId The report.
     */
    error SiteOperations__InvalidReport(uint256 reportId);

    /**
     * @notice A closed tunnel cannot change state.
     * @param tunnelId The tunnel.
     */
    error SiteOperations__TunnelClosed(bytes32 tunnelId);

    /**
     * @notice Invalid position request (title, headcount, currency or rate).
     */
    error SiteOperations__InvalidPosition();

    /**
     * @notice The position is not in the state this needs.
     * @param positionId The position.
     * @param status Its current state.
     */
    error SiteOperations__InvalidPositionStatus(uint256 positionId, PositionStatus status);

    /**
     * @notice Every slot of the position is filled or waiting for approval.
     * @param positionId The position.
     */
    error SiteOperations__NoOpenSlot(uint256 positionId);

    /**
     * @notice The position still has hires waiting for the company.
     * @param positionId The position.
     */
    error SiteOperations__HiresPending(uint256 positionId);

    /**
     * @notice Invalid worker id, no wallet to be paid in, or the worker belongs to another company.
     * @param workerId The worker.
     */
    error SiteOperations__InvalidWorker(bytes32 workerId);

    /**
     * @notice The worker already has a pending or active hire.
     * @param workerId The worker.
     * @param hireId That hire.
     */
    error SiteOperations__AlreadyHired(bytes32 workerId, uint256 hireId);

    /**
     * @notice The hire is not in the state this needs.
     * @param hireId The hire.
     * @param status Its current state.
     */
    error SiteOperations__InvalidHireStatus(uint256 hireId, HireStatus status);

    /*//////////////////////////////////////////////////////////////
                                FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Estimated monthly cost of one person on a position (standard month).
     * @param basis Daily rate or monthly salary.
     * @param rate The rate.
     * @return Monthly cost.
     */
    function monthlyCost(PayBasis basis, uint128 rate) internal pure returns (uint128) {
        return basis == PayBasis.Daily ? rate * WORKDAYS_PER_MONTH : rate;
    }

    /**
     * @notice Length of a pay period in days.
     * @param f Pay frequency.
     * @return Days per period.
     */
    function periodDays(PayFrequency f) internal pure returns (uint64) {
        if (f == PayFrequency.Daily) return 1;
        if (f == PayFrequency.Weekly) return 7;
        if (f == PayFrequency.Biweekly) return 14;
        return 30;
    }
}
