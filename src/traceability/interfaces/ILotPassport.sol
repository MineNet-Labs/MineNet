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
     * @notice Whether a lot is locked under a trade (escrow order or B2B delivery).
     * @param tokenId Token id.
     * @return locked True if locked.
     */
    function escrowLocked(uint256 tokenId) external view returns (bool locked);

    /**
     * @notice While a lot is locked under a trade, the first time its custody reached an organisation's account
     * (including the custodian at lock time).
     * @param tokenId Token id.
     * @param orgId Organisation.
     * @return When custody first reached the organisation during the current lock (0 = never, or not locked).
     */
    function custodyReachedAt(uint256 tokenId, bytes32 orgId) external view returns (uint64);

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
     * @notice Splits an inspected lot into inspected children of the same mineral, owner, custodian and site.
     * @dev Only a module.
     * @param tokenId Lot to split.
     * @param quantities Child quantities in grams (at least 2), summing to the lot's quantity.
     * @param splitHash Hash of the split record.
     * @return ids Child token ids.
     */
    function moduleSplit(uint256 tokenId, uint128[] calldata quantities, bytes32 splitHash)
        external
        returns (uint256[] memory ids);

    /**
     * @notice The escrow or an approved trade contract locks a lot it was approved for.
     * @param tokenId Lot.
     */
    function lockForEscrow(uint256 tokenId) external;

    /**
     * @notice The contract that locked a lot unlocks it after a trade ended without a sale.
     * @param tokenId Lot.
     */
    function unlockFromEscrow(uint256 tokenId) external;

    /**
     * @notice The contract that locked a lot settles it to the buyer.
     * @param tokenId Lot.
     * @param to Buyer.
     */
    function escrowTransfer(uint256 tokenId, address to) external;

    /**
     * @notice The lot-finance contract ({LotFinance}) records a lien, its release, or insurance cover on a lot.
     * @param tokenId Lot.
     * @param eventType `Lien`, `LienReleased` or `Insured`.
     * @param actor Financier or insurer recorded as the event's actor.
     * @param dataHash Hash of the loan terms, release proof or policy.
     */
    function recordFinancing(uint256 tokenId, PassportLib.EventType eventType, address actor, bytes32 dataHash) external;

    /**
     * @notice The lot-finance contract ({LotFinance}); zero if not set.
     * @return The lot-finance contract.
     */
    function financing() external view returns (address);

    /**
     * @notice The escrow contract ({EscrowManager}).
     * @return The escrow contract.
     */
    function escrow() external view returns (address);
}
