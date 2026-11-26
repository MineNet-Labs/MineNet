// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {ILicenceRegistry} from "src/compliance/interfaces/ILicenceRegistry.sol";
import {IAutomationCompatible} from "@chainlink/contracts/src/v0.8/automation-cre/interfaces/IAutomationCompatible.sol";
import {IMineNetRegistry} from "src/access/interfaces/IMineNetRegistry.sol";
import {Actions} from "src/access/libraries/Actions.sol";
import {LicenceLib} from "src/compliance/libraries/LicenceLib.sol";

/**
 * @title LicenceRegistry
 * @author 0xEmmyb2
 * @notice Licences held by each organisation (mining licences and permits, transport, customs, insurance and
 * finance licences...), with their validity periods, so they are visible on the platform and their expiry can be
 * tracked.
 * @dev Regulators (`REGULATE`) issue, renew, suspend, reinstate and revoke licences. The issuing authority is the
 * regulator's own organisation, so it cannot be misstated.
 *
 * Expiry reminders: the admin sets reminder thresholds (by default 90, 30 and 7 days before expiry). When a
 * threshold is crossed, a {LicenceLib.LicenceExpiryReminder} event is emitted, and a {LicenceLib.LicenceExpired}
 * event once the licence has expired. The backend turns these events into notifications (email, SMS,
 * dashboard). Anyone can trigger a due notice with {sendNotice}, and the contract is Chainlink Automation
 * compatible ({checkUpkeep} / {performUpkeep}), so a Chainlink upkeep can send them without a backend. Each
 * notice is sent once per validity period; renewing a licence resets them.
 *
 * Only hashes and opaque ids are stored: no documents and no personal data.
 */
