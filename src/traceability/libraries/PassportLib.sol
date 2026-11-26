// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

/**
 * @title PassportLib
 * @author 0xEmmyb2
 * @notice Shared types, events and custom errors of {LotPassport}.
 */
library PassportLib {
    /**
     * @notice Lifecycle status of a lot.
     * @dev `Registered`: minted, awaiting inspection. `Inspected`: passed inspection. `Rejected`: failed
     * inspection. `Consumed`: used as input to processing (terminal).
     */
    enum LotStatus {
        None,
        Registered, // minted, awaiting inspection
        Inspected, // passed inspection
        Rejected, // failed inspection
        Consumed // used as input to processing; terminal
    }

    /**
     * @notice Kind of entry in a lot's append-only passport history.
     */
    enum EventType {
        Registration,
        Document,
        Inspection,
        OwnershipTransfer,
        CustodyInitiated,
        CustodyConfirmed,
        CustodyCancelled,
        ProcessingInput,
        ProcessingOutput,
        FlagRaised,
        FlagResolved,
        Frozen,
        Unfrozen,
        Correction
    }

    /**
     * @notice Status of a flag raised on a lot.
     */
    enum FlagStatus {
        None,
        Open,
        Dismissed,
        Upheld
    }

    /**
     * @notice A mineral lot.
     * @param lotId Internal, immutable lot id from the backend.
     * @param mineralType Mineral identifier, e.g. `keccak256("CASSITERITE")`.
     * @param quantity Quantity, in grams.
     * @param registeredAt When the lot was registered.
     * @param status Current status.
     * @param regulatorHold True while a regulator has frozen the lot.
     * @param openFlags Number of open flags; any open flag freezes the lot.
     * @param custodian Account physically holding the lot.
     */
    struct Lot {
        bytes32 lotId;
        bytes32 mineralType;
        uint128 quantity;
        uint64 registeredAt;
        LotStatus status;
        bool regulatorHold;
        uint32 openFlags;
        address custodian;
    }

    /**
     * @notice One entry of a lot's append-only passport history.
     * @param eventType Kind of event.
     * @param timestamp Block timestamp.
     * @param actor Account that signed it.
     * @param counterparty The other party, where there is one (zero otherwise).
     * @param dataHash Hash of the off-chain evidence.
     * @param corrects Correction: corrected index + 1. Inspection: 1 pass / 0 fail. Flags: the flag id.
     */
    struct PassportEvent {
        EventType eventType;
        uint64 timestamp;
        address actor;
        address counterparty;
        bytes32 dataHash;
        uint256 corrects;
    }

    /**
     * @notice A custody hand-over initiated by the sender and awaiting the receiver's confirmation.
     * @param from Current custodian.
     * @param to Receiver.
     * @param evidenceHash Hash of the hand-over evidence.
     * @param initiatedAt When it was initiated.
     */
    struct PendingCustody {
        address from;
        address to;
        bytes32 evidenceHash;
        uint64 initiatedAt;
    }

    /**
     * @notice A fraud or discrepancy flag raised on a lot, reviewed by a person.
     * @param tokenId Flagged lot.
     * @param raisedBy Account or module that raised it.
     * @param evidenceHash Hash of the evidence.
     * @param status Current status.
     */
    struct Flag {
        uint256 tokenId;
        address raisedBy;
        bytes32 evidenceHash;
        FlagStatus status;
    }

    /**
     * @notice A derived lot produced by processing.
     * @param lotId Internal lot id of the output.
     * @param mineralType Mineral identifier of the output.
     * @param quantity Quantity, in grams.
     * @param docsHash Hash of the processing documents.
     */
    struct LotOutput {
        bytes32 lotId;
        bytes32 mineralType;
        uint128 quantity;
        bytes32 docsHash;
    }

    /**
     * @notice Emitted for every entry appended to a lot's passport history.
     * @param tokenId Lot.
     * @param index Entry index.
     * @param eventType Kind of event.
     * @param actor Signing account.
     * @param counterparty Other party (zero if none).
     * @param dataHash Hash of the evidence.
     * @param corrects See {PassportEvent}.
     */
    event PassportEventRecorded(
        uint256 indexed tokenId,
        uint256 indexed index,
        EventType indexed eventType,
        address actor,
        address counterparty,
        bytes32 dataHash,
        uint256 corrects
    );

    /**
     * @notice Emitted when a lot passport is minted.
     * @param tokenId New token id.
     * @param lotId Internal lot id.
     * @param miner Registering miner.
     * @param quantity Quantity, in grams.
     */
    event LotRegistered(uint256 indexed tokenId, bytes32 indexed lotId, address indexed miner, uint128 quantity);

    /**
     * @notice Emitted when a lot's mine site of origin is recorded.
     * @param tokenId Lot.
     * @param siteId Mine site.
     */
    event LotSiteRecorded(uint256 indexed tokenId, uint256 indexed siteId);

    /**
     * @notice Emitted when the admin sets the site registry.
     * @param siteRegistry Site registry contract.
     */
    event SiteRegistrySet(address indexed siteRegistry);

    /**
     * @notice Emitted when the admin sets the inspection registry.
     * @param inspectionRegistry Inspection registry contract.
     */
    event InspectionRegistrySet(address indexed inspectionRegistry);

    /**
     * @notice Emitted when a lot's status changes.
     * @param tokenId Lot.
     * @param status New status.
     */
    event LotStatusChanged(uint256 indexed tokenId, LotStatus status);

    /**
     * @notice Emitted when a lot's physical custody changes.
     * @param tokenId Lot.
     * @param from Previous custodian.
     * @param to New custodian.
     */
    event CustodyChanged(uint256 indexed tokenId, address indexed from, address indexed to);

    /**
     * @notice Emitted when a flag is raised on a lot; the lot is frozen while it is open.
     * @param flagId New flag id.
     * @param tokenId Lot.
     * @param raisedBy Account or module that raised it.
     * @param evidenceHash Hash of the evidence.
     */
    event FlagRaised(uint256 indexed flagId, uint256 indexed tokenId, address indexed raisedBy, bytes32 evidenceHash);

    /**
     * @notice Emitted when a regulator resolves a flag.
     * @param flagId Flag id.
     * @param tokenId Lot.
     * @param status Outcome (`Dismissed` or `Upheld`).
     * @param resolutionHash Hash of the decision.
     */
    event FlagResolved(uint256 indexed flagId, uint256 indexed tokenId, FlagStatus status, bytes32 resolutionHash);

    /**
     * @notice Emitted when the admin sets the escrow contract.
     * @param escrow Escrow contract.
     */
    event EscrowSet(address indexed escrow);

    /**
     * @notice Emitted when a module contract is trusted or untrusted.
     * @param module Module contract.
     * @param enabled Whether it is trusted.
     */
    event ModuleSet(address indexed module, bool enabled);

    /**
     * @notice Emitted when a trade contract is allowed or disallowed to lock lots.
     * @param locker Trade contract.
     * @param enabled Whether it may lock lots.
     */
    event LockerSet(address indexed locker, bool enabled);

    /**
     * @notice Emitted when the escrow locks or unlocks a lot.
     * @param tokenId Lot.
     * @param locked Whether the lot is now locked.
     */
    event EscrowLockChanged(uint256 indexed tokenId, bool locked);

    /**
     * @notice `account` may not perform `action`.
     * @param account The account.
     * @param action Required action ({Actions}).
     */
    error LotPassport__Unauthorized(address account, bytes32 action);

    /**
     * @notice `account` is not an admin of {MineNetRegistry}.
     * @param account The account.
     */
    error LotPassport__NotRegistryAdmin(address account);

    /**
     * @notice Lot `lotId` is already registered as token `tokenId`.
     * @param lotId The lot id.
     * @param tokenId Its token.
     */
    error LotPassport__LotAlreadyRegistered(bytes32 lotId, uint256 tokenId);

    /**
     * @notice The lot id is zero.
     */
    error LotPassport__InvalidLotId();

    /**
     * @notice The quantity is zero.
     */
    error LotPassport__InvalidQuantity();

    /**
     * @notice Lot `tokenId` does not exist.
     * @param tokenId The token id.
     */
    error LotPassport__UnknownLot(uint256 tokenId);

    /**
     * @notice Lot `tokenId` is in `status`, which does not allow the operation.
     * @param tokenId The lot.
     * @param status Its current status.
     */
    error LotPassport__InvalidStatus(uint256 tokenId, LotStatus status);

    /**
     * @notice Lot `tokenId` is frozen by a regulator hold or an open flag.
     * @param tokenId The lot.
     */
    error LotPassport__LotFrozen(uint256 tokenId);

    /**
     * @notice `account` is not the custodian of lot `tokenId`.
     * @param tokenId The lot.
     * @param account The account.
     */
    error LotPassport__NotCustodian(uint256 tokenId, address account);

    /**
     * @notice `account` is neither the owner nor the custodian of lot `tokenId`.
     * @param tokenId The lot.
     * @param account The account.
     */
    error LotPassport__NotOwnerOrCustodian(uint256 tokenId, address account);

    /**
     * @notice `inspector` belongs to an organisation involved with lot `tokenId`.
     * @param tokenId The lot.
     * @param inspector The inspector.
     */
    error LotPassport__InspectorConflict(uint256 tokenId, address inspector);

    /**
     * @notice `to` cannot receive the lot (zero address, the sender, or not authorised).
     * @param to The recipient.
     */
    error LotPassport__InvalidRecipient(address to);

    /**
     * @notice Lot `tokenId` has a pending custody hand-over.
     * @param tokenId The lot.
     */
    error LotPassport__CustodyPending(uint256 tokenId);

    /**
     * @notice Lot `tokenId` has no pending custody hand-over.
     * @param tokenId The lot.
     */
    error LotPassport__NoPendingCustody(uint256 tokenId);

    /**
     * @notice `account` is not a party to lot `tokenId`'s pending hand-over.
     * @param tokenId The lot.
     * @param account The account.
     */
    error LotPassport__NotPendingParty(uint256 tokenId, address account);

    /**
     * @notice A processing batch has no inputs or no outputs.
     */
    error LotPassport__EmptyBatch();

    /**
     * @notice Input lot `tokenId` has a different owner from the other inputs.
     * @param tokenId The lot.
     */
    error LotPassport__MixedOwnership(uint256 tokenId);

    /**
     * @notice The outputs of processing weigh more than its inputs.
     * @param inputTotal Total input quantity, in grams.
     * @param outputTotal Total output quantity, in grams.
     */
    error LotPassport__QuantityExceeded(uint256 inputTotal, uint256 outputTotal);

    /**
     * @notice Lot `tokenId` has no passport event at `index`.
     * @param tokenId The lot.
     * @param index Event index.
     */
    error LotPassport__UnknownEvent(uint256 tokenId, uint256 index);

    /**
     * @notice `account` did not sign event `index` of lot `tokenId` and cannot correct it.
     * @param tokenId The lot.
     * @param index Event index.
     * @param account The account.
     */
    error LotPassport__NotEventActor(uint256 tokenId, uint256 index, address account);

    /**
     * @notice Flag `flagId` is not open.
     * @param flagId The flag.
     */
    error LotPassport__FlagNotOpen(uint256 flagId);

    /**
     * @notice Lot `tokenId` has no regulator hold.
     * @param tokenId The lot.
     */
    error LotPassport__NotFrozenByRegulator(uint256 tokenId);

    /**
     * @notice `account` is not the escrow contract.
     * @param account The account.
     */
    error LotPassport__NotEscrow(address account);

    /**
     * @notice Lot `tokenId` is locked under an escrow order.
     * @param tokenId The lot.
     */
    error LotPassport__LotLocked(uint256 tokenId);

    /**
     * @notice Lot `tokenId` is not locked.
     * @param tokenId The lot.
     */
    error LotPassport__NotLocked(uint256 tokenId);

    /**
     * @notice `processor` may not process lot `tokenId`: it is outside the owner's organisation and the owner did
     * not approve it for the lot.
     * @param tokenId The lot.
     * @param processor The processor.
     */
    error LotPassport__NoOwnerConsent(uint256 tokenId, address processor);

    /**
     * @notice The escrow is not approved to transfer lot `tokenId`.
     * @param tokenId The lot.
     */
    error LotPassport__EscrowNotApproved(uint256 tokenId);

    /**
     * @notice `account` is not a trusted module.
     * @param account The account.
     */
    error LotPassport__NotModule(address account);

    /**
     * @notice The site registry has not been set.
     */
    error LotPassport__SitesNotConfigured();

    /**
     * @notice `miner` may not register lots from site `siteId`.
     * @param siteId The site.
     * @param miner The miner.
     */
    error LotPassport__SiteNotProducing(uint256 siteId, address miner);

    /**
     * @notice An address that must be set is zero.
     */
    error LotPassport__ZeroAddress();

    /**
     * @notice `inspector` is not the inspector the platform assigned to lot `tokenId`.
     * @param tokenId The lot.
     * @param inspector The inspector.
     */
    error LotPassport__NotAssignedInspector(uint256 tokenId, address inspector);
}
