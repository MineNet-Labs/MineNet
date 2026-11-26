// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {PassportLib} from "src/traceability/libraries/PassportLib.sol";

/**
 * @title ILotPassport
 * @author 0xEmmyb2
 * @notice What other MineNet contracts need from {LotPassport}: lots, custody, freezes, escrow locks, history and
 * the module hooks. Ownership is the standard ERC-721 interface.
 */
interface ILotPassport is IERC721 {
    /**
     * @notice The token minted for an internal lot id (0 if none).
     * @param lotId Internal lot id.
     * @return tokenId The token id.
     */
    function tokenOfLot(bytes32 lotId) external view returns (uint256 tokenId);

    /**
     * @notice Whether a lot is locked under an escrow order.
     * @param tokenId Token id.
     * @return locked True if locked.
     */
    function escrowLocked(uint256 tokenId) external view returns (bool locked);

    /**
     * @notice The mine site a registered lot came from (0 for derived lots).
     * @param tokenId Token id.
     * @return siteId The site id.
     */
    function siteOf(uint256 tokenId) external view returns (uint256 siteId);

    /**
     * @notice Returns a lot; reverts for an unknown lot.
     * @param tokenId Token id.
     * @return The lot.
     */
    function getLot(uint256 tokenId) external view returns (PassportLib.Lot memory);

    /**
     * @notice Whether a lot is frozen by a regulatory hold or an open flag.
     * @param tokenId Token id.
     * @return True if frozen.
     */
    function isFrozen(uint256 tokenId) external view returns (bool);

    /**
     * @notice The account physically holding a lot; reverts for an unknown lot.
     * @param tokenId Token id.
     * @return The custodian.
     */
    function custodianOf(uint256 tokenId) external view returns (address);

    /**
     * @notice Number of events in a lot's history.
     * @param tokenId Token id.
     * @return Event count.
     */
    function eventCount(uint256 tokenId) external view returns (uint256);

    /**
     * @notice Paginated event history.
     * @param tokenId Token id.
     * @param offset First index.
     * @param limit Maximum number of events.
     * @return page Up to `limit` events starting at `offset`.
     */
    function getEvents(uint256 tokenId, uint256 offset, uint256 limit)
        external
        view
        returns (PassportLib.PassportEvent[] memory page);

    /**
     * @notice The input lots a derived lot was processed from.
     * @param tokenId Token id.
     * @return Parent token ids.
     */
    function parentsOf(uint256 tokenId) external view returns (uint256[] memory);

    /**
     * @notice The derived lots made from a lot.
     * @param tokenId Token id.
     * @return Child token ids.
     */
    function childrenOf(uint256 tokenId) external view returns (uint256[] memory);

    /**
     * @notice A module moves custody after collecting both parties' confirmations.
     * @param tokenId Lot.
     * @param from Current custodian.
     * @param to New custodian.
     * @param evidenceHash Hash of the handover evidence.
     */
    function moduleHandover(uint256 tokenId, address from, address to, bytes32 evidenceHash) external;

    /**
     * @notice A module raises a flag on behalf of `reporter`; the lot is frozen while it is open.
     * @param tokenId Lot.
     * @param reporter Account recorded as raising the flag.
     * @param evidenceHash Hash of the evidence.
     * @return flagId New flag id.
     */
    function moduleFlag(uint256 tokenId, address reporter, bytes32 evidenceHash) external returns (uint256 flagId);

    /**
     * @notice The escrow locks a lot under an accepted order.
     * @param tokenId Lot.
     */
    function lockForEscrow(uint256 tokenId) external;

    /**
     * @notice The escrow unlocks a lot whose order ended without a sale.
     * @param tokenId Lot.
     */
    function unlockFromEscrow(uint256 tokenId) external;

    /**
     * @notice The escrow settles a locked lot to the buyer.
     * @param tokenId Lot.
     * @param to Buyer.
     */
    function escrowTransfer(uint256 tokenId, address to) external;
}