contract LicenceRegistry is IAutomationCompatible, ILicenceRegistry {
    /**
     * @notice Maximum number of licences handled in one upkeep.
     */
    uint256 public constant MAX_UPKEEP_BATCH = 50;

    /**
     * @notice Maximum number of reminder thresholds.
     */
    uint256 public constant MAX_THRESHOLDS = 5;

    /**
     * @notice Participant, role and permission registry.
     */
    IMineNetRegistry public immutable registry;

    /**
     * @dev Next licence id; ids start at 1 so that 0 means "none".
     */
    uint256 private _nextLicenceId = 1;

    /**
     * @dev Licence id => licence.
     */
    mapping(uint256 licenceId => LicenceLib.Licence) private _licences;

    /**
     * @dev Organisation => ids of its licences, in issue order.
     */
    mapping(bytes32 orgId => uint256[]) private _licencesOf;

    /**
     * @dev Seconds before expiry at which reminders go out, largest first.
     */
    uint32[] private _thresholds;

    /**
     * @dev Installs the default reminder thresholds: 90, 30 and 7 days.
     * @param registry_ Participant, role and permission registry.
     */
    constructor(IMineNetRegistry registry_) {
        registry = registry_;
        _thresholds.push(90 days);
        _thresholds.push(30 days);
        _thresholds.push(7 days);
    }

    /*//////////////////////////////////////////////////////////////
                                  ADMIN
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Replaces the reminder thresholds.
     * @dev Only a {MineNetRegistry} admin.
     * @param thresholds Seconds before expiry: 1 to {MAX_THRESHOLDS} entries, non-zero and strictly decreasing.
     * @custom:emits ReminderThresholdsSet
     */
    function setReminderThresholds(uint32[] calldata thresholds) external {
        if (!registry.isAdmin(msg.sender)) {
            revert LicenceLib.LicenceRegistry__NotRegistryAdmin(msg.sender);
        }
        if (thresholds.length == 0 || thresholds.length > MAX_THRESHOLDS) {
            revert LicenceLib.LicenceRegistry__InvalidThresholds();
        }
        for (uint256 i; i < thresholds.length; ++i) {
            if (thresholds[i] == 0 || (i > 0 && thresholds[i] >= thresholds[i - 1])) {
                revert LicenceLib.LicenceRegistry__InvalidThresholds();
            }
        }
        _thresholds = thresholds;
        emit LicenceLib.ReminderThresholdsSet(thresholds);
    }

    /*//////////////////////////////////////////////////////////////
                                REGULATOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Records a licence issued to an organisation.
     * @dev Only a regulator; the issuing authority is the regulator's own organisation.
     * @param orgId Holder organisation; non-zero.
     * @param licenceType Licence type, e.g. `keccak256("MINING_LICENCE")`.
     * @param referenceHash Hash of the licence number.
     * @param validFrom Start of validity (unix seconds); 0 means "from now".
     * @param validUntil End of validity; after `validFrom` and in the future.
     * @param docHash Hash of the licence document.
     * @return licenceId New licence id.
     * @custom:emits LicenceIssued
     */
    function issueLicence(
        bytes32 orgId,
        bytes32 licenceType,
        bytes32 referenceHash,
        uint64 validFrom,
        uint64 validUntil,
        bytes32 docHash
    ) external returns (uint256 licenceId) {
        _onlyRegulator();
        if (orgId == bytes32(0)) revert LicenceLib.LicenceRegistry__InvalidOrg();
        if (validFrom == 0) validFrom = uint64(block.timestamp);
        if (validUntil <= validFrom || validUntil <= block.timestamp) {
            revert LicenceLib.LicenceRegistry__InvalidPeriod(validFrom, validUntil);
        }
        bytes32 authority = registry.participant(msg.sender).orgId;

        licenceId = _nextLicenceId++;
        _licences[licenceId] = LicenceLib.Licence({
            orgId: orgId,
            licenceType: licenceType,
            authority: authority,
            referenceHash: referenceHash,
            docHash: docHash,
            issuedBy: msg.sender,
            validFrom: validFrom,
            validUntil: validUntil,
            noticesSent: 0,
            suspended: false,
            revoked: false
        });
        _licencesOf[orgId].push(licenceId);
        emit LicenceLib.LicenceIssued(licenceId, orgId, licenceType, authority, validFrom, validUntil, docHash);
    }

    /**
     * @notice Extends a licence to a new expiry date. Reminders start again for the new period.
     * @dev Only a regulator. Not allowed for revoked licences.
     * @param licenceId Licence id.
     * @param validUntil New end of validity; later than the current one and in the future.
     * @param docHash Hash of the renewal document.
     * @custom:emits LicenceRenewed
     */
    function renewLicence(uint256 licenceId, uint64 validUntil, bytes32 docHash) external {
        _onlyRegulator();
        LicenceLib.Licence storage l = _requireLicence(licenceId);
        if (l.revoked) revert LicenceLib.LicenceRegistry__Revoked(licenceId);
        if (validUntil <= l.validUntil || validUntil <= block.timestamp) {
            revert LicenceLib.LicenceRegistry__InvalidPeriod(l.validFrom, validUntil);
        }
        l.validUntil = validUntil;
        l.docHash = docHash;
        l.noticesSent = 0;
        emit LicenceLib.LicenceRenewed(licenceId, validUntil, docHash);
    }

    /**
     * @notice Suspends a licence. Sites and concessions depending on it stop producing.
     * @dev Only a regulator. Not allowed for revoked or already suspended licences.
     * @param licenceId Licence id.
     * @param reasonHash Hash of the suspension decision.
     * @custom:emits LicenceSuspended
     */
    function suspendLicence(uint256 licenceId, bytes32 reasonHash) external {
        _onlyRegulator();
        LicenceLib.Licence storage l = _requireLicence(licenceId);
        if (l.revoked) revert LicenceLib.LicenceRegistry__Revoked(licenceId);
        if (l.suspended) revert LicenceLib.LicenceRegistry__AlreadySuspended(licenceId);
        l.suspended = true;
        emit LicenceLib.LicenceSuspended(licenceId, msg.sender, reasonHash);
    }

    /**
     * @notice Reinstates a suspended licence.
     * @dev Only a regulator. Not allowed for revoked licences.
     * @param licenceId Licence id.
     * @param reasonHash Hash of the reinstatement decision.
     * @custom:emits LicenceReinstated
     */
    function reinstateLicence(uint256 licenceId, bytes32 reasonHash) external {
        _onlyRegulator();
        LicenceLib.Licence storage l = _requireLicence(licenceId);
        if (l.revoked) revert LicenceLib.LicenceRegistry__Revoked(licenceId);
        if (!l.suspended) revert LicenceLib.LicenceRegistry__NotSuspended(licenceId);
        l.suspended = false;
        emit LicenceLib.LicenceReinstated(licenceId, msg.sender, reasonHash);
    }

    /**
     * @notice Permanently revokes a licence.
     * @dev Only a regulator. Irreversible.
     * @param licenceId Licence id.
     * @param reasonHash Hash of the revocation decision.
     * @custom:emits LicenceRevoked
     */
    function revokeLicence(uint256 licenceId, bytes32 reasonHash) external {
        _onlyRegulator();
        LicenceLib.Licence storage l = _requireLicence(licenceId);
        if (l.revoked) revert LicenceLib.LicenceRegistry__Revoked(licenceId);
        l.revoked = true;
        emit LicenceLib.LicenceRevoked(licenceId, msg.sender, reasonHash);
    }

    /*//////////////////////////////////////////////////////////////
             EXPIRY NOTICES (ANYONE, OR CHAINLINK AUTOMATION)
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Emits the reminder (or expiry notice) that is due for a licence.
     * @dev Callable by anyone. Reverts if no notice is due.
     * @param licenceId Licence id.
     * @custom:emits LicenceExpiryReminder or LicenceExpired
     */
    function sendNotice(uint256 licenceId) external {
        if (!_sendNotice(licenceId)) revert LicenceLib.LicenceRegistry__NoNoticeDue(licenceId);
    }

    /**
     * @notice Chainlink Automation: finds licences with a notice due.
     * @dev Scans licences `[start, start + count)` abi-encoded in `checkData` (empty = all), returning at most
     * {MAX_UPKEEP_BATCH} ids. Meant for off-chain simulation.
     * @param checkData Empty, or `abi.encode(uint256 start, uint256 count)`.
     * @return upkeepNeeded True if at least one notice is due.
     * @return performData `abi.encode(uint256[] ids)` of the licences with a notice due.
     */
    function checkUpkeep(bytes calldata checkData) external view returns (bool upkeepNeeded, bytes memory performData) {
        uint256 start = 1;
        uint256 end = _nextLicenceId;
        if (checkData.length != 0) {
            (uint256 from, uint256 count) = abi.decode(checkData, (uint256, uint256));
            start = from == 0 ? 1 : from;
            if (start < end && count < end - start) end = start + count;
        }
        uint256[] memory due = new uint256[](MAX_UPKEEP_BATCH);
        uint256 n;
        for (uint256 id = start; id < end && n < MAX_UPKEEP_BATCH; ++id) {
            if (_dueNotices(_licences[id]) > _licences[id].noticesSent) due[n++] = id;
        }
        assembly ("memory-safe") {
            mstore(due, n)
        }
        upkeepNeeded = n != 0;
        performData = abi.encode(due);
    }

    /**
     * @notice Chainlink Automation: sends the notices found by {checkUpkeep}.
     * @dev The input is untrusted, so each licence is re-checked and skipped when nothing is due. At most
     * {MAX_UPKEEP_BATCH} licences are processed.
     * @param performData `abi.encode(uint256[] ids)`.
     */
    function performUpkeep(bytes calldata performData) external {
        uint256[] memory ids = abi.decode(performData, (uint256[]));
        uint256 n = ids.length < MAX_UPKEEP_BATCH ? ids.length : MAX_UPKEEP_BATCH;
        for (uint256 i; i < n; ++i) {
            _sendNotice(ids[i]);
        }
    }

    /*//////////////////////////////////////////////////////////////
                                  VIEWS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns a licence.
     * @param licenceId Licence id.
     * @return The licence (all fields zero if unknown).
     */
    function getLicence(uint256 licenceId) external view returns (LicenceLib.Licence memory) {
        return _licences[licenceId];
    }

    /**
     * @notice Returns all licences of an organisation, in issue order.
     * @param orgId Organisation id.
     * @return Licence ids.
     */
    function licencesOf(bytes32 orgId) external view returns (uint256[] memory) {
        return _licencesOf[orgId];
    }

    /**
     * @notice Returns the reminder thresholds.
     * @return Seconds before expiry, largest first.
     */
    function reminderThresholds() external view returns (uint32[] memory) {
        return _thresholds;
    }

    /**
     * @notice Number of licences ever issued.
     * @return Total licence count.
     */
    function totalLicences() external view returns (uint256) {
        return _nextLicenceId - 1;
    }

    /**
     * @notice Current status of a licence.
     * @dev `Revoked`, `Suspended` and `Expired` take precedence over `ExpiringSoon`, which applies inside the first
     * (largest) reminder threshold.
     * @param licenceId Licence id.
     * @return The status (`None` if unknown).
     */
    function status(uint256 licenceId) public view returns (LicenceLib.Status) {
        LicenceLib.Licence storage l = _licences[licenceId];
        if (l.issuedBy == address(0)) return LicenceLib.Status.None;
        if (l.revoked) return LicenceLib.Status.Revoked;
        if (l.suspended) return LicenceLib.Status.Suspended;
        if (block.timestamp > l.validUntil) return LicenceLib.Status.Expired;
        if (block.timestamp + _thresholds[0] >= l.validUntil) return LicenceLib.Status.ExpiringSoon;
        return LicenceLib.Status.Valid;
    }

    /**
     * @notice Whether a licence is in force now: started, and not expired, suspended or revoked.
     * @param licenceId Licence id.
     * @return True if in force.
     */
    function isValid(uint256 licenceId) public view returns (bool) {
        LicenceLib.Status s = status(licenceId);
        return (s == LicenceLib.Status.Valid || s == LicenceLib.Status.ExpiringSoon)
            && _licences[licenceId].validFrom <= block.timestamp;
    }

    /**
     * @notice Whether a licence belongs to `orgId`, is of `licenceType` and is in force now.
     * @param licenceId Licence id.
     * @param orgId Expected holder.
     * @param licenceType Expected licence type.
     * @return True if all three hold.
     */
    function isValidFor(uint256 licenceId, bytes32 orgId, bytes32 licenceType) external view returns (bool) {
        LicenceLib.Licence storage l = _licences[licenceId];
        return l.orgId == orgId && l.licenceType == licenceType && isValid(licenceId);
    }

    /**
     * @notice An organisation's licences that need attention: expiring soon, expired or suspended.
     * @param orgId Organisation id.
     * @return ids Licence ids.
     */
    function attentionNeeded(bytes32 orgId) external view returns (uint256[] memory ids) {
        uint256[] storage all = _licencesOf[orgId];
        ids = new uint256[](all.length);
        uint256 n;
        for (uint256 i; i < all.length; ++i) {
            LicenceLib.Status s = status(all[i]);
            if (
                s == LicenceLib.Status.ExpiringSoon || s == LicenceLib.Status.Expired
                    || s == LicenceLib.Status.Suspended
            ) {
                ids[n++] = all[i];
            }
        }
        assembly ("memory-safe") {
            mstore(ids, n)
        }
    }

    /*//////////////////////////////////////////////////////////////
                                 INTERNAL
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Number of notices due by now: one per crossed threshold, plus one once expired. Revoked and unknown
     * licences get none.
     * @param l The licence.
     * @return due Number of notices due.
     */
    function _dueNotices(LicenceLib.Licence storage l) private view returns (uint256 due) {
        if (l.issuedBy == address(0) || l.revoked) return 0;
        uint256 n = _thresholds.length;
        for (uint256 i; i < n; ++i) {
            if (block.timestamp + _thresholds[i] >= l.validUntil) ++due;
        }
        if (block.timestamp > l.validUntil) ++due;
    }

    /**
     * @dev Emits the most urgent due notice (skipping ones that were missed) and marks it sent.
     * @param licenceId Licence id.
     * @return sent True if a notice was emitted.
     */
    function _sendNotice(uint256 licenceId) private returns (bool sent) {
        LicenceLib.Licence storage l = _licences[licenceId];
        uint256 due = _dueNotices(l);
        if (due <= l.noticesSent) return false;
        l.noticesSent = uint8(due);
        if (block.timestamp > l.validUntil) {
            emit LicenceLib.LicenceExpired(licenceId, l.orgId, l.validUntil);
        } else {
            emit LicenceLib.LicenceExpiryReminder(
                licenceId, l.orgId, l.validUntil, uint64(l.validUntil - block.timestamp)
            );
        }
        return true;
    }

    /**
     * @dev Returns the licence, reverting if it does not exist.
     * @param licenceId Licence id.
     * @return l Storage pointer to the licence.
     */
    function _requireLicence(uint256 licenceId) private view returns (LicenceLib.Licence storage l) {
        l = _licences[licenceId];
        if (l.issuedBy == address(0)) revert LicenceLib.LicenceRegistry__UnknownLicence(licenceId);
    }

    /**
     * @dev Reverts unless the caller is an authorised regulator.
     */
    function _onlyRegulator() private view {
        if (!registry.isAuthorized(msg.sender, Actions.REGULATE)) {
            revert LicenceLib.LicenceRegistry__NotRegulator(msg.sender);
        }
    }
}
