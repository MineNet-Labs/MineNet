// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

/**
 * @title SiteLib
 * @author 0xEmmyb2
 * @notice Shared types, constants, events and custom errors of {MineSiteRegistry}.
 * @dev Kept in a library so that other contracts, off-chain indexers and tests can import the
 * definitions without importing the registry itself.
 */
library SiteLib {
    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Licence type a concession's permit must carry in {LicenceRegistry}.
     */
    bytes32 internal constant MINING_LICENCE = keccak256("MINING_LICENCE");

    /**
     * @notice Fixed-point scale of {SiteLocation} coordinates: one unit is one micro-degree (1e-6°),
     * a resolution of roughly 0.11 m at the equator.
     */
    int32 internal constant COORDINATE_SCALE = 1e6;

    /**
     * @notice Largest valid latitude, in micro-degrees (90°).
     */
    int32 internal constant MAX_LATITUDE = 90 * COORDINATE_SCALE;

    /**
     * @notice Largest valid longitude, in micro-degrees (180°).
     */
    int32 internal constant MAX_LONGITUDE = 180 * COORDINATE_SCALE;

    /**
     * @notice Maximum length, in bytes, of an administrative-division name in {SiteLocation}.
     * @dev Bounds the storage and gas cost of a registration and keeps names display-friendly.
     */
    uint256 internal constant MAX_PLACE_NAME_LENGTH = 64;

    /*//////////////////////////////////////////////////////////////
                                  ENUMS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Lifecycle status of a mine site.
     * @dev `None` is the default value and marks a site id that was never registered.
     */
    enum SiteStatus {
        // Unregistered site id.
        None,
        // Being mined; lots may be registered from it.
        Active,
        // Mining stopped; the open ground must be made safe and inspected.
        Dormant,
        // Rehabilitated and closed (e.g. REMA rehabilitation certificate). Terminal.
        Closed
    }

    /**
     * @notice Kind of measure taken to make the open ground of a dormant site safe.
     */
    enum SafetyMeasure {
        Fencing,
        Backfilling,
        WarningSigns,
        SlopeStabilisation,
        Drainage,
        Revegetation,
        SecurityGuard,
        Other
    }

    /*//////////////////////////////////////////////////////////////
                                 STRUCTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice A mining concession granted by a regulator to an organisation.
     * @param orgId Holder organisation.
     * @param licenceId Mining licence (permit) in {LicenceRegistry} the concession is granted under.
     * @param areaHash Hash of the concession boundary (cadastre reference, polygon).
     * @param docHash Hash of the concession deed / supporting document.
     * @param grantedBy Regulator account that granted the concession.
     * @param grantedAt Block timestamp of the grant.
     * @param revoked True once the concession has been revoked.
     */
    struct Concession {
        bytes32 orgId;
        uint256 licenceId;
        bytes32 areaHash;
        bytes32 docHash;
        address grantedBy;
        uint64 grantedAt;
        bool revoked;
    }

    /**
     * @notice Geographic location of a mine site, supplied when the site is registered.
     * @dev Coordinates are WGS-84 decimal degrees scaled by {COORDINATE_SCALE} (micro-degrees), e.g.
     * Kigali (-1.944073°, 30.061885°) is `latitude = -1_944_073`, `longitude = 30_061_885`.
     * The administrative divisions follow Rwanda's hierarchy (Province > District > Sector > Cell
     * > Village). Province, district and sector are mandatory; cell and village are optional.
     * Each name is at most {MAX_PLACE_NAME_LENGTH} bytes.
     *
     * Site locations are public on purpose: they let buyers, regulators and oracle nodes verify a
     * lot's origin. The detailed site plan (boundary polygon, survey) stays off-chain and is
     * referenced by the site's `surveyHash`.
     * @param latitude Latitude in micro-degrees, in [-90e6, 90e6].
     * @param longitude Longitude in micro-degrees, in [-180e6, 180e6].
     * @param elevation Elevation above mean sea level, in metres.
     * @param province Province (e.g. "Western Province").
     * @param district District (e.g. "Rutsiro").
     * @param sector Sector (e.g. "Nyabirasi").
     * @param cell Cell, or empty if not provided.
     * @param village Village, or empty if not provided.
     */
    struct SiteLocation {
        int32 latitude;
        int32 longitude;
        int16 elevation;
        string province;
        string district;
        string sector;
        string cell;
        string village;
    }

    /**
     * @notice A mine site inside a concession and its current state.
     * @dev The site's {SiteLocation} is stored separately and read with
     * {MineSiteRegistry-getSiteLocation}.
     * @param concessionId Concession the site belongs to.
     * @param siteRef Internal site id from the backend (unique across the registry).
     * @param surveyHash Hash of the off-chain site survey / site plan (boundary, maps, photos).
     * @param status Current lifecycle status.
     * @param statusSince Block timestamp of the last status change.
     * @param safetyPlanHash Plan filed for protecting people and animals from the open ground.
     * @param safetyMeasures Number of safety measures recorded since the site went dormant.
     * @param safetyCheckedAt Last safety inspection (0 = none since the site went dormant).
     * @param safetyPassed Result of the last safety inspection.
     */
    struct Site {
        uint256 concessionId;
        bytes32 siteRef;
        bytes32 surveyHash;
        SiteStatus status;
        uint64 statusSince;
        bytes32 safetyPlanHash;
        uint32 safetyMeasures;
        uint64 safetyCheckedAt;
        bool safetyPassed;
    }

    /**
     * @notice A declared mineral deposit at a site: data for investors and the AI market assistant.
     * @param estimatedQty Estimated quantity, in grams.
     * @param reportHash Hash of the resource / exploration report.
     * @param declaredBy Account that made the declaration.
     * @param declaredAt Block timestamp of the declaration.
     * @param verifiedBy Independent inspector or regulator that verified it (zero = unverified).
     * @param verifiedAt Block timestamp of the verification (0 = unverified).
     */
    struct Reserve {
        uint128 estimatedQty;
        bytes32 reportHash;
        address declaredBy;
        uint64 declaredAt;
        address verifiedBy;
        uint64 verifiedAt;
    }

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Emitted when a regulator grants a concession.
     * @param concessionId New concession id.
     * @param orgId Holder organisation.
     * @param licenceId Mining licence the concession is granted under.
     * @param areaHash Hash of the concession boundary.
     * @param docHash Hash of the concession document.
     */
    event ConcessionGranted(
        uint256 indexed concessionId,
        bytes32 indexed orgId,
        uint256 indexed licenceId,
        bytes32 areaHash,
        bytes32 docHash
    );

    /**
     * @notice Emitted when a regulator revokes a concession.
     * @param concessionId Revoked concession.
     * @param by Regulator account.
     * @param reasonHash Hash of the revocation decision.
     */
    event ConcessionRevoked(uint256 indexed concessionId, address indexed by, bytes32 reasonHash);

    /**
     * @notice Emitted when a holder registers a mine site.
     * @param siteId New site id.
     * @param concessionId Concession the site belongs to.
     * @param orgId Holder organisation.
     * @param siteRef Internal site id from the backend.
     * @param location Geographic location of the site.
     * @param surveyHash Hash of the off-chain site survey.
     */
    event SiteRegistered(
        uint256 indexed siteId,
        uint256 indexed concessionId,
        bytes32 indexed orgId,
        bytes32 siteRef,
        SiteLocation location,
        bytes32 surveyHash
    );

    /**
     * @notice Emitted when a regulator corrects a site's recorded location.
     * @dev The previous location remains available in the {SiteRegistered} or earlier
     * {SiteLocationCorrected} event, so the location history is append-only.
     * @param siteId Site whose location was corrected.
     * @param location Corrected location.
     * @param surveyHash Hash of the new survey that supports the correction.
     * @param by Regulator account.
     */
    event SiteLocationCorrected(uint256 indexed siteId, SiteLocation location, bytes32 surveyHash, address indexed by);

    /**
     * @notice Emitted whenever a site changes status, including at registration.
     * @param siteId Site id.
     * @param status New status.
     * @param by Account that made the change.
     * @param evidenceHash Hash of the supporting evidence (safety plan, certificate, survey...).
     */
    event SiteStatusChanged(uint256 indexed siteId, SiteStatus status, address indexed by, bytes32 evidenceHash);

    /**
     * @notice Emitted when a safety measure is recorded at a dormant site.
     * @param siteId Dormant site.
     * @param measure Kind of measure.
     * @param by Account that recorded it.
     * @param evidenceHash Hash of the evidence (photos, invoices...).
     */
    event SafetyMeasureRecorded(
        uint256 indexed siteId, SafetyMeasure indexed measure, address indexed by, bytes32 evidenceHash
    );

    /**
     * @notice Emitted when an independent inspector or a regulator inspects a dormant site.
     * @param siteId Dormant site.
     * @param inspector Inspecting account.
     * @param passed Whether the inspection passed.
     * @param reportHash Hash of the inspection report.
     */
    event SafetyInspected(uint256 indexed siteId, address indexed inspector, bool passed, bytes32 reportHash);

    /**
     * @notice Emitted when a holder declares or updates a mineral reserve.
     * @param siteId Site id.
     * @param mineralType Mineral identifier (e.g. `keccak256("TIN")`).
     * @param estimatedQty Estimated quantity, in grams.
     * @param reportHash Hash of the resource report.
     * @param by Declaring account.
     */
    event ReserveDeclared(
        uint256 indexed siteId, bytes32 indexed mineralType, uint128 estimatedQty, bytes32 reportHash, address by
    );

    /**
     * @notice Emitted when an independent inspector or a regulator verifies a reserve.
     * @param siteId Site id.
     * @param mineralType Mineral identifier.
     * @param by Verifying account.
     * @param reportHash Hash of the verification report.
     */
    event ReserveVerified(uint256 indexed siteId, bytes32 indexed mineralType, address indexed by, bytes32 reportHash);

    /**
     * @notice Emitted when the registry admin changes the dormant-site safety policy.
     * @param gracePeriod New grace period for the first safety inspection, in seconds.
     * @param recheckInterval New maximum interval between safety inspections, in seconds.
     */
    event SafetyPolicySet(uint32 gracePeriod, uint32 recheckInterval);

    /**
     * @notice Emitted when the registry admin sets the staff directory.
     * @param staff New staff directory (zero disables staff permissions).
     */
    event StaffDirectorySet(address indexed staff);

    /**
     * @notice Emitted when the admin sets the inspector roster.
     * @param inspections Inspection registry ({InspectionRegistry}).
     */
    event InspectionRegistrySet(address indexed inspections);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice `account` is not an admin of {MineNetRegistry}.
     * @param account The account.
     */
    error MineSiteRegistry__NotRegistryAdmin(address account);

    /**
     * @notice `account` is not an authorised regulator.
     * @param account The account.
     */
    error MineSiteRegistry__NotRegulator(address account);

    /**
     * @notice `account` is neither an authorised inspector nor a regulator.
     * @param account The account.
     */
    error MineSiteRegistry__NotInspectorOrRegulator(address account);

    /**
     * @notice `account` may not act for organisation `orgId`.
     * @param account The account.
     * @param orgId The organisation.
     */
    error MineSiteRegistry__NotOrgMember(address account, bytes32 orgId);

    /**
     * @notice `account` belongs to the organisation it would be checking.
     * @param account The account.
     */
    error MineSiteRegistry__NotIndependent(address account);

    /**
     * @notice Inspector `account` is not deployed to the district of site `siteId`.
     * @param account The inspector.
     * @param siteId The site.
     */
    error MineSiteRegistry__NotDeployedToSite(address account, uint256 siteId);

    /**
     * @notice Licence `licenceId` is not a valid mining licence for the operation.
     * @param licenceId The licence.
     */
    error MineSiteRegistry__InvalidLicence(uint256 licenceId);

    /**
     * @notice Concession `concessionId` does not exist.
     * @param concessionId The concession.
     */
    error MineSiteRegistry__UnknownConcession(uint256 concessionId);

    /**
     * @notice Concession `concessionId` has been revoked.
     * @param concessionId The concession.
     */
    error MineSiteRegistry__ConcessionRevoked(uint256 concessionId);

    /**
     * @notice Site `siteId` does not exist.
     * @param siteId The site.
     */
    error MineSiteRegistry__UnknownSite(uint256 siteId);

    /**
     * @notice A site with reference `siteRef` is already registered.
     * @param siteRef The site reference.
     */
    error MineSiteRegistry__DuplicateSiteRef(bytes32 siteRef);

    /**
     * @notice The site reference is zero.
     */
    error MineSiteRegistry__InvalidSiteRef();

    /**
     * @notice Site `siteId` is in `status`, which does not allow the operation.
     * @param siteId The site.
     * @param status Its current status.
     */
    error MineSiteRegistry__InvalidStatus(uint256 siteId, SiteStatus status);

    /**
     * @notice Site `siteId` has no passing safety inspection.
     * @param siteId The site.
     */
    error MineSiteRegistry__SafetyNotVerified(uint256 siteId);

    /**
     * @notice The quantity is zero.
     */
    error MineSiteRegistry__InvalidQuantity();

    /**
     * @notice No reserve of `mineralType` has been declared at site `siteId`.
     * @param siteId The site.
     * @param mineralType The mineral.
     */
    error MineSiteRegistry__UnknownReserve(uint256 siteId, bytes32 mineralType);

    /**
     * @notice The safety policy has a zero duration.
     */
    error MineSiteRegistry__InvalidPolicy();

    /**
     * @notice The coordinates are out of range, or both zero (an unset location).
     * @param latitude Supplied latitude, in micro-degrees.
     * @param longitude Supplied longitude, in micro-degrees.
     */
    error MineSiteRegistry__InvalidCoordinates(int32 latitude, int32 longitude);

    /**
     * @notice A mandatory administrative division (province, district or sector) is empty, or a
     * division name exceeds {MAX_PLACE_NAME_LENGTH} bytes.
     */
    error MineSiteRegistry__InvalidAdministrativeArea();

    /*//////////////////////////////////////////////////////////////
                               VALIDATION
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Reverts unless `location` is a well-formed site location.
     * @dev Checks that the coordinates are within WGS-84 bounds and not the (0, 0) placeholder, that
     * province, district and sector are set, and that no name exceeds {MAX_PLACE_NAME_LENGTH}.
     * Whether the point lies inside the concession area cannot be checked on-chain (the area is
     * only a hash); that check is left to the regulator and oracle nodes.
     * @param location Location to validate.
     */
    function validateLocation(SiteLocation calldata location) internal pure {
        int32 lat = location.latitude;
        int32 lon = location.longitude;
        if (
            lat < -MAX_LATITUDE || lat > MAX_LATITUDE || lon < -MAX_LONGITUDE || lon > MAX_LONGITUDE
                || (lat == 0 && lon == 0)
        ) revert MineSiteRegistry__InvalidCoordinates(lat, lon);

        if (
            !_isValidName(location.province, true) || !_isValidName(location.district, true)
                || !_isValidName(location.sector, true) || !_isValidName(location.cell, false)
                || !_isValidName(location.village, false)
        ) revert MineSiteRegistry__InvalidAdministrativeArea();
    }

    /**
     * @dev Whether `name` is at most {MAX_PLACE_NAME_LENGTH} bytes and, when `required`, not empty.
     * @param name Administrative-division name.
     * @param required Whether the name is mandatory.
     * @return True if the name is acceptable.
     */
    function _isValidName(string calldata name, bool required) private pure returns (bool) {
        uint256 len = bytes(name).length;
        return len <= MAX_PLACE_NAME_LENGTH && (!required || len != 0);
    }
}
