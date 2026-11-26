// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {IMineNetRegistry} from "src/access/interfaces/IMineNetRegistry.sol";
import {Actions} from "src/access/libraries/Actions.sol";
import {AuditLib} from "src/compliance/libraries/AuditLib.sol";

/**
 * @title AuditRegistry
 * @author 0xEmmyb2
 * @notice The roster of accredited audit firms and the audits of mineral companies: accreditation by a standards
 * body, selection by the audited company from the accredited roster, independence and rotation safeguards, and
 * review of reports by the accreditation body before a certification counts.
 * @dev Mirrors how mineral supply-chain audits work under the OECD Due Diligence Guidance and the ICGLR Regional
 * Certification Mechanism:
 *
 * 1. Accreditation. Audit firms cannot declare themselves auditors. An accreditation body (role ACCREDITOR, e.g.
 *    the ICGLR Audit Committee for ICGLR third-party audits, the Responsible Minerals Initiative for RMAP audits,
 *    ICPAR for financial audits) vets a firm and places it on the scheme's roster with an expiry
 *    ({accredit}); it can suspend it at any time.
 * 2. Selection. The audited company (e.g. an exporter keeping its ICGLR Certified Exporter status) chooses and pays a
 *    firm strictly from that roster ({requestAudit}). A buyer can also request an audit of a supplier, which the
 *    supplier must consent to. Only one engagement per company and scheme can be open at a time, which prevents
 *    opinion shopping.
 * 3. Independence. The firm cannot be the company itself, nor have declared financial, consulting or ownership ties
 *    with it ({setConflict}: disclosed by the firm or the company, cleared only by an accreditation body). The same
 *    firm cannot audit the same company more than `maxConsecutive` times in a row until a cooling-off period has
 *    passed.
 * 4. Review. For schemes that require it (ICGLR: the Independent Mineral Chain Auditor), the accreditation body
 *    reviews the report and publishes an executive summary ({reviewReport}) before the certification counts, which
 *    prevents rubber-stamping. A passed and approved audit certifies the company for the scheme's validity period
 *    ({isCertified}); a failed or rejected one ends any current certification.
 *
 * Fees are agreed off-chain or through a {B2BServices} `Audit` agreement. Only document hashes are stored.
 */
