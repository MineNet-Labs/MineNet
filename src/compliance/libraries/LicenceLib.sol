// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

/**
 * @title LicenceLib
 * @author 0xEmmyb2
 * @notice Shared types, events and custom errors of {LicenceRegistry}.
 */
library LicenceLib {
    /**
     * @notice Computed status of a licence.
     * @dev After `None`, ordered from least to most serious. `ExpiringSoon` is still valid, but inside the first
     * reminder window.
     */
    enum Status {
        None,
        Valid,
        ExpiringSoon, // valid, but inside the first reminder window
        Expired,
        Suspended,
        Revoked
    }

    /**
     * @notice A licence or permit issued by a regulator to an organisation.
     * @param orgId Holder organisation.
     * @param licenceType Licence type, e.g. `keccak256("MINING_LICENCE")`, `keccak256("TRANSPORT_LICENCE")`.
     * @param authority Organisation id of the issuing institution's regulator (e.g. "org-rmb").
     * @param referenceHash Hash of the licence number.
     * @param docHash Hash of the licence document held off-chain.
     * @param issuedBy Regulator account that issued it.
     * @param validFrom Start of validity (unix seconds).
     * @param validUntil End of validity (unix seconds).
     * @param noticesSent Reminders (and the expiry notice) already emitted for this validity period.
     * @param suspended True while suspended.
     * @param revoked True once revoked (terminal).
     */
    struct Licence {
        bytes32 orgId;
        bytes32 licenceType;
        bytes32 authority;
        bytes32 referenceHash;
        bytes32 docHash;
        address issuedBy;
        uint64 validFrom;
        uint64 validUntil;
        uint8 noticesSent;
        bool suspended;
        bool revoked;
    }

    /**
     * @notice Emitted when a regulator issues a licence.
     * @param licenceId New licence id.
     * @param orgId Holder organisation.
     * @param licenceType Licence type.
     * @param authority Issuing institution.
     * @param validFrom Start of validity.
     * @param validUntil End of validity.
     * @param docHash Hash of the licence document.
     */
    event LicenceIssued(
        uint256 indexed licenceId,
        bytes32 indexed orgId,
        bytes32 indexed licenceType,
        bytes32 authority,
        uint64 validFrom,
        uint64 validUntil,
        bytes32 docHash
    );

    /**
     * @notice Emitted when a licence is renewed. Expiry notices restart for the new period.
     * @param licenceId Licence id.
     * @param validUntil New end of validity.
     * @param docHash Hash of the renewal document.
     */
    event LicenceRenewed(uint256 indexed licenceId, uint64 validUntil, bytes32 docHash);

    /**
     * @notice Emitted when a licence is suspended.
     * @param licenceId Licence id.
     * @param by Regulator account.
     * @param reasonHash Hash of the suspension decision.
     */
    event LicenceSuspended(uint256 indexed licenceId, address indexed by, bytes32 reasonHash);

    /**
     * @notice Emitted when a suspended licence is reinstated.
     * @param licenceId Licence id.
     * @param by Regulator account.
     * @param reasonHash Hash of the reinstatement decision.
     */
    event LicenceReinstated(uint256 indexed licenceId, address indexed by, bytes32 reasonHash);

    /**
     * @notice Emitted when a licence is revoked.
     * @param licenceId Licence id.
     * @param by Regulator account.
     * @param reasonHash Hash of the revocation decision.
     */
    event LicenceRevoked(uint256 indexed licenceId, address indexed by, bytes32 reasonHash);

    /**
     * @notice Emitted when a licence is about to expire, for email, SMS and dashboard notices.
     * @param licenceId Licence id.
     * @param orgId Holder organisation.
     * @param validUntil End of validity.
     * @param secondsLeft Time left when the reminder went out.
     */
    event LicenceExpiryReminder(
        uint256 indexed licenceId, bytes32 indexed orgId, uint64 validUntil, uint64 secondsLeft
    );

    /**
     * @notice Emitted once when a licence has expired.
     * @param licenceId Licence id.
     * @param orgId Holder organisation.
     * @param validUntil End of validity that has passed.
     */
    event LicenceExpired(uint256 indexed licenceId, bytes32 indexed orgId, uint64 validUntil);

    /**
     * @notice Emitted when the admin sets the expiry reminder thresholds.
     * @param thresholds Seconds before expiry at which reminders go out, largest first.
     */
    event ReminderThresholdsSet(uint32[] thresholds);

    /**
     * @notice `account` is not an admin of {MineNetRegistry}.
     * @param account The account.
     */
    error LicenceRegistry__NotRegistryAdmin(address account);

    /**
     * @notice `account` is not an authorised regulator.
     * @param account The account.
     */
    error LicenceRegistry__NotRegulator(address account);

    /**
     * @notice Licence `licenceId` does not exist.
     * @param licenceId The licence id.
     */
    error LicenceRegistry__UnknownLicence(uint256 licenceId);

    /**
     * @notice The holder organisation is zero.
     */
    error LicenceRegistry__InvalidOrg();

    /**
     * @notice The validity period ends before it starts or is already over, or a renewal does not extend it.
     * @param validFrom Supplied start of validity.
     * @param validUntil Supplied end of validity.
     */
    error LicenceRegistry__InvalidPeriod(uint64 validFrom, uint64 validUntil);

    /**
     * @notice Licence `licenceId` has been revoked.
     * @param licenceId The licence id.
     */
    error LicenceRegistry__Revoked(uint256 licenceId);

    /**
     * @notice Licence `licenceId` is already suspended.
     * @param licenceId The licence id.
     */
    error LicenceRegistry__AlreadySuspended(uint256 licenceId);

    /**
     * @notice Licence `licenceId` is not suspended.
     * @param licenceId The licence id.
     */
    error LicenceRegistry__NotSuspended(uint256 licenceId);

    /**
     * @notice The reminder thresholds are empty, too many, zero, or not strictly decreasing.
     */
    error LicenceRegistry__InvalidThresholds();

    /**
     * @notice No reminder or expiry notice is due for licence `licenceId`.
     * @param licenceId The licence id.
     */
    error LicenceRegistry__NoNoticeDue(uint256 licenceId);
}
