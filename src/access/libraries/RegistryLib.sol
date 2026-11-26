// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

/**
 * @title RegistryLib
 * @author 0xEmmyb2
 * @notice Shared types, events and custom errors of {MineNetRegistry}.
 */
library RegistryLib {
    /**
     * @notice An onboarded platform participant.
     * @param orgId Internal, opaque organisation id.
     * @param licenceHash Hash of the licence document held off-chain.
     * @param licenceExpiry Licence expiry (unix seconds); 0 = no expiry (e.g. regulators, oracle nodes).
     * @param suspended True while the participant is suspended.
     */
    struct Participant {
        bytes32 orgId;
        bytes32 licenceHash;
        uint64 licenceExpiry;
        bool suspended;
    }

    /**
     * @notice Emitted when the admin onboards a participant.
     * @param account Participant account.
     * @param role Role granted.
     * @param orgId Organisation the account acts for.
     * @param licenceHash Hash of the licence document.
     * @param licenceExpiry Licence expiry (0 = none).
     */
    event ParticipantOnboarded(
        address indexed account, bytes32 indexed role, bytes32 indexed orgId, bytes32 licenceHash, uint64 licenceExpiry
    );

    /**
     * @notice Emitted when a participant's role is changed.
     * @param account Participant account.
     * @param fromRole Previous role.
     * @param toRole New role.
     */
    event ParticipantRoleChanged(address indexed account, bytes32 indexed fromRole, bytes32 indexed toRole);

    /**
     * @notice Emitted when a participant's licence record is updated.
     * @param account Participant account.
     * @param licenceHash Hash of the new licence document.
     * @param licenceExpiry New licence expiry (0 = none).
     */
    event LicenceUpdated(address indexed account, bytes32 licenceHash, uint64 licenceExpiry);

    /**
     * @notice Emitted when a participant is suspended.
     * @param account Suspended account.
     * @param by Regulator that suspended it.
     * @param reasonHash Hash of the suspension decision.
     */
    event ParticipantSuspended(address indexed account, address indexed by, bytes32 reasonHash);

    /**
     * @notice Emitted when a suspended participant is reinstated.
     * @param account Reinstated account.
     * @param by Regulator that reinstated it.
     * @param reasonHash Hash of the reinstatement decision.
     */
    event ParticipantReinstated(address indexed account, address indexed by, bytes32 reasonHash);

    /**
     * @notice Emitted when a regulator suspends a whole organisation.
     * @param orgId The organisation.
     * @param by The regulator.
     * @param reasonHash Hash of the decision.
     */
    event OrgSuspended(bytes32 indexed orgId, address indexed by, bytes32 reasonHash);

    /**
     * @notice Emitted when a regulator lifts an organisation's suspension.
     * @param orgId The organisation.
     * @param by The regulator.
     * @param reasonHash Hash of the decision.
     */
    event OrgReinstated(bytes32 indexed orgId, address indexed by, bytes32 reasonHash);

    /**
     * @notice Emitted when the admin sets the company account receiving an organisation's proceeds.
     * @param orgId The organisation.
     * @param payout The company account (zero = the trading account).
     */
    event OrgPayoutSet(bytes32 indexed orgId, address payout);

    /**
     * @notice Emitted when a participant role is enabled or disabled.
     * @param role Role id.
     * @param enabled Whether the role can now be granted.
     */
    event ParticipantRoleSet(bytes32 indexed role, bool enabled);

    /**
     * @notice Emitted when the roles allowed to perform an action are replaced.
     * @param action Action id ({Actions}).
     * @param roles New list of roles allowed to perform it.
     */
    event ActionRolesSet(bytes32 indexed action, bytes32[] roles);

    /**
     * @notice The account is the zero address.
     */
    error MineNetRegistry__ZeroAddress();

    /**
     * @notice `role` is not an enabled participant role.
     * @param role The role.
     */
    error MineNetRegistry__UnknownRole(bytes32 role);

    /**
     * @notice The account already belongs to organisation `existing`, not `provided`.
     * @param existing Organisation on record.
     * @param provided Organisation supplied.
     */
    error MineNetRegistry__OrgMismatch(bytes32 existing, bytes32 provided);

    /**
     * @notice `account` is not suspended.
     * @param account The account.
     */
    error MineNetRegistry__NotSuspended(address account);

    /**
     * @notice `account` is already suspended.
     * @param account The account.
     */
    error MineNetRegistry__AlreadySuspended(address account);

    /**
     * @notice Organisation `orgId` is unknown, or not in the state the call needs.
     * @param orgId The organisation.
     */
    error MineNetRegistry__InvalidOrg(bytes32 orgId);

    /**
     * @notice A caller cannot suspend itself.
     */
    error MineNetRegistry__CannotSuspendSelf();

    /**
     * @notice `account` is not an authorised regulator.
     * @param account The account.
     */
    error MineNetRegistry__NotRegulator(address account);

    /**
     * @notice `account` does not hold `role`.
     * @param account The account.
     * @param role The role.
     */
    error MineNetRegistry__RoleNotHeld(address account, bytes32 role);

    /**
     * @notice `role` is reserved (the admin role) and cannot be used as a participant role.
     * @param role The role.
     */
    error MineNetRegistry__ReservedRole(bytes32 role);

    /**
     * @notice A pending request by an existing participant for an additional role.
     * @param account Requesting account.
     * @param role Role requested.
     * @param orgId Organisation of the requester.
     * @param authority Regulator institution (organisation id) that licenses the role.
     * @param requestedAt When the request was made (0 = no request).
     * @param evidenceHash Hash of the supporting documents (licence application, permit, certificates...).
     */
    struct RoleRequest {
        address account;
        bytes32 role;
        bytes32 orgId;
        bytes32 authority;
        uint64 requestedAt;
        bytes32 evidenceHash;
    }

    /**
     * @notice Emitted when the admin assigns the regulator institution that licenses a role.
     * @param role Role id.
     * @param authority Organisation id of the licensing institution (zero = admin only).
     */
    event RoleAuthoritySet(bytes32 indexed role, bytes32 indexed authority);

    /**
     * @notice Emitted when a regulator registers a new company.
     * @param orgId The new organisation.
     * @param account Its first account.
     * @param role Role granted.
     * @param by Registering regulator.
     */
    event CompanyRegistered(bytes32 indexed orgId, address indexed account, bytes32 indexed role, address by);

    /**
     * @notice Emitted when a participant requests an additional role.
     * @param account Requesting account.
     * @param role Role requested.
     * @param authority Licensing institution that will decide.
     * @param evidenceHash Hash of the supporting documents.
     */
    event RoleRequested(address indexed account, bytes32 indexed role, bytes32 indexed authority, bytes32 evidenceHash);

    /**
     * @notice Emitted when a requester cancels its role request.
     * @param account Requesting account.
     * @param role Role requested.
     */
    event RoleRequestCancelled(address indexed account, bytes32 indexed role);

    /**
     * @notice Emitted when a regulator approves a role request; the role is granted.
     * @param account Requesting account.
     * @param role Role granted.
     * @param by Approving regulator.
     * @param decisionHash Hash of the decision.
     */
    event RoleRequestApproved(address indexed account, bytes32 indexed role, address indexed by, bytes32 decisionHash);

    /**
     * @notice Emitted when a regulator rejects a role request.
     * @param account Requesting account.
     * @param role Role requested.
     * @param by Rejecting regulator.
     * @param reasonHash Hash of the reasons.
     */
    event RoleRequestRejected(address indexed account, bytes32 indexed role, address indexed by, bytes32 reasonHash);

    /**
     * @notice Emitted when the licensing authority withdraws a role it licensed.
     * @param account The account.
     * @param role Role revoked.
     * @param by Revoking regulator.
     * @param reasonHash Hash of the decision.
     */
    event RoleRevokedByAuthority(address indexed account, bytes32 indexed role, address indexed by, bytes32 reasonHash);

    /**
     * @notice `role` has no licensing authority, so only the admin can grant it.
     * @param role The role.
     */
    error MineNetRegistry__NoAuthority(bytes32 role);

    /**
     * @notice `account` is not a regulator of the institution that licenses `role`.
     * @param account The account.
     * @param role The role.
     */
    error MineNetRegistry__NotRoleAuthority(address account, bytes32 role);

    /**
     * @notice Organisation `orgId` is already registered; add roles through a role request.
     * @param orgId The organisation.
     */
    error MineNetRegistry__OrgExists(bytes32 orgId);

    /**
     * @notice `account` already belongs to an organisation.
     * @param account The account.
     */
    error MineNetRegistry__AccountExists(address account);

    /**
     * @notice The organisation id, licence hash or licence expiry is missing or already past.
     */
    error MineNetRegistry__InvalidRegistration();

    /**
     * @notice `account` is not an onboarded participant in good standing (unknown, suspended or licence expired).
     * @param account The account.
     */
    error MineNetRegistry__NotInGoodStanding(address account);

    /**
     * @notice `account` already holds `role`.
     * @param account The account.
     * @param role The role.
     */
    error MineNetRegistry__RoleAlreadyHeld(address account, bytes32 role);

    /**
     * @notice `account` already has a pending request for `role`.
     * @param account The account.
     * @param role The role.
     */
    error MineNetRegistry__RequestPending(address account, bytes32 role);

    /**
     * @notice `account` has no pending request for `role`.
     * @param account The account.
     * @param role The role.
     */
    error MineNetRegistry__NoRequest(address account, bytes32 role);

    /**
     * @notice The evidence hash is zero.
     */
    error MineNetRegistry__MissingEvidence();

    /**
     * @notice A regulator cannot decide on its own organisation.
     * @param account The account concerned.
     */
    error MineNetRegistry__ConflictOfInterest(address account);
}
