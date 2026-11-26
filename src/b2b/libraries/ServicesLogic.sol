// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {IMineNetRegistry} from "src/access/interfaces/IMineNetRegistry.sol";
import {ICurrencyManager} from "src/finance/interfaces/ICurrencyManager.sol";
import {ILotPassport} from "src/traceability/interfaces/ILotPassport.sol";
import {ISupplyChain} from "src/traceability/interfaces/ISupplyChain.sol";
import {IDeliveryManager} from "src/traceability/interfaces/IDeliveryManager.sol";
import {Actions} from "src/access/libraries/Actions.sol";
import {B2BLib} from "src/b2b/libraries/B2BLib.sol";
import {ServicesLib} from "src/b2b/libraries/ServicesLib.sol";
import {PassportLib} from "src/traceability/libraries/PassportLib.sol";
import {SupplyChainLib} from "src/traceability/libraries/SupplyChainLib.sol";
import {DeliveryLib} from "src/traceability/libraries/DeliveryLib.sol";

/**
 * @title ServicesLogic
 * @author 0xEmmyb2
 * @notice Term validation and on-chain work verification of {B2BServices}.
 * @dev An external library: {B2BServices} calls it with `DELEGATECALL`, so it runs on {B2BServices}' storage. It
 * exists to keep {B2BServices} under the EIP-170 contract size limit, and is linked at deployment.
 */
