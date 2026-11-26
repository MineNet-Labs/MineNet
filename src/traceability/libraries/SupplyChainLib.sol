// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

/**
 * @title SupplyChainLib
 * @author 0xEmmyb2
 * @notice Shared types, events, custom errors and mass-balance maths of {SupplyChain}.
 */
library SupplyChainLib {
    /**
     * @notice Kind of supply-chain checkpoint.
     * @dev `Audit` is recorded only by `recordAudit` and `OracleReport` only by `submitOracleReport`.
     */
    enum CheckpointType {
        Weighing,
        Pickup,
        Arrival,
        WarehouseIn,
        WarehouseOut,
        ProcessingIn,
        Inspection,
        CustomsDeclared,
        CustomsReleased,
        BorderExit,
        Audit, // recordAudit only
        OracleReport // submitOracleReport only
    }

    /**
     * @notice Physical condition of a lot observed at a checkpoint.
     */
    enum Condition {
        NotAssessed,
        Good,
        Damaged,
        SealBroken
    }

    /**
     * @notice Customs progress of a lot being exported.
     */
    enum CustomsStatus {
        None,
        Declared,
        Released,
        Exited
    }

    /**
     * @notice A signed supply-chain checkpoint of a lot.
     * @param cpType Checkpoint type.
     * @param condition Observed condition.
     * @param withinTolerance Weights: within tolerance. Audit / OracleReport: passed.
     * @param hopDeviationBps Deviation from the last trusted weight, in basis points (capped at the uint16
     * maximum).
     * @param cumulativeDeviationBps Deviation from the baseline weight, in basis points (capped at the uint16
     * maximum).
     * @param gradeBps Inspection only: attested grade / purity, in basis points (0 = not graded).
     * @param timestamp Block timestamp.
     * @param signer Account that recorded it.
     * @param measuredQty Measured weight in grams; 0 = not weighed at this checkpoint.
     * @param referenceQty Trusted weight it was compared with.
     * @param evidenceHash Hash of the evidence (weighbridge ticket, receipt, declaration...).
     * @param locationHash Hash of the location (site id / geohash).
     */
    struct Checkpoint {
        CheckpointType cpType;
        Condition condition;
        bool withinTolerance;
        uint16 hopDeviationBps;
        uint16 cumulativeDeviationBps;
        uint16 gradeBps;
        uint64 timestamp;
        address signer;
        uint128 measuredQty;
        uint128 referenceQty;
        bytes32 evidenceHash;
        bytes32 locationHash;
    }

    /**
     * @notice Everything a caller supplies for one checkpoint.
     * @param tokenId Lot.
     * @param cpType Checkpoint type.
     * @param measuredQty Measured weight in grams (0 = not weighed).
     * @param condition Observed condition.
     * @param gradeBps Inspection only: attested grade in basis points; must be 0 for every other type.
     * @param evidenceHash Hash of the evidence; required.
     * @param locationHash Hash of the location.
     */
    struct CheckpointInput {
        uint256 tokenId;
        CheckpointType cpType;
        uint128 measuredQty;
        Condition condition;
        uint16 gradeBps;
        bytes32 evidenceHash;
        bytes32 locationHash;
    }

    /**
     * @notice The latest grade an inspector attested for a lot.
     * @param gradeBps Grade / purity, in basis points.
     * @param at When it was attested.
     * @param inspector Attesting inspector.
     */
    struct Grade {
        uint16 gradeBps;
        uint64 at;
        address inspector;
    }

    /**
     * @notice Emitted for every checkpoint recorded.
     * @param tokenId Lot.
     * @param index Checkpoint index in the lot's history.
     * @param cpType Checkpoint type.
     * @param signer Recording account.
     * @param measuredQty Measured weight in grams (0 = not weighed).
     * @param referenceQty Trusted weight it was compared with.
     * @param hopDeviationBps Deviation from the last trusted weight, in basis points.
     * @param cumulativeDeviationBps Deviation from the baseline, in basis points.
     * @param condition Observed condition.
     * @param evidenceHash Hash of the evidence.
     * @param locationHash Hash of the location.
     */
    event CheckpointRecorded(
        uint256 indexed tokenId,
        uint256 indexed index,
        CheckpointType indexed cpType,
        address signer,
        uint128 measuredQty,
        uint128 referenceQty,
        uint16 hopDeviationBps,
        uint16 cumulativeDeviationBps,
        Condition condition,
        bytes32 evidenceHash,
        bytes32 locationHash
    );

    /**
     * @notice Emitted when an inspector attests a lot's grade.
     * @param tokenId Lot.
     * @param index Checkpoint index.
     * @param inspector Attesting inspector.
     * @param gradeBps Grade, in basis points.
     */
    event GradeAttested(uint256 indexed tokenId, uint256 indexed index, address indexed inspector, uint16 gradeBps);

    /**
     * @notice Emitted when a measured weight is outside tolerance; the lot is flagged.
     * @param tokenId Lot.
     * @param index Checkpoint index.
     * @param referenceQty Expected weight, in grams.
     * @param measuredQty Measured weight, in grams.
     * @param flagId Flag raised on the passport.
     */
    event MassBalanceMismatch(
        uint256 indexed tokenId, uint256 indexed index, uint128 referenceQty, uint128 measuredQty, uint256 flagId
    );

    /**
     * @notice Emitted when a checkpoint reports a damaged lot or a broken seal; the lot is flagged.
     * @param tokenId Lot.
     * @param index Checkpoint index.
     * @param condition Reported condition.
     * @param flagId Flag raised on the passport.
     */
    event ConditionFlagged(uint256 indexed tokenId, uint256 indexed index, Condition condition, uint256 flagId);

    /**
     * @notice Emitted when an auditor, regulator or oracle flags a lot.
     * @param tokenId Lot.
     * @param by Flagging account.
     * @param reasonHash Hash of the reason.
     * @param flagId Flag raised on the passport.
     */
    event LotFlagged(uint256 indexed tokenId, address indexed by, bytes32 reasonHash, uint256 flagId);

    /**
     * @notice Emitted when a participant is assigned to record checkpoints for a lot.
     * @param tokenId Lot.
     * @param account Assigned participant.
     * @param by Owner or custodian that assigned it.
     */
    event ParticipantAssigned(uint256 indexed tokenId, address indexed account, address indexed by);

    /**
     * @notice Emitted when a participant assignment is removed.
     * @param tokenId Lot.
     * @param account Unassigned participant.
     * @param by Owner or custodian that removed it.
     */
    event ParticipantUnassigned(uint256 indexed tokenId, address indexed account, address indexed by);

    /**
     * @notice Emitted when a lot's customs status changes.
     * @param tokenId Lot.
     * @param status New customs status.
     */
    event CustomsStatusChanged(uint256 indexed tokenId, CustomsStatus status);

    /**
     * @notice Emitted when the admin sets a mineral-specific weight tolerance.
     * @param mineralType Mineral identifier.
     * @param toleranceBps Tolerance, in basis points (0 = use the default).
     */
    event ToleranceUpdated(bytes32 indexed mineralType, uint16 toleranceBps);

    /**
     * @notice Emitted when the admin sets the default weight tolerances.
     * @param hopToleranceBps Tolerance between two consecutive weighings, in basis points.
     * @param cumulativeToleranceBps Tolerance against the baseline, in basis points.
     */
    event DefaultToleranceUpdated(uint16 hopToleranceBps, uint16 cumulativeToleranceBps);

    /**
     * @notice Emitted when the admin sets the certificates required for customs release.
     * @param certTypes Required certificate types.
     */
    event CustomsRequiredCertsUpdated(bytes32[] certTypes);

    /**
     * @notice Emitted when a module contract is trusted or untrusted.
     * @param module Module contract.
     * @param enabled Whether it is trusted.
     */
    event ModuleSet(address indexed module, bool enabled);

    /**
     * @notice Emitted when the customs authority whose oracles may release goods is set.
     * @param orgId The customs authority's organisation.
     */
    event CustomsAuthoritySet(bytes32 indexed orgId);

    /**
     * @notice Emitted when the admin sets the contract that assigns inspectors to lots ({InspectionRegistry}).
     * @param assigner The inspection assigner (zero = owners assign inspectors, legacy mode).
     */
    event InspectionAssignerSet(address indexed assigner);

    /**
     * @notice Emitted when a regulator resets a lot's trusted weight.
     * @param tokenId Lot.
     * @param regulator Regulator account.
     * @param newQty New trusted weight, in grams.
     * @param reasonHash Hash of the decision.
     */
    event WeightRebaselined(uint256 indexed tokenId, address indexed regulator, uint128 newQty, bytes32 reasonHash);

    /**
     * @notice `account` is not an admin of {MineNetRegistry}.
     * @param account The account.
     */
    error SupplyChain__NotRegistryAdmin(address account);

    /**
     * @notice `account` is not a trusted module.
     * @param account The account.
     */
    error SupplyChain__NotModule(address account);

    /**
     * @notice `toleranceBps` is zero (where required) or above the maximum tolerance.
     * @param toleranceBps The tolerance.
     */
    error SupplyChain__InvalidTolerance(uint16 toleranceBps);

    /**
     * @notice `account` may not record checkpoints of type `cpType`.
     * @param account The account.
     * @param cpType Checkpoint type.
     */
    error SupplyChain__Unauthorized(address account, CheckpointType cpType);

    /**
     * @notice `account` is neither the owner nor the custodian of lot `tokenId`.
     * @param tokenId The lot.
     * @param account The account.
     */
    error SupplyChain__NotOwnerOrCustodian(uint256 tokenId, address account);

    /**
     * @notice `account` cannot be assigned to the lot: it is the lot's owner or custodian, or is neither an
     * inspector
     * nor a customs agent.
     * @param account The account.
     */
    error SupplyChain__NotAssignable(address account);

    /**
     * @notice `account` is not assigned to lot `tokenId`.
     * @param tokenId The lot.
     * @param account The account.
     */
    error SupplyChain__NotAssignedParticipant(uint256 tokenId, address account);

    /**
     * @notice `account` belongs to an organisation involved with lot `tokenId` and cannot check it.
     * @param tokenId The lot.
     * @param account The account.
     */
    error SupplyChain__NotIndependent(uint256 tokenId, address account);

    /**
     * @notice Checkpoints of type `cpType` must carry a measured weight.
     * @param cpType Checkpoint type.
     */
    error SupplyChain__WeightRequired(CheckpointType cpType);

    /**
     * @notice The evidence or reason hash is zero.
     */
    error SupplyChain__EvidenceRequired();

    /**
     * @notice `gradeBps` is out of range or supplied for a non-inspection checkpoint.
     * @param gradeBps The grade.
     */
    error SupplyChain__InvalidGrade(uint16 gradeBps);

    /**
     * @notice Checkpoints of type `cpType` can only be recorded through their dedicated function.
     * @param cpType Checkpoint type.
     */
    error SupplyChain__ModuleOnlyType(CheckpointType cpType);

    /**
     * @notice Lot `tokenId` is in customs status `status`, which does not allow the operation.
     * @param tokenId The lot.
     * @param status Its current customs status.
     */
    error SupplyChain__InvalidCustomsStatus(uint256 tokenId, CustomsStatus status);

    /**
     * @notice Lot `tokenId` lacks a valid certificate required for customs release.
     * @param tokenId The lot.
     */
    error SupplyChain__MissingCertificates(uint256 tokenId);

    /**
     * @notice Lot `tokenId` is frozen.
     * @param tokenId The lot.
     */
    error SupplyChain__LotFrozen(uint256 tokenId);

    /**
     * @notice Lot `tokenId` was consumed by processing.
     * @param tokenId The lot.
     */
    error SupplyChain__LotConsumed(uint256 tokenId);

    /**
     * @notice `account` may not raise or resolve flags here.
     * @param account The account.
     */
    error SupplyChain__NotFlagAuthority(address account);

    /**
     * @notice Inspectors are assigned by the platform ({InspectionRegistry}); lot owners and custodians can neither
     * assign nor remove them.
     * @param account The inspector.
     */
    error SupplyChain__InspectorsArePlatformAssigned(address account);

    /**
     * @notice `account` is not the inspection assigner.
     * @param account The account.
     */
    error SupplyChain__NotInspectionAssigner(address account);

    /**
     * @notice 100%, in basis points.
     */
    uint16 internal constant MAX_BPS = 10_000;

    /**
     * @notice Relative deviation `|measured - expected| / expected`, in basis points (uncapped).
     * @param measured Measured value.
     * @param expected Expected value.
     * @return Deviation in basis points (the uint16 maximum if `expected` is 0).
     */
    function deviationBps(uint256 measured, uint256 expected) internal pure returns (uint256) {
        if (expected == 0) return type(uint16).max;
        uint256 diff = measured > expected ? measured - expected : expected - measured;
        return (diff * MAX_BPS) / expected;
    }

    /**
     * @notice Narrows a value to uint16, saturating at the uint16 maximum.
     * @param v Value.
     * @return `v`, or the uint16 maximum if larger.
     */
    function cap16(uint256 v) internal pure returns (uint16) {
        return v > type(uint16).max ? type(uint16).max : uint16(v);
    }

    /**
     * @notice Whether checkpoints of type `t` must carry a measured weight.
     * @param t Checkpoint type.
     * @return True for weighing, warehouse, processing-in and customs-declaration checkpoints.
     */
    function needsWeight(CheckpointType t) internal pure returns (bool) {
        return t == CheckpointType.Weighing || t == CheckpointType.WarehouseIn || t == CheckpointType.WarehouseOut
            || t == CheckpointType.ProcessingIn || t == CheckpointType.CustomsDeclared;
    }
}
