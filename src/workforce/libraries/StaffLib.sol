// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

/**
 * @title StaffLib
 * @author 0xEmmyb2
 * @notice Company staff roles: what a mining company's own members may do at its sites.
 * @dev These roles live inside a company and are separate from platform roles ({MineNetRegistry}). The company
 * account (`MANAGE_WORKFORCE`) defines roles as sets of permissions and assigns a role to a worker for one site
 * (the worker's site) or for all of the company's sites. A worker then acts from their own wallet within that
 * scope.
 *
 * Built-in roles can be used as they are, or redefined by the company:
 * - `SITE_MANAGER`: attendance, payment records, site status, safety, reserves, reports, report inspection,
 *   dispatch, overtime
 * - `SUPERVISOR`: attendance, shift reports, overtime
 * - `PAYROLL_OFFICER`: payment records and stablecoin wages
 * - `SAFETY_OFFICER`: safety measures on dormant sites
 * - `GEOLOGIST`: reserve declarations
 * - `LABOURER`: no permissions (a labelled worker)
 * - `SITE_HR`: attendance, payment records, stablecoin wages, hiring
 * - `SITE_INSPECTOR`: inspecting site reports
 * A company can also create its own roles (e.g. "SHIFT_LEAD") with any set of permissions.
 *
 * Site seats: besides roles, the company appoints one site manager, one site HR and one report inspector per site
 * ({WorkforceManager-appointSiteSeat}). A seat holder has the company's `SITE_MANAGER` / `SITE_HR` permissions
 * (or `SITE_INSPECTOR`) at that site, on top of any role of their own, until the company removes or replaces
 * them.
 */
