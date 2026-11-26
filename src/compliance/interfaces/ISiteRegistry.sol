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
}
