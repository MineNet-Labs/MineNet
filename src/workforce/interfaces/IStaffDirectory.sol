// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

/**
 * @title IStaffDirectory
 * @author 0xEmmyb2
 * @notice What other MineNet contracts need to know about a company's staff ({WorkforceManager}).
 */
interface IStaffDirectory {
    /**
     * @notice The company `account` acts for as a staff member holding `permission` at `siteId`.
     * @dev Non-zero only if `account` is the wallet of an active worker whose staff role grants every bit of
     * `permission` at `siteId`. `siteId = 0` means company-wide, which needs an all-sites role.
     * @param account Account to check.
     * @param siteId Mine site, or 0 for company-wide.
     * @param permission Required permissions ({StaffLib} bit flags).
     * @return Organisation id of the company, or zero if `account` lacks the permission there.
     */
    function staffOrg(address account, uint256 siteId, uint32 permission) external view returns (bytes32);
}