library StaffLib {
    /*//////////////////////////////////////////////////////////////
                         PERMISSIONS (BIT FLAGS)
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Register workers, move them between sites, activate and deactivate them.
     */
    uint32 internal constant MANAGE_WORKERS = 1 << 0;

    /**
     * @notice Record attendance.
     */
    uint32 internal constant RECORD_ATTENDANCE = 1 << 1;

    /**
     * @notice Record mobile-money, e-banking and cash payments.
     */
    uint32 internal constant RECORD_PAYMENTS = 1 << 2;

    /**
     * @notice Pay stablecoin wages from the staff member's own wallet.
     */
    uint32 internal constant PAY_WAGES = 1 << 3;

    /**
     * @notice Record safety measures at dormant sites.
     */
    uint32 internal constant SITE_SAFETY = 1 << 4;

    /**
     * @notice Declare mineral reserves.
     */
    uint32 internal constant DECLARE_RESERVES = 1 << 5;

    /**
     * @notice Declare a site dormant or reactivate it.
     */
    uint32 internal constant MANAGE_SITE = 1 << 6;

    /**
     * @notice Record extraction (production) at a site, which caps the lots the company can register there.
     */
    uint32 internal constant RECORD_PRODUCTION = 1 << 7;

    /**
     * @notice Submit site reports (output, tunnels, headcount, incidents) to the company ({SiteOperations}).
     */
    uint32 internal constant SUBMIT_REPORTS = 1 << 8;

    /**
     * @notice Request positions, open job adverts and submit hires for the company's approval ({SiteOperations}).
     */
    uint32 internal constant MANAGE_HIRING = 1 << 9;

    /**
     * @notice Dispatch the company's lots from the site to a carrier ({DeliveryManager-dispatch}), signing the
     * physical handover with the vehicle, driver and receiving worker.
     */
    uint32 internal constant DISPATCH_LOTS = 1 << 10;

    /**
     * @notice Inspect site reports before they reach the company ({SiteOperations-inspectReport}).
     */
    uint32 internal constant INSPECT_REPORTS = 1 << 11;

    /**
     * @notice Authorise a worker's overtime on a rest day, holiday or leave day ({PayrollEngine-authorizeOvertime}).
     * Overriding the 1-in-7 rest lock also needs `MANAGE_SITE`.
     */
    uint32 internal constant AUTHORIZE_OVERTIME = 1 << 12;

    /**
     * @notice Every permission.
     */
    uint32 internal constant ALL = (1 << 13) - 1;

    /*//////////////////////////////////////////////////////////////
                              BUILT-IN ROLES
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Built-in role: attendance, payment records, site status, safety, reserves, reports, report inspection
     * (not of their own reports), dispatch and overtime. Not `MANAGE_WORKERS` (workers join through approved hires),
     * `RECORD_PRODUCTION` (official output comes from inspected shift reports), `PAY_WAGES` or `MANAGE_HIRING`.
     */
    bytes32 internal constant SITE_MANAGER = "SITE_MANAGER";

    /**
     * @notice Built-in role of a shift supervisor: `RECORD_ATTENDANCE`, `SUBMIT_REPORTS` (shift reports) and
     * `AUTHORIZE_OVERTIME`.
     */
    bytes32 internal constant SUPERVISOR = "SUPERVISOR";

    /**
     * @notice Built-in role: `RECORD_PAYMENTS` and `PAY_WAGES`.
     */
    bytes32 internal constant PAYROLL_OFFICER = "PAYROLL_OFFICER";

    /**
     * @notice Built-in role: `SITE_SAFETY`.
     */
    bytes32 internal constant SAFETY_OFFICER = "SAFETY_OFFICER";

    /**
     * @notice Built-in role: `DECLARE_RESERVES`.
     */
    bytes32 internal constant GEOLOGIST = "GEOLOGIST";

    /**
     * @notice Built-in role with no permissions (a labelled worker).
     */
    bytes32 internal constant LABOURER = "LABOURER";

    /**
     * @notice Built-in role of an appointed site HR: `RECORD_ATTENDANCE`, `RECORD_PAYMENTS`, `PAY_WAGES` and
     * `MANAGE_HIRING`. Workers join through approved hires, so it has no `MANAGE_WORKERS`.
     */
    bytes32 internal constant SITE_HR = "SITE_HR";

    /**
     * @notice Built-in role of an appointed site inspector: `INSPECT_REPORTS`.
     */
    bytes32 internal constant SITE_INSPECTOR = "SITE_INSPECTOR";

    /*//////////////////////////////////////////////////////////////
                               SITE TEAM
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice A seat in a site's leadership team, appointed by the company account.
     */
    enum SiteSeat {
        // Runs the site and reports to the company; holds the company's `SITE_MANAGER` permissions there.
        Manager,
        // Hires and pays the site's people; holds the company's `SITE_HR` permissions there.
        Hr,
        // Checks the manager's reports before they reach the company; holds `SITE_INSPECTOR` permissions there.
        Inspector
    }

    /**
     * @notice The appointed leadership of one site.
     * @param manager Worker id of the site manager (zero = vacant).
     * @param hr Worker id of the site HR (zero = vacant).
     * @param inspector Worker id of the company's report inspector for the site (zero = vacant).
     */
    struct SiteTeam {
        bytes32 manager;
        bytes32 hr;
        bytes32 inspector;
    }

    /**
     * @notice The staff role assigned to a worker.
     * @param roleId Role id; zero = no role.
     * @param allSites True for every company site; false for the worker's own site only.
     */
    struct StaffRole {
        bytes32 roleId;
        bool allSites;
    }

    /**
     * @notice A company's definition of a role.
     * @param permissions Permission bit flags.
     * @param defined True once set by the company; overrides the built-in permissions of the same id.
     */
    struct RoleDef {
        uint32 permissions;
        bool defined;
    }

    /**
     * @notice Emitted when a company defines or redefines a staff role.
     * @param orgId Company.
     * @param roleId Role id.
     * @param permissions Permission bit flags.
     */
    event RoleDefined(bytes32 indexed orgId, bytes32 indexed roleId, uint32 permissions);

    /**
     * @notice Emitted when a staff role is assigned to (or removed from) a worker.
     * @param workerId Opaque worker id.
     * @param roleId Role id (zero = removed).
     * @param allSites Whether the role applies at every company site.
     * @param by Account that made the assignment.
     */
    event RoleAssigned(bytes32 indexed workerId, bytes32 indexed roleId, bool allSites, address indexed by);

    /**
     * @notice Emitted when the company appoints, replaces or removes a site's manager or HR.
     * @param siteId Mine site.
     * @param seat Manager or HR.
     * @param workerId New holder (zero = removed).
     * @param previous Previous holder (zero = was vacant).
     * @param by Company account that made the change.
     */
    event SiteSeatAssigned(
        uint256 indexed siteId, SiteSeat indexed seat, bytes32 indexed workerId, bytes32 previous, address by
    );

    /**
     * @notice A worker cannot hold two seats (manager, HR, inspector) of the same site.
     * @param siteId The site.
     * @param workerId The worker.
     */
    error WorkforceManager__SeatConflict(uint256 siteId, bytes32 workerId);

    /**
     * @notice The worker must be active and have a wallet to hold a site seat.
     * @param workerId The worker.
     */
    error WorkforceManager__CannotHoldSeat(bytes32 workerId);

    /**
     * @notice The caller is not the {SiteOperations} (or, for salaries, the {PayrollEngine}) contract.
     * @param account The caller.
     */
    error WorkforceManager__NotSiteOperations(address account);

    /**
     * @notice `roleId` is zero or not defined.
     * @param roleId The role id.
     */
    error WorkforceManager__InvalidRole(bytes32 roleId);

    /**
     * @notice `permissions` contains unknown bits.
     * @param permissions The permission flags.
     */
    error WorkforceManager__InvalidPermissions(uint32 permissions);

    /**
     * @notice `wallet` is already linked to worker `workerId`.
     * @param wallet The wallet.
     * @param workerId Worker it is linked to.
     */
    error WorkforceManager__WalletInUse(address wallet, bytes32 workerId);

    /**
     * @notice `account`'s staff role does not cover site `siteId`.
     * @param account The account.
     * @param siteId The site.
     */
    error WorkforceManager__OutOfScope(address account, uint256 siteId);

    /**
     * @notice Staff cannot change role holders or themselves.
     * @param workerId The protected worker.
     */
    error WorkforceManager__ProtectedWorker(bytes32 workerId);

    /**
     * @notice A staff member cannot pay themselves.
     * @param workerId The worker.
     */
    error WorkforceManager__SelfPayment(bytes32 workerId);

    /**
     * @notice Permissions of a built-in role.
     * @param roleId Role id.
     * @return Permission bit flags (0 for unknown ids and `LABOURER`).
     */
    function builtIn(bytes32 roleId) internal pure returns (uint32) {
        if (roleId == SITE_MANAGER) {
            return RECORD_ATTENDANCE | RECORD_PAYMENTS | SITE_SAFETY | DECLARE_RESERVES | MANAGE_SITE | SUBMIT_REPORTS
                | DISPATCH_LOTS | INSPECT_REPORTS | AUTHORIZE_OVERTIME;
        }
        if (roleId == SUPERVISOR) return RECORD_ATTENDANCE | SUBMIT_REPORTS | AUTHORIZE_OVERTIME;
        if (roleId == PAYROLL_OFFICER) return RECORD_PAYMENTS | PAY_WAGES;
        if (roleId == SAFETY_OFFICER) return SITE_SAFETY;
        if (roleId == GEOLOGIST) return DECLARE_RESERVES;
        if (roleId == SITE_HR) return RECORD_ATTENDANCE | RECORD_PAYMENTS | PAY_WAGES | MANAGE_HIRING;
        if (roleId == SITE_INSPECTOR) return INSPECT_REPORTS;
        return 0;
    }

    /**
     * @notice Whether `roleId` is one of the built-in roles.
     * @param roleId Role id.
     * @return True for a built-in role.
     */
    function isBuiltIn(bytes32 roleId) internal pure returns (bool) {
        return roleId == SITE_MANAGER || roleId == SUPERVISOR || roleId == PAYROLL_OFFICER || roleId == SAFETY_OFFICER
            || roleId == GEOLOGIST || roleId == LABOURER || roleId == SITE_HR || roleId == SITE_INSPECTOR;
    }
}
