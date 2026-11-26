// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

/**
 * @title IInspectionRegistry
 * @author 0xEmmyb2
 * @notice What other MineNet contracts need from {InspectionRegistry}: which inspector the platform assigned to a
 * lot, whether that assignment is still open, and whether an inspector is deployed to a mine site's district.
 */
interface IInspectionRegistry {
    /**
     * @notice Closes the open assignment of `inspector` to a lot once it submitted its pass / fail result.
     * @dev Only the lot passport. Reverts unless the assignment is open.
     * @param tokenId The lot.
     * @param inspector The inspector that submitted the result.
     * @custom:emits InspectionCompleted
     */
    function completeInspection(uint256 tokenId, address inspector) external;

    /**
     * @notice Whether `inspector` holds an open assignment for a lot: assigned, result not yet submitted, and
     * within the inspection window.
     * @param tokenId The lot.
     * @param inspector The inspector.
     * @return True if the assignment is open.
     */
    function isAssignmentOpen(uint256 tokenId, address inspector) external view returns (bool);

    /**
     * @notice The inspector the platform currently assigns to a lot.
     * @param tokenId The lot.
     * @return inspector The assigned inspector (zero if none).
     */
    function assignedInspector(uint256 tokenId) external view returns (address inspector);

    /**
     * @notice Whether an inspector on the roster is deployed to the district of a mine site (or nationwide).
     * @param inspector The inspector.
     * @param siteId Mine site.
     * @return True if the inspector covers the site.
     */
    function coversSite(address inspector, uint256 siteId) external view returns (bool);
}
