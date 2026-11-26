// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {SupplyChainLib} from "src/traceability/libraries/SupplyChainLib.sol";

/**
 * @title ISupplyChain
 * @author 0xEmmyb2
 * @notice What other MineNet contracts need from {SupplyChain}: trusted weights, grades, checkpoints, customs
 * status, and checkpoint recording by modules.
 */
interface ISupplyChain {
    /**
     * @notice A lot's customs progress.
     * @param tokenId Lot.
     * @return status The customs status.
     */
    function customsStatus(uint256 tokenId) external view returns (SupplyChainLib.CustomsStatus status);

    /**
     * @notice A lot's last trusted (within-tolerance) weight, or its baseline if never weighed.
     * @param tokenId Lot.
     * @return Weight, in grams.
     */
    function lastWeight(uint256 tokenId) external view returns (uint128);

    /**
     * @notice The most recent grade attested by an inspector.
     * @param tokenId Lot.
     * @return The grade (`gradeBps` 0 if never graded).
     */
    function latestGrade(uint256 tokenId) external view returns (SupplyChainLib.Grade memory);

    /**
     * @notice Number of checkpoints recorded for a lot.
     * @param tokenId Lot.
     * @return Checkpoint count.
     */
    function checkpointCount(uint256 tokenId) external view returns (uint256);

    /**
     * @notice Returns one checkpoint of a lot; reverts if `index` is out of range.
     * @param tokenId Lot.
     * @param index Checkpoint index.
     * @return The checkpoint.
     */
    function getCheckpoint(uint256 tokenId, uint256 index) external view returns (SupplyChainLib.Checkpoint memory);

    /**
     * @notice The platform assigns an inspector to a lot; only the inspection assigner.
     * @param tokenId Lot.
     * @param inspector Assigned inspector.
     */
    function assignInspector(uint256 tokenId, address inspector) external;

    /**
     * @notice The platform removes an inspector from a lot; only the inspection assigner.
     * @param tokenId Lot.
     * @param inspector Inspector to remove.
     */
    function unassignInspector(uint256 tokenId, address inspector) external;

    /**
     * @notice A module records a `Pickup` or `Arrival` checkpoint for `signer`.
     * @param input The checkpoint.
     * @param signer Account recorded as signing it.
     * @return index Position of the checkpoint in the lot's log.
     * @return flagId Passport flag raised by this checkpoint (0 if none).
     */
    function recordFromModule(SupplyChainLib.CheckpointInput calldata input, address signer)
        external
        returns (uint256 index, uint256 flagId);
}