library ServicesLogic {
    /*//////////////////////////////////////////////////////////////
                                 LIMITS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Maximum number of jobs or billing periods in one agreement.
     */
    uint32 internal constant MAX_JOBS = 365;

    /**
     * @notice Shortest interval between two jobs.
     */
    uint32 internal constant MIN_JOB_INTERVAL = 1 days;

    /**
     * @notice Longest interval between two jobs.
     */
    uint32 internal constant MAX_JOB_INTERVAL = 365 days;

    /**
     * @notice Longest time from activation to the first job.
     */
    uint32 internal constant MAX_FIRST_JOB_OFFSET = 365 days;

    /**
     * @notice Shortest review period a client may be given.
     */
    uint32 internal constant MIN_REVIEW_PERIOD = 1 days;

    /**
     * @notice Longest review period a client may be given.
     */
    uint32 internal constant MAX_REVIEW_PERIOD = 30 days;

    /**
     * @notice Longest time a proposal may stay open for signature.
     */
    uint64 internal constant MAX_PROPOSAL_DURATION = 60 days;

    /**
     * @notice Time after a job's due date before the client may close it as missed; also the billing window of a
     * single-period storage agreement.
     */
    uint64 internal constant MISSED_GRACE = 30 days;

    /**
     * @notice The contracts {B2BServices} reads from.
     * @param registry Participant, role and permission registry.
     * @param passport Lot passport.
     * @param supplyChain Supply-chain ledger.
     * @param deliveryManager Delivery manager.
     */
    struct Deps {
        IMineNetRegistry registry;
        ILotPassport passport;
        ISupplyChain supplyChain;
        IDeliveryManager deliveryManager;
    }

    /*//////////////////////////////////////////////////////////////
                               NEGOTIATION
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Validates and stores new terms, bumping the version and clearing both signatures.
     * @param a The agreement.
     * @param t The terms.
     * @param registry Participant registry.
     * @param currencies Currency manager (settlement tokens).
     */
    function setTerms(
        ServicesLib.Agreement storage a,
        ServicesLib.Terms calldata t,
        IMineNetRegistry registry,
        ICurrencyManager currencies
    ) external {
        if (
            t.termsHash == bytes32(0) || t.reviewPeriod < MIN_REVIEW_PERIOD || t.reviewPeriod > MAX_REVIEW_PERIOD
                || t.proposalExpiresAt <= block.timestamp
                || t.proposalExpiresAt > block.timestamp + MAX_PROPOSAL_DURATION
        ) revert B2BLib.B2B__InvalidTerms();
        bool escrowed = address(t.paymentToken) != address(0);
        if (escrowed && !currencies.isSettlementToken(t.paymentToken)) {
            revert B2BLib.B2B__TokenNotAllowed(t.paymentToken);
        }

        ServicesLib.ServiceTerms calldata s = t.service;
        if (
            s.maxUnitsPerJob == 0 || (escrowed && s.ratePerUnit == 0) || s.totalJobs == 0 || s.totalJobs > MAX_JOBS
                || (s.totalJobs > 1 && (s.jobInterval < MIN_JOB_INTERVAL || s.jobInterval > MAX_JOB_INTERVAL))
                || s.firstJobOffset > MAX_FIRST_JOB_OFFSET || t.maxMissed > s.totalJobs
        ) revert ServicesLib.B2BServices__InvalidSchedule();
        requireQualified(s.kind, _party(a, s.provider).account, registry);
        if (t.arbiter != address(0) && !_isNeutral(a, t.arbiter, registry)) {
            revert B2BLib.B2B__InvalidArbiter(t.arbiter);
        }

        a.service = s;
        a.arbiter = t.arbiter;
        a.paymentToken = t.paymentToken;
        a.reviewPeriod = t.reviewPeriod;
        a.maxMissed = t.maxMissed;
        a.proposalExpiresAt = t.proposalExpiresAt;
        a.termsHash = t.termsHash;
        a.version += 1;
        a.proposerSigned = false;
        a.counterpartySigned = false;
    }

    /**
     * @notice Reverts unless `account` holds the permission the service kind requires of its provider.
     * @param kind Service kind.
     * @param account Provider account.
     * @param registry Participant registry.
     */
    function requireQualified(ServicesLib.ServiceKind kind, address account, IMineNetRegistry registry) public view {
        bytes32 action;
        if (kind == ServicesLib.ServiceKind.Haulage) {
            action = Actions.CARRY;
        } else if (kind == ServicesLib.ServiceKind.Storage) {
            action = Actions.OPERATE_WAREHOUSE;
        } else if (kind == ServicesLib.ServiceKind.TollProcessing || kind == ServicesLib.ServiceKind.TollRefining) {
            action = Actions.PROCESS_LOTS;
        } else if (kind == ServicesLib.ServiceKind.InspectionAssay) {
            action = Actions.INSPECT_LOT;
        } else if (kind == ServicesLib.ServiceKind.Audit) {
            action = Actions.AUDIT;
        } else if (kind == ServicesLib.ServiceKind.CustomsClearing) {
            action = Actions.FILE_CUSTOMS;
        } else {
            action = Actions.ENTER_AGREEMENT;
        }
        if (!registry.isAuthorized(account, action)) revert ServicesLib.B2BServices__ProviderNotQualified(account);
    }

    /*//////////////////////////////////////////////////////////////
                            WORK VERIFICATION
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Computes the units of a claim, verifying its on-chain work and marking it billed.
     * @dev See {B2BServices} for what counts as work per kind. Each piece of work is billed once.
     * @param agreementId Agreement id.
     * @param a The agreement.
     * @param workBilled {B2BServices}' map of billed work.
     * @param index Job index.
     * @param refs Work references (shipment ids or lot ids).
     * @param cpIndexes Checkpoint indexes (inspection, audit, customs).
     * @param claimedUnits Units for claimed kinds.
     * @param deps Contracts to read from.
     * @return units Units of verified (or claimed) work.
     */
    function verifyWork(
        uint256 agreementId,
        ServicesLib.Agreement storage a,
        mapping(bytes32 => bool) storage workBilled,
        uint256 index,
        uint256[] calldata refs,
        uint256[] calldata cpIndexes,
        uint128 claimedUnits,
        Deps memory deps
    ) external returns (uint256 units) {
        ServicesLib.ServiceKind kind = a.service.kind;
        if (ServicesLib.isClaimed(kind)) {
            if (refs.length != 0) revert ServicesLib.B2BServices__InvalidWork(refs.length);
            return claimedUnits;
        }
        bytes32 providerOrg = _party(a, a.service.provider).orgId;
        bytes32 clientOrg = _party(a, B2BLib.other(a.service.provider)).orgId;

        if (kind == ServicesLib.ServiceKind.Haulage) {
            for (uint256 i; i < refs.length; ++i) {
                units += _verifyShipment(a, workBilled, refs[i], providerOrg, clientOrg, deps);
            }
        } else if (kind == ServicesLib.ServiceKind.Storage) {
            uint64 periodEnd = uint64(a.activatedAt + uint256(a.service.firstJobOffset) + index * a.service.jobInterval);
            if (block.timestamp < periodEnd) revert B2BLib.B2B__TooEarly(index, periodEnd);
            uint64 window = a.service.totalJobs > 1 ? a.service.jobInterval : MISSED_GRACE;
            if (block.timestamp >= periodEnd + window) revert ServicesLib.B2BServices__InvalidWork(index);
            for (uint256 i; i < refs.length; ++i) {
                uint256 id = refs[i];
                if (
                    _orgOf(deps.passport.custodianOf(id), deps.registry) != providerOrg
                        || _orgOf(deps.passport.ownerOf(id), deps.registry) != clientOrg
                ) revert ServicesLib.B2BServices__InvalidWork(id);
                _markBilled(workBilled, keccak256(abi.encode("STORAGE", agreementId, index, id)), id);
                units += deps.supplyChain.lastWeight(id);
            }
        } else if (kind == ServicesLib.ServiceKind.TollProcessing || kind == ServicesLib.ServiceKind.TollRefining) {
            for (uint256 i; i < refs.length; ++i) {
                units += _verifyTolling(a, workBilled, refs[i], providerOrg, clientOrg, deps);
            }
        } else {
            if (cpIndexes.length != refs.length) revert ServicesLib.B2BServices__InvalidWork(cpIndexes.length);
            for (uint256 i; i < refs.length; ++i) {
                _verifyCheckpoint(a, workBilled, refs[i], cpIndexes[i], providerOrg, clientOrg, deps);
                units += 1;
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                                 PRIVATE
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Verifies a delivered shipment carried by the provider for the client after activation, marks it billed,
     * and returns the trusted weight of its lots.
     * @param a The agreement.
     * @param workBilled Map of billed work.
     * @param shipmentId Shipment id.
     * @param providerOrg Provider organisation.
     * @param clientOrg Client organisation.
     * @param deps Contracts to read from.
     * @return grams Weight carried.
     */
    function _verifyShipment(
        ServicesLib.Agreement storage a,
        mapping(bytes32 => bool) storage workBilled,
        uint256 shipmentId,
        bytes32 providerOrg,
        bytes32 clientOrg,
        Deps memory deps
    ) private returns (uint256 grams) {
        DeliveryLib.Shipment memory s = deps.deliveryManager.getShipment(shipmentId);
        if (
            s.status != DeliveryLib.ShipmentStatus.Delivered || _orgOf(s.carrier, deps.registry) != providerOrg
                || (_orgOf(s.shipper, deps.registry) != clientOrg && _orgOf(s.consignee, deps.registry) != clientOrg)
                || s.createdAt < a.activatedAt
        ) revert ServicesLib.B2BServices__InvalidWork(shipmentId);
        _markBilled(workBilled, keccak256(abi.encode("SHIPMENT", shipmentId)), shipmentId);
        uint256[] memory lots = deps.deliveryManager.lotsOf(shipmentId);
        for (uint256 i; i < lots.length; ++i) {
            grams += deps.supplyChain.lastWeight(lots[i]);
        }
    }

    /**
     * @dev Verifies a client lot consumed by `processLots` in the provider's custody into outputs created after
     * activation, marks it billed, and returns its input weight.
     * @param a The agreement.
     * @param workBilled Map of billed work.
     * @param id Input lot.
     * @param providerOrg Provider organisation.
     * @param clientOrg Client organisation.
     * @param deps Contracts to read from.
     * @return grams Input weight.
     */
    function _verifyTolling(
        ServicesLib.Agreement storage a,
        mapping(bytes32 => bool) storage workBilled,
        uint256 id,
        bytes32 providerOrg,
        bytes32 clientOrg,
        Deps memory deps
    ) private returns (uint256 grams) {
        PassportLib.Lot memory lot = deps.passport.getLot(id);
        uint256[] memory outputs = deps.passport.childrenOf(id);
        if (
            lot.status != PassportLib.LotStatus.Consumed || _orgOf(lot.custodian, deps.registry) != providerOrg
                || _orgOf(deps.passport.ownerOf(id), deps.registry) != clientOrg || outputs.length == 0
                || deps.passport.getLot(outputs[0]).registeredAt < a.activatedAt
        ) revert ServicesLib.B2BServices__InvalidWork(id);
        _markBilled(workBilled, keccak256(abi.encode("TOLL", id)), id);
        grams = deps.supplyChain.lastWeight(id);
    }

    /**
     * @dev Verifies a checkpoint of the kind's type signed by the provider's organisation after activation, on a lot
     * the client owns or holds (customs: since released), and marks it billed.
     * @param a The agreement.
     * @param workBilled Map of billed work.
     * @param tokenId Lot.
     * @param cpIndex Checkpoint index in the lot's log.
     * @param providerOrg Provider organisation.
     * @param clientOrg Client organisation.
     * @param deps Contracts to read from.
     */
    function _verifyCheckpoint(
        ServicesLib.Agreement storage a,
        mapping(bytes32 => bool) storage workBilled,
        uint256 tokenId,
        uint256 cpIndex,
        bytes32 providerOrg,
        bytes32 clientOrg,
        Deps memory deps
    ) private {
        ServicesLib.ServiceKind kind = a.service.kind;
        SupplyChainLib.CheckpointType expected = kind == ServicesLib.ServiceKind.InspectionAssay
            ? SupplyChainLib.CheckpointType.Inspection
            : kind == ServicesLib.ServiceKind.Audit
                ? SupplyChainLib.CheckpointType.Audit
                : SupplyChainLib.CheckpointType.CustomsDeclared;
        if (cpIndex >= deps.supplyChain.checkpointCount(tokenId)) revert ServicesLib.B2BServices__InvalidWork(tokenId);
        SupplyChainLib.Checkpoint memory cp = deps.supplyChain.getCheckpoint(tokenId, cpIndex);
        if (
            cp.cpType != expected || _orgOf(cp.signer, deps.registry) != providerOrg || cp.timestamp < a.activatedAt
                || (_orgOf(deps.passport.ownerOf(tokenId), deps.registry) != clientOrg
                    && _orgOf(deps.passport.custodianOf(tokenId), deps.registry) != clientOrg)
        ) revert ServicesLib.B2BServices__InvalidWork(tokenId);
        if (expected == SupplyChainLib.CheckpointType.CustomsDeclared) {
            SupplyChainLib.CustomsStatus cs = deps.supplyChain.customsStatus(tokenId);
            if (cs != SupplyChainLib.CustomsStatus.Released && cs != SupplyChainLib.CustomsStatus.Exited) {
                revert ServicesLib.B2BServices__InvalidWork(tokenId);
            }
        }
        _markBilled(workBilled, keccak256(abi.encode("CHECKPOINT", tokenId, cpIndex)), tokenId);
    }

    /**
     * @dev Marks a piece of work billed, reverting if it already was.
     * @param workBilled Map of billed work.
     * @param key Work key.
     * @param ref Reference reported in the error.
     */
    function _markBilled(mapping(bytes32 => bool) storage workBilled, bytes32 key, uint256 ref) private {
        if (workBilled[key]) revert ServicesLib.B2BServices__InvalidWork(ref);
        workBilled[key] = true;
    }

    /**
     * @dev Whether `account` is outside both parties' organisations.
     * @param a The agreement.
     * @param account The account.
     * @param registry Participant registry.
     * @return True if neutral.
     */
    function _isNeutral(ServicesLib.Agreement storage a, address account, IMineNetRegistry registry)
        private
        view
        returns (bool)
    {
        if (account == a.proposer.account || account == a.counterparty.account) return false;
        bytes32 org = registry.participant(account).orgId;
        return org == bytes32(0) || (org != a.proposer.orgId && org != a.counterparty.orgId);
    }

    /**
     * @dev An account's organisation (zero if not a participant).
     * @param account The account.
     * @param registry Participant registry.
     * @return The organisation id.
     */
    function _orgOf(address account, IMineNetRegistry registry) private view returns (bytes32) {
        return registry.participant(account).orgId;
    }

    /**
     * @dev A side's party record.
     * @param a The agreement.
     * @param side The side.
     * @return Storage pointer to the party.
     */
    function _party(ServicesLib.Agreement storage a, B2BLib.Side side) private view returns (B2BLib.Party storage) {
        return side == B2BLib.Side.Proposer ? a.proposer : a.counterparty;
    }
}
