// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {LicenceLib} from "src/compliance/libraries/LicenceLib.sol";

/**
 * @title ILicenceRegistry
 * @author 0xEmmyb2
 * @notice What other MineNet contracts need from {LicenceRegistry}: whether a licence is in force.
 */
interface ILicenceRegistry {
    /**
     * @notice Current status of a licence.
     * @param licenceId Licence id.
     * @return The status (`None` if unknown).
     */
    function status(uint256 licenceId) external view returns (LicenceLib.Status);

    /**
     * @notice Whether a licence is in force now: started, and not expired, suspended or revoked.
     * @param licenceId Licence id.
     * @return True if in force.
     */
    function isValid(uint256 licenceId) external view returns (bool);

    /**
     * @notice Whether a licence belongs to `orgId`, is of `licenceType` and is in force now.
     * @param licenceId Licence id.
     * @param orgId Expected holder.
     * @param licenceType Expected licence type.
     * @return True if all three hold.
     */
    function isValidFor(uint256 licenceId, bytes32 orgId, bytes32 licenceType) external view returns (bool);
}
