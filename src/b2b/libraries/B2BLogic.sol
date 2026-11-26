// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {IMineNetRegistry} from "src/access/interfaces/IMineNetRegistry.sol";
import {ICurrencyManager} from "src/finance/interfaces/ICurrencyManager.sol";
import {ILotPassport} from "src/traceability/interfaces/ILotPassport.sol";
import {ISupplyChain} from "src/traceability/interfaces/ISupplyChain.sol";
import {IDeliveryManager} from "src/traceability/interfaces/IDeliveryManager.sol";
import {Actions} from "src/access/libraries/Actions.sol";
import {B2BLib} from "src/b2b/libraries/B2BLib.sol";
import {PassportLib} from "src/traceability/libraries/PassportLib.sol";
import {SupplyChainLib} from "src/traceability/libraries/SupplyChainLib.sol";
import {DeliveryLib} from "src/traceability/libraries/DeliveryLib.sol";

/**
 * @title B2BLogic
 * @author 0xEmmyb2
 * @notice Validation and verification logic of {B2B}: terms, lots, shipments, arrival, inspection and title.
 * @dev An external library: {B2B} calls it with `DELEGATECALL`, so it runs on {B2B}'s storage and its events
 * come from {B2B}. It exists to keep {B2B} under the EIP-170 contract size limit. It is deployed once and linked
 * at deployment (Foundry links it automatically in tests and `forge script`).
 */
