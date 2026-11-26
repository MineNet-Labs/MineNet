// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {IMineNetRegistry} from "src/access/interfaces/IMineNetRegistry.sol";
import {
    AccessControlDefaultAdminRules
} from "@openzeppelin/contracts/access/extensions/AccessControlDefaultAdminRules.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {Roles} from "src/access/libraries/Roles.sol";
import {Actions} from "src/access/libraries/Actions.sol";
import {RegistryLib} from "src/access/libraries/RegistryLib.sol";

/**
 * @title MineNetRegistry
 * @author 0xEmmyb2
 * @notice Who may act in MineNet, and what each role may do.
 * @dev Participants: the admin onboards an account into a role with an organisation id and a licence (hash +
 * expiry), can move it to another role ({changeRole}), and can revoke it. Regulators suspend or reinstate
 * accounts. Suspension or licence expiry blocks the account everywhere at once.
 *
 * Permissions: contracts never check roles directly. They ask {isAuthorized} whether an account may perform an
 * action (see {Actions}). The admin maps each action to a set of roles, and can add new participant roles, so
 * role management changes without redeploying any contract.
 *
 * Licensing: the admin maps each role to the regulator institution that licenses it ({setRoleAuthority}), e.g.
 * MINER -> RMB, CUSTOMS -> RRA. A regulator of that institution registers new companies in the role
 * ({registerCompany}) and decides on role requests from existing participants ({requestRole},
 * {approveRoleRequest}, {rejectRoleRequest}); it can also withdraw a role it licensed. A regulator never decides
 * on its own organisation, and the REGULATOR role itself can only be granted by the admin.
 *
 * Admin transfers are two-step and delayed (`AccessControlDefaultAdminRules`). Only hashes and opaque ids are
 * stored: no documents and no personal data.
 */
