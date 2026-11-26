// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {ISupplyChain} from "src/traceability/interfaces/ISupplyChain.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {IMineNetRegistry} from "src/access/interfaces/IMineNetRegistry.sol";
import {ILotPassport} from "src/traceability/interfaces/ILotPassport.sol";
import {ICertificateRegistry} from "src/compliance/interfaces/ICertificateRegistry.sol";
import {Actions} from "src/access/libraries/Actions.sol";
import {PassportLib} from "src/traceability/libraries/PassportLib.sol";
import {SupplyChainLib} from "src/traceability/libraries/SupplyChainLib.sol";

/**
 * @title SupplyChain
 * @author 0xEmmyb2
 * @notice Stage checkpoints and the mass-balance ledger for every lot (project.md 4.2, 6.4, 7.5).
 * @dev Each checkpoint has a type, and each type needs a specific role:
 * - `Weighing`: ORACLE device (weighbridge / scale), independent of the lot's parties.
 * - `Pickup`, `Arrival`: only through a module ({DeliveryManager}), as part of a two-party handover.
 * - `WarehouseIn` / `WarehouseOut`: WAREHOUSE holding the lot (check-in and check-out weights).
 * - `ProcessingIn`: PROCESSOR or REFINERY holding the lot (input weight).
 * - `Inspection`: INSPECTOR assigned to the lot; may attest a grade (`gradeBps`), used by escrow disputes.
 * - `CustomsDeclared`: CUSTOMS assigned to the lot (declared weight; required certificates attached).
 * - `CustomsReleased`: ORACLE (RRA record) or REGULATOR (where no system link exists).
 * - `BorderExit`: CUSTOMS assigned to the lot, once released.
 * - `Audit`: any AUDITOR (read-only plus flagging); a finding raises a flag.
 * - `OracleReport`: ORACLE node independent of the lot's parties; a mismatch raises a flag.
 *
 * Mass balance: every measured weight is compared with the lot's last trusted weight (per-hop tolerance, set per
 * mineral) and with the lot's baseline, its registered quantity unless a regulator re-baselined it (cumulative
 * tolerance), which catches slow skimming across hops. Only readings within tolerance become the new trusted
 * weight. A failed reading is kept as evidence but cannot poison the reference (a faulty scale, or a swap
 * followed by "normal" readings). After investigating, a regulator can accept a new weight with {rebaseline}.
 *
 * A weight outside either tolerance, a `Damaged` condition, or a broken seal raises a flag on the passport, which
 * freezes the lot until a regulator resolves it. The checkpoint is still recorded either way, so the evidence is
 * kept.
 *
 * Types, events, errors and the deviation maths live in {SupplyChainLib}; permissions are registry actions (see
 * {Actions}), so they can be changed without redeploying. Must be enabled as a passport module
 * (`passport.setModule`) so it can raise flags.
 */
