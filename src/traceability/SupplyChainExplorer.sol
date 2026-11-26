// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {ILotPassport} from "src/traceability/interfaces/ILotPassport.sol";
import {ISupplyChain} from "src/traceability/interfaces/ISupplyChain.sol";
import {ISiteRegistry} from "src/compliance/interfaces/ISiteRegistry.sol";
import {ILotTagRegistry} from "src/traceability/interfaces/ILotTagRegistry.sol";
import {ExplorerLib} from "src/traceability/libraries/ExplorerLib.sol";
import {PassportLib} from "src/traceability/libraries/PassportLib.sol";
import {SupplyChainLib} from "src/traceability/libraries/SupplyChainLib.sol";

/**
 * @title SupplyChainExplorer
 * @author 0xEmmyb2
 * @notice Read-only view of a product's whole supply chain, for buyers, auditors, regulators and the app.
 * @dev A lot's history is split across contracts: {LotPassport} holds registration, inspections, ownership and
 * custody handovers, processing, flags and corrections; {SupplyChain} holds the checkpoints (weighings, pickups
 * and arrivals, warehouse in and out, processing input, grades, customs, border exit, audits and oracle
 * reports). This contract merges both into a single timeline in time order ({timeline}).
 *
 * A refined product is made from other lots, which may come from several mine sites. {provenance} walks the
 * parent links back to the original lots, and {fullJourney} returns the summary and timeline of every lot in the
 * chain, from the mine to the product, so the whole journey can be shown with every checkpoint.
 *
 * Views only, meant for `eth_call`; no state and no permissions. Everything shown is already public on-chain;
 * private documents stay off-chain and appear here only as hashes.
 */
