// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

/**
 * @title IAttendanceGate
 * @author 0xEmmyb2
 * @notice The check {WorkforceManager} runs before recording a check-in, as a gate terminal would: blocks routine
 * check-in on a worker's rest day, a public holiday or a leave day, and on a 7th consecutive working day, unless
 * overtime was authorised ({PayrollEngine}).
 */
interface IAttendanceGate {
    /**
     * @notice Reverts if `workerId` may not be checked in on `day` without an overtime authorisation.
     * @param workerId Worker.
     * @param siteId Site of the check-in.
     * @param day Day (unix time / 1 day).
     */
    function checkAttendance(bytes32 workerId, uint256 siteId, uint64 day) external view;
}
