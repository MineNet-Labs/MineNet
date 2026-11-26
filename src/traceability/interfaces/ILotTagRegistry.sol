// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

/**
 * @title ILotTagRegistry
 * @author 0xEmmyb2
 * @notice What other MineNet contracts need from {LotTagRegistry}: a lot's current QR tag.
 */
interface ILotTagRegistry {
    /**
     * @notice A lot's current active tag.
     * @param tokenId Lot.
     * @return tagHash Hash of the tag's payload (zero if none).
     */
    function tagOf(uint256 tokenId) external view returns (bytes32 tagHash);
}