contract MineNetRegistry is AccessControlDefaultAdminRules, IMineNetRegistry {
    using EnumerableSet for EnumerableSet.Bytes32Set;

    /**
     * @dev Account => participant record.
     */
    mapping(address account => RegistryLib.Participant) private _participants;

    /**
     * @dev Enabled participant roles.
     */
    EnumerableSet.Bytes32Set private _participantRoles;

    /**
     * @dev Action => roles allowed to perform it.
     */
    mapping(bytes32 action => EnumerableSet.Bytes32Set) private _actionRoles;

    /**
     * @notice The regulator institution (organisation id) that licenses each role (zero = admin only).
     */
    mapping(bytes32 role => bytes32 authorityOrg) public roleAuthority;

    /**
     * @notice Whether an organisation has been registered (by the admin or a regulator).
     */
    mapping(bytes32 orgId => bool) public orgRegistered;

    /**
     * @notice Organisations suspended as a whole: every account of the company is blocked, not just one.
     */
    mapping(bytes32 orgId => bool) public orgSuspended;

    /**
     * @notice The company account that receives the organisation's trade proceeds and refunds (zero = paid to the
     * account that is party to the trade).
     */
    mapping(bytes32 orgId => address) public orgPayout;

    /**
     * @dev Request key (`keccak256(account, role)`) => role request.
     */
    mapping(bytes32 key => RegistryLib.RoleRequest) private _requests;

    /**
     * @dev Licensing institution => keys of its pending role requests.
     */
    mapping(bytes32 authorityOrg => EnumerableSet.Bytes32Set) private _pendingRequests;

    /**
     * @dev Enables the 12 default participant roles and installs the default action table ({Actions-defaults}).
     * @param initialDelay Delay (seconds) before a proposed admin transfer can be accepted.
     * @param admin Initial platform admin; should be a multisig.
     */
    constructor(uint48 initialDelay, address admin) AccessControlDefaultAdminRules(initialDelay, admin) {
        bytes32[12] memory roles = [
            Roles.MINER,
            Roles.REFINERY,
            Roles.TRANSPORTER,
            Roles.BUYER,
            Roles.WAREHOUSE,
            Roles.INSPECTOR,
            Roles.AUDITOR,
            Roles.REGULATOR,
            Roles.ORACLE,
            Roles.PROCESSOR,
            Roles.CUSTOMS,
            Roles.ACCREDITOR
        ];
        for (uint256 i; i < roles.length; ++i) {
            _participantRoles.add(roles[i]);
        }
        (bytes32[] memory actions, bytes32[][] memory actionRoles_) = Actions.defaults();
        for (uint256 i; i < actions.length; ++i) {
            _setActionRoles(actions[i], actionRoles_[i]);
        }
    }

    /*//////////////////////////////////////////////////////////////
                           ADMIN: PARTICIPANTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Onboards `account` into `role`, or adds a further role to an existing account.
     * @dev Only the admin. One account belongs to one organisation: a further role must use the same `orgId`. The
     * licence record is overwritten.
     * @param account Account to onboard.
     * @param role Enabled participant role.
     * @param orgId Organisation the account acts for.
     * @param licenceHash Hash of the licence document.
     * @param licenceExpiry Licence expiry (unix seconds), or 0 for none.
     * @custom:emits ParticipantOnboarded
     */
    function onboard(address account, bytes32 role, bytes32 orgId, bytes32 licenceHash, uint64 licenceExpiry)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        if (account == address(0)) revert RegistryLib.MineNetRegistry__ZeroAddress();
        _requireParticipantRole(role);

        RegistryLib.Participant storage p = _participants[account];
        if (p.orgId != bytes32(0) && p.orgId != orgId) revert RegistryLib.MineNetRegistry__OrgMismatch(p.orgId, orgId);

        p.orgId = orgId;
        p.licenceHash = licenceHash;
        p.licenceExpiry = licenceExpiry;
        orgRegistered[orgId] = true;
        _grantRole(role, account);

        emit RegistryLib.ParticipantOnboarded(account, role, orgId, licenceHash, licenceExpiry);
    }

    /**
     * @notice Moves an account from one role to another (e.g. a trader that becomes a refinery), keeping its
     * organisation and licence record.
     * @dev Only the admin.
     * @param account The account.
     * @param fromRole Role it currently holds.
     * @param toRole Enabled participant role to move it to.
     * @custom:emits ParticipantRoleChanged
     */
    function changeRole(address account, bytes32 fromRole, bytes32 toRole) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (!hasRole(fromRole, account)) revert RegistryLib.MineNetRegistry__RoleNotHeld(account, fromRole);
        _requireParticipantRole(toRole);
        _revokeRole(fromRole, account);
        _grantRole(toRole, account);
        emit RegistryLib.ParticipantRoleChanged(account, fromRole, toRole);
    }

    /**
     * @notice Records a renewed or changed licence.
     * @dev Only the admin.
     * @param account The account.
     * @param licenceHash Hash of the new licence document.
     * @param licenceExpiry New licence expiry (unix seconds), or 0 for none.
     * @custom:emits LicenceUpdated
     */
    function updateLicence(address account, bytes32 licenceHash, uint64 licenceExpiry)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        RegistryLib.Participant storage p = _participants[account];
        p.licenceHash = licenceHash;
        p.licenceExpiry = licenceExpiry;
        emit RegistryLib.LicenceUpdated(account, licenceHash, licenceExpiry);
    }

    /*//////////////////////////////////////////////////////////////
                  ADMIN: ROLE AND PERMISSION MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Adds a new participant role (e.g. INSURER) or retires one.
     * @dev Only the admin. Retiring a role stops it from being granted; accounts that hold it lose every action
     * through {isAuthorized}. The admin role is reserved.
     * @param role Role id.
     * @param enabled Whether the role is enabled.
     * @custom:emits ParticipantRoleSet
     */
    function setParticipantRole(bytes32 role, bool enabled) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (role == DEFAULT_ADMIN_ROLE) revert RegistryLib.MineNetRegistry__ReservedRole(role);
        if (enabled) _participantRoles.add(role);
        else _participantRoles.remove(role);
        emit RegistryLib.ParticipantRoleSet(role, enabled);
    }

    /**
     * @notice Replaces the set of roles allowed to perform `action`.
     * @dev Only the admin. Every role must be an enabled participant role.
     * @param action Action id ({Actions}).
     * @param roles Roles allowed to perform it.
     * @custom:emits ActionRolesSet
     */
    function setActionRoles(bytes32 action, bytes32[] calldata roles) external onlyRole(DEFAULT_ADMIN_ROLE) {
        for (uint256 i; i < roles.length; ++i) {
            _requireParticipantRole(roles[i]);
        }
        _setActionRoles(action, roles);
    }

    /*//////////////////////////////////////////////////////////////
                   LICENSING: REGISTRATION AND ROLE REQUESTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Assigns the regulator institution that licenses `role` (e.g. MINER -> RMB's organisation id).
     * @dev Only the admin. Zero makes the role admin-only again. The REGULATOR role cannot be delegated, so
     * regulators can never create regulators.
     * @param role Enabled participant role.
     * @param authorityOrg Organisation id of the licensing institution, or zero.
     * @custom:emits RoleAuthoritySet
     */
    function setRoleAuthority(bytes32 role, bytes32 authorityOrg) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (role == DEFAULT_ADMIN_ROLE || role == Roles.REGULATOR) {
            revert RegistryLib.MineNetRegistry__ReservedRole(role);
        }
        _requireParticipantRole(role);
        roleAuthority[role] = authorityOrg;
        emit RegistryLib.RoleAuthoritySet(role, authorityOrg);
    }

    /**
     * @notice A regulator registers a new company (e.g. a newly licensed mining company) with its first account
     * and role.
     * @dev Only a regulator of the institution that licenses `role`. The organisation must be new and the
     * account must not belong to any organisation. The licence must be on record and unexpired.
     * @param account The company's first account.
     * @param role Role granted (e.g. MINER).
     * @param orgId New organisation id.
     * @param licenceHash Hash of the licence document; non-zero.
     * @param licenceExpiry Licence expiry (unix seconds); in the future.
     * @custom:emits ParticipantOnboarded
     * @custom:emits CompanyRegistered
     */
    function registerCompany(address account, bytes32 role, bytes32 orgId, bytes32 licenceHash, uint64 licenceExpiry)
        external
    {
        _onlyRoleAuthority(role);
        if (account == address(0)) revert RegistryLib.MineNetRegistry__ZeroAddress();
        if (_participants[account].orgId != bytes32(0)) revert RegistryLib.MineNetRegistry__AccountExists(account);
        if (orgRegistered[orgId]) revert RegistryLib.MineNetRegistry__OrgExists(orgId);
        if (orgId == bytes32(0) || licenceHash == bytes32(0) || licenceExpiry <= block.timestamp) {
            revert RegistryLib.MineNetRegistry__InvalidRegistration();
        }

        _participants[account] = RegistryLib.Participant({
            orgId: orgId, licenceHash: licenceHash, licenceExpiry: licenceExpiry, suspended: false
        });
        orgRegistered[orgId] = true;
        _grantRole(role, account);
        emit RegistryLib.ParticipantOnboarded(account, role, orgId, licenceHash, licenceExpiry);
        emit RegistryLib.CompanyRegistered(orgId, account, role, _msgSender());
    }

    /**
     * @notice An existing participant requests an additional role (e.g. a trader applying to become a refinery).
     * @dev The caller must be an onboarded participant in good standing, not already holding the role, with no
     * pending request for it. The role must have a licensing authority, whose regulators decide.
     * @param role Role requested.
     * @param evidenceHash Hash of the supporting documents; non-zero.
     * @custom:emits RoleRequested
     */
    function requestRole(bytes32 role, bytes32 evidenceHash) external {
        address account = _msgSender();
        RegistryLib.Participant storage p = _participants[account];
        if (p.orgId == bytes32(0) || !_inGoodStanding(account)) {
            revert RegistryLib.MineNetRegistry__NotInGoodStanding(account);
        }
        _requireParticipantRole(role);
        bytes32 authority = roleAuthority[role];
        if (authority == bytes32(0)) revert RegistryLib.MineNetRegistry__NoAuthority(role);
        if (hasRole(role, account)) revert RegistryLib.MineNetRegistry__RoleAlreadyHeld(account, role);
        if (evidenceHash == bytes32(0)) revert RegistryLib.MineNetRegistry__MissingEvidence();
        bytes32 key = _requestKey(account, role);
        if (_requests[key].requestedAt != 0) revert RegistryLib.MineNetRegistry__RequestPending(account, role);

        _requests[key] = RegistryLib.RoleRequest({
            account: account,
            role: role,
            orgId: p.orgId,
            authority: authority,
            requestedAt: uint64(block.timestamp),
            evidenceHash: evidenceHash
        });
        _pendingRequests[authority].add(key);
        emit RegistryLib.RoleRequested(account, role, authority, evidenceHash);
    }

    /**
     * @notice Cancels the caller's pending request for `role`.
     * @param role Role requested.
     * @custom:emits RoleRequestCancelled
     */
    function cancelRoleRequest(bytes32 role) external {
        _deleteRequest(_msgSender(), role);
        emit RegistryLib.RoleRequestCancelled(_msgSender(), role);
    }

    /**
     * @notice Approves a pending role request; the role is granted.
     * @dev Only a regulator of the institution that currently licenses the role, from another organisation. The
     * requester must still be in good standing and the role still enabled.
     * @param account Requesting account.
     * @param role Role requested.
     * @param decisionHash Hash of the decision (licence number, conditions...).
     * @custom:emits RoleRequestApproved
     */
    function approveRoleRequest(address account, bytes32 role, bytes32 decisionHash) external {
        _decideRequest(account, role);
        if (!_inGoodStanding(account)) revert RegistryLib.MineNetRegistry__NotInGoodStanding(account);
        _requireParticipantRole(role);
        _grantRole(role, account);
        emit RegistryLib.RoleRequestApproved(account, role, _msgSender(), decisionHash);
    }

    /**
     * @notice Rejects a pending role request.
     * @dev Only a regulator of the institution that currently licenses the role, from another organisation.
     * @param account Requesting account.
     * @param role Role requested.
     * @param reasonHash Hash of the reasons.
     * @custom:emits RoleRequestRejected
     */
    function rejectRoleRequest(address account, bytes32 role, bytes32 reasonHash) external {
        _decideRequest(account, role);
        emit RegistryLib.RoleRequestRejected(account, role, _msgSender(), reasonHash);
    }

    /**
     * @notice The licensing authority withdraws a role it licenses from an account (e.g. licence revoked).
     * @dev Only a regulator of the institution that licenses the role, from another organisation. Suspension
     * ({suspend}) blocks every role; this removes one.
     * @param account The account.
     * @param role Role to revoke.
     * @param reasonHash Hash of the decision.
     * @custom:emits RoleRevokedByAuthority
     */
    function revokeRoleByAuthority(address account, bytes32 role, bytes32 reasonHash) external {
        _onlyRoleAuthority(role);
        _requireOtherOrg(account);
        if (!hasRole(role, account)) revert RegistryLib.MineNetRegistry__RoleNotHeld(account, role);
        _revokeRole(role, account);
        emit RegistryLib.RoleRevokedByAuthority(account, role, _msgSender(), reasonHash);
    }

    /*//////////////////////////////////////////////////////////////
                          REGULATOR: SUSPENSION
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Suspends an account, blocking it from every action at once.
     * @dev Only a regulator, and not on itself.
     * @param account Account to suspend.
     * @param reasonHash Hash of the suspension decision.
     * @custom:emits ParticipantSuspended
     */
    function suspend(address account, bytes32 reasonHash) external {
        _onlyRegulator();
        if (account == _msgSender()) revert RegistryLib.MineNetRegistry__CannotSuspendSelf();
        RegistryLib.Participant storage p = _participants[account];
        if (p.suspended) revert RegistryLib.MineNetRegistry__AlreadySuspended(account);
        p.suspended = true;
        emit RegistryLib.ParticipantSuspended(account, _msgSender(), reasonHash);
    }

    /**
     * @notice Suspends a whole organisation: every one of its accounts is blocked from every action at once.
     * @dev Only a regulator, and not on its own organisation.
     * @param orgId Organisation to suspend.
     * @param reasonHash Hash of the suspension decision.
     * @custom:emits OrgSuspended
     */
    function suspendOrg(bytes32 orgId, bytes32 reasonHash) external {
        _onlyRegulator();
        if (orgId == _participants[_msgSender()].orgId) revert RegistryLib.MineNetRegistry__CannotSuspendSelf();
        if (!orgRegistered[orgId] || orgSuspended[orgId]) revert RegistryLib.MineNetRegistry__InvalidOrg(orgId);
        orgSuspended[orgId] = true;
        emit RegistryLib.OrgSuspended(orgId, _msgSender(), reasonHash);
    }

    /**
     * @notice Lifts an organisation's suspension (accounts suspended individually stay suspended).
     * @dev Only a regulator.
     * @param orgId Organisation to reinstate.
     * @param reasonHash Hash of the reinstatement decision.
     * @custom:emits OrgReinstated
     */
    function reinstateOrg(bytes32 orgId, bytes32 reasonHash) external {
        _onlyRegulator();
        if (!orgSuspended[orgId]) revert RegistryLib.MineNetRegistry__InvalidOrg(orgId);
        orgSuspended[orgId] = false;
        emit RegistryLib.OrgReinstated(orgId, _msgSender(), reasonHash);
    }

    /**
     * @notice Sets the company account that receives an organisation's trade proceeds and refunds.
     * @dev Only the admin (from the company's verified banking / treasury details), so no single employee can
     * redirect the company's money. Zero pays the account that is party to each trade.
     * @param orgId Organisation.
     * @param payout Company account.
     * @custom:emits OrgPayoutSet
     */
    function setOrgPayout(bytes32 orgId, address payout) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (!orgRegistered[orgId]) revert RegistryLib.MineNetRegistry__InvalidOrg(orgId);
        orgPayout[orgId] = payout;
        emit RegistryLib.OrgPayoutSet(orgId, payout);
    }

    /**
     * @notice Reinstates a suspended account.
     * @dev Only a regulator.
     * @param account Account to reinstate.
     * @param reasonHash Hash of the reinstatement decision.
     * @custom:emits ParticipantReinstated
     */
    function reinstate(address account, bytes32 reasonHash) external {
        _onlyRegulator();
        RegistryLib.Participant storage p = _participants[account];
        if (!p.suspended) revert RegistryLib.MineNetRegistry__NotSuspended(account);
        p.suspended = false;
        emit RegistryLib.ParticipantReinstated(account, _msgSender(), reasonHash);
    }

    /*//////////////////////////////////////////////////////////////
                                  VIEWS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Whether `account` may perform `action`.
     * @param account The account.
     * @param action Action id ({Actions}).
     * @return True if it holds an enabled role mapped to the action, is not suspended, and its licence has not
     * expired.
     */
    function isAuthorized(address account, bytes32 action) public view returns (bool) {
        if (!_inGoodStanding(account)) return false;
        EnumerableSet.Bytes32Set storage roles = _actionRoles[action];
        uint256 n = roles.length();
        for (uint256 i; i < n; ++i) {
            bytes32 role = roles.at(i);
            if (hasRole(role, account) && _participantRoles.contains(role)) return true;
        }
        return false;
    }

    /**
     * @notice Whether `account` is the platform admin (`DEFAULT_ADMIN_ROLE`).
     * @param account The account.
     * @return True if it holds the admin role.
     */
    function isAdmin(address account) external view returns (bool) {
        return hasRole(DEFAULT_ADMIN_ROLE, account);
    }

    /**
     * @notice Whether `account` actively holds `role`.
     * @param account The account.
     * @param role Role id.
     * @return True if it holds the (still enabled) role, is not suspended, and its licence is valid.
     */
    function isActive(address account, bytes32 role) public view returns (bool) {
        return hasRole(role, account) && _participantRoles.contains(role) && _inGoodStanding(account);
    }

    /**
     * @inheritdoc IMineNetRegistry
     */
    function payoutOf(address account) external view returns (address) {
        address payout = orgPayout[_participants[account].orgId];
        return payout == address(0) ? account : payout;
    }

    /**
     * @notice Whether two accounts belong to the same organisation.
     * @param a First account.
     * @param b Second account.
     * @return True if they are the same account or share a non-zero organisation id.
     */
    function sameOrg(address a, address b) external view returns (bool) {
        if (a == b) return true;
        bytes32 orgA = _participants[a].orgId;
        return orgA != bytes32(0) && orgA == _participants[b].orgId;
    }

    /**
     * @notice Returns an account's participant record.
     * @param account The account.
     * @return The record (all fields zero if never onboarded).
     */
    function participant(address account) external view returns (RegistryLib.Participant memory) {
        return _participants[account];
    }

    /**
     * @notice Whether `role` is an enabled participant role.
     * @param role Role id.
     * @return True if enabled.
     */
    function isParticipantRole(bytes32 role) public view returns (bool) {
        return _participantRoles.contains(role);
    }

    /**
     * @notice Returns every enabled participant role.
     * @return Role ids.
     */
    function participantRoles() external view returns (bytes32[] memory) {
        return _participantRoles.values();
    }

    /**
     * @notice Returns the roles allowed to perform `action`.
     * @param action Action id.
     * @return Role ids.
     */
    function actionRoles(bytes32 action) external view returns (bytes32[] memory) {
        return _actionRoles[action].values();
    }

    /**
     * @notice Returns the request of `account` for `role`.
     * @param account Requesting account.
     * @param role Role requested.
     * @return The request (`requestedAt` 0 if none is pending).
     */
    function getRoleRequest(address account, bytes32 role) external view returns (RegistryLib.RoleRequest memory) {
        return _requests[_requestKey(account, role)];
    }

    /**
     * @notice Returns the pending role requests a licensing institution has to decide.
     * @param authorityOrg Organisation id of the licensing institution.
     * @return requests The pending requests.
     */
    function pendingRoleRequests(bytes32 authorityOrg)
        external
        view
        returns (RegistryLib.RoleRequest[] memory requests)
    {
        EnumerableSet.Bytes32Set storage keys = _pendingRequests[authorityOrg];
        uint256 n = keys.length();
        requests = new RegistryLib.RoleRequest[](n);
        for (uint256 i; i < n; ++i) {
            requests[i] = _requests[keys.at(i)];
        }
    }

    /*//////////////////////////////////////////////////////////////
                                 INTERNAL
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Replaces the roles of an action.
     * @param action Action id.
     * @param roles New roles.
     */
    function _setActionRoles(bytes32 action, bytes32[] memory roles) private {
        EnumerableSet.Bytes32Set storage set = _actionRoles[action];
        bytes32[] memory current = set.values();
        for (uint256 i; i < current.length; ++i) {
            set.remove(current[i]);
        }
        for (uint256 i; i < roles.length; ++i) {
            set.add(roles[i]);
        }
        emit RegistryLib.ActionRolesSet(action, roles);
    }

    /**
     * @dev Whether an account is not suspended and its licence has not expired.
     * @param account The account.
     * @return True if in good standing.
     */
    function _inGoodStanding(address account) private view returns (bool) {
        RegistryLib.Participant storage p = _participants[account];
        return !p.suspended && !orgSuspended[p.orgId] && (p.licenceExpiry == 0 || p.licenceExpiry >= block.timestamp);
    }

    /**
     * @dev Reverts unless `role` is an enabled participant role.
     * @param role Role id.
     */
    function _requireParticipantRole(bytes32 role) private view {
        if (!_participantRoles.contains(role)) revert RegistryLib.MineNetRegistry__UnknownRole(role);
    }

    /**
     * @dev Reverts unless the caller is an authorised regulator.
     */
    function _onlyRegulator() private view {
        if (!isAuthorized(_msgSender(), Actions.REGULATE)) {
            revert RegistryLib.MineNetRegistry__NotRegulator(_msgSender());
        }
    }

    /**
     * @dev Reverts unless the caller is an authorised regulator of the institution that licenses `role`.
     * @param role The role.
     */
    function _onlyRoleAuthority(bytes32 role) private view {
        bytes32 authority = roleAuthority[role];
        if (authority == bytes32(0)) revert RegistryLib.MineNetRegistry__NoAuthority(role);
        if (!isAuthorized(_msgSender(), Actions.REGULATE) || _participants[_msgSender()].orgId != authority) {
            revert RegistryLib.MineNetRegistry__NotRoleAuthority(_msgSender(), role);
        }
    }

    /**
     * @dev Reverts if `account` belongs to the caller's organisation.
     * @param account The account concerned.
     */
    function _requireOtherOrg(address account) private view {
        if (_participants[account].orgId == _participants[_msgSender()].orgId) {
            revert RegistryLib.MineNetRegistry__ConflictOfInterest(account);
        }
    }

    /**
     * @dev Checks the caller may decide `account`'s request for `role`, then removes the request.
     * @param account Requesting account.
     * @param role Role requested.
     */
    function _decideRequest(address account, bytes32 role) private {
        _onlyRoleAuthority(role);
        _requireOtherOrg(account);
        _deleteRequest(account, role);
    }

    /**
     * @dev Removes a pending request, reverting if there is none.
     * @param account Requesting account.
     * @param role Role requested.
     */
    function _deleteRequest(address account, bytes32 role) private {
        bytes32 key = _requestKey(account, role);
        RegistryLib.RoleRequest storage req = _requests[key];
        if (req.requestedAt == 0) revert RegistryLib.MineNetRegistry__NoRequest(account, role);
        _pendingRequests[req.authority].remove(key);
        delete _requests[key];
    }

    /**
     * @dev Storage key of a role request.
     * @param account Requesting account.
     * @param role Role requested.
     * @return The key.
     */
    function _requestKey(address account, bytes32 role) private pure returns (bytes32) {
        return keccak256(abi.encode(account, role));
    }
}