library B2BLogic {
    /*//////////////////////////////////////////////////////////////
                                 LIMITS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Maximum number of deliveries in one agreement.
     */
    uint32 internal constant MAX_DELIVERIES = 365;

    /**
     * @notice Shortest interval between two deliveries.
     */
    uint32 internal constant MIN_DELIVERY_INTERVAL = 1 days;

    /**
     * @notice Longest interval between two deliveries.
     */
    uint32 internal constant MAX_DELIVERY_INTERVAL = 365 days;

    /**
     * @notice Longest time from activation to the first delivery.
     */
    uint32 internal constant MAX_FIRST_DELIVERY_OFFSET = 365 days;

    /**
     * @notice Largest quantity tolerance (20%), in basis points.
     */
    uint16 internal constant MAX_QUANTITY_TOLERANCE_BPS = 2_000;

    /**
     * @notice Shortest review period a buyer may be given.
     */
    uint32 internal constant MIN_REVIEW_PERIOD = 1 days;

    /**
     * @notice Longest review period a buyer may be given.
     */
    uint32 internal constant MAX_REVIEW_PERIOD = 30 days;

    /**
     * @notice Longest time a proposal may stay open for signature.
     */
    uint64 internal constant MAX_PROPOSAL_DURATION = 60 days;

    /**
     * @notice Time after arrival an automatic release waits for the destination inspection.
     */
    uint64 internal constant INSPECTION_GRACE = 14 days;

    /**
     * @notice The contracts {B2B} reads from.
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
     * @notice Validates and stores new terms, bumping the version and clearing every signature.
     * @param a The agreement.
     * @param t The terms.
     * @param registry Participant registry.
     * @param currencies Currency manager (settlement tokens).
     */
    function setTerms(
        B2BLib.Agreement storage a,
        B2BLib.Terms calldata t,
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
        _validateSchedule(t.supply, t.maxMissed, escrowed);

        a.seller = t.seller;
        requireTradingRole(a, B2BLib.Side.Proposer, a.proposer.account, registry);
        requireTradingRole(a, B2BLib.Side.Counterparty, a.counterparty.account, registry);

        B2BLib.TransportTerms calldata tr = t.transport;
        if (tr.transporter != address(0)) {
            if (
                !_isNeutral(a, tr.transporter, registry) || !registry.isAuthorized(tr.transporter, Actions.CARRY)
                    || (escrowed && (tr.distanceKm == 0 || tr.feePerKm == 0))
            ) revert B2BLib.B2B__InvalidTransporter(tr.transporter);
        } else if (tr.distanceKm != 0 || tr.feePerKm != 0) {
            revert B2BLib.B2B__InvalidTransporter(address(0));
        }
        if (t.arbiter != address(0) && !_isNeutral(a, t.arbiter, registry)) {
            revert B2BLib.B2B__InvalidArbiter(t.arbiter);
        }

        a.supply = t.supply;
        a.transport = tr;
        a.inspectionRequired = t.inspectionRequired;
        a.arbiter = t.arbiter;
        a.paymentToken = t.paymentToken;
        a.reviewPeriod = t.reviewPeriod;
        a.maxMissed = t.maxMissed;
        a.proposalExpiresAt = t.proposalExpiresAt;
        a.termsHash = t.termsHash;
        a.version += 1;
        a.proposerSigned = false;
        a.counterpartySigned = false;
        a.transporterAccepted = false;
    }

    /**
     * @notice Reverts unless `account` can take its side's trading role: `SELL_LOT` for the seller, `OWN_LOT` for
     * the buyer.
     * @param a The agreement.
     * @param side The side `account` acts for.
     * @param account The account.
     * @param registry Participant registry.
     */
    function requireTradingRole(
        B2BLib.Agreement storage a,
        B2BLib.Side side,
        address account,
        IMineNetRegistry registry
    ) public view {
        bytes32 action = side == a.seller ? Actions.SELL_LOT : Actions.OWN_LOT;
        if (!registry.isAuthorized(account, action)) revert B2BLib.B2B__InvalidTradingRole(account);
    }

    /*//////////////////////////////////////////////////////////////
                                DISPATCH
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Validates and commits the lots of a delivery and its shipment, returning the lots' total trusted
     * weight.
     * @dev Every lot must be of the agreed mineral, inspected, not frozen or escrow-locked, owned by the seller's
     * organisation, not committed elsewhere, at or above the minimum grade, approved for transfer to {B2B}, and
     * (with a shipment) in that shipment. The shipment is then checked as a whole.
     * @param a The agreement.
     * @param lotCommitted {B2B}'s lot commitment map.
     * @param tokenIds Lots.
     * @param shipmentId Shipment that must contain them (0 = none).
     * @param deps Contracts to read from.
     * @return weight Total trusted weight, in grams.
     */
    function commitLots(
        B2BLib.Agreement storage a,
        mapping(uint256 => bool) storage lotCommitted,
        uint256[] calldata tokenIds,
        uint256 shipmentId,
        Deps memory deps
    ) external returns (uint128 weight) {
        bytes32 sellerOrg = _party(a, a.seller).orgId;
        for (uint256 i; i < tokenIds.length; ++i) {
            uint256 id = tokenIds[i];
            if (lotCommitted[id]) revert B2BLib.B2B__InvalidLot(id);
            PassportLib.Lot memory lot = deps.passport.getLot(id);
            address owner = deps.passport.ownerOf(id);
            if (
                lot.mineralType != a.supply.mineralType || lot.status != PassportLib.LotStatus.Inspected
                    || deps.passport.isFrozen(id) || deps.passport.escrowLocked(id)
                    || deps.registry.participant(owner).orgId != sellerOrg || !_approved(owner, id, deps.passport)
                    || (shipmentId != 0 && deps.deliveryManager.activeShipmentOf(id) != shipmentId)
            ) revert B2BLib.B2B__InvalidLot(id);
            uint16 minGrade = a.supply.minGradeBps;
            if (minGrade != 0) {
                uint16 grade = deps.supplyChain.latestGrade(id).gradeBps;
                if (grade < minGrade) revert B2BLib.B2B__GradeTooLow(id, grade, minGrade);
            }
            lotCommitted[id] = true;
            weight += deps.supplyChain.lastWeight(id);
        }
        _checkShipment(a, shipmentId, tokenIds.length, deps);
    }

    /*//////////////////////////////////////////////////////////////
                           ARRIVAL & INSPECTION
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Whether the buyer's organisation holds custody of every lot of a delivery, and its shipment (if
     * any) is delivered.
     * @param a The agreement.
     * @param lots The delivery's lots.
     * @param shipmentId Its shipment (0 = none).
     * @param deps Contracts to read from.
     * @return True if arrived.
     */
    function hasArrived(B2BLib.Agreement storage a, uint256[] storage lots, uint256 shipmentId, Deps memory deps)
        external
        view
        returns (bool)
    {
        if (
            shipmentId != 0
                && deps.deliveryManager.getShipment(shipmentId).status != DeliveryLib.ShipmentStatus.Delivered
        ) return false;
        bytes32 buyerOrg = _party(a, B2BLib.other(a.seller)).orgId;
        for (uint256 i; i < lots.length; ++i) {
            if (deps.registry.participant(deps.passport.custodianOf(lots[i])).orgId != buyerOrg) return false;
        }
        return true;
    }

    /**
     * @notice The first frozen lot of a delivery, or 0 if none.
     * @param lots The delivery's lots.
     * @param passport Lot passport.
     * @return The frozen lot's token id (token ids start at 1).
     */
    function firstFrozenLot(uint256[] storage lots, ILotPassport passport) external view returns (uint256) {
        for (uint256 i; i < lots.length; ++i) {
            if (passport.isFrozen(lots[i])) return lots[i];
        }
        return 0;
    }

    /**
     * @notice Reverts unless an arrived delivery can be released automatically: no lot frozen and, when inspection
     * is required, every lot inspected since dispatch by an independent, platform-assigned inspector at or above the
     * minimum grade, or {INSPECTION_GRACE} passed since arrival without an inspection.
     * @param a The agreement.
     * @param lots The delivery's lots.
     * @param index Delivery index (for the error).
     * @param d The delivery.
     * @param deps Contracts to read from.
     */
    function requireCleared(
        B2BLib.Agreement storage a,
        uint256[] storage lots,
        uint256 index,
        B2BLib.Delivery storage d,
        Deps memory deps
    ) external view {
        uint64 graceEnds = d.arrivedAt + INSPECTION_GRACE;
        for (uint256 i; i < lots.length; ++i) {
            uint256 id = lots[i];
            if (deps.passport.isFrozen(id)) revert B2BLib.B2B__LotNotReleasable(id);
            if (!a.inspectionRequired) continue;
            (bool inspected, bool gradeOk) = _inspection(a, id, d.dispatchedAt, deps);
            if (inspected && !gradeOk) revert B2BLib.B2B__LotNotReleasable(id);
            if (!inspected && block.timestamp <= graceEnds) revert B2BLib.B2B__InspectionPending(index, graceEnds);
        }
    }

    /**
     * @notice Whether an arrived delivery has a problem that allows a late rejection: a frozen lot, or a lot an
     * independent inspector found below the minimum grade.
     * @param a The agreement.
     * @param lots The delivery's lots.
     * @param dispatchedAt Dispatch time; older inspections do not count.
     * @param deps Contracts to read from.
     * @return True if there is such a problem.
     */
    function hasProblem(B2BLib.Agreement storage a, uint256[] storage lots, uint64 dispatchedAt, Deps memory deps)
        external
        view
        returns (bool)
    {
        for (uint256 i; i < lots.length; ++i) {
            if (deps.passport.isFrozen(lots[i])) return true;
            (bool inspected, bool gradeOk) = _inspection(a, lots[i], dispatchedAt, deps);
            if (inspected && !gradeOk) return true;
        }
        return false;
    }

    /*//////////////////////////////////////////////////////////////
                                  TITLE
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Transfers every lot of a delivery from the seller's organisation to the buyer's account of record.
     * @dev Reverts if a lot left the seller's organisation, or the passport refuses the transfer (e.g. frozen).
     * @param a The agreement.
     * @param lots The delivery's lots.
     * @param deps Contracts to use.
     */
    function transferTitle(B2BLib.Agreement storage a, uint256[] storage lots, Deps memory deps) external {
        bytes32 sellerOrg = _party(a, a.seller).orgId;
        address buyer = _party(a, B2BLib.other(a.seller)).account;
        for (uint256 i; i < lots.length; ++i) {
            uint256 id = lots[i];
            address owner = deps.passport.ownerOf(id);
            if (deps.registry.participant(owner).orgId != sellerOrg) revert B2BLib.B2B__LotNotReleasable(id);
            // `owner` is in the seller's organisation, approved B2B and committed this lot to the delivery itself.
            // slither-disable-next-line arbitrary-send-erc20
            deps.passport.transferFrom(owner, buyer, id);
        }
    }

    /*//////////////////////////////////////////////////////////////
                                 PRIVATE
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Reverts unless the supply schedule is within the limits.
     * @param s The supply terms.
     * @param maxMissed Termination-for-cause threshold.
     * @param escrowed Whether payment is escrowed (a price is then required).
     */
    function _validateSchedule(B2BLib.SupplyTerms calldata s, uint16 maxMissed, bool escrowed) private pure {
        if (
            s.mineralType == bytes32(0) || s.quantityPerDelivery == 0
                || s.quantityToleranceBps > MAX_QUANTITY_TOLERANCE_BPS || s.minGradeBps > B2BLib.BPS
                || (escrowed && s.pricePerKg == 0) || s.totalDeliveries == 0 || s.totalDeliveries > MAX_DELIVERIES
                || (s.totalDeliveries > 1
                    && (s.deliveryInterval < MIN_DELIVERY_INTERVAL || s.deliveryInterval > MAX_DELIVERY_INTERVAL))
                || s.firstDeliveryOffset > MAX_FIRST_DELIVERY_OFFSET || maxMissed > s.totalDeliveries
        ) revert B2BLib.B2B__InvalidSchedule();
    }

    /**
     * @dev Reverts unless the shipment matches the delivery: required when a transporter is named, open, carried
     * by the named transporter, from the seller's to the buyer's organisation, with `lotCount` lots (each already
     * checked to be in it).
     * @param a The agreement.
     * @param shipmentId Shipment id (0 = none).
     * @param lotCount Number of lots in the delivery.
     * @param deps Contracts to read from.
     */
    function _checkShipment(B2BLib.Agreement storage a, uint256 shipmentId, uint256 lotCount, Deps memory deps)
        private
        view
    {
        address transporter = a.transport.transporter;
        if (shipmentId == 0) {
            if (transporter != address(0)) revert B2BLib.B2B__InvalidShipment(0);
            return;
        }
        DeliveryLib.Shipment memory s = deps.deliveryManager.getShipment(shipmentId);
        if (
            (s.status != DeliveryLib.ShipmentStatus.Created && s.status != DeliveryLib.ShipmentStatus.InTransit)
                || (transporter != address(0) && s.carrier != transporter)
                || deps.registry.participant(s.shipper).orgId != _party(a, a.seller).orgId
                || deps.registry.participant(s.consignee).orgId != _party(a, B2BLib.other(a.seller)).orgId
                || deps.deliveryManager.lotsOf(shipmentId).length != lotCount
        ) revert B2BLib.B2B__InvalidShipment(shipmentId);
    }

    /**
     * @dev The latest inspection of a lot since dispatch by an inspector independent of both parties. Inspection
     * checkpoints can only be recorded by the inspector the platform assigned ({InspectionRegistry}), so neither
     * party chooses who inspects.
     * @param a The agreement.
     * @param tokenId The lot.
     * @param since Dispatch time; older inspections do not count.
     * @param deps Contracts to read from.
     * @return inspected Whether an independent inspection was recorded since then.
     * @return gradeOk Whether that inspection meets the minimum grade (true when no minimum is set).
     */
    function _inspection(B2BLib.Agreement storage a, uint256 tokenId, uint64 since, Deps memory deps)
        private
        view
        returns (bool inspected, bool gradeOk)
    {
        bytes32 sellerOrg = _party(a, a.seller).orgId;
        bytes32 buyerOrg = _party(a, B2BLib.other(a.seller)).orgId;
        uint256 n = deps.supplyChain.checkpointCount(tokenId);
        for (uint256 i = n; i > 0; --i) {
            SupplyChainLib.Checkpoint memory cp = deps.supplyChain.getCheckpoint(tokenId, i - 1);
            if (cp.timestamp < since) break;
            if (cp.cpType != SupplyChainLib.CheckpointType.Inspection) continue;
            bytes32 org = deps.registry.participant(cp.signer).orgId;
            if (org == sellerOrg || org == buyerOrg) continue;
            return (true, a.supply.minGradeBps == 0 || cp.gradeBps >= a.supply.minGradeBps);
        }
    }

    /**
     * @dev Whether {B2B} (the delegate caller) may transfer lot `id` from `owner`.
     * @param owner The lot's owner.
     * @param id The lot.
     * @param passport Lot passport.
     * @return True if approved for the lot or for all of the owner's lots.
     */
    function _approved(address owner, uint256 id, ILotPassport passport) private view returns (bool) {
        return passport.getApproved(id) == address(this) || passport.isApprovedForAll(owner, address(this));
    }

    /**
     * @dev Whether `account` is a non-zero account outside both parties' organisations.
     * @param a The agreement.
     * @param account The account.
     * @param registry Participant registry.
     * @return True if neutral.
     */
    function _isNeutral(B2BLib.Agreement storage a, address account, IMineNetRegistry registry)
        private
        view
        returns (bool)
    {
        if (account == address(0) || account == a.proposer.account || account == a.counterparty.account) {
            return false;
        }
        bytes32 org = registry.participant(account).orgId;
        return org == bytes32(0) || (org != a.proposer.orgId && org != a.counterparty.orgId);
    }

    /**
     * @dev A side's party record.
     * @param a The agreement.
     * @param side The side.
     * @return Storage pointer to the party.
     */
    function _party(B2BLib.Agreement storage a, B2BLib.Side side) private view returns (B2BLib.Party storage) {
        return side == B2BLib.Side.Proposer ? a.proposer : a.counterparty;
    }
}
