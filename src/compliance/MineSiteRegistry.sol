// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {IMineNetRegistry} from "src/access/interfaces/IMineNetRegistry.sol";
import {ILicenceRegistry} from "src/compliance/interfaces/ILicenceRegistry.sol";
import {ISiteRegistry} from "src/compliance/interfaces/ISiteRegistry.sol";
import {IStaffDirectory} from "src/workforce/interfaces/IStaffDirectory.sol";
import {IInspectionRegistry} from "src/compliance/interfaces/IInspectionRegistry.sol";
import {Actions} from "src/access/libraries/Actions.sol";
import {SiteLib} from "src/compliance/libraries/SiteLib.sol";
import {StaffLib} from "src/workforce/libraries/StaffLib.sol";

/**
 * @title MineSiteRegistry
 * @author 0xEmmyb2
 * @notice Registry of mining concessions, the mine sites inside them, where each site is located, and
 * each site's operating status, safety record and declared mineral reserves.
 *
 * @dev ## Concessions
 * A regulator grants a concession to an organisation under a valid `MINING_LICENCE` recorded in
 * {LicenceRegistry}. When that licence expires, is suspended or is revoked, or the concession
 * itself is revoked, the concession's sites stop producing.
 *
 * ## Sites
 * The concession holder registers its sites. Every site is registered with its
 * {SiteLib.SiteLocation}: GPS coordinates (WGS-84, micro-degrees), elevation and the Rwandan
 * administrative divisions it lies in (province, district, sector, cell, village). The location
 * is public so that buyers, regulators and oracle nodes can check a lot's origin; the detailed
 * survey (boundary polygon, maps, photos) stays off-chain and is referenced by `surveyHash`.
 * Only a regulator can correct a recorded location, and every correction is emitted as an event,
 * so the location history stays append-only.
 *
 * A site is Active, Dormant or Closed:
 * - Active -> Dormant: the holder (or a regulator) stops mining and files a safety plan for the
 * open ground left behind.
 * - Dormant: the holder records the measures taken (fencing, backfilling, signs...) and an
 * independent inspector or a regulator inspects them. A dormant site with no passing inspection
 * after the grace period, or whose last inspection is older than the recheck interval, is
 * reported by {isSafetyOverdue}.
 * - Dormant -> Active: the holder resumes mining (the concession must still be valid).
 * - Dormant -> Closed: a regulator closes the site with the rehabilitation certificate, once a
 * safety inspection has passed.
 *
 * Lots can only be registered from an Active site of the miner's own organisation with a valid
 * permit ({canProduce}, used by {LotPassport}).
 *
 * ## Reserves
 * The holder declares estimated deposits per mineral and an independent inspector or regulator
 * can verify them. Together with production and the licence record this lets investors (and the
 * AI market assistant) find companies and sites with significant deposits.
 *
 * ## Staff
 * Company staff ({WorkforceManager} staff roles) can act at their sites: `MANAGE_SITE` declares a
 * site dormant or reactivates it, `SITE_SAFETY` records safety measures and `DECLARE_RESERVES`
 * declares reserves. Registering sites stays with the company's miner accounts.
 *
 * Apart from the public site location, only hashes and opaque ids are stored.
 */