contract SupplyChainExplorer {
    /**
     * @notice Maximum number of lots {provenance} and {fullJourney} will follow.
     */
    uint256 public constant MAX_LOTS = 64;

    /**
     * @notice Lot passport.
     */
    ILotPassport public immutable passport;

    /**
     * @notice Supply-chain checkpoints.
     */
    ISupplyChain public immutable supplyChain;

    /**
     * @notice Mine sites of origin.
     */
    ISiteRegistry public immutable sites;

    /**
     * @notice Lot QR tags.
     */
    ILotTagRegistry public immutable tags;

    /**
     * @notice The product's provenance has more than {MAX_LOTS} lots.
     */
    error SupplyChainExplorer__TooManyLots();

    /**
     * @param passport_ Lot passport.
     * @param supplyChain_ Supply-chain checkpoints.
     * @param sites_ Mine site registry.
     * @param tags_ Lot tag registry.
     */
    constructor(ILotPassport passport_, ISupplyChain supplyChain_, ISiteRegistry sites_, ILotTagRegistry tags_) {
        passport = passport_;
        supplyChain = supplyChain_;
        sites = sites_;
        tags = tags_;
    }

    /**
     * @notice Where a lot stands now and where it came from.
     * @dev Reverts for an unknown lot.
     * @param tokenId Lot.
     * @return s The lot summary.
     */
    function summary(uint256 tokenId) public view returns (ExplorerLib.LotSummary memory s) {
        PassportLib.Lot memory lot = passport.getLot(tokenId);
        s.tokenId = tokenId;
        s.lotId = lot.lotId;
        s.mineralType = lot.mineralType;
        s.registeredQty = lot.quantity;
        s.lastWeight = supplyChain.lastWeight(tokenId);
        s.status = lot.status;
        s.frozen = passport.isFrozen(tokenId);
        s.owner = passport.ownerOf(tokenId);
        s.custodian = lot.custodian;
        s.siteId = passport.siteOf(tokenId);
        if (s.siteId != 0) {
            s.siteRef = sites.getSite(s.siteId).siteRef;
            s.producerOrg = sites.orgOfSite(s.siteId);
        }
        s.tagHash = tags.tagOf(tokenId);
        s.customs = supplyChain.customsStatus(tokenId);
        s.gradeBps = supplyChain.latestGrade(tokenId).gradeBps;
        s.passportEvents = passport.eventCount(tokenId);
        s.checkpoints = supplyChain.checkpointCount(tokenId);
        s.parents = passport.parentsOf(tokenId);
        s.children = passport.childrenOf(tokenId);
    }

    /**
     * @notice Every passport event and checkpoint of one lot, merged in time order.
     * @dev Passport events come first when both happened in the same block.
     * @param tokenId Lot.
     * @return steps The merged timeline.
     */
    function timeline(uint256 tokenId) public view returns (ExplorerLib.Step[] memory steps) {
        uint256 nEvents = passport.eventCount(tokenId);
        uint256 nCheckpoints = supplyChain.checkpointCount(tokenId);
        PassportLib.PassportEvent[] memory events = passport.getEvents(tokenId, 0, nEvents);
        steps = new ExplorerLib.Step[](nEvents + nCheckpoints);

        uint256 e;
        uint256 c;
        ExplorerLib.Step memory nextCheckpoint;
        bool haveCheckpoint;
        for (uint256 k; k < steps.length; ++k) {
            if (!haveCheckpoint && c < nCheckpoints) {
                nextCheckpoint = _fromCheckpoint(supplyChain.getCheckpoint(tokenId, c));
                haveCheckpoint = true;
            }
            if (e < nEvents && (!haveCheckpoint || events[e].timestamp <= nextCheckpoint.timestamp)) {
                steps[k] = _fromEvent(events[e++]);
            } else {
                steps[k] = nextCheckpoint;
                haveCheckpoint = false;
                ++c;
            }
        }
    }

    /**
     * @notice The lot and every lot it was made from, ordered from the original mine lots to the lot itself.
     * @dev Breadth-first walk over parent links, reversed. Reverts beyond {MAX_LOTS} lots.
     * @param tokenId Lot or product.
     * @return lots Token ids, mine lots first.
     */
    function provenance(uint256 tokenId) public view returns (uint256[] memory lots) {
        passport.getLot(tokenId); // reverts for an unknown lot
        uint256[] memory queue = new uint256[](MAX_LOTS);
        uint256 n = 1;
        queue[0] = tokenId;
        for (uint256 head; head < n; ++head) {
            uint256[] memory parents = passport.parentsOf(queue[head]);
            for (uint256 i; i < parents.length; ++i) {
                if (_contains(queue, n, parents[i])) continue;
                if (n == MAX_LOTS) revert SupplyChainExplorer__TooManyLots();
                queue[n++] = parents[i];
            }
        }
        // breadth-first from the product backwards; reverse so the journey reads mine -> product
        lots = new uint256[](n);
        for (uint256 i; i < n; ++i) {
            lots[i] = queue[n - 1 - i];
        }
    }

    /**
     * @notice The original lots (registered at a mine site) a product comes from, with their sites.
     * @param tokenId Lot or product.
     * @return lots Original lot token ids.
     * @return siteIds Mine site of each original lot (same order).
     */
    function origins(uint256 tokenId) external view returns (uint256[] memory lots, uint256[] memory siteIds) {
        uint256[] memory chain = provenance(tokenId);
        lots = new uint256[](chain.length);
        siteIds = new uint256[](chain.length);
        uint256 n;
        for (uint256 i; i < chain.length; ++i) {
            if (passport.parentsOf(chain[i]).length == 0) {
                lots[n] = chain[i];
                siteIds[n] = passport.siteOf(chain[i]);
                ++n;
            }
        }
        assembly ("memory-safe") {
            mstore(lots, n)
            mstore(siteIds, n)
        }
    }

    /**
     * @notice The whole supply chain of a product: the summary and full timeline of every lot from the mine lots to
     * the product itself, in {provenance} order.
     * @param tokenId Lot or product.
     * @return journey One entry per lot.
     */
    function fullJourney(uint256 tokenId) external view returns (ExplorerLib.LotJourney[] memory journey) {
        uint256[] memory chain = provenance(tokenId);
        journey = new ExplorerLib.LotJourney[](chain.length);
        for (uint256 i; i < chain.length; ++i) {
            journey[i].lot = summary(chain[i]);
            journey[i].steps = timeline(chain[i]);
        }
    }

    /*//////////////////////////////////////////////////////////////
                                 INTERNAL
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Converts a passport event into a timeline step.
     * @param ev The passport event.
     * @return s The step.
     */
    function _fromEvent(PassportLib.PassportEvent memory ev) private pure returns (ExplorerLib.Step memory s) {
        s.source = ExplorerLib.Source.Passport;
        s.kind = uint8(ev.eventType);
        s.timestamp = ev.timestamp;
        s.actor = ev.actor;
        s.counterparty = ev.counterparty;
        s.dataHash = ev.dataHash;
        // an Inspection event stores 1 (passed) or 0 (failed) in `corrects`
        s.ok = ev.eventType != PassportLib.EventType.Inspection || ev.corrects == 1;
    }

    /**
     * @dev Converts a supply-chain checkpoint into a timeline step.
     * @param cp The checkpoint.
     * @return s The step.
     */
    function _fromCheckpoint(SupplyChainLib.Checkpoint memory cp) private pure returns (ExplorerLib.Step memory s) {
        s.source = ExplorerLib.Source.Checkpoint;
        s.kind = uint8(cp.cpType);
        s.timestamp = cp.timestamp;
        s.actor = cp.signer;
        s.quantity = cp.measuredQty;
        s.gradeBps = cp.gradeBps;
        s.condition = uint8(cp.condition);
        s.ok = cp.withinTolerance;
        s.dataHash = cp.evidenceHash;
        s.locationHash = cp.locationHash;
    }

    /**
     * @dev Whether `value` is among the first `n` entries of `arr`.
     * @param arr Array to search.
     * @param n Number of entries in use.
     * @param value Value to find.
     * @return True if found.
     */
    function _contains(uint256[] memory arr, uint256 n, uint256 value) private pure returns (bool) {
        for (uint256 i; i < n; ++i) {
            if (arr[i] == value) return true;
        }
        return false;
    }
}
