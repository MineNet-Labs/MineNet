// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

/**
 * @title AuditLib
 * @author 0xEmmyb2
 * @notice Shared types, constants, events and custom errors of {AuditRegistry}.
 */
library AuditLib {
    /*//////////////////////////////////////////////////////////////
                                 SCHEMES
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice ICGLR Regional Certification Mechanism third-party audit of a mineral exporter (needed to keep ICGLR
     * Certified Exporter status). Auditors are accredited by the ICGLR Audit Committee; reports are reviewed by the
     * Independent Mineral Chain Auditor (IMCA), which publishes an executive summary.
     */
    bytes32 internal constant ICGLR_THIRD_PARTY_AUDIT = keccak256("ICGLR_THIRD_PARTY_AUDIT");

    /**
     * @notice Responsible Minerals Initiative RMAP audit of a smelter or refiner, aligned with the OECD Due Diligence
     * Guidance. Auditors are approved by the RMI.
     */
    bytes32 internal constant RMI_RMAP_AUDIT = keccak256("RMI_RMAP_AUDIT");

    /**
     * @notice Statutory financial audit of a company's books by an external auditor licensed by the Institute of
     * Certified Public Accountants of Rwanda (ICPAR), elected by the shareholders.
     */
    bytes32 internal constant ICPAR_FINANCIAL_AUDIT = keccak256("ICPAR_FINANCIAL_AUDIT");

    /*//////////////////////////////////////////////////////////////
                                  ENUMS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Lifecycle status of an audit engagement.
     * @dev `Requested`: waiting for the subject's consent (when a buyer requested it) and the auditor's acceptance.
     * `Fieldwork`: accepted by the auditor. `InReview`: report submitted, waiting for the accreditation body's review
     * (schemes that require it, e.g. ICGLR / IMCA). `Completed`: final. `Declined`: refused by the auditor or the
     * subject. `Cancelled`: withdrawn by the requester before acceptance.
     */
    enum EngagementStatus {
        None,
        Requested,
        Fieldwork,
        InReview,
        Completed,
        Declined,
        Cancelled,
        Lapsed // fieldwork or review ran past its time limit
    }

    /*//////////////////////////////////////////////////////////////
                                 STRUCTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Configuration of an audit scheme.
     * @param enabled Whether engagements can be requested.
     * @param reviewRequired Whether reports must be reviewed (and a summary published) by the accreditation body.
     * @param maxConsecutive Consecutive engagements the same audit firm may perform for the same company.
     * @param accreditorOrg Organisation of the accreditation body that governs the scheme.
     * @param validity How long a passed (and approved) audit certifies the company, in seconds.
     * @param coolingOff Time after the last engagement before a firm that reached `maxConsecutive` may audit the
     * same company again, in seconds.
     */
    struct Scheme {
        bool enabled;
        bool reviewRequired;
        uint8 maxConsecutive;
        bytes32 accreditorOrg;
        uint32 validity;
        uint32 coolingOff;
    }

    /**
     * @notice An audit firm's accreditation for a scheme.
     * @param expiresAt When it expires (0 = never accredited).
     * @param suspended Whether the accreditation body has suspended it.
     * @param accreditedBy Accreditation body account that granted it.
     * @param docHash Hash of the accreditation certificate.
     */
    struct Accreditation {
        uint64 expiresAt;
        bool suspended;
        address accreditedBy;
        bytes32 docHash;
    }

    /**
     * @notice An audit engagement between an audited company and an accredited audit firm.
     * @param scheme Audit scheme.
     * @param subjectOrg Audited company.
     * @param auditorOrg Accredited audit firm.
     * @param requestedBy Account that requested it (the company, or a buyer with the company's consent).
     * @param leadAuditor Account of the audit firm that accepted it.
     * @param status Current status.
     * @param subjectConsented Whether the audited company consented (implicit when it requested the audit).
     * @param passed The auditor's conclusion.
     * @param approved The accreditation body's review outcome (true when no review is required).
     * @param requestedAt When it was requested.
     * @param completedAt When it was completed (0 = not yet).
     * @param stageStartedAt When the current stage (fieldwork or review) started, for its time limit.
     * @param scopeHash Hash of the audit scope and terms.
     * @param reportHash Hash of the full audit report (kept off-chain).
     * @param summaryHash Hash of the published executive summary.
     */
    struct Engagement {
        bytes32 scheme;
        bytes32 subjectOrg;
        bytes32 auditorOrg;
        address requestedBy;
        address leadAuditor;
        EngagementStatus status;
        bool subjectConsented;
        bool passed;
        bool approved;
        uint64 requestedAt;
        uint64 completedAt;
        uint64 stageStartedAt;
        bytes32 scopeHash;
        bytes32 reportHash;
        bytes32 summaryHash;
    }

    /**
     * @notice Rotation state of a company for a scheme.
     * @param lastAuditorOrg Audit firm of the last completed engagement.
     * @param consecutive Consecutive completed engagements by that firm.
     * @param lastCompletedAt When the last engagement was completed.
     */
    struct Rotation {
        bytes32 lastAuditorOrg;
        uint8 consecutive;
        uint64 lastCompletedAt;
    }

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Emitted when the admin configures a scheme.
     * @param scheme Scheme id.
     * @param config Its configuration.
     */
    event SchemeSet(bytes32 indexed scheme, Scheme config);

    /**
     * @notice Emitted when an accreditation body accredits (or re-accredits) an audit firm.
     * @param auditorOrg Audit firm.
     * @param scheme Scheme.
     * @param expiresAt Expiry.
     * @param by Accreditation body account.
     * @param docHash Hash of the accreditation certificate.
     */
    event AuditorAccredited(
        bytes32 indexed auditorOrg, bytes32 indexed scheme, uint64 expiresAt, address indexed by, bytes32 docHash
    );

    /**
     * @notice Emitted when an accreditation is suspended or reinstated.
     * @param auditorOrg Audit firm.
     * @param scheme Scheme.
     * @param suspended Whether it is now suspended.
     * @param by Accreditation body account.
     * @param reasonHash Hash of the decision.
     */
    event AccreditationSuspended(
        bytes32 indexed auditorOrg, bytes32 indexed scheme, bool suspended, address indexed by, bytes32 reasonHash
    );

    /**
     * @notice Emitted when a conflict of interest between an audit firm and a company is declared or cleared.
     * @param auditorOrg Audit firm.
     * @param subjectOrg Company.
     * @param conflicted Whether a conflict is now recorded.
     * @param by Declaring account.
     * @param reasonHash Hash of the disclosure (financial, consulting or ownership ties).
     */
    event ConflictSet(
        bytes32 indexed auditorOrg, bytes32 indexed subjectOrg, bool conflicted, address indexed by, bytes32 reasonHash
    );

    /**
     * @notice Emitted when an audit is requested.
     * @param engagementId New engagement id.
     * @param scheme Scheme.
     * @param subjectOrg Audited company.
     * @param auditorOrg Chosen audit firm.
     * @param requestedBy Requesting account.
     */
    event AuditRequested(
        uint256 indexed engagementId,
        bytes32 indexed scheme,
        bytes32 indexed subjectOrg,
        bytes32 auditorOrg,
        address requestedBy
    );

    /**
     * @notice Emitted when the audited company consents to an audit requested by someone else.
     * @param engagementId Engagement id.
     * @param by Consenting account.
     */
    event AuditConsented(uint256 indexed engagementId, address indexed by);

    /**
     * @notice Emitted when the audit firm accepts an engagement.
     * @param engagementId Engagement id.
     * @param leadAuditor Accepting auditor.
     */
    event AuditAccepted(uint256 indexed engagementId, address indexed leadAuditor);

    /**
     * @notice Emitted when an engagement is declined or cancelled before fieldwork.
     * @param engagementId Engagement id.
     * @param status `Declined` or `Cancelled`.
     * @param by Account that ended it.
     */
    event AuditEnded(uint256 indexed engagementId, EngagementStatus status, address indexed by);

    /**
     * @notice Emitted when the auditor submits its report.
     * @param engagementId Engagement id.
     * @param passed The auditor's conclusion.
     * @param reportHash Hash of the report.
     */
    event AuditReported(uint256 indexed engagementId, bool passed, bytes32 reportHash);

    /**
     * @notice Emitted when an engagement is completed (after review where required).
     * @param engagementId Engagement id.
     * @param subjectOrg Audited company.
     * @param passed The auditor's conclusion.
     * @param approved The accreditation body's review outcome.
     * @param summaryHash Hash of the published executive summary.
     * @param certifiedUntil Certification expiry granted (0 = not certified).
     */
    event AuditCompleted(
        uint256 indexed engagementId,
        bytes32 indexed subjectOrg,
        bool passed,
        bool approved,
        bytes32 summaryHash,
        uint64 certifiedUntil
    );

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice `account` is not a {MineNetRegistry} admin.
     * @param account The account.
     */
    error AuditRegistry__NotRegistryAdmin(address account);

    /**
     * @notice The scheme configuration is invalid (no accreditation body, zero validity or rotation limit).
     */
    error AuditRegistry__InvalidScheme();

    /**
     * @notice Scheme `scheme` is not enabled.
     * @param scheme The scheme.
     */
    error AuditRegistry__SchemeDisabled(bytes32 scheme);

    /**
     * @notice `account` is not an account of the accreditation body that governs `scheme`.
     * @param account The account.
     * @param scheme The scheme.
     */
    error AuditRegistry__NotAccreditor(address account, bytes32 scheme);

    /**
     * @notice The audit firm or expiry is invalid (unregistered, the accreditation body itself, or already expired).
     */
    error AuditRegistry__InvalidAccreditation();

    /**
     * @notice Audit firm `auditorOrg` is not currently accredited for `scheme`.
     * @param auditorOrg The audit firm.
     * @param scheme The scheme.
     */
    error AuditRegistry__NotAccredited(bytes32 auditorOrg, bytes32 scheme);

    /**
     * @notice The audit firm is not independent of the company (same organisation or a declared conflict).
     * @param auditorOrg The audit firm.
     * @param subjectOrg The company.
     */
    error AuditRegistry__NotIndependent(bytes32 auditorOrg, bytes32 subjectOrg);

    /**
     * @notice The firm has audited the company `consecutive` times in a row; another firm is required until
     * `availableAt`.
     * @param auditorOrg The audit firm.
     * @param availableAt End of the cooling-off period.
     */
    error AuditRegistry__RotationRequired(bytes32 auditorOrg, uint64 availableAt);

    /**
     * @notice Engagement `engagementId` is still within its stage's time limit, which ends at `until`.
     * @param engagementId The engagement.
     * @param until End of the time limit.
     */
    error AuditRegistry__NotLapsed(uint256 engagementId, uint64 until);

    /**
     * @notice The company already has an open engagement `engagementId` for this scheme (no opinion shopping).
     * @param engagementId The open engagement.
     */
    error AuditRegistry__EngagementOpen(uint256 engagementId);

    /**
     * @notice Engagement `engagementId` does not exist.
     * @param engagementId The engagement.
     */
    error AuditRegistry__UnknownEngagement(uint256 engagementId);

    /**
     * @notice Engagement `engagementId` is in `status`, which does not allow the operation.
     * @param engagementId The engagement.
     * @param status Its current status.
     */
    error AuditRegistry__InvalidStatus(uint256 engagementId, EngagementStatus status);

    /**
     * @notice `account` may not perform the operation on this engagement.
     * @param account The account.
     */
    error AuditRegistry__Unauthorized(address account);

    /**
     * @notice The audited company has not consented to the engagement yet.
     * @param engagementId The engagement.
     */
    error AuditRegistry__ConsentRequired(uint256 engagementId);

    /**
     * @notice A required hash (scope, report, summary or reason) is zero.
     */
    error AuditRegistry__MissingDocument();
}