contract AuditRegistry {
    using EnumerableSet for EnumerableSet.Bytes32Set;

    /*//////////////////////////////////////////////////////////////
                                 STORAGE
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Participant, role and permission registry.
     */
    IMineNetRegistry public immutable registry;

    /**
     * @dev Next engagement id; ids start at 1 so that 0 means "none".
     */
    uint256 private _nextEngagementId = 1;

    /**
     * @dev Scheme => configuration.
     */
    mapping(bytes32 scheme => AuditLib.Scheme) private _schemes;

    /**
     * @dev Audit firm => scheme => accreditation.
     */
    mapping(bytes32 auditorOrg => mapping(bytes32 scheme => AuditLib.Accreditation)) private _accreditations;

    /**
     * @dev Scheme => audit firms ever accredited for it (the roster; check {isAccredited} for current standing).
     */
    mapping(bytes32 scheme => EnumerableSet.Bytes32Set) private _rosters;

    /**
     * @notice Whether a conflict of interest is recorded between an audit firm and a company.
     */
    mapping(bytes32 auditorOrg => mapping(bytes32 subjectOrg => bool)) public conflicted;

    /**
     * @dev Engagement id => engagement.
     */
    mapping(uint256 engagementId => AuditLib.Engagement) private _engagements;

    /**
     * @notice A company's open engagement for a scheme (0 if none).
     */
    mapping(bytes32 subjectOrg => mapping(bytes32 scheme => uint256 engagementId)) public openEngagementOf;

    /**
     * @dev Company => scheme => rotation state.
     */
    mapping(bytes32 subjectOrg => mapping(bytes32 scheme => AuditLib.Rotation)) private _rotations;

    /**
     * @notice Until when a company is certified under a scheme (0 = not certified).
     */
    mapping(bytes32 subjectOrg => mapping(bytes32 scheme => uint64 until)) public certifiedUntil;

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @param registry_ Participant, role and permission registry.
     */
    constructor(IMineNetRegistry registry_) {
        registry = registry_;
    }

    /*//////////////////////////////////////////////////////////////
                  USER-FACING STATE-CHANGING FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Configures an audit scheme: its accreditation body, certification validity, rotation limits and
     * whether reports are reviewed.
     * @dev Only a {MineNetRegistry} admin. Changes apply to engagements requested afterwards.
     * @param scheme Scheme id (e.g. {AuditLib.ICGLR_THIRD_PARTY_AUDIT}).
     * @param config The configuration.
     * @custom:emits SchemeSet
     */
    function setScheme(bytes32 scheme, AuditLib.Scheme calldata config) external {
        if (!registry.isAdmin(msg.sender)) revert AuditLib.AuditRegistry__NotRegistryAdmin(msg.sender);
        if (
            scheme == bytes32(0) || config.accreditorOrg == bytes32(0) || config.validity == 0
                || config.maxConsecutive == 0
        ) revert AuditLib.AuditRegistry__InvalidScheme();
        _schemes[scheme] = config;
        emit AuditLib.SchemeSet(scheme, config);
    }

    /**
     * @notice Accredits (or re-accredits) an audit firm for a scheme, placing it on the roster.
     * @dev Only an account of the scheme's accreditation body (`ACCREDIT`). The firm must be a registered organisation
     * other than the accreditation body.
     * @param auditorOrg The audit firm.
     * @param scheme The scheme.
     * @param expiresAt Accreditation expiry; in the future.
     * @param docHash Hash of the accreditation certificate; non-zero.
     * @custom:emits AuditorAccredited
     */
    function accredit(bytes32 auditorOrg, bytes32 scheme, uint64 expiresAt, bytes32 docHash) external {
        AuditLib.Scheme storage s = _onlyAccreditor(scheme);
        if (
            !registry.orgRegistered(auditorOrg) || auditorOrg == s.accreditorOrg || expiresAt <= block.timestamp
                || docHash == bytes32(0)
        ) revert AuditLib.AuditRegistry__InvalidAccreditation();
        _accreditations[auditorOrg][scheme] = AuditLib.Accreditation({
            expiresAt: expiresAt, suspended: false, accreditedBy: msg.sender, docHash: docHash
        });
        // slither-disable-next-line unused-return (re-accrediting a firm already on the roster is a no-op)
        _rosters[scheme].add(auditorOrg);
        emit AuditLib.AuditorAccredited(auditorOrg, scheme, expiresAt, msg.sender, docHash);
    }

    /**
     * @notice Suspends or reinstates an audit firm's accreditation.
     * @dev Only an account of the scheme's accreditation body.
     * @param auditorOrg The audit firm.
     * @param scheme The scheme.
     * @param suspended Whether to suspend.
     * @param reasonHash Hash of the decision; non-zero.
     * @custom:emits AccreditationSuspended
     */
    function setAccreditationSuspended(bytes32 auditorOrg, bytes32 scheme, bool suspended, bytes32 reasonHash)
        external
    {
        _onlyAccreditor(scheme);
        if (reasonHash == bytes32(0)) revert AuditLib.AuditRegistry__MissingDocument();
        AuditLib.Accreditation storage acc = _accreditations[auditorOrg][scheme];
        if (acc.expiresAt == 0) revert AuditLib.AuditRegistry__NotAccredited(auditorOrg, scheme);
        acc.suspended = suspended;
        emit AuditLib.AccreditationSuspended(auditorOrg, scheme, suspended, msg.sender, reasonHash);
    }

    /**
     * @notice Records or clears a conflict of interest (financial, consulting or ownership ties) between an audit firm
     * and a company. A recorded conflict blocks engagements between them.
     * @dev Recording: an account of the audit firm or of the company (self-disclosure), or an accreditation body.
     * Clearing: an accreditation body only.
     * @param auditorOrg The audit firm.
     * @param subjectOrg The company.
     * @param isConflicted Whether a conflict exists.
     * @param reasonHash Hash of the disclosure or decision; non-zero.
     * @custom:emits ConflictSet
     */
    function setConflict(bytes32 auditorOrg, bytes32 subjectOrg, bool isConflicted, bytes32 reasonHash) external {
        if (reasonHash == bytes32(0)) revert AuditLib.AuditRegistry__MissingDocument();
        bool accreditor = registry.isAuthorized(msg.sender, Actions.ACCREDIT);
        bytes32 callerOrg = registry.participant(msg.sender).orgId;
        bool party = callerOrg != bytes32(0) && (callerOrg == auditorOrg || callerOrg == subjectOrg);
        if (isConflicted ? !(accreditor || party) : !accreditor) {
            revert AuditLib.AuditRegistry__Unauthorized(msg.sender);
        }
        conflicted[auditorOrg][subjectOrg] = isConflicted;
        emit AuditLib.ConflictSet(auditorOrg, subjectOrg, isConflicted, msg.sender, reasonHash);
    }

    /**
     * @notice Requests an audit of a company by an audit firm chosen from the scheme's accredited roster.
     * @dev The company itself (an account of `subjectOrg`, consent implicit), or a buyer (`BUY_LOT` or `OWN_LOT`)
     * auditing a supplier, which must then consent. The firm must be accredited and independent, the rotation rule
     * must allow it, and the company must have no other open engagement for the scheme.
     * @param scheme The scheme.
     * @param subjectOrg The company to audit.
     * @param auditorOrg The chosen audit firm.
     * @param scopeHash Hash of the audit scope and terms; non-zero.
     * @return engagementId New engagement id.
     * @custom:emits AuditRequested
     */
    function requestAudit(bytes32 scheme, bytes32 subjectOrg, bytes32 auditorOrg, bytes32 scopeHash)
        external
        returns (uint256 engagementId)
    {
        if (scopeHash == bytes32(0)) revert AuditLib.AuditRegistry__MissingDocument();
        AuditLib.Scheme storage s = _schemes[scheme];
        if (!s.enabled) revert AuditLib.AuditRegistry__SchemeDisabled(scheme);
        bytes32 callerOrg = registry.participant(msg.sender).orgId;
        bool bySubject = callerOrg != bytes32(0) && callerOrg == subjectOrg;
        if (
            !bySubject && !registry.isAuthorized(msg.sender, Actions.BUY_LOT)
                && !registry.isAuthorized(msg.sender, Actions.OWN_LOT)
        ) revert AuditLib.AuditRegistry__Unauthorized(msg.sender);
        if (!registry.orgRegistered(subjectOrg)) revert AuditLib.AuditRegistry__Unauthorized(msg.sender);
        uint256 open = openEngagementOf[subjectOrg][scheme];
        if (open != 0) revert AuditLib.AuditRegistry__EngagementOpen(open);
        _requireEligible(scheme, s, subjectOrg, auditorOrg);

        engagementId = _nextEngagementId++;
        AuditLib.Engagement storage e = _engagements[engagementId];
        e.scheme = scheme;
        e.subjectOrg = subjectOrg;
        e.auditorOrg = auditorOrg;
        e.requestedBy = msg.sender;
        e.status = AuditLib.EngagementStatus.Requested;
        e.subjectConsented = bySubject;
        e.requestedAt = uint64(block.timestamp);
        e.scopeHash = scopeHash;
        openEngagementOf[subjectOrg][scheme] = engagementId;
        emit AuditLib.AuditRequested(engagementId, scheme, subjectOrg, auditorOrg, msg.sender);
    }

    /**
     * @notice The audited company consents to an audit a buyer requested.
     * @dev An account of the audited company, while the engagement is requested.
     * @param engagementId Engagement id.
     * @custom:emits AuditConsented
     */
    function consentAudit(uint256 engagementId) external {
        AuditLib.Engagement storage e = _requireStatus(engagementId, AuditLib.EngagementStatus.Requested);
        if (registry.participant(msg.sender).orgId != e.subjectOrg) {
            revert AuditLib.AuditRegistry__Unauthorized(msg.sender);
        }
        e.subjectConsented = true;
        emit AuditLib.AuditConsented(engagementId, msg.sender);
    }

    /**
     * @notice The audit firm accepts the engagement and starts fieldwork.
     * @dev An auditor (`AUDIT`) of the chosen firm, once the company has consented, while the firm is still
     * accredited.
     * @param engagementId Engagement id.
     * @custom:emits AuditAccepted
     */
    function acceptAudit(uint256 engagementId) external {
        AuditLib.Engagement storage e = _requireStatus(engagementId, AuditLib.EngagementStatus.Requested);
        _onlyFirmAuditor(e.auditorOrg);
        if (!e.subjectConsented) revert AuditLib.AuditRegistry__ConsentRequired(engagementId);
        if (!isAccredited(e.auditorOrg, e.scheme)) {
            revert AuditLib.AuditRegistry__NotAccredited(e.auditorOrg, e.scheme);
        }
        e.status = AuditLib.EngagementStatus.Fieldwork;
        e.leadAuditor = msg.sender;
        emit AuditLib.AuditAccepted(engagementId, msg.sender);
    }

    /**
     * @notice Ends an engagement before fieldwork: the audit firm or the company declines it, or the requester
     * cancels it.
     * @dev While the engagement is requested. The company may decline an audit it did not request.
     * @param engagementId Engagement id.
     * @custom:emits AuditEnded
     */
    function endAudit(uint256 engagementId) external {
        AuditLib.Engagement storage e = _requireStatus(engagementId, AuditLib.EngagementStatus.Requested);
        bytes32 callerOrg = registry.participant(msg.sender).orgId;
        AuditLib.EngagementStatus outcome;
        if (msg.sender == e.requestedBy) {
            outcome = AuditLib.EngagementStatus.Cancelled;
        } else if (callerOrg != bytes32(0) && (callerOrg == e.auditorOrg || callerOrg == e.subjectOrg)) {
            outcome = AuditLib.EngagementStatus.Declined;
        } else {
            revert AuditLib.AuditRegistry__Unauthorized(msg.sender);
        }
        e.status = outcome;
        delete openEngagementOf[e.subjectOrg][e.scheme];
        emit AuditLib.AuditEnded(engagementId, outcome, msg.sender);
    }

    /**
     * @notice The audit firm submits its report. Schemes without review complete at once; the others wait for the
     * accreditation body.
     * @dev An auditor of the engaged firm, during fieldwork.
     * @param engagementId Engagement id.
     * @param passed The auditor's conclusion.
     * @param reportHash Hash of the full report; non-zero.
     * @param summaryHash Hash of the executive summary (used when no review is required).
     * @custom:emits AuditReported
     * @custom:emits AuditCompleted (schemes without review)
     */
    function submitReport(uint256 engagementId, bool passed, bytes32 reportHash, bytes32 summaryHash) external {
        AuditLib.Engagement storage e = _requireStatus(engagementId, AuditLib.EngagementStatus.Fieldwork);
        _onlyFirmAuditor(e.auditorOrg);
        if (reportHash == bytes32(0)) revert AuditLib.AuditRegistry__MissingDocument();
        e.passed = passed;
        e.reportHash = reportHash;
        emit AuditLib.AuditReported(engagementId, passed, reportHash);
        if (_schemes[e.scheme].reviewRequired) {
            e.status = AuditLib.EngagementStatus.InReview;
        } else {
            _complete(engagementId, e, true, summaryHash);
        }
    }

    /**
     * @notice The accreditation body reviews a report and publishes its executive summary (e.g. the ICGLR
     * Independent Mineral Chain Auditor). Only an approved, passed audit certifies the company.
     * @dev An account of the scheme's accreditation body, while the engagement is in review.
     * @param engagementId Engagement id.
     * @param approved Whether the review upholds the report.
     * @param summaryHash Hash of the published executive summary; non-zero.
     * @custom:emits AuditCompleted
     */
    function reviewReport(uint256 engagementId, bool approved, bytes32 summaryHash) external {
        AuditLib.Engagement storage e = _requireStatus(engagementId, AuditLib.EngagementStatus.InReview);
        _onlyAccreditor(e.scheme);
        if (summaryHash == bytes32(0)) revert AuditLib.AuditRegistry__MissingDocument();
        _complete(engagementId, e, approved, summaryHash);
    }

    /*//////////////////////////////////////////////////////////////
                     USER-FACING READ-ONLY FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Whether an audit firm is currently accredited for a scheme (unexpired and not suspended).
     * @param auditorOrg The audit firm.
     * @param scheme The scheme.
     * @return True if accredited.
     */
    function isAccredited(bytes32 auditorOrg, bytes32 scheme) public view returns (bool) {
        AuditLib.Accreditation storage acc = _accreditations[auditorOrg][scheme];
        return acc.expiresAt > block.timestamp && !acc.suspended;
    }

    /**
     * @notice Whether a company holds a current certification under a scheme.
     * @param subjectOrg The company.
     * @param scheme The scheme.
     * @return True if certified now.
     */
    function isCertified(bytes32 subjectOrg, bytes32 scheme) external view returns (bool) {
        return certifiedUntil[subjectOrg][scheme] > block.timestamp;
    }

    /**
     * @notice The audit firms on a scheme's roster that are accredited right now.
     * @param scheme The scheme.
     * @return firms Accredited audit firms.
     */
    function accreditedFirms(bytes32 scheme) external view returns (bytes32[] memory firms) {
        EnumerableSet.Bytes32Set storage roster = _rosters[scheme];
        uint256 n = roster.length();
        firms = new bytes32[](n);
        uint256 count;
        for (uint256 i; i < n; ++i) {
            bytes32 org = roster.at(i);
            if (isAccredited(org, scheme)) firms[count++] = org;
        }
        assembly ("memory-safe") {
            mstore(firms, count)
        }
    }

    /**
     * @notice Returns a scheme's configuration.
     * @param scheme The scheme.
     * @return The configuration.
     */
    function getScheme(bytes32 scheme) external view returns (AuditLib.Scheme memory) {
        return _schemes[scheme];
    }

    /**
     * @notice Returns an audit firm's accreditation for a scheme.
     * @param auditorOrg The audit firm.
     * @param scheme The scheme.
     * @return The accreditation (zero expiry if never accredited).
     */
    function getAccreditation(bytes32 auditorOrg, bytes32 scheme)
        external
        view
        returns (AuditLib.Accreditation memory)
    {
        return _accreditations[auditorOrg][scheme];
    }

    /**
     * @notice Returns an engagement.
     * @param engagementId Engagement id.
     * @return The engagement (status `None` if unknown).
     */
    function getEngagement(uint256 engagementId) external view returns (AuditLib.Engagement memory) {
        return _engagements[engagementId];
    }

    /**
     * @notice Returns a company's rotation state for a scheme.
     * @param subjectOrg The company.
     * @param scheme The scheme.
     * @return The rotation state.
     */
    function rotationOf(bytes32 subjectOrg, bytes32 scheme) external view returns (AuditLib.Rotation memory) {
        return _rotations[subjectOrg][scheme];
    }

    /**
     * @notice Number of engagements ever requested.
     * @return Total engagement count.
     */
    function totalEngagements() external view returns (uint256) {
        return _nextEngagementId - 1;
    }

    /*//////////////////////////////////////////////////////////////
                    INTERNAL STATE-CHANGING FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Completes an engagement, updates the rotation state and the company's certification: a passed and
     * approved audit certifies it for the scheme's validity; anything else ends its current certification.
     * @param engagementId Engagement id.
     * @param e The engagement.
     * @param approved The review outcome (true when no review is required).
     * @param summaryHash Hash of the executive summary.
     */
    function _complete(uint256 engagementId, AuditLib.Engagement storage e, bool approved, bytes32 summaryHash)
        private
    {
        AuditLib.Scheme storage s = _schemes[e.scheme];
        AuditLib.Rotation storage r = _rotations[e.subjectOrg][e.scheme];
        bool continuing =
            r.lastAuditorOrg == e.auditorOrg && block.timestamp < uint256(r.lastCompletedAt) + s.coolingOff;
        r.consecutive = continuing ? r.consecutive + 1 : 1;
        r.lastAuditorOrg = e.auditorOrg;
        r.lastCompletedAt = uint64(block.timestamp);

        e.status = AuditLib.EngagementStatus.Completed;
        e.approved = approved;
        e.completedAt = uint64(block.timestamp);
        e.summaryHash = summaryHash;
        delete openEngagementOf[e.subjectOrg][e.scheme];

        uint64 until = e.passed && approved ? uint64(block.timestamp) + s.validity : 0;
        certifiedUntil[e.subjectOrg][e.scheme] = until;
        emit AuditLib.AuditCompleted(engagementId, e.subjectOrg, e.passed, approved, summaryHash, until);
    }

    /*//////////////////////////////////////////////////////////////
                      INTERNAL READ-ONLY FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Reverts unless the firm may audit the company under the scheme: accredited, independent, and allowed by
     * the rotation rule.
     * @param scheme The scheme.
     * @param s The scheme's configuration.
     * @param subjectOrg The company.
     * @param auditorOrg The audit firm.
     */
    function _requireEligible(bytes32 scheme, AuditLib.Scheme storage s, bytes32 subjectOrg, bytes32 auditorOrg)
        private
        view
    {
        if (!isAccredited(auditorOrg, scheme)) revert AuditLib.AuditRegistry__NotAccredited(auditorOrg, scheme);
        if (auditorOrg == subjectOrg || conflicted[auditorOrg][subjectOrg]) {
            revert AuditLib.AuditRegistry__NotIndependent(auditorOrg, subjectOrg);
        }
        AuditLib.Rotation storage r = _rotations[subjectOrg][scheme];
        if (r.lastAuditorOrg == auditorOrg && r.consecutive >= s.maxConsecutive) {
            uint64 availableAt = r.lastCompletedAt + s.coolingOff;
            if (block.timestamp < availableAt) {
                revert AuditLib.AuditRegistry__RotationRequired(auditorOrg, availableAt);
            }
        }
    }

    /**
     * @dev Returns an engagement in `expected` status, reverting otherwise.
     * @param engagementId Engagement id.
     * @param expected Required status.
     * @return e Storage pointer to the engagement.
     */
    function _requireStatus(uint256 engagementId, AuditLib.EngagementStatus expected)
        private
        view
        returns (AuditLib.Engagement storage e)
    {
        e = _engagements[engagementId];
        if (e.status == AuditLib.EngagementStatus.None) revert AuditLib.AuditRegistry__UnknownEngagement(engagementId);
        if (e.status != expected) revert AuditLib.AuditRegistry__InvalidStatus(engagementId, e.status);
    }

    /**
     * @dev Returns the scheme, reverting unless the caller is an accreditation body account (`ACCREDIT`) of the
     * organisation that governs it.
     * @param scheme The scheme.
     * @return s Storage pointer to the scheme's configuration.
     */
    function _onlyAccreditor(bytes32 scheme) private view returns (AuditLib.Scheme storage s) {
        s = _schemes[scheme];
        if (
            s.accreditorOrg == bytes32(0) || !registry.isAuthorized(msg.sender, Actions.ACCREDIT)
                || registry.participant(msg.sender).orgId != s.accreditorOrg
        ) revert AuditLib.AuditRegistry__NotAccreditor(msg.sender, scheme);
    }

    /**
     * @dev Reverts unless the caller is an auditor (`AUDIT`) of the given audit firm.
     * @param auditorOrg The audit firm.
     */
    function _onlyFirmAuditor(bytes32 auditorOrg) private view {
        if (!registry.isAuthorized(msg.sender, Actions.AUDIT) || registry.participant(msg.sender).orgId != auditorOrg) {
            revert AuditLib.AuditRegistry__Unauthorized(msg.sender);
        }
    }
}
