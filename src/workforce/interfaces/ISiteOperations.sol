// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {SiteOpsLib} from "src/workforce/libraries/SiteOpsLib.sol";

/**
 * @title ISiteOperations
 * @author 0xEmmyb2
 * @notice What {PayrollEngine} reads from {SiteOperations}: hires and their positions.
 */
interface ISiteOperations {
    /**
     * @notice A worker's latest hire.
     * @param workerId Worker id.
     * @return hireId Hire id (zero = none).
     */
    function hireOf(bytes32 workerId) external view returns (uint256 hireId);

    /**
     * @notice Returns a hire.
     * @param hireId Hire id.
     * @return The hire.
     */
    function getHire(uint256 hireId) external view returns (SiteOpsLib.Hire memory);

    /**
     * @notice Returns a position.
     * @param positionId Position id.
     * @return The position.
     */
    function getPosition(uint256 positionId) external view returns (SiteOpsLib.Position memory);
}
