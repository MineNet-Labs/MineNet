// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {SiteLib} from "src/compliance/libraries/SiteLib.sol";

/**
 * @title ISiteRegistry
 * @author 0xEmmyb2
 * @notice Minimal view of {MineSiteRegistry} needed by other MineNet contracts (e.g. {LotPassport}).
 */
interface ISiteRegistry {
    /**
     * @notice Whether `account` may register lots produced at `siteId`.
     * @dev True only if the site is Active, its concession is not revoked, the concession's mining
     * licence is valid, and `account` belongs to the holder organisation.
     * @param siteId Mine site id.
     * @param account Account that wants to register a lot.
     * @return True if `account` may register lots from `siteId`.
     */
    function canProduce(uint256 siteId, address account) external view returns (bool);

    /**
     * @notice The organisation that holds `siteId`.
     * @param siteId Mine site id.
     * @return orgId Holder organisation id, or zero if the site is unknown.
     */
    function orgOfSite(uint256 siteId) external view returns (bytes32 orgId);

    /**
     * @notice Draws `quantity` of `mineralType` from a site's recorded, not yet lotted extraction.
     * @dev Only the lot passport, when a lot is registered. Reverts if the site has not recorded enough extraction.
     * @param siteId Mine site id.
     * @param mineralType Mineral identifier.
     * @param quantity Quantity, in grams.
     */
    function consumeExtraction(uint256 siteId, bytes32 mineralType, uint128 quantity) external;

    /**
     * @notice A site's recorded extraction of a mineral and how much of it has been lotted.
     * @param siteId Mine site id.
     * @param mineralType Mineral identifier.
     * @return The production record.
     */
    function productionOf(uint256 siteId, bytes32 mineralType) external view returns (SiteLib.Production memory);

    /**
     * @notice Returns a site's state.
     * @param siteId Mine site id.
     * @return The site (all fields zero if unknown).
     */
    function getSite(uint256 siteId) external view returns (SiteLib.Site memory);

    /**
     * @notice Returns a site's current geographic location.
     * @param siteId Mine site id.
     * @return The location (all fields zero / empty if unknown).
     */
    function getSiteLocation(uint256 siteId) external view returns (SiteLib.SiteLocation memory);

    /**
     * @notice Records output verified by the company's inspector; it counts toward extraction and its ceiling.
     * @dev Only the {SiteOperations} contract.
     * @param siteId Site id.
     * @param mineralType Mineral identifier.
     * @param quantity Verified quantity, in grams.
     * @param evidenceHash Hash of the approved report and inspection.
     * @param inspector Inspector who approved it.
     */
    function recordVerifiedExtraction(
        uint256 siteId,
        bytes32 mineralType,
        uint128 quantity,
        bytes32 evidenceHash,
        address inspector
    ) external;
}
