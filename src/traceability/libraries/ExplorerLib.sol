// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {PassportLib} from "src/traceability/libraries/PassportLib.sol";
import {SupplyChainLib} from "src/traceability/libraries/SupplyChainLib.sol";

/**
 * @title ExplorerLib
 * @author 0xEmmyb2
 * @notice Types returned by {SupplyChainExplorer}.
 */
library ExplorerLib {
    /**
     * @notice Where a {Step} of a lot's journey comes from.
     * @dev `Passport`: a {LotPassport} event, `kind` is a `PassportLib.EventType`. `Checkpoint`: a {SupplyChain}
     * checkpoint, `kind` is a `SupplyChainLib.CheckpointType`.
     */
    enum Source {
        Passport, // a LotPassport event: kind = PassportLib.EventType
        Checkpoint // a SupplyChain checkpoint: kind = SupplyChainLib.CheckpointType
    }

    /**
     * @notice One step of a lot's journey, from either source, in time order.
     * @param source Where the step comes from.
     * @param kind Event or checkpoint type, depending on `source`.
     * @param timestamp When the step happened.
     * @param actor Account that signed it.
     * @param counterparty Passport events: the other party (zero if none).
     * @param quantity Checkpoints: measured weight in grams (0 = not weighed).
     * @param gradeBps Inspection checkpoints: attested grade, in basis points.
     * @param condition Checkpoints: a `SupplyChainLib.Condition`.
     * @param ok Checkpoint within tolerance, audit or oracle passed, or passport inspection passed; otherwise true.
     * @param dataHash Hash of the evidence (document, ticket, report...).
     * @param locationHash Checkpoints: hash of where it happened.
     */
    struct Step {
        Source source;
        uint8 kind;
        uint64 timestamp;
        address actor;
        address counterparty;
        uint128 quantity;
        uint16 gradeBps;
        uint8 condition;
        bool ok;
        bytes32 dataHash;
        bytes32 locationHash;
    }

    /**
     * @notice Where a lot stands now, and where it came from.
     * @param tokenId Lot passport token id.
     * @param lotId Internal lot id from the backend.
     * @param mineralType Mineral identifier.
     * @param registeredQty Quantity registered, in grams.
     * @param lastWeight Last trusted weight, in grams.
     * @param status Current lot status.
     * @param frozen True while a regulator freeze or an open flag blocks the lot.
     * @param owner Current ERC-721 owner.
     * @param custodian Account physically holding the lot.
     * @param siteId Mine site of origin (0 for derived lots: see `parents`).
     * @param siteRef Backend reference of the mine site.
     * @param producerOrg Organisation holding the mine site.
     * @param tagHash Current QR tag.
     * @param customs Customs status.
     * @param gradeBps Latest attested grade, in basis points.
     * @param passportEvents Number of passport events.
     * @param checkpoints Number of supply-chain checkpoints.
     * @param parents Input lots it was processed from.
     * @param children Lots made from it.
     */
    struct LotSummary {
        uint256 tokenId;
        bytes32 lotId;
        bytes32 mineralType;
        uint128 registeredQty;
        uint128 lastWeight;
        PassportLib.LotStatus status;
        bool frozen;
        address owner;
        address custodian;
        uint256 siteId;
        bytes32 siteRef;
        bytes32 producerOrg;
        bytes32 tagHash;
        SupplyChainLib.CustomsStatus customs;
        uint16 gradeBps;
        uint256 passportEvents;
        uint256 checkpoints;
        uint256[] parents;
        uint256[] children;
    }

    /**
     * @notice A lot's summary and its full, time-ordered journey.
     * @param lot Summary of the lot.
     * @param steps Every passport event and checkpoint, in time order.
     */
    struct LotJourney {
        LotSummary lot;
        Step[] steps;
    }
}
