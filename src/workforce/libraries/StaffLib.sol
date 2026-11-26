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
 * - `SITE_MANAGER`: workers, attendance, payment records, site status, safety, reserves
 * - `SUPERVISOR`: attendance
 * - `PAYROLL_OFFICER`: payment records and stablecoin wages
 * - `SAFETY_OFFICER`: safety measures on dormant sites
 * - `GEOLOGIST`: reserve declarations
 * - `LABOURER`: no permissions (a labelled worker)
 * A company can also create its own roles (e.g. "SHIFT_LEAD") with any set of permissions.
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
     * @notice Every permission.
     */
    uint32 internal constant ALL = (1 << 7) - 1;

    /*//////////////////////////////////////////////////////////////
                              BUILT-IN ROLES
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Built-in role: every permission except `PAY_WAGES`.
     */
    bytes32 internal constant SITE_MANAGER = "SITE_MANAGER";

    /**
     * @notice Built-in role: `RECORD_ATTENDANCE`.
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
            return MANAGE_WORKERS | RECORD_ATTENDANCE | RECORD_PAYMENTS | SITE_SAFETY | DECLARE_RESERVES | MANAGE_SITE;
        }
        if (roleId == SUPERVISOR) return RECORD_ATTENDANCE;
        if (roleId == PAYROLL_OFFICER) return RECORD_PAYMENTS | PAY_WAGES;
        if (roleId == SAFETY_OFFICER) return SITE_SAFETY;
        if (roleId == GEOLOGIST) return DECLARE_RESERVES;
        return 0;
    }

    /**
     * @notice Whether `roleId` is one of the built-in roles.
     * @param roleId Role id.
     * @return True for a built-in role.
     */
    function isBuiltIn(bytes32 roleId) internal pure returns (bool) {
        return roleId == SITE_MANAGER || roleId == SUPERVISOR || roleId == PAYROLL_OFFICER || roleId == SAFETY_OFFICER
            || roleId == GEOLOGIST || roleId == LABOURER;
    }
}
