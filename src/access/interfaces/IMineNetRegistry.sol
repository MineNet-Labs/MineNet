// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {RegistryLib} from "src/access/libraries/RegistryLib.sol";

/**
 * @title IMineNetRegistry
 * @author 0xEmmyb2
 * @notice What other MineNet contracts need from {MineNetRegistry}: participants, organisations and permission
 * checks.
 * @dev Contracts check actions ({isAuthorized}), never roles directly.
 */
interface IMineNetRegistry is IAccessControl {
    /**
     * @notice Whether `account` is the platform admin (`DEFAULT_ADMIN_ROLE`).
     * @param account The account.
     * @return True if it holds the admin role.
     */
    function isAdmin(address account) external view returns (bool);

    /**
     * @notice Whether `account` may perform `action`.
     * @param account The account.
     * @param action Action id ({Actions}).
     * @return True if it holds an enabled role mapped to the action, is not suspended, and its licence has not
     * expired.
     */
    function isAuthorized(address account, bytes32 action) external view returns (bool);

    /**
     * @notice Whether `account` actively holds `role`.
     * @param account The account.
     * @param role Role id.
     * @return True if it holds the (still enabled) role, is not suspended, and its licence is valid.
     */
    function isActive(address account, bytes32 role) external view returns (bool);

    /**
     * @notice Whether two accounts belong to the same organisation.
     * @param a First account.
     * @param b Second account.
     * @return True if they are the same account or share a non-zero organisation id.
     */
    function sameOrg(address a, address b) external view returns (bool);

    /**
     * @notice Returns an account's participant record.
     * @param account The account.
     * @return The record (all fields zero if never onboarded).
     */
    function participant(address account) external view returns (RegistryLib.Participant memory);

    /**
     * @notice Whether `role` is an enabled participant role.
     * @param role Role id.
     * @return True if enabled.
     */
    function isParticipantRole(bytes32 role) external view returns (bool);

    /**
     * @notice The regulator institution (organisation id) that licenses a role (zero = admin only).
     * @param role Role id.
     * @return authorityOrg The licensing institution.
     */
    function roleAuthority(bytes32 role) external view returns (bytes32 authorityOrg);

    /**
     * @notice Whether an organisation has been registered.
     * @param orgId Organisation id.
     * @return registered True if registered.
     */
    function orgRegistered(bytes32 orgId) external view returns (bool registered);
}