contract MineSiteRegistry is ISiteRegistry {
    /*//////////////////////////////////////////////////////////////
                                 STORAGE
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Participant, role and permission registry.
     */
    IMineNetRegistry public immutable registry;

    /**
     * @notice Licence registry that holds the mining licences concessions are granted under.
     */
    ILicenceRegistry public immutable licences;

    /**
     * @notice Time a dormant site has to pass its first safety inspection.
     */
    uint32 public safetyGracePeriod = 30 days;

    /**
     * @notice Maximum time between two safety inspections of a dormant site.
     */
    uint32 public safetyRecheckInterval = 180 days;

    /**
     * @notice Company staff directory ({WorkforceManager}).
     * @dev Zero means only the company's miner accounts can act at its sites.
     */
    IStaffDirectory public staff;

    /**
     * @notice Inspector roster ({InspectionRegistry}). Once set, site safety inspections and reserve verifications
     * are accepted from regulators, or from inspectors deployed to the site's district (or nationwide).
     */
    IInspectionRegistry public inspections;

    /**
     * @dev Next concession id; ids start at 1 so that 0 means "none".
     */
    uint256 private _nextConcessionId = 1;

    /**
     * @dev Next site id; ids start at 1 so that 0 means "none".
     */
    uint256 private _nextSiteId = 1;

    /**
     * @dev Concession id => concession.
     */
    mapping(uint256 concessionId => SiteLib.Concession) private _concessions;

    /**
     * @dev Site id => site.
     */
    mapping(uint256 siteId => SiteLib.Site) private _sites;

    /**
     * @dev Site id => geographic location.
     */
    mapping(uint256 siteId => SiteLib.SiteLocation) private _locations;

    /**
     * @notice Backend site reference => site id (0 if unregistered).
     */
    mapping(bytes32 siteRef => uint256 siteId) public siteOfRef;

    /**
     * @dev Organisation => ids of its sites, in registration order.
     */
    mapping(bytes32 orgId => uint256[]) private _sitesOf;

    /**
     * @dev Concession => ids of its sites, in registration order.
     */
    mapping(uint256 concessionId => uint256[]) private _sitesOfConcession;

    /**
     * @dev Site => mineral => declared reserve.
     */
    mapping(uint256 siteId => mapping(bytes32 mineralType => SiteLib.Reserve)) private _reserves;

    /**
     * @dev Site => minerals with a declared reserve, in declaration order.
     */
    mapping(uint256 siteId => bytes32[]) private _reserveMinerals;

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @param registry_ Participant, role and permission registry.
     * @param licences_ Licence registry holding the mining licences.
     */
    constructor(IMineNetRegistry registry_, ILicenceRegistry licences_) {
        registry = registry_;
        licences = licences_;
    }

    /*//////////////////////////////////////////////////////////////
                                  ADMIN
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Sets the dormant-site safety policy.
     * @dev Only a {MineNetRegistry} admin. Applies immediately to every dormant site.
     * @param gracePeriod Time a dormant site has to pass its first safety inspection.
     * @param recheckInterval Maximum time between two safety inspections.
     * @custom:emits SafetyPolicySet
     */
    function setSafetyPolicy(uint32 gracePeriod, uint32 recheckInterval) external {
        _onlyRegistryAdmin();
        if (gracePeriod == 0 || recheckInterval == 0) revert SiteLib.MineSiteRegistry__InvalidPolicy();
        safetyGracePeriod = gracePeriod;
        safetyRecheckInterval = recheckInterval;
        emit SiteLib.SafetyPolicySet(gracePeriod, recheckInterval);
    }

    /**
     * @notice Sets the staff directory used to authorise company staff at their sites.
     * @dev Only a {MineNetRegistry} admin. Pass the zero address to disable staff permissions.
     * @param staff_ Staff directory ({WorkforceManager}).
     * @custom:emits StaffDirectorySet
     */
    function setStaffDirectory(IStaffDirectory staff_) external {
        _onlyRegistryAdmin();
        staff = staff_;
        emit SiteLib.StaffDirectorySet(address(staff_));
    }

    /**
     * @notice Sets the inspector roster that decides which inspectors may inspect each site.
     * @dev Only a {MineNetRegistry} admin. Zero lets any independent inspector inspect any site.
     * @param inspections_ Inspection registry ({InspectionRegistry}).
     * @custom:emits InspectionRegistrySet
     */
    function setInspectionRegistry(IInspectionRegistry inspections_) external {
        _onlyRegistryAdmin();
        inspections = inspections_;
        emit SiteLib.InspectionRegistrySet(address(inspections_));
    }

    /*//////////////////////////////////////////////////////////////
                          REGULATOR: CONCESSIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Grants a concession to `orgId` under its mining licence `licenceId`.
     * @dev Only a regulator. The licence must be a valid `MINING_LICENCE` held by `orgId`.
     * @param orgId Holder organisation.
     * @param licenceId Mining licence in {LicenceRegistry}.
     * @param areaHash Hash of the concession boundary (cadastre reference, polygon).
     * @param docHash Hash of the concession document.
     * @return concessionId New concession id.
     * @custom:emits ConcessionGranted
     */
    function grantConcession(bytes32 orgId, uint256 licenceId, bytes32 areaHash, bytes32 docHash)
        external
        returns (uint256 concessionId)
    {
        _onlyRegulator();
        if (!licences.isValidFor(licenceId, orgId, SiteLib.MINING_LICENCE)) {
            revert SiteLib.MineSiteRegistry__InvalidLicence(licenceId);
        }
        concessionId = _nextConcessionId++;
        _concessions[concessionId] = SiteLib.Concession({
            orgId: orgId,
            licenceId: licenceId,
            areaHash: areaHash,
            docHash: docHash,
            grantedBy: msg.sender,
            grantedAt: uint64(block.timestamp),
            revoked: false
        });
        emit SiteLib.ConcessionGranted(concessionId, orgId, licenceId, areaHash, docHash);
    }

    /**
     * @notice Revokes a concession. Its sites can no longer produce or be reactivated.
     * @dev Only a regulator. Irreversible.
     * @param concessionId Concession to revoke.
     * @param reasonHash Hash of the revocation decision.
     * @custom:emits ConcessionRevoked
     */
    function revokeConcession(uint256 concessionId, bytes32 reasonHash) external {
        _onlyRegulator();
        SiteLib.Concession storage c = _requireConcession(concessionId);
        if (c.revoked) revert SiteLib.MineSiteRegistry__ConcessionRevoked(concessionId);
        c.revoked = true;
        emit SiteLib.ConcessionRevoked(concessionId, msg.sender, reasonHash);
    }

    /*//////////////////////////////////////////////////////////////
                              HOLDER: SITES
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Registers a new Active mine site, with its location, inside one of the caller's
     * organisation's concessions.
     * @dev Only an active miner account (`REGISTER_LOT`) of the concession holder. The concession must
     * not be revoked and its mining licence must be valid. `location` is validated by
     * {SiteLib.validateLocation}: coordinates within WGS-84 bounds and not (0, 0); province,
     * district and sector set; every name at most {SiteLib.MAX_PLACE_NAME_LENGTH} bytes.
     *
     * Example location (Rutsiro district, Western Province):
     * `SiteLocation(-1_939_100, 29_366_200, 2_150, "Western Province", "Rutsiro", "Nyabirasi", "", "")`.
     * @param concessionId Concession the site lies in.
     * @param siteRef Internal site id from the backend; non-zero and unique.
     * @param location Geographic location of the site.
     * @param surveyHash Hash of the off-chain site survey (boundary polygon, maps, photos).
     * @return siteId New site id.
     * @custom:emits SiteRegistered
     * @custom:emits SiteStatusChanged (status Active)
     */
    function registerSite(
        uint256 concessionId,
        bytes32 siteRef,
        SiteLib.SiteLocation calldata location,
        bytes32 surveyHash
    ) external returns (uint256 siteId) {
        SiteLib.Concession storage c = _requireConcession(concessionId);
        _onlyOrgMiner(c.orgId);
        if (c.revoked) revert SiteLib.MineSiteRegistry__ConcessionRevoked(concessionId);
        if (!licences.isValid(c.licenceId)) revert SiteLib.MineSiteRegistry__InvalidLicence(c.licenceId);
        if (siteRef == bytes32(0)) revert SiteLib.MineSiteRegistry__InvalidSiteRef();
        if (siteOfRef[siteRef] != 0) revert SiteLib.MineSiteRegistry__DuplicateSiteRef(siteRef);
        SiteLib.validateLocation(location);

        siteId = _nextSiteId++;
        SiteLib.Site storage s = _sites[siteId];
        s.concessionId = concessionId;
        s.siteRef = siteRef;
        s.surveyHash = surveyHash;
        s.status = SiteLib.SiteStatus.Active;
        s.statusSince = uint64(block.timestamp);
        _locations[siteId] = location;
        siteOfRef[siteRef] = siteId;
        _sitesOf[c.orgId].push(siteId);
        _sitesOfConcession[concessionId].push(siteId);

        emit SiteLib.SiteRegistered(siteId, concessionId, c.orgId, siteRef, location, surveyHash);
        emit SiteLib.SiteStatusChanged(siteId, SiteLib.SiteStatus.Active, msg.sender, surveyHash);
    }

    /**
     * @notice Corrects the recorded location of a site, e.g. after a new survey.
     * @dev Only a regulator, so a holder cannot move a site after lots have been traced to it. The
     * previous location stays available in earlier events. Allowed in any status.
     * @param siteId Site to correct.
     * @param location Corrected location (validated like at registration).
     * @param surveyHash Hash of the survey that supports the correction; becomes the site's survey.
     * @custom:emits SiteLocationCorrected
     */
    function correctSiteLocation(uint256 siteId, SiteLib.SiteLocation calldata location, bytes32 surveyHash) external {
        _onlyRegulator();
        SiteLib.Site storage s = _requireSite(siteId);
        SiteLib.validateLocation(location);
        s.surveyHash = surveyHash;
        _locations[siteId] = location;
        emit SiteLib.SiteLocationCorrected(siteId, location, surveyHash, msg.sender);
    }

    /**
     * @notice Stops mining at an Active site and files the plan for making the open ground safe.
     * @dev The holder's miner accounts, its staff with `MANAGE_SITE` at the site, or a regulator (e.g.
     * a stop order). Resets the site's safety record; the safety inspection clock starts now.
     * @param siteId Active site.
     * @param safetyPlanHash Hash of the safety plan for the open ground.
     * @custom:emits SiteStatusChanged (status Dormant)
     */
    function declareDormant(uint256 siteId, bytes32 safetyPlanHash) external {
        SiteLib.Site storage s = _requireSite(siteId);
        if (!registry.isAuthorized(msg.sender, Actions.REGULATE)) {
            _onlySiteActor(_concessions[s.concessionId].orgId, siteId, StaffLib.MANAGE_SITE);
        }
        _requireStatus(siteId, SiteLib.SiteStatus.Active);
        s.safetyPlanHash = safetyPlanHash;
        s.safetyMeasures = 0;
        s.safetyCheckedAt = 0;
        s.safetyPassed = false;
        _setStatus(siteId, SiteLib.SiteStatus.Dormant, safetyPlanHash);
    }

    /**
     * @notice Records a measure taken at a dormant site to protect people and animals from the open
     * ground.
     * @dev The holder's miner accounts or its staff with `SITE_SAFETY` at the site.
     * @param siteId Dormant site.
     * @param measure Kind of measure.
     * @param evidenceHash Hash of the evidence (photos, invoices...).
     * @custom:emits SafetyMeasureRecorded
     */
    function recordSafetyMeasure(uint256 siteId, SiteLib.SafetyMeasure measure, bytes32 evidenceHash) external {
        SiteLib.Site storage s = _requireSite(siteId);
        _onlySiteActor(_concessions[s.concessionId].orgId, siteId, StaffLib.SITE_SAFETY);
        _requireStatus(siteId, SiteLib.SiteStatus.Dormant);
        s.safetyMeasures += 1;
        emit SiteLib.SafetyMeasureRecorded(siteId, measure, msg.sender, evidenceHash);
    }

    /**
     * @notice Records the result of a safety inspection of a dormant site.
     * @dev An inspector or a regulator from outside the holder organisation.
     * @param siteId Dormant site.
     * @param passed Whether the site's measures make the open ground safe.
     * @param reportHash Hash of the inspection report.
     * @custom:emits SafetyInspected
     */
    function inspectSafety(uint256 siteId, bool passed, bytes32 reportHash) external {
        SiteLib.Site storage s = _requireSite(siteId);
        _onlyIndependentChecker(_concessions[s.concessionId].orgId, siteId);
        _requireStatus(siteId, SiteLib.SiteStatus.Dormant);
        s.safetyCheckedAt = uint64(block.timestamp);
        s.safetyPassed = passed;
        emit SiteLib.SafetyInspected(siteId, msg.sender, passed, reportHash);
    }

    /**
     * @notice Resumes mining at a dormant site.
     * @dev The holder's miner accounts or its staff with `MANAGE_SITE` at the site. The concession must
     * not be revoked and its mining licence must be valid.
     * @param siteId Dormant site.
     * @param evidenceHash Hash of the supporting evidence.
     * @custom:emits SiteStatusChanged (status Active)
     */
    function reactivateSite(uint256 siteId, bytes32 evidenceHash) external {
        SiteLib.Site storage s = _requireSite(siteId);
        SiteLib.Concession storage c = _concessions[s.concessionId];
        _onlySiteActor(c.orgId, siteId, StaffLib.MANAGE_SITE);
        _requireStatus(siteId, SiteLib.SiteStatus.Dormant);
        if (c.revoked) revert SiteLib.MineSiteRegistry__ConcessionRevoked(s.concessionId);
        if (!licences.isValid(c.licenceId)) revert SiteLib.MineSiteRegistry__InvalidLicence(c.licenceId);
        _setStatus(siteId, SiteLib.SiteStatus.Active, evidenceHash);
    }

    /**
     * @notice Closes a rehabilitated dormant site for good.
     * @dev Only a regulator. The site's last safety inspection must have passed. Irreversible.
     * @param siteId Dormant site.
     * @param rehabilitationCertHash Hash of the rehabilitation certificate (e.g. issued by REMA).
     * @custom:emits SiteStatusChanged (status Closed)
     */
    function closeSite(uint256 siteId, bytes32 rehabilitationCertHash) external {
        _onlyRegulator();
        SiteLib.Site storage s = _requireSite(siteId);
        _requireStatus(siteId, SiteLib.SiteStatus.Dormant);
        if (s.safetyCheckedAt == 0 || !s.safetyPassed) revert SiteLib.MineSiteRegistry__SafetyNotVerified(siteId);
        _setStatus(siteId, SiteLib.SiteStatus.Closed, rehabilitationCertHash);
    }

    /*//////////////////////////////////////////////////////////////
                                 RESERVES
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Declares, or updates, the estimated deposit of a mineral at a site.
     * @dev The holder's miner accounts or its staff with `DECLARE_RESERVES` at the site. An update
     * clears any earlier verification.
     * @param siteId Site id.
     * @param mineralType Mineral identifier (e.g. `keccak256("TIN")`).
     * @param estimatedQty Estimated quantity, in grams; non-zero.
     * @param reportHash Hash of the resource / exploration report.
     * @custom:emits ReserveDeclared
     */
    function declareReserve(uint256 siteId, bytes32 mineralType, uint128 estimatedQty, bytes32 reportHash) external {
        SiteLib.Site storage s = _requireSite(siteId);
        _onlySiteActor(_concessions[s.concessionId].orgId, siteId, StaffLib.DECLARE_RESERVES);
        if (estimatedQty == 0) revert SiteLib.MineSiteRegistry__InvalidQuantity();
        SiteLib.Reserve storage r = _reserves[siteId][mineralType];
        if (r.declaredBy == address(0)) _reserveMinerals[siteId].push(mineralType);
        r.estimatedQty = estimatedQty;
        r.reportHash = reportHash;
        r.declaredBy = msg.sender;
        r.declaredAt = uint64(block.timestamp);
        r.verifiedBy = address(0);
        r.verifiedAt = 0;
        emit SiteLib.ReserveDeclared(siteId, mineralType, estimatedQty, reportHash, msg.sender);
    }

    /**
     * @notice Confirms a declared reserve.
     * @dev An inspector or a regulator from outside the holder organisation.
     * @param siteId Site id.
     * @param mineralType Mineral identifier.
     * @param reportHash Hash of the verification report.
     * @custom:emits ReserveVerified
     */
    function verifyReserve(uint256 siteId, bytes32 mineralType, bytes32 reportHash) external {
        SiteLib.Site storage s = _requireSite(siteId);
        _onlyIndependentChecker(_concessions[s.concessionId].orgId, siteId);
        SiteLib.Reserve storage r = _reserves[siteId][mineralType];
        if (r.declaredBy == address(0)) revert SiteLib.MineSiteRegistry__UnknownReserve(siteId, mineralType);
        r.verifiedBy = msg.sender;
        r.verifiedAt = uint64(block.timestamp);
        emit SiteLib.ReserveVerified(siteId, mineralType, msg.sender, reportHash);
    }

    /*//////////////////////////////////////////////////////////////
                                  VIEWS
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc ISiteRegistry
     */
    function canProduce(uint256 siteId, address account) external view returns (bool) {
        SiteLib.Site storage s = _sites[siteId];
        if (s.status != SiteLib.SiteStatus.Active) return false;
        SiteLib.Concession storage c = _concessions[s.concessionId];
        return !c.revoked && licences.isValid(c.licenceId) && registry.participant(account).orgId == c.orgId;
    }

    /**
     * @inheritdoc ISiteRegistry
     */
    function orgOfSite(uint256 siteId) public view returns (bytes32) {
        return _concessions[_sites[siteId].concessionId].orgId;
    }

    /**
     * @notice Whether a dormant site's open ground is not, or no longer, verified safe in time.
     * @dev True if the site is Dormant and either: it has not been inspected within
     * {safetyGracePeriod} of going dormant; its last inspection failed; or its last passing
     * inspection is older than {safetyRecheckInterval}.
     * @param siteId Site id.
     * @return True if the site's safety is overdue.
     */
    function isSafetyOverdue(uint256 siteId) public view returns (bool) {
        SiteLib.Site storage s = _sites[siteId];
        if (s.status != SiteLib.SiteStatus.Dormant) return false;
        if (s.safetyCheckedAt == 0) return block.timestamp > s.statusSince + safetyGracePeriod;
        if (!s.safetyPassed) return true;
        return block.timestamp > s.safetyCheckedAt + safetyRecheckInterval;
    }

    /**
     * @notice An organisation's dormant sites whose safety is overdue, for regulators and management.
     * @dev Iterates over all the organisation's sites; intended for off-chain calls.
     * @param orgId Organisation id.
     * @return ids Ids of the overdue sites.
     */
    function overdueSafetySites(bytes32 orgId) external view returns (uint256[] memory ids) {
        uint256[] storage all = _sitesOf[orgId];
        ids = new uint256[](all.length);
        uint256 n;
        for (uint256 i; i < all.length; ++i) {
            if (isSafetyOverdue(all[i])) ids[n++] = all[i];
        }
        assembly ("memory-safe") {
            mstore(ids, n)
        }
    }

    /**
     * @notice Returns a concession.
     * @param concessionId Concession id.
     * @return The concession (all fields zero if unknown).
     */
    function getConcession(uint256 concessionId) external view returns (SiteLib.Concession memory) {
        return _concessions[concessionId];
    }

    /**
     * @notice Returns a site's state.
     * @param siteId Site id.
     * @return The site (all fields zero if unknown).
     */
    function getSite(uint256 siteId) external view returns (SiteLib.Site memory) {
        return _sites[siteId];
    }

    /**
     * @notice Returns a site's current geographic location.
     * @param siteId Site id.
     * @return The site's location (all fields zero / empty if unknown).
     */
    function getSiteLocation(uint256 siteId) external view returns (SiteLib.SiteLocation memory) {
        return _locations[siteId];
    }

    /**
     * @notice Returns all sites of an organisation, in registration order.
     * @param orgId Organisation id.
     * @return Site ids.
     */
    function sitesOf(bytes32 orgId) external view returns (uint256[] memory) {
        return _sitesOf[orgId];
    }

    /**
     * @notice Returns all sites of a concession, in registration order.
     * @param concessionId Concession id.
     * @return Site ids.
     */
    function sitesOfConcession(uint256 concessionId) external view returns (uint256[] memory) {
        return _sitesOfConcession[concessionId];
    }

    /**
     * @notice Returns the reserve of a mineral declared at a site.
     * @param siteId Site id.
     * @param mineralType Mineral identifier.
     * @return The reserve (all fields zero if none declared).
     */
    function getReserve(uint256 siteId, bytes32 mineralType) external view returns (SiteLib.Reserve memory) {
        return _reserves[siteId][mineralType];
    }

    /**
     * @notice Returns the minerals with a declared reserve at a site, in declaration order.
     * @param siteId Site id.
     * @return Mineral identifiers.
     */
    function reserveMinerals(uint256 siteId) external view returns (bytes32[] memory) {
        return _reserveMinerals[siteId];
    }

    /**
     * @notice Number of sites ever registered.
     * @return Total site count.
     */
    function totalSites() external view returns (uint256) {
        return _nextSiteId - 1;
    }

    /**
     * @notice Number of concessions ever granted.
     * @return Total concession count.
     */
    function totalConcessions() external view returns (uint256) {
        return _nextConcessionId - 1;
    }

    /*//////////////////////////////////////////////////////////////
                                INTERNAL
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Moves a site to `status` and timestamps the change.
     * @param siteId Site id.
     * @param status New status.
     * @param evidenceHash Hash of the supporting evidence.
     */
    function _setStatus(uint256 siteId, SiteLib.SiteStatus status, bytes32 evidenceHash) private {
        SiteLib.Site storage s = _sites[siteId];
        s.status = status;
        s.statusSince = uint64(block.timestamp);
        emit SiteLib.SiteStatusChanged(siteId, status, msg.sender, evidenceHash);
    }

    /**
     * @dev Returns the concession, reverting if it does not exist.
     * @param concessionId Concession id.
     * @return c Storage pointer to the concession.
     */
    function _requireConcession(uint256 concessionId) private view returns (SiteLib.Concession storage c) {
        c = _concessions[concessionId];
        if (c.grantedBy == address(0)) revert SiteLib.MineSiteRegistry__UnknownConcession(concessionId);
    }

    /**
     * @dev Returns the site, reverting if it does not exist.
     * @param siteId Site id.
     * @return s Storage pointer to the site.
     */
    function _requireSite(uint256 siteId) private view returns (SiteLib.Site storage s) {
        s = _sites[siteId];
        if (s.status == SiteLib.SiteStatus.None) revert SiteLib.MineSiteRegistry__UnknownSite(siteId);
    }

    /**
     * @dev Reverts unless the site is in `expected` status.
     * @param siteId Site id.
     * @param expected Required status.
     */
    function _requireStatus(uint256 siteId, SiteLib.SiteStatus expected) private view {
        SiteLib.SiteStatus current = _sites[siteId].status;
        if (current != expected) revert SiteLib.MineSiteRegistry__InvalidStatus(siteId, current);
    }

    /**
     * @dev Reverts unless the caller is an active miner (`REGISTER_LOT`) of `orgId`.
     * @param orgId Organisation id.
     */
    function _onlyOrgMiner(bytes32 orgId) private view {
        if (registry.participant(msg.sender).orgId != orgId || !registry.isAuthorized(msg.sender, Actions.REGISTER_LOT))
        {
            revert SiteLib.MineSiteRegistry__NotOrgMember(msg.sender, orgId);
        }
    }

    /**
     * @dev Reverts unless the caller is a miner account of `orgId`, or its staff holding `permission`
     * at `siteId`.
     * @param orgId Organisation id.
     * @param siteId Site id.
     * @param permission Required staff permission ({StaffLib}).
     */
    function _onlySiteActor(bytes32 orgId, uint256 siteId, uint32 permission) private view {
        if (registry.participant(msg.sender).orgId == orgId && registry.isAuthorized(msg.sender, Actions.REGISTER_LOT))
        {
            return;
        }
        IStaffDirectory dir = staff;
        if (address(dir) != address(0) && dir.staffOrg(msg.sender, siteId, permission) == orgId) return;
        revert SiteLib.MineSiteRegistry__NotOrgMember(msg.sender, orgId);
    }

    /**
     * @dev Reverts unless the caller is a regulator, or an inspector deployed to the site's district (once the
     * roster is set), from outside `orgId`.
     * @param orgId Organisation being checked.
     * @param siteId Site being checked.
     */
    function _onlyIndependentChecker(bytes32 orgId, uint256 siteId) private view {
        bool regulator = registry.isAuthorized(msg.sender, Actions.REGULATE);
        if (!regulator && !registry.isAuthorized(msg.sender, Actions.INSPECT_LOT)) {
            revert SiteLib.MineSiteRegistry__NotInspectorOrRegulator(msg.sender);
        }
        if (registry.participant(msg.sender).orgId == orgId) {
            revert SiteLib.MineSiteRegistry__NotIndependent(msg.sender);
        }
        IInspectionRegistry roster = inspections;
        if (!regulator && address(roster) != address(0) && !roster.coversSite(msg.sender, siteId)) {
            revert SiteLib.MineSiteRegistry__NotDeployedToSite(msg.sender, siteId);
        }
    }

    /**
     * @dev Reverts unless the caller is an authorised regulator.
     */
    function _onlyRegulator() private view {
        if (!registry.isAuthorized(msg.sender, Actions.REGULATE)) {
            revert SiteLib.MineSiteRegistry__NotRegulator(msg.sender);
        }
    }

    /**
     * @dev Reverts unless the caller is a {MineNetRegistry} admin.
     */
    function _onlyRegistryAdmin() private view {
        if (!registry.isAdmin(msg.sender)) {
            revert SiteLib.MineSiteRegistry__NotRegistryAdmin(msg.sender);
        }
    }
}