contract SupplyChain is Pausable, ISupplyChain {
    /**
     * @notice Maximum configurable tolerance (20%), in basis points.
     */
    uint16 public constant MAX_TOLERANCE_BPS = 2_000;

    /**
     * @notice Participant, role and permission registry.
     */
    IMineNetRegistry public immutable registry;

    /**
     * @notice Lot passport on which lots are flagged.
     */
    ILotPassport public immutable passport;

    /**
     * @notice Certificates required for customs declaration.
     */
    ICertificateRegistry public immutable certificates;

    /**
     * @notice Per-hop tolerance when a mineral has none of its own (2%), in basis points.
     */
    uint16 public defaultToleranceBps = 200;

    /**
     * @notice Allowed drift from the baseline over the whole journey (5%), in basis points.
     */
    uint16 public cumulativeToleranceBps = 500;

    /**
     * @dev Mineral => per-hop tolerance in basis points (0 = use the default).
     */
    mapping(bytes32 mineralType => uint16) private _mineralToleranceBps;

    /**
     * @dev Certificate types a lot needs before customs can declare it.
     */
    bytes32[] private _customsRequiredCerts;

    /**
     * @notice Contracts ({DeliveryManager}) trusted to record `Pickup` and `Arrival` checkpoints.
     */
    mapping(address module => bool) public isModule;

    /**
     * @dev Lot => append-only checkpoint log.
     */
    mapping(uint256 tokenId => SupplyChainLib.Checkpoint[]) private _checkpoints;

    /**
     * @dev Lot => last trusted weight in grams (0 = never weighed: use the baseline).
     */
    mapping(uint256 tokenId => uint128) private _lastWeight;

    /**
     * @dev Lot => re-baselined weight in grams (0 = use the registered quantity).
     */
    mapping(uint256 tokenId => uint128) private _baseline;

    /**
     * @notice A lot's customs progress.
     */
    mapping(uint256 tokenId => SupplyChainLib.CustomsStatus) public customsStatus;

    /**
     * @dev Lot => latest attested grade.
     */
    mapping(uint256 tokenId => SupplyChainLib.Grade) private _grades;

    /**
     * @notice Whether an inspector or customs agent is assigned to a lot.
     */
    mapping(uint256 tokenId => mapping(address account => bool)) public isAssigned;

    /**
     * @notice The contract that assigns inspectors to lots ({InspectionRegistry}). Once set, only it can assign or
     * remove inspectors: a lot's owner or custodian never chooses who inspects it.
     */
    address public inspectionAssigner;

    /**
     * @dev Lot => inspector => assigned by the platform (cannot be removed by the owner or custodian).
     */
    mapping(uint256 tokenId => mapping(address account => bool)) private _platformAssigned;

    /**
     * @notice Restricts a function to {MineNetRegistry} admins.
     */
    modifier onlyAdmin() {
        _onlyAdmin();
        _;
    }

    /**
     * @param registry_ Participant, role and permission registry.
     * @param passport_ Lot passport.
     * @param certificates_ Certificate registry.
     */
    constructor(IMineNetRegistry registry_, ILotPassport passport_, ICertificateRegistry certificates_) {
        registry = registry_;
        passport = passport_;
        certificates = certificates_;
    }

    /*//////////////////////////////////////////////////////////////
                                  ADMIN
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Sets the default per-hop and cumulative weight tolerances.
     * @dev Only a {MineNetRegistry} admin.
     * @param hopBps Per-hop tolerance, in basis points; in `(0, MAX_TOLERANCE_BPS]`.
     * @param cumulativeBps Cumulative tolerance, in basis points; in `[hopBps, MAX_TOLERANCE_BPS]`.
     * @custom:emits DefaultToleranceUpdated
     */
    function setDefaultTolerances(uint16 hopBps, uint16 cumulativeBps) external onlyAdmin {
        if (hopBps == 0 || hopBps > MAX_TOLERANCE_BPS) revert SupplyChainLib.SupplyChain__InvalidTolerance(hopBps);
        if (cumulativeBps < hopBps || cumulativeBps > MAX_TOLERANCE_BPS) {
            revert SupplyChainLib.SupplyChain__InvalidTolerance(cumulativeBps);
        }
        defaultToleranceBps = hopBps;
        cumulativeToleranceBps = cumulativeBps;
        emit SupplyChainLib.DefaultToleranceUpdated(hopBps, cumulativeBps);
    }

    /**
     * @notice Sets the per-hop tolerance of one mineral (wet ores lose more moisture).
     * @dev Only a {MineNetRegistry} admin.
     * @param mineralType Mineral identifier.
     * @param toleranceBps Tolerance, in basis points; 0 means use the default.
     * @custom:emits ToleranceUpdated
     */
    function setMineralTolerance(bytes32 mineralType, uint16 toleranceBps) external onlyAdmin {
        if (toleranceBps > MAX_TOLERANCE_BPS) revert SupplyChainLib.SupplyChain__InvalidTolerance(toleranceBps);
        _mineralToleranceBps[mineralType] = toleranceBps;
        emit SupplyChainLib.ToleranceUpdated(mineralType, toleranceBps);
    }

    /**
     * @notice Sets the certificates a lot needs before customs can declare it (e.g. EXPORT_PERMIT, ICGLR).
     * @dev Only a {MineNetRegistry} admin.
     * @param certTypes Certificate types.
     * @custom:emits CustomsRequiredCertsUpdated
     */
    function setCustomsRequiredCerts(bytes32[] calldata certTypes) external onlyAdmin {
        _customsRequiredCerts = certTypes;
        emit SupplyChainLib.CustomsRequiredCertsUpdated(certTypes);
    }

    /**
     * @notice Sets the contract that assigns inspectors to lots ({InspectionRegistry}).
     * @dev Only a {MineNetRegistry} admin. Once set, owners and custodians can only assign customs agents.
     * @param assigner The inspection assigner.
     * @custom:emits InspectionAssignerSet
     */
    function setInspectionAssigner(address assigner) external onlyAdmin {
        inspectionAssigner = assigner;
        emit SupplyChainLib.InspectionAssignerSet(assigner);
    }

    /**
     * @notice Allows or disallows a contract ({DeliveryManager}) to record `Pickup` / `Arrival` checkpoints.
     * @dev Only a {MineNetRegistry} admin.
     * @param module Module contract.
     * @param enabled Whether it is trusted.
     * @custom:emits ModuleSet
     */
    function setModule(address module, bool enabled) external onlyAdmin {
        isModule[module] = enabled;
        emit SupplyChainLib.ModuleSet(module, enabled);
    }

    /**
     * @notice Pauses checkpoint recording, assignment and flagging.
     * @dev Only a {MineNetRegistry} admin.
     */
    function pause() external onlyAdmin {
        _pause();
    }

    /**
     * @notice Resumes checkpoint recording, assignment and flagging.
     * @dev Only a {MineNetRegistry} admin.
     */
    function unpause() external onlyAdmin {
        _unpause();
    }

    /*//////////////////////////////////////////////////////////////
      ASSIGNMENT (INSPECTORS AND CUSTOMS AGENTS WORK ON LOTS THEY ARE ASSIGNED TO)
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Assigns a customs agent (or, before an inspection assigner is set, an inspector) to a lot.
     * @dev Only the lot's owner or custodian. The assignee cannot be the lot's owner or custodian (separation of
     * duties).
     * @param tokenId Lot.
     * @param account Inspector (`INSPECT_LOT`) or customs agent (`FILE_CUSTOMS`).
     * @custom:emits ParticipantAssigned
     */
    function assign(uint256 tokenId, address account) external whenNotPaused {
        (address lotOwner, address custodian) = _parties(tokenId);
        if (msg.sender != lotOwner && msg.sender != custodian) {
            revert SupplyChainLib.SupplyChain__NotOwnerOrCustodian(tokenId, msg.sender);
        }
        if (
            account == lotOwner || account == custodian
                || (!registry.isAuthorized(account, Actions.INSPECT_LOT)
                    && !registry.isAuthorized(account, Actions.FILE_CUSTOMS))
        ) revert SupplyChainLib.SupplyChain__NotAssignable(account);
        if (inspectionAssigner != address(0) && registry.isAuthorized(account, Actions.INSPECT_LOT)) {
            revert SupplyChainLib.SupplyChain__InspectorsArePlatformAssigned(account);
        }
        isAssigned[tokenId][account] = true;
        emit SupplyChainLib.ParticipantAssigned(tokenId, account, msg.sender);
    }

    /**
     * @notice The platform assigns an inspector to a lot.
     * @dev Only the inspection assigner ({InspectionRegistry}), which picks the inspector.
     * @param tokenId Lot.
     * @param inspector Assigned inspector.
     * @custom:emits ParticipantAssigned
     */
    function assignInspector(uint256 tokenId, address inspector) external {
        if (msg.sender != inspectionAssigner) revert SupplyChainLib.SupplyChain__NotInspectionAssigner(msg.sender);
        isAssigned[tokenId][inspector] = true;
        _platformAssigned[tokenId][inspector] = true;
        emit SupplyChainLib.ParticipantAssigned(tokenId, inspector, msg.sender);
    }

    /**
     * @notice The platform removes an inspector from a lot (reassignment).
     * @dev Only the inspection assigner ({InspectionRegistry}).
     * @param tokenId Lot.
     * @param inspector Inspector to remove.
     * @custom:emits ParticipantUnassigned
     */
    function unassignInspector(uint256 tokenId, address inspector) external {
        if (msg.sender != inspectionAssigner) revert SupplyChainLib.SupplyChain__NotInspectionAssigner(msg.sender);
        isAssigned[tokenId][inspector] = false;
        _platformAssigned[tokenId][inspector] = false;
        emit SupplyChainLib.ParticipantUnassigned(tokenId, inspector, msg.sender);
    }

    /**
     * @notice Removes an assignment.
     * @dev The lot's owner or custodian, or the assignee itself. A platform-assigned inspector can only step down
     * itself (or be reassigned by the platform).
     * @param tokenId Lot.
     * @param account Assigned participant.
     * @custom:emits ParticipantUnassigned
     */
    function unassign(uint256 tokenId, address account) external {
        (address lotOwner, address custodian) = _parties(tokenId);
        if (msg.sender != lotOwner && msg.sender != custodian && msg.sender != account) {
            revert SupplyChainLib.SupplyChain__NotOwnerOrCustodian(tokenId, msg.sender);
        }
        if (_platformAssigned[tokenId][account] && msg.sender != account) {
            revert SupplyChainLib.SupplyChain__InspectorsArePlatformAssigned(account);
        }
        _platformAssigned[tokenId][account] = false;
        isAssigned[tokenId][account] = false;
        emit SupplyChainLib.ParticipantUnassigned(tokenId, account, msg.sender);
    }

    /*//////////////////////////////////////////////////////////////
                               CHECKPOINTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Records a stage checkpoint. `Pickup` and `Arrival` are recorded only by {DeliveryManager}.
     * @dev The caller must hold the role required by the checkpoint type (see the contract documentation).
     * @param input The checkpoint.
     * @return index Position of the checkpoint in the lot's log.
     * @return flagId Passport flag raised by this checkpoint (0 if none).
     * @custom:emits CheckpointRecorded
     */
    function recordCheckpoint(SupplyChainLib.CheckpointInput calldata input)
        external
        whenNotPaused
        returns (uint256 index, uint256 flagId)
    {
        if (
            input.cpType == SupplyChainLib.CheckpointType.Pickup
                || input.cpType == SupplyChainLib.CheckpointType.Arrival
        ) {
            revert SupplyChainLib.SupplyChain__ModuleOnlyType(input.cpType);
        }
        _authorize(input, msg.sender);
        return _record(input, msg.sender);
    }

    /**
     * @notice Records a `Pickup` or `Arrival` checkpoint for `signer`, after the module has checked that the signer
     * is the receiving party of the handover.
     * @dev Only a trusted module. A measured weight is required.
     * @param input The checkpoint.
     * @param signer Account recorded as signing it.
     * @return index Position of the checkpoint in the lot's log.
     * @return flagId Passport flag raised by this checkpoint (0 if none).
     * @custom:emits CheckpointRecorded
     */
    function recordFromModule(SupplyChainLib.CheckpointInput calldata input, address signer)
        external
        whenNotPaused
        returns (uint256 index, uint256 flagId)
    {
        if (!isModule[msg.sender]) revert SupplyChainLib.SupplyChain__NotModule(msg.sender);
        if (
            input.cpType != SupplyChainLib.CheckpointType.Pickup
                && input.cpType != SupplyChainLib.CheckpointType.Arrival
        ) {
            revert SupplyChainLib.SupplyChain__ModuleOnlyType(input.cpType);
        }
        if (input.measuredQty == 0) revert SupplyChainLib.SupplyChain__WeightRequired(input.cpType);
        return _record(input, signer);
    }

    /**
     * @notice Flags a lot without a checkpoint, freezing it until a regulator resolves the flag.
     * @dev Any auditor, or an inspector or customs agent assigned to the lot.
     * @param tokenId Lot.
     * @param reasonHash Hash of the reason; non-zero.
     * @return flagId Passport flag raised.
     * @custom:emits LotFlagged
     */
    function flagLot(uint256 tokenId, bytes32 reasonHash) external whenNotPaused returns (uint256 flagId) {
        if (reasonHash == bytes32(0)) revert SupplyChainLib.SupplyChain__EvidenceRequired();
        if (
            !registry.isAuthorized(msg.sender, Actions.AUDIT)
                && !(isAssigned[tokenId][msg.sender]
                    && (registry.isAuthorized(msg.sender, Actions.INSPECT_LOT)
                        || registry.isAuthorized(msg.sender, Actions.FILE_CUSTOMS)))
        ) revert SupplyChainLib.SupplyChain__NotFlagAuthority(msg.sender);
        flagId = passport.moduleFlag(tokenId, msg.sender, reasonHash);
        emit SupplyChainLib.LotFlagged(tokenId, msg.sender, reasonHash, flagId);
    }

    /**
     * @notice Records an audit (project.md 6.3: auditors are read-only plus flagging).
     * @dev Any auditor. Allowed on any lot, including consumed ones. If `clean` is false, a flag is raised and the
     * lot is frozen.
     * @param tokenId Lot.
     * @param findingsHash Hash of the audit findings; non-zero.
     * @param clean Whether the audit passed.
     * @return index Position of the checkpoint in the lot's log.
     * @return flagId Passport flag raised (0 if clean).
     * @custom:emits CheckpointRecorded
     */
    function recordAudit(uint256 tokenId, bytes32 findingsHash, bool clean)
        external
        whenNotPaused
        returns (uint256 index, uint256 flagId)
    {
        _requireAction(msg.sender, Actions.AUDIT, SupplyChainLib.CheckpointType.Audit);
        passport.getLot(tokenId); // reverts for unknown lots
        return _attest(tokenId, SupplyChainLib.CheckpointType.Audit, findingsHash, clean);
    }

    /**
     * @notice Records an oracle integrity report (project.md 7.5): the node compared an on-chain event with its
     * off-chain source. A mismatch raises a flag and freezes the lot.
     * @dev An oracle node independent of the lot's owner and custodian. Phase 1 accepts one node's report. Quorum
     * aggregation across nodes belongs in a dedicated OracleRegistry that calls this function once quorum is
     * reached.
     * @param tokenId Lot.
     * @param reportHash Hash of the report; non-zero.
     * @param matched Whether the on-chain record matched the source.
     * @return index Position of the checkpoint in the lot's log.
     * @return flagId Passport flag raised (0 if matched).
     * @custom:emits CheckpointRecorded
     */
    function submitOracleReport(uint256 tokenId, bytes32 reportHash, bool matched)
        external
        whenNotPaused
        returns (uint256 index, uint256 flagId)
    {
        _requireAction(msg.sender, Actions.REPORT_READING, SupplyChainLib.CheckpointType.OracleReport);
        (address lotOwner, address custodian) = _parties(tokenId);
        _requireIndependent(tokenId, msg.sender, lotOwner, custodian);
        return _attest(tokenId, SupplyChainLib.CheckpointType.OracleReport, reportHash, matched);
    }

    /**
     * @notice After investigating a mismatch, a regulator accepts `newQty` as the lot's true weight (e.g. confirmed
     * moisture loss).
     * @dev Only a regulator. Resets both the per-hop and cumulative references. The flag itself is resolved
     * separately on the passport.
     * @param tokenId Lot.
     * @param newQty New trusted weight, in grams; non-zero.
     * @param reasonHash Hash of the decision; non-zero.
     * @custom:emits WeightRebaselined
     */
    function rebaseline(uint256 tokenId, uint128 newQty, bytes32 reasonHash) external whenNotPaused {
        if (!registry.isAuthorized(msg.sender, Actions.REGULATE)) {
            revert SupplyChainLib.SupplyChain__NotFlagAuthority(msg.sender);
        }
        if (newQty == 0) revert SupplyChainLib.SupplyChain__WeightRequired(SupplyChainLib.CheckpointType.Weighing);
        if (reasonHash == bytes32(0)) revert SupplyChainLib.SupplyChain__EvidenceRequired();
        passport.getLot(tokenId); // reverts for unknown lots
        _lastWeight[tokenId] = newQty;
        _baseline[tokenId] = newQty;
        emit SupplyChainLib.WeightRebaselined(tokenId, msg.sender, newQty, reasonHash);
    }

    /*//////////////////////////////////////////////////////////////
                                  VIEWS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Per-hop tolerance applied to a mineral.
     * @param mineralType Mineral identifier.
     * @return Tolerance, in basis points.
     */
    function toleranceOf(bytes32 mineralType) public view returns (uint16) {
        uint16 t = _mineralToleranceBps[mineralType];
        return t == 0 ? defaultToleranceBps : t;
    }

    /**
     * @notice A lot's last trusted (within-tolerance) weight, or its baseline if never weighed.
     * @param tokenId Lot.
     * @return Weight, in grams.
     */
    function lastWeight(uint256 tokenId) public view returns (uint128) {
        uint128 w = _lastWeight[tokenId];
        return w != 0 ? w : baselineOf(tokenId);
    }

    /**
     * @notice Reference for the cumulative check: the registered quantity unless a regulator re-baselined it.
     * @param tokenId Lot.
     * @return Weight, in grams.
     */
    function baselineOf(uint256 tokenId) public view returns (uint128) {
        uint128 b = _baseline[tokenId];
        return b != 0 ? b : passport.getLot(tokenId).quantity;
    }

    /**
     * @notice Number of checkpoints recorded for a lot.
     * @param tokenId Lot.
     * @return Checkpoint count.
     */
    function checkpointCount(uint256 tokenId) external view returns (uint256) {
        return _checkpoints[tokenId].length;
    }

    /**
     * @notice Returns one checkpoint of a lot.
     * @dev Reverts if `index` is out of range.
     * @param tokenId Lot.
     * @param index Checkpoint index.
     * @return The checkpoint.
     */
    function getCheckpoint(uint256 tokenId, uint256 index) external view returns (SupplyChainLib.Checkpoint memory) {
        return _checkpoints[tokenId][index];
    }

    /**
     * @notice Paginated checkpoint history.
     * @param tokenId Lot.
     * @param offset First index.
     * @param limit Maximum number of checkpoints.
     * @return page Up to `limit` checkpoints starting at `offset` (empty if `offset` is past the end).
     */
    function getCheckpoints(uint256 tokenId, uint256 offset, uint256 limit)
        external
        view
        returns (SupplyChainLib.Checkpoint[] memory page)
    {
        SupplyChainLib.Checkpoint[] storage log = _checkpoints[tokenId];
        if (offset >= log.length) return page;
        uint256 end = offset + limit > log.length ? log.length : offset + limit;
        page = new SupplyChainLib.Checkpoint[](end - offset);
        for (uint256 i = offset; i < end; ++i) {
            page[i - offset] = log[i];
        }
    }

    /**
     * @notice The most recent grade attested by an inspector.
     * @param tokenId Lot.
     * @return The grade (`gradeBps` 0 if the lot was never graded).
     */
    function latestGrade(uint256 tokenId) external view returns (SupplyChainLib.Grade memory) {
        return _grades[tokenId];
    }

    /**
     * @notice Certificates a lot needs before customs can declare it.
     * @return Certificate types.
     */
    function customsRequiredCerts() external view returns (bytes32[] memory) {
        return _customsRequiredCerts;
    }

    /*//////////////////////////////////////////////////////////////
                                 INTERNAL
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Reverts unless `signer` may record `input` (role, custody, assignment and independence checks), and
     * unless a required weight is present.
     * @param input The checkpoint.
     * @param signer Signing account.
     */
    function _authorize(SupplyChainLib.CheckpointInput calldata input, address signer) private view {
        uint256 tokenId = input.tokenId;
        SupplyChainLib.CheckpointType t = input.cpType;
        (address lotOwner, address custodian) = _parties(tokenId);

        if (t == SupplyChainLib.CheckpointType.Weighing) {
            _requireAction(signer, Actions.REPORT_READING, t);
            _requireIndependent(tokenId, signer, lotOwner, custodian);
        } else if (t == SupplyChainLib.CheckpointType.WarehouseIn || t == SupplyChainLib.CheckpointType.WarehouseOut) {
            _requireAction(signer, Actions.OPERATE_WAREHOUSE, t);
            _requireCustodian(signer, custodian, t);
        } else if (t == SupplyChainLib.CheckpointType.ProcessingIn) {
            _requireAction(signer, Actions.PROCESS_LOTS, t);
            _requireCustodian(signer, custodian, t);
        } else if (t == SupplyChainLib.CheckpointType.Inspection) {
            _requireAction(signer, Actions.INSPECT_LOT, t);
            _requireAssigned(tokenId, signer);
        } else if (t == SupplyChainLib.CheckpointType.CustomsDeclared || t == SupplyChainLib.CheckpointType.BorderExit)
        {
            _requireAction(signer, Actions.FILE_CUSTOMS, t);
            _requireAssigned(tokenId, signer);
        } else if (t == SupplyChainLib.CheckpointType.CustomsReleased) {
            if (!registry.isAuthorized(signer, Actions.REGULATE)) {
                _requireAction(signer, Actions.REPORT_READING, t);
                _requireIndependent(tokenId, signer, lotOwner, custodian);
            }
        } else {
            revert SupplyChainLib.SupplyChain__Unauthorized(signer, t); // Audit / OracleReport have their own functions
        }

        if (SupplyChainLib.needsWeight(t) && input.measuredQty == 0) {
            revert SupplyChainLib.SupplyChain__WeightRequired(t);
        }
    }

    /**
     * @dev Validates and appends a checkpoint, applies the mass-balance check, updates customs and grade, and
     * raises
     * at most one flag (weight first, then condition).
     * @param input The checkpoint.
     * @param signer Signing account.
     * @return index Position of the checkpoint in the lot's log.
     * @return flagId Passport flag raised (0 if none).
     */
    function _record(SupplyChainLib.CheckpointInput calldata input, address signer)
        private
        returns (uint256 index, uint256 flagId)
    {
        uint256 tokenId = input.tokenId;
        if (input.evidenceHash == bytes32(0)) revert SupplyChainLib.SupplyChain__EvidenceRequired();
        PassportLib.Lot memory lot = passport.getLot(tokenId); // reverts for unknown lots
        if (lot.status == PassportLib.LotStatus.Consumed) revert SupplyChainLib.SupplyChain__LotConsumed(tokenId);

        _advanceCustoms(tokenId, input.cpType);
        if (
            input.gradeBps > 10_000 || (input.gradeBps != 0 && input.cpType != SupplyChainLib.CheckpointType.Inspection)
        ) {
            revert SupplyChainLib.SupplyChain__InvalidGrade(input.gradeBps);
        }

        // ---- mass balance ----
        uint128 refQty = lastWeight(tokenId);
        uint16 hopDev;
        uint16 cumDev;
        bool within = true;
        if (input.measuredQty != 0) {
            uint256 hop = SupplyChainLib.deviationBps(input.measuredQty, refQty);
            uint256 cum = SupplyChainLib.deviationBps(input.measuredQty, baselineOf(tokenId));
            hopDev = SupplyChainLib.cap16(hop);
            cumDev = SupplyChainLib.cap16(cum);
            within = hop <= toleranceOf(lot.mineralType) && cum <= cumulativeToleranceBps;
            if (within) _lastWeight[tokenId] = input.measuredQty; // failed readings never become the reference
        }

        index = _checkpoints[tokenId].length;
        _checkpoints[tokenId].push(
            SupplyChainLib.Checkpoint({
                cpType: input.cpType,
                condition: input.condition,
                withinTolerance: within,
                hopDeviationBps: hopDev,
                cumulativeDeviationBps: cumDev,
                gradeBps: input.gradeBps,
                timestamp: uint64(block.timestamp),
                signer: signer,
                measuredQty: input.measuredQty,
                referenceQty: refQty,
                evidenceHash: input.evidenceHash,
                locationHash: input.locationHash
            })
        );
        emit SupplyChainLib.CheckpointRecorded(
            tokenId,
            index,
            input.cpType,
            signer,
            input.measuredQty,
            refQty,
            hopDev,
            cumDev,
            input.condition,
            input.evidenceHash,
            input.locationHash
        );
        if (input.gradeBps != 0) {
            _grades[tokenId] =
                SupplyChainLib.Grade({gradeBps: input.gradeBps, at: uint64(block.timestamp), inspector: signer});
            emit SupplyChainLib.GradeAttested(tokenId, index, signer, input.gradeBps);
        }

        // ---- flags: one per checkpoint, weight first ----
        if (!within) {
            flagId = passport.moduleFlag(tokenId, signer, input.evidenceHash);
            emit SupplyChainLib.MassBalanceMismatch(tokenId, index, refQty, input.measuredQty, flagId);
        } else if (
            input.condition == SupplyChainLib.Condition.Damaged
                || input.condition == SupplyChainLib.Condition.SealBroken
        ) {
            flagId = passport.moduleFlag(tokenId, signer, input.evidenceHash);
            emit SupplyChainLib.ConditionFlagged(tokenId, index, input.condition, flagId);
        }
    }

    /**
     * @dev Pass/fail attestation without a weight: stored as a checkpoint (`withinTolerance` = passed). A failure
     * raises a flag.
     * @param tokenId Lot.
     * @param t `Audit` or `OracleReport`.
     * @param evidenceHash Hash of the evidence; non-zero.
     * @param passed Whether the attestation passed.
     * @return index Position of the checkpoint in the lot's log.
     * @return flagId Passport flag raised (0 if passed).
     */
    function _attest(uint256 tokenId, SupplyChainLib.CheckpointType t, bytes32 evidenceHash, bool passed)
        private
        returns (uint256 index, uint256 flagId)
    {
        if (evidenceHash == bytes32(0)) revert SupplyChainLib.SupplyChain__EvidenceRequired();
        index = _checkpoints[tokenId].length;
        _checkpoints[tokenId].push(
            SupplyChainLib.Checkpoint({
                cpType: t,
                condition: SupplyChainLib.Condition.NotAssessed,
                withinTolerance: passed,
                hopDeviationBps: 0,
                cumulativeDeviationBps: 0,
                gradeBps: 0,
                timestamp: uint64(block.timestamp),
                signer: msg.sender,
                measuredQty: 0,
                referenceQty: 0,
                evidenceHash: evidenceHash,
                locationHash: bytes32(0)
            })
        );
        emit SupplyChainLib.CheckpointRecorded(
            tokenId, index, t, msg.sender, 0, 0, 0, 0, SupplyChainLib.Condition.NotAssessed, evidenceHash, bytes32(0)
        );
        if (!passed) {
            flagId = passport.moduleFlag(tokenId, msg.sender, evidenceHash);
            emit SupplyChainLib.LotFlagged(tokenId, msg.sender, evidenceHash, flagId);
        }
    }

    /**
     * @dev Moves a lot through `None -> Declared -> Released -> Exited` for customs checkpoints. Declaration needs
     * the required certificates; release and exit need an unfrozen lot. No-op for other types.
     * @param tokenId Lot.
     * @param t Checkpoint type.
     */
    function _advanceCustoms(uint256 tokenId, SupplyChainLib.CheckpointType t) private {
        SupplyChainLib.CustomsStatus s = customsStatus[tokenId];
        SupplyChainLib.CustomsStatus next;
        if (t == SupplyChainLib.CheckpointType.CustomsDeclared) {
            if (s != SupplyChainLib.CustomsStatus.None) {
                revert SupplyChainLib.SupplyChain__InvalidCustomsStatus(tokenId, s);
            }
            bool certsOk =
                _customsRequiredCerts.length == 0 || certificates.hasValidCertificates(tokenId, _customsRequiredCerts);
            if (!certsOk) revert SupplyChainLib.SupplyChain__MissingCertificates(tokenId);
            next = SupplyChainLib.CustomsStatus.Declared;
        } else if (t == SupplyChainLib.CheckpointType.CustomsReleased) {
            if (s != SupplyChainLib.CustomsStatus.Declared) {
                revert SupplyChainLib.SupplyChain__InvalidCustomsStatus(tokenId, s);
            }
            if (passport.isFrozen(tokenId)) revert SupplyChainLib.SupplyChain__LotFrozen(tokenId);
            next = SupplyChainLib.CustomsStatus.Released;
        } else if (t == SupplyChainLib.CheckpointType.BorderExit) {
            if (s != SupplyChainLib.CustomsStatus.Released) {
                revert SupplyChainLib.SupplyChain__InvalidCustomsStatus(tokenId, s);
            }
            if (passport.isFrozen(tokenId)) revert SupplyChainLib.SupplyChain__LotFrozen(tokenId);
            next = SupplyChainLib.CustomsStatus.Exited;
        } else {
            return;
        }
        customsStatus[tokenId] = next;
        emit SupplyChainLib.CustomsStatusChanged(tokenId, next);
    }

    /**
     * @dev A lot's owner and custodian. Reverts for unknown lots.
     * @param tokenId Lot.
     * @return lotOwner ERC-721 owner.
     * @return custodian Physical custodian.
     */
    function _parties(uint256 tokenId) private view returns (address lotOwner, address custodian) {
        custodian = passport.custodianOf(tokenId); // reverts for unknown lots
        lotOwner = passport.ownerOf(tokenId);
    }

    /**
     * @dev Reverts unless `account` may perform `action`.
     * @param account The account.
     * @param action Required action.
     * @param t Checkpoint type (for the error).
     */
    function _requireAction(address account, bytes32 action, SupplyChainLib.CheckpointType t) private view {
        if (!registry.isAuthorized(account, action)) revert SupplyChainLib.SupplyChain__Unauthorized(account, t);
    }

    /**
     * @dev Reverts unless `account` is the custodian.
     * @param account The account.
     * @param custodian The lot's custodian.
     * @param t Checkpoint type (for the error).
     */
    function _requireCustodian(address account, address custodian, SupplyChainLib.CheckpointType t) private pure {
        if (account != custodian) revert SupplyChainLib.SupplyChain__Unauthorized(account, t);
    }

    /**
     * @dev Reverts unless `account` is assigned to the lot.
     * @param tokenId Lot.
     * @param account The account.
     */
    function _requireAssigned(uint256 tokenId, address account) private view {
        if (!isAssigned[tokenId][account]) revert SupplyChainLib.SupplyChain__NotAssignedParticipant(tokenId, account);
    }

    /**
     * @dev project.md 6.3: "no node may check a lot in which its operator is a party". Compared by organisation, so
     * a second wallet of the same company does not count as independent.
     * @param tokenId Lot.
     * @param node Checking account.
     * @param lotOwner The lot's owner.
     * @param custodian The lot's custodian.
     */
    function _requireIndependent(uint256 tokenId, address node, address lotOwner, address custodian) private view {
        if (registry.sameOrg(node, lotOwner) || registry.sameOrg(node, custodian)) {
            revert SupplyChainLib.SupplyChain__NotIndependent(tokenId, node);
        }
    }

    /**
     * @dev Reverts unless the caller is a {MineNetRegistry} admin.
     */
    function _onlyAdmin() private view {
        if (!registry.isAdmin(msg.sender)) {
            revert SupplyChainLib.SupplyChain__NotRegistryAdmin(msg.sender);
        }
    }
}
