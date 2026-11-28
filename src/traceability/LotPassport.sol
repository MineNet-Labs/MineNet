// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {ILotPassport} from "src/traceability/interfaces/ILotPassport.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {IMineNetRegistry} from "src/access/interfaces/IMineNetRegistry.sol";
import {ISiteRegistry} from "src/compliance/interfaces/ISiteRegistry.sol";
import {IInspectionRegistry} from "src/compliance/interfaces/IInspectionRegistry.sol";
import {Actions} from "src/access/libraries/Actions.sol";
import {PassportLib} from "src/traceability/libraries/PassportLib.sol";

/**
 * @title LotPassport
 * @author 0xEmmyb2
 * @notice Digital passport for mineral lots. Each lot is one ERC-721 token, with an append-only history of
 * events.
 * @dev Ownership and custody are tracked separately:
 * - ownership: the ERC-721 owner (a miner, refinery or buyer), changed by a normal token transfer;
 * - custody: who physically holds the lot ({custodianOf}), changed only when the sender initiates and the
 *   receiver confirms.
 *
 * Only hashes and opaque references go on-chain. Documents stay encrypted off-chain.
 *
 * Types, events and errors live in {PassportLib}. Permissions are actions resolved by the registry (see
 * {Actions}), so the admin can change which roles may do what without redeploying.
 *
 * Responsibilities here:
 * - MINER: registers lots from its own Active mine site ({MineSiteRegistry}).
 * - INSPECTOR: attests grade and compliance; a passing inspection is needed to list or sell.
 * - PROCESSOR / REFINERY: turn lots they hold into derived lots (split, merge, concentrate, refine).
 * - BUYER / REFINERY: acquire ownership (through escrow or a direct transfer).
 * - Custody roles: hand lots over directly (both sides confirm) or through {DeliveryManager}.
 * - REGULATOR: freezes and unfreezes lots and resolves flags.
 * Weights, stage checkpoints, audits, oracle reports and customs live in {SupplyChain}. It raises flags here
 * through the module hook, so every freeze is enforced by this contract.
 */
contract LotPassport is ERC721, Pausable, ILotPassport {
    /*//////////////////////////////////////////////////////////////
                                 STORAGE
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Participant, role and permission registry.
     */
    IMineNetRegistry public immutable registry;

    /**
     * @dev Next token id; ids start at 1 so that 0 means "none".
     */
    uint256 private _nextTokenId = 1;

    /**
     * @dev Next flag id; ids start at 1 so that 0 means "none".
     */
    uint256 private _nextFlagId = 1;

    /**
     * @dev Token id => lot.
     */
    mapping(uint256 tokenId => PassportLib.Lot) private _lots;

    /**
     * @notice The token minted for an internal lot id (0 if none).
     */
    mapping(bytes32 lotId => uint256 tokenId) public tokenOfLot;

    /**
     * @dev Token id => append-only event history.
     */
    // slither-disable-next-line uninitialized-state (written through a storage pointer in _recordAs)
    mapping(uint256 tokenId => PassportLib.PassportEvent[]) private _events;

    /**
     * @dev Derived lot => input lots it was processed from.
     */
    mapping(uint256 tokenId => uint256[]) private _parents;

    /**
     * @dev Input lot => derived lots made from it.
     */
    // slither-disable-next-line uninitialized-state (written through a storage pointer in processLots)
    mapping(uint256 tokenId => uint256[]) private _children;

    /**
     * @dev Token id => pending direct custody handover.
     */
    mapping(uint256 tokenId => PassportLib.PendingCustody) private _pendingCustody;

    /**
     * @dev Flag id => flag.
     */
    mapping(uint256 flagId => PassportLib.Flag) private _flags;

    /**
     * @notice The escrow contract ({EscrowManager}) allowed to lock lots that are under an accepted order.
     */
    address public escrow;

    /**
     * @notice The contract that holds a lot locked under a trade ({EscrowManager} order or {B2B} delivery); zero if
     * unlocked. Only that contract can transfer the lot while it is locked.
     */
    mapping(uint256 tokenId => address locker) public lockedBy;

    /**
     * @notice Trade contracts other than {escrow} (e.g. {B2B}) allowed to lock lots they were approved for.
     */
    mapping(address locker => bool) public isLocker;

    /**
     * @dev Lock nonce of a lot, incremented on every lock so custody records of an earlier trade never count.
     */
    mapping(uint256 tokenId => uint32) private _lockNonce;

    /**
     * @dev keccak(tokenId, lock nonce, orgId) => first time custody reached that organisation during the lock.
     */
    mapping(bytes32 key => uint64) private _custodyReachedAt;

    /**
     * @notice Flags a reporter raised that a regulator later dismissed (a public record against frivolous flags).
     */
    mapping(address reporter => uint32) public dismissedFlagsOf;

    /**
     * @notice Module contracts ({DeliveryManager}, {SupplyChain}...) trusted to hand over custody and raise flags.
     */
    mapping(address module => bool) public isModule;

    /**
     * @dev Metadata is served by the platform at `<base>/<tokenId>`; private data never goes on-chain.
     */
    string private _baseTokenURI;

    /**
     * @notice Mine sites and concessions ({MineSiteRegistry}). Lots are registered only from an Active site of the
     * miner's organisation with a valid mining licence.
     */
    ISiteRegistry public siteRegistry;

    /**
     * @notice The inspection registry ({InspectionRegistry}). Once set, only the inspector it assigned to a lot may
     * record the lot's inspection.
     */
    IInspectionRegistry public inspectionRegistry;

    /**
     * @notice The mine site a registered lot came from (0 for derived lots: follow {parentsOf}).
     */
    mapping(uint256 tokenId => uint256 siteId) public siteOf;

    /**
     * @notice The lot-finance contract ({LotFinance}) that records liens and insurance cover.
     */
    address public financing;

    /**
     * @dev Token id => collateral for an active lien. An encumbered lot changes owner only through an
     * {escrow} sale (which repays the financier first), and cannot be processed or locked by another trade contract.
     */
    mapping(uint256 tokenId => bool) private _encumbered;

    /*//////////////////////////////////////////////////////////////
                                MODIFIERS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Restricts a function to accounts authorised for `action`.
     * @param action Required action ({Actions}).
     */
    modifier onlyAuthorized(bytes32 action) {
        _requireAuthorized(_msgSender(), action);
        _;
    }

    /**
     * @notice Restricts a function to {MineNetRegistry} admins.
     */
    modifier onlyRegistryAdmin() {
        _onlyRegistryAdmin();
        _;
    }

    /**
     * @notice Reverts unless lot `tokenId` exists.
     * @param tokenId Token id.
     */
    modifier lotExists(uint256 tokenId) {
        _requireLot(tokenId);
        _;
    }

    /**
     * @param registry_ Participant, role and permission registry.
     */
    constructor(IMineNetRegistry registry_) ERC721("MINENET Lot Passport", "MNLP") {
        registry = registry_;
    }

    /*//////////////////////////////////////////////////////////////
                                  ADMIN
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Pauses registration, transfers, custody, processing and corrections.
     * @dev Only a {MineNetRegistry} admin.
     */
    function pause() external onlyRegistryAdmin {
        _pause();
    }

    /**
     * @notice Resumes normal operation.
     * @dev Only a {MineNetRegistry} admin.
     */
    function unpause() external onlyRegistryAdmin {
        _unpause();
    }

    /**
     * @notice Sets the escrow contract.
     * @dev Only a {MineNetRegistry} admin. Locks placed by the previous escrow stay in force, and the new escrow
     * can release them, so the escrow can never be unset.
     * @param escrow_ Escrow contract; non-zero.
     * @custom:emits EscrowSet
     */
    function setEscrow(address escrow_) external onlyRegistryAdmin {
        if (escrow_ == address(0)) revert PassportLib.LotPassport__ZeroAddress();
        escrow = escrow_;
        emit PassportLib.EscrowSet(escrow_);
    }

    /**
     * @notice Sets the base URI of token metadata, served by the platform at `<base>/<tokenId>`.
     * @dev Only a {MineNetRegistry} admin. Private data never goes into public metadata.
     * @param baseURI_ New base URI.
     */
    function setBaseURI(string calldata baseURI_) external onlyRegistryAdmin {
        _baseTokenURI = baseURI_;
    }

    /**
     * @notice Sets the mine-site registry that gates lot registration.
     * @dev Only a {MineNetRegistry} admin.
     * @param siteRegistry_ Site registry ({MineSiteRegistry}).
     * @custom:emits SiteRegistrySet
     */
    function setSiteRegistry(ISiteRegistry siteRegistry_) external onlyRegistryAdmin {
        siteRegistry = siteRegistry_;
        emit PassportLib.SiteRegistrySet(address(siteRegistry_));
    }

    /**
     * @notice Sets the inspection registry that assigns inspectors to lots.
     * @dev Only a {MineNetRegistry} admin. Once set, a lot's inspection is accepted only from its assigned inspector.
     * @param inspectionRegistry_ Inspection registry ({InspectionRegistry}).
     * @custom:emits InspectionRegistrySet
     */
    function setInspectionRegistry(IInspectionRegistry inspectionRegistry_) external onlyRegistryAdmin {
        inspectionRegistry = inspectionRegistry_;
        emit PassportLib.InspectionRegistrySet(address(inspectionRegistry_));
    }

    /**
     * @notice Allows or disallows a trade contract (e.g. {B2B}) to lock lots it was approved for.
     * @dev Only a registry admin. {escrow} is always a locker.
     * @param locker The trade contract.
     * @param enabled Whether it may lock lots.
     * @custom:emits LockerSet
     */
    function setLocker(address locker, bool enabled) external onlyRegistryAdmin {
        if (locker == address(0)) revert PassportLib.LotPassport__ZeroAddress();
        isLocker[locker] = enabled;
        emit PassportLib.LockerSet(locker, enabled);
    }

    /**
     * @notice Enables or disables a module contract ({DeliveryManager}, {SupplyChain}, {LotTagRegistry},
     * {CargoTracker}).
     * @dev Only a {MineNetRegistry} admin. A module can move custody after its own two-party checks and raise flags
     * for a reporter. Disabling a module revokes these powers at once. Because a module can append custody events,
     * this power belongs behind the admin multisig and, in production, a timelock.
     * @param module Module contract.
     * @param enabled Whether it is trusted.
     * @custom:emits ModuleSet
     */
    function setModule(address module, bool enabled) external onlyRegistryAdmin {
        isModule[module] = enabled;
        emit PassportLib.ModuleSet(module, enabled);
    }

    /**
     * @notice Sets the lot-finance contract that records liens and insurance cover.
     * @dev Only a {MineNetRegistry} admin, once: the escrow settles liens through this contract, so replacing it
     * would strand the liens recorded by the old one.
     * @param financing_ Lot-finance contract ({LotFinance}); non-zero.
     * @custom:emits FinancingSet
     */
    function setFinancing(address financing_) external onlyRegistryAdmin {
        if (financing_ == address(0)) revert PassportLib.LotPassport__ZeroAddress();
        if (financing != address(0)) revert PassportLib.LotPassport__FinancingAlreadySet(financing);
        financing = financing_;
        emit PassportLib.FinancingSet(financing_);
    }

    /*//////////////////////////////////////////////////////////////
                 FINANCE: LIENS AND INSURANCE COVER
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc ILotPassport
     * @dev Only {financing}, which checks the owner's consent and the financier's or insurer's licence. `Lien`
     * encumbers the lot and `LienReleased` frees it; `Insured` only records the cover. Works while paused, so a
     * repayment can always release its lien.
     * @custom:emits PassportEventRecorded (Lien / LienReleased / Insured)
     */
    function recordFinancing(uint256 tokenId, PassportLib.EventType eventType, address actor, bytes32 dataHash)
        external
        lotExists(tokenId)
    {
        if (_msgSender() != financing) revert PassportLib.LotPassport__NotFinancing(_msgSender());
        if (eventType == PassportLib.EventType.Lien) {
            _encumbered[tokenId] = true;
        } else if (eventType == PassportLib.EventType.LienReleased) {
            delete _encumbered[tokenId];
        } else if (eventType != PassportLib.EventType.Insured) {
            revert PassportLib.LotPassport__InvalidFinanceEvent(eventType);
        }
        _recordAs(tokenId, eventType, actor, address(0), dataHash, 0);
    }

    /*//////////////////////////////////////////////////////////////
                   MODULES: TWO-PARTY HANDOVER & FLAGS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Moves custody from `from` to `to` once a module has collected both parties' confirmations (e.g.
     * {DeliveryManager}: the shipper named the carrier and the carrier confirmed pickup).
     * @dev Only a module. All direct-handover rules still apply: `from` is the custodian, the lot is not frozen,
     * not
     * consumed and not in a passport-level handover, and `to` is an active custody role.
     * @param tokenId Lot.
     * @param from Current custodian.
     * @param to New custodian.
     * @param evidenceHash Hash of the handover evidence.
     * @custom:emits PassportEventRecorded (CustodyConfirmed)
     * @custom:emits CustodyChanged
     */
    function moduleHandover(uint256 tokenId, address from, address to, bytes32 evidenceHash)
        external
        whenNotPaused
        lotExists(tokenId)
    {
        _onlyModule();
        PassportLib.Lot storage lot = _lots[tokenId];
        if (lot.custodian != from) revert PassportLib.LotPassport__NotCustodian(tokenId, from);
        if (lot.status == PassportLib.LotStatus.Consumed) {
            revert PassportLib.LotPassport__InvalidStatus(tokenId, lot.status);
        }
        _requireNotFrozen(tokenId);
        if (_pendingCustody[tokenId].to != address(0)) revert PassportLib.LotPassport__CustodyPending(tokenId);
        if (to == from || !_isCustodyRecipient(to)) revert PassportLib.LotPassport__InvalidRecipient(to);

        lot.custodian = to;
        _trackCustody(tokenId, to);
        _recordAs(tokenId, PassportLib.EventType.CustodyConfirmed, to, from, evidenceHash, 0);
        emit PassportLib.CustodyChanged(tokenId, from, to);
    }

    /**
     * @notice Raises a flag on behalf of `reporter`, whose authority the module has already checked (e.g. customs
     * holding a shipment, a weight mismatch, a broken seal). The flag freezes the lot.
     * @dev Only a module. Works while paused, so evidence of fraud is never lost.
     * @param tokenId Lot.
     * @param reporter Account recorded as raising the flag.
     * @param evidenceHash Hash of the evidence.
     * @return flagId New flag id.
     * @custom:emits FlagRaised
     */
    function moduleFlag(uint256 tokenId, address reporter, bytes32 evidenceHash)
        external
        lotExists(tokenId)
        returns (uint256 flagId)
    {
        _onlyModule();
        flagId = _raiseFlag(tokenId, reporter, evidenceHash);
    }

    /**
     * @notice Splits an inspected lot into smaller lots of the same mineral that stay inspected (e.g. to fill an
     * order for part of a batch). The parent is consumed; children keep its owner, custodian and site.
     * @dev Only a module ({SupplyChain}, which also carries over the trusted weights and grade). The lot must be
     * inspected, unfrozen, not locked under a trade, not pledged and have no pending handover. Child lot ids are
     * `keccak256(abi.encode(parentLotId, index))`.
     * @param tokenId Lot to split.
     * @param quantities Child quantities in grams (at least 2, each non-zero), summing to the lot's quantity.
     * @param splitHash Hash of the split record (order reference, weighing tickets).
     * @return ids Child token ids, in `quantities` order.
     * @custom:emits PassportEventRecorded (ProcessingInput / ProcessingOutput)
     */
    function moduleSplit(uint256 tokenId, uint128[] calldata quantities, bytes32 splitHash)
        external
        whenNotPaused
        lotExists(tokenId)
        returns (uint256[] memory ids)
    {
        _onlyModule();
        PassportLib.Lot storage lot = _lots[tokenId];
        if (lot.status != PassportLib.LotStatus.Inspected) {
            revert PassportLib.LotPassport__InvalidStatus(tokenId, lot.status);
        }
        if (quantities.length < 2) revert PassportLib.LotPassport__EmptyBatch();
        if (_pendingCustody[tokenId].to != address(0)) revert PassportLib.LotPassport__CustodyPending(tokenId);
        if (lockedBy[tokenId] != address(0)) revert PassportLib.LotPassport__LotLocked(tokenId);
        if (_encumbered[tokenId]) revert PassportLib.LotPassport__LotEncumbered(tokenId);
        _requireNotFrozen(tokenId);

        _setStatus(tokenId, PassportLib.LotStatus.Consumed);
        _record(tokenId, PassportLib.EventType.ProcessingInput, address(0), splitHash, 0);
        address lotOwner = _ownerOf(tokenId);
        uint256 site = siteOf[tokenId];
        uint256 total;
        ids = new uint256[](quantities.length);
        uint256[] storage kids = _children[tokenId];
        for (uint256 i; i < quantities.length; ++i) {
            total += quantities[i];
            uint256 id = _createLot(
                keccak256(abi.encode(lot.lotId, i)), lot.mineralType, quantities[i], lotOwner, lot.custodian
            );
            ids[i] = id;
            _setStatus(id, PassportLib.LotStatus.Inspected);
            siteOf[id] = site;
            _parents[id].push(tokenId);
            kids.push(id);
            _record(id, PassportLib.EventType.ProcessingOutput, address(0), splitHash, tokenId);
        }
        if (total != lot.quantity) revert PassportLib.LotPassport__QuantityExceeded(lot.quantity, total);
    }

    /*//////////////////////////////////////////////////////////////
                           ESCROW: TRADE LOCKS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Locks a lot under a trade: an accepted escrow order, or a dispatched B2B delivery.
     * @dev Only {escrow} or an approved locker. The owner must have approved the caller for this token (or for all
     * tokens): that approval is the seller's consent. The lot must not be frozen or already locked. While locked,
     * only the locker can transfer the lot (revoking the approval no longer stops the trade), it cannot be sold
     * elsewhere or processed, and every organisation custody reaches is recorded ({custodyReachedAt}).
     * @param tokenId Lot.
     * @custom:emits EscrowLockChanged
     */
    function lockForEscrow(uint256 tokenId) external whenNotPaused {
        address locker = _onlyLocker();
        if (lockedBy[tokenId] != address(0)) revert PassportLib.LotPassport__LotLocked(tokenId);
        if (_encumbered[tokenId] && locker != escrow) revert PassportLib.LotPassport__LotEncumbered(tokenId);
        if (!_isAuthorized(_requireOwned(tokenId), locker, tokenId)) {
            revert PassportLib.LotPassport__EscrowNotApproved(tokenId);
        }
        _requireNotFrozen(tokenId);
        lockedBy[tokenId] = locker;
        _lockNonce[tokenId] += 1;
        _trackCustody(tokenId, _lots[tokenId].custodian);
        emit PassportLib.EscrowLockChanged(tokenId, true);
    }

    /**
     * @notice Unlocks a lot whose trade ended without a sale.
     * @dev Only the contract that locked it.
     * @param tokenId Lot.
     * @custom:emits EscrowLockChanged
     */
    function unlockFromEscrow(uint256 tokenId) external {
        _onlyLockerOf(tokenId);
        delete lockedBy[tokenId];
        emit PassportLib.EscrowLockChanged(tokenId, false);
    }

    /**
     * @notice Settles a locked lot to the buyer and unlocks it.
     * @dev Only the contract that locked it. The ownership-transfer rules of {_update} apply (e.g. the lot must not
     * be frozen), except that the buyer's `OWN_LOT` authorisation is not re-checked: it was checked when the trade
     * was entered, and a licence lapsing mid-trade must not keep the seller from being paid.
     * @param tokenId Lot.
     * @param to Buyer.
     * @custom:emits PassportEventRecorded (OwnershipTransfer)
     * @custom:emits EscrowLockChanged
     */
    function escrowTransfer(uint256 tokenId, address to) external {
        _onlyLockerOf(tokenId);
        _update(to, tokenId, address(0)); // approval was checked when the lot was locked
        delete lockedBy[tokenId];
        emit PassportLib.EscrowLockChanged(tokenId, false);
    }

    /*//////////////////////////////////////////////////////////////
                           MINER: REGISTRATION
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Registers a mineral lot extracted at a mine site and mints its passport to the caller, who is also
     * the first custodian.
     * @dev The caller needs `REGISTER_LOT`. The site must be Active, belong to the caller's organisation, and sit
     * in
     * a concession with a valid mining licence (licence-gated entry). Idempotent: each internal `lotId` can produce
     * at most one token; a retry reverts with `LotPassport__LotAlreadyRegistered`, which tells the backend the earlier
     * mint already succeeded. The quantity is drawn from the site's recorded, not yet lotted extraction of that
     * mineral ({MineSiteRegistry-recordExtraction}), so a site cannot lot more than it reported producing (stops
     * outside minerals being laundered through a licensed site).
     * @param lotId Internal, immutable lot id from the backend; non-zero.
     * @param mineralType Mineral identifier, e.g. `keccak256("CASSITERITE")`.
     * @param quantity Quantity, in grams; non-zero.
     * @param siteId Mine site the lot was extracted at.
     * @param docsHash Hash of the registration documents.
     * @return tokenId New token id.
     * @custom:emits LotRegistered
     * @custom:emits LotSiteRecorded
     */
    function registerLot(bytes32 lotId, bytes32 mineralType, uint128 quantity, uint256 siteId, bytes32 docsHash)
        external
        whenNotPaused
        onlyAuthorized(Actions.REGISTER_LOT)
        returns (uint256 tokenId)
    {
        address miner = _msgSender();
        ISiteRegistry sites = siteRegistry;
        if (address(sites) == address(0)) revert PassportLib.LotPassport__SitesNotConfigured();
        if (!sites.canProduce(siteId, miner)) revert PassportLib.LotPassport__SiteNotProducing(siteId, miner);
        sites.consumeExtraction(siteId, mineralType, quantity); // reverts above the site's recorded extraction
        tokenId = _createLot(lotId, mineralType, quantity, miner, miner);
        siteOf[tokenId] = siteId;
        _record(tokenId, PassportLib.EventType.Registration, address(0), docsHash, 0);
        emit PassportLib.LotRegistered(tokenId, lotId, miner, quantity);
        emit PassportLib.LotSiteRecorded(tokenId, siteId);
    }

    /*//////////////////////////////////////////////////////////////
                       OWNER / CUSTODIAN: DOCUMENTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Anchors the hash of a supporting document (certificate, permit, customs form...).
     * @dev Only the lot's owner or custodian.
     * @param tokenId Lot.
     * @param docHash Hash of the document.
     * @custom:emits PassportEventRecorded (Document)
     */
    function anchorDocument(uint256 tokenId, bytes32 docHash) external whenNotPaused lotExists(tokenId) {
        address sender = _msgSender();
        if (sender != _ownerOf(tokenId) && sender != _lots[tokenId].custodian) {
            revert PassportLib.LotPassport__NotOwnerOrCustodian(tokenId, sender);
        }
        _record(tokenId, PassportLib.EventType.Document, address(0), docHash, 0);
    }

    /*//////////////////////////////////////////////////////////////
                          INSPECTOR: ATTESTATION
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Records an inspection result.
     * @dev The caller needs `INSPECT_LOT` and must be independent: neither the lot's owner nor its custodian. Once
     * the inspection registry is set, it must hold the open assignment the platform made for the lot (operators
     * never choose their inspector); submitting closes that assignment, so a result can never be revised. Effect:
     * - a newly registered lot becomes Inspected or Rejected;
     * - a Rejected lot (re-inspected on a regulator's order) becomes Inspected if it now passes;
     * - an Inspected lot that fails a later inspection is flagged, which freezes it until a regulator reviews the
     *   finding ({resolveFlag}); its status is not flipped, so trades in progress follow the regulator's decision.
     * Not allowed on consumed lots.
     * @param tokenId Lot.
     * @param passed Whether the lot passed.
     * @param reportHash Hash of the inspection report.
     * @custom:emits LotStatusChanged
     * @custom:emits PassportEventRecorded (Inspection)
     * @custom:emits FlagRaised
     */
    function submitInspection(uint256 tokenId, bool passed, bytes32 reportHash)
        external
        whenNotPaused
        lotExists(tokenId)
        onlyAuthorized(Actions.INSPECT_LOT)
    {
        PassportLib.Lot storage lot = _lots[tokenId];
        address inspector = _msgSender();
        if (inspector == _ownerOf(tokenId) || inspector == lot.custodian) {
            revert PassportLib.LotPassport__InspectorConflict(tokenId, inspector);
        }
        IInspectionRegistry inspections = inspectionRegistry;
        if (address(inspections) != address(0) && !inspections.isAssignmentOpen(tokenId, inspector)) {
            revert PassportLib.LotPassport__NotAssignedInspector(tokenId, inspector);
        }
        PassportLib.LotStatus status = lot.status;
        if (status == PassportLib.LotStatus.Consumed) revert PassportLib.LotPassport__InvalidStatus(tokenId, status);

        _record(tokenId, PassportLib.EventType.Inspection, address(0), reportHash, passed ? 1 : 0);
        if (status == PassportLib.LotStatus.Inspected) {
            if (!passed) _raiseFlag(tokenId, inspector, reportHash);
        } else if (passed || status == PassportLib.LotStatus.Registered) {
            _setStatus(tokenId, passed ? PassportLib.LotStatus.Inspected : PassportLib.LotStatus.Rejected);
        }
        if (address(inspections) != address(0)) inspections.completeInspection(tokenId, inspector);
    }

    /*//////////////////////////////////////////////////////////////
      OWNERSHIP TRANSFER: STANDARD ERC-721 TRANSFER, RESTRICTED IN {_UPDATE}
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Restricts ownership transfers made with `transferFrom` / `safeTransferFrom` (direct deals) or through
     * the
     * escrow (escrowed sales):
     * - the lot has passed inspection and is not frozen;
     * - the recipient is authorised to own lots (`OWN_LOT`: BUYER or REFINERY by default);
     * - a lot locked under an escrow order moves only through the escrow;
     * - a lot under a lien never moves: an escrow sale has {financing} repay and release the lien before the
     *   title transfer;
     * - passports are never burned.
     * Custody does not move with ownership; physical handover uses the custody flow. Listings live in the
     * {Marketplace}, not here. Every transfer is recorded as an `OwnershipTransfer` event.
     * @param to Recipient.
     * @param tokenId Lot.
     * @param auth Account whose approval is checked (zero to skip).
     * @return from Previous owner (zero for a mint).
     */
    function _update(address to, uint256 tokenId, address auth) internal override returns (address from) {
        from = _ownerOf(tokenId);

        if (from != address(0)) {
            _requireNotPaused();
            if (to == address(0)) revert PassportLib.LotPassport__InvalidRecipient(to); // passports are never burned
            address locker = lockedBy[tokenId];
            bool settlement = locker != address(0) && _msgSender() == locker;
            if (locker != address(0) && !settlement) revert PassportLib.LotPassport__LotLocked(tokenId);
            if (_encumbered[tokenId]) revert PassportLib.LotPassport__LotEncumbered(tokenId); // sale releases it first
            PassportLib.Lot storage lot = _lots[tokenId];
            if (lot.status != PassportLib.LotStatus.Inspected) {
                revert PassportLib.LotPassport__InvalidStatus(tokenId, lot.status);
            }
            _requireNotFrozen(tokenId);
            if (!settlement && !registry.isAuthorized(to, Actions.OWN_LOT)) {
                revert PassportLib.LotPassport__InvalidRecipient(to);
            }
        }

        from = super._update(to, tokenId, auth);

        if (from != address(0)) {
            _recordAs(tokenId, PassportLib.EventType.OwnershipTransfer, from, to, bytes32(0), 0);
        }
    }

    /*//////////////////////////////////////////////////////////////
               CUSTODY: SENDER INITIATES, RECEIVER CONFIRMS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice The current custodian proposes a handover to `to` (a transporter, warehouse, refinery or buyer).
     * @dev Only the custodian, while the lot is not frozen, not consumed and has no pending handover.
     * @param tokenId Lot.
     * @param to Receiver; an active custody role other than the caller.
     * @param evidenceHash Hash of the handover evidence.
     * @custom:emits PassportEventRecorded (CustodyInitiated)
     */
    function initiateCustodyTransfer(uint256 tokenId, address to, bytes32 evidenceHash)
        external
        whenNotPaused
        lotExists(tokenId)
    {
        PassportLib.Lot storage lot = _lots[tokenId];
        address sender = _msgSender();
        if (sender != lot.custodian) revert PassportLib.LotPassport__NotCustodian(tokenId, sender);
        if (lot.status == PassportLib.LotStatus.Consumed) {
            revert PassportLib.LotPassport__InvalidStatus(tokenId, lot.status);
        }
        _requireNotFrozen(tokenId);
        if (_pendingCustody[tokenId].to != address(0)) revert PassportLib.LotPassport__CustodyPending(tokenId);
        if (to == sender || !_isCustodyRecipient(to)) revert PassportLib.LotPassport__InvalidRecipient(to);

        _pendingCustody[tokenId] = PassportLib.PendingCustody(sender, to, evidenceHash, uint64(block.timestamp));
        _record(tokenId, PassportLib.EventType.CustodyInitiated, to, evidenceHash, 0);
    }

    /**
     * @notice The named receiver confirms receipt. Only then does custody change.
     * @dev Only the named receiver, while the lot is not frozen and it is still an active custody role.
     * @param tokenId Lot.
     * @param receiptHash Hash of the receipt.
     * @custom:emits PassportEventRecorded (CustodyConfirmed)
     * @custom:emits CustodyChanged
     */
    function confirmCustodyTransfer(uint256 tokenId, bytes32 receiptHash) external whenNotPaused {
        PassportLib.PendingCustody memory p = _pendingCustody[tokenId];
        if (p.to == address(0)) revert PassportLib.LotPassport__NoPendingCustody(tokenId);
        address receiver = _msgSender();
        if (receiver != p.to) revert PassportLib.LotPassport__NotPendingParty(tokenId, receiver);
        _requireNotFrozen(tokenId);
        if (!_isCustodyRecipient(receiver)) revert PassportLib.LotPassport__InvalidRecipient(receiver); // re-check: may be suspended since

        delete _pendingCustody[tokenId];
        _lots[tokenId].custodian = receiver;
        _trackCustody(tokenId, receiver);
        _record(tokenId, PassportLib.EventType.CustodyConfirmed, p.from, receiptHash, 0);
        emit PassportLib.CustodyChanged(tokenId, p.from, receiver);
    }

    /**
     * @notice The sender withdraws, or the receiver rejects, a pending handover. A regulator can also cancel one.
     * @param tokenId Lot.
     * @param reasonHash Hash of the reason.
     * @custom:emits PassportEventRecorded (CustodyCancelled)
     */
    function cancelCustodyTransfer(uint256 tokenId, bytes32 reasonHash) external whenNotPaused {
        PassportLib.PendingCustody memory p = _pendingCustody[tokenId];
        if (p.to == address(0)) revert PassportLib.LotPassport__NoPendingCustody(tokenId);
        address sender = _msgSender();
        if (sender != p.from && sender != p.to && !registry.isAuthorized(sender, Actions.REGULATE)) {
            revert PassportLib.LotPassport__NotPendingParty(tokenId, sender);
        }
        delete _pendingCustody[tokenId];
        _record(tokenId, PassportLib.EventType.CustodyCancelled, sender == p.from ? p.to : p.from, reasonHash, 0);
    }

    /*//////////////////////////////////////////////////////////////
      PROCESSOR / REFINERY: PROCESSING (SPLIT / MERGE / CONCENTRATE / REFINE)
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Uses input lots held by the calling processor or refinery to produce derived lots.
     * @dev The caller needs `PROCESS_LOTS`. Rules:
     * - each input passed inspection, is not frozen or locked under a trade, has no pending custody, and is held by
     *   the caller;
     * - all inputs have the same owner, who becomes the owner of the outputs, and who consented: the caller is in
     *   the owner's organisation, or was approved by the owner (ERC-721 approval) for each input;
     * - total output quantity <= total input quantity (no mass is created);
     * - inputs become Consumed; outputs start as Registered and need their own inspection.
     * Parent and child links are recorded for provenance.
     * @param inputIds Input lots (no duplicates).
     * @param outputs Derived lots to create.
     * @param processHash Hash of the off-chain processing record (yield report, assay...).
     * @return outputIds Token ids of the derived lots, in `outputs` order.
     * @custom:emits PassportEventRecorded (ProcessingInput / ProcessingOutput)
     */
    function processLots(uint256[] calldata inputIds, PassportLib.LotOutput[] calldata outputs, bytes32 processHash)
        external
        whenNotPaused
        returns (uint256[] memory outputIds)
    {
        address refinery = _msgSender(); // processor or refinery
        _requireAuthorized(refinery, Actions.PROCESS_LOTS);
        if (inputIds.length == 0 || outputs.length == 0) revert PassportLib.LotPassport__EmptyBatch();
        address lotOwner = _ownerOf(inputIds[0]);

        uint256 inputTotal;
        for (uint256 i; i < inputIds.length; ++i) {
            uint256 id = inputIds[i];
            PassportLib.Lot storage lot = _lots[id];
            if (lot.status != PassportLib.LotStatus.Inspected) {
                revert PassportLib.LotPassport__InvalidStatus(id, lot.status);
            }
            if (lot.custodian != refinery) revert PassportLib.LotPassport__NotCustodian(id, refinery);
            if (_ownerOf(id) != lotOwner) revert PassportLib.LotPassport__MixedOwnership(id);
            if (!registry.sameOrg(refinery, lotOwner) && !_isAuthorized(lotOwner, refinery, id)) {
                revert PassportLib.LotPassport__NoOwnerConsent(id, refinery);
            }
            if (_pendingCustody[id].to != address(0)) revert PassportLib.LotPassport__CustodyPending(id);
            if (lockedBy[id] != address(0)) revert PassportLib.LotPassport__LotLocked(id);
            if (_encumbered[id]) revert PassportLib.LotPassport__LotEncumbered(id);
            _requireNotFrozen(id);
            // Status becomes Consumed below, so a repeated id fails the status check above.
            inputTotal += lot.quantity;
            _setStatus(id, PassportLib.LotStatus.Consumed);
            _record(id, PassportLib.EventType.ProcessingInput, address(0), processHash, 0);
        }

        uint256 outputTotal;
        outputIds = new uint256[](outputs.length);
        for (uint256 j; j < outputs.length; ++j) {
            PassportLib.LotOutput calldata o = outputs[j];
            outputTotal += o.quantity;
            uint256 outId = _createLot(o.lotId, o.mineralType, o.quantity, lotOwner, refinery);
            outputIds[j] = outId;
            _parents[outId] = inputIds;
            _record(outId, PassportLib.EventType.ProcessingOutput, address(0), o.docsHash, 0);
        }
        if (outputTotal > inputTotal) revert PassportLib.LotPassport__QuantityExceeded(inputTotal, outputTotal);

        for (uint256 i; i < inputIds.length; ++i) {
            uint256[] storage kids = _children[inputIds[i]];
            for (uint256 j; j < outputIds.length; ++j) {
                kids.push(outputIds[j]);
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                          REGULATOR: ENFORCEMENT
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Puts a regulatory hold on a lot. A frozen lot cannot be listed, sold, moved or processed.
     * @dev The caller needs `REGULATE`.
     * @param tokenId Lot.
     * @param reasonHash Hash of the decision.
     * @custom:emits PassportEventRecorded (Frozen)
     */
    function freezeLot(uint256 tokenId, bytes32 reasonHash)
        external
        lotExists(tokenId)
        onlyAuthorized(Actions.REGULATE)
    {
        _lots[tokenId].regulatorHold = true;
        _record(tokenId, PassportLib.EventType.Frozen, address(0), reasonHash, 0);
    }

    /**
     * @notice Lifts a regulatory hold. Open flags still keep the lot frozen until they are resolved.
     * @dev The caller needs `REGULATE`.
     * @param tokenId Lot under a regulatory hold.
     * @param reasonHash Hash of the decision.
     * @custom:emits PassportEventRecorded (Unfrozen)
     */
    function unfreezeLot(uint256 tokenId, bytes32 reasonHash)
        external
        lotExists(tokenId)
        onlyAuthorized(Actions.REGULATE)
    {
        if (!_lots[tokenId].regulatorHold) {
            revert PassportLib.LotPassport__NotFrozenByRegulator(tokenId);
        }
        _lots[tokenId].regulatorHold = false;
        _record(tokenId, PassportLib.EventType.Unfrozen, address(0), reasonHash, 0);
    }

    /**
     * @notice Resolves a flag after human review. If `upheld`, the lot is also put on a regulatory hold; if
     * dismissed, it counts against the reporter in {dismissedFlagsOf}, a public record regulators use to act on
     * reporters who freeze lots without cause.
     * @dev The caller needs `REGULATE`.
     * @param flagId Open flag.
     * @param upheld True to uphold the flag, false to dismiss it.
     * @param resolutionHash Hash of the decision.
     * @custom:emits PassportEventRecorded (FlagResolved)
     * @custom:emits FlagResolved
     */
    function resolveFlag(uint256 flagId, bool upheld, bytes32 resolutionHash)
        external
        onlyAuthorized(Actions.REGULATE)
    {
        PassportLib.Flag storage f = _flags[flagId];
        if (f.status != PassportLib.FlagStatus.Open) revert PassportLib.LotPassport__FlagNotOpen(flagId);
        uint256 tokenId = f.tokenId;

        f.status = upheld ? PassportLib.FlagStatus.Upheld : PassportLib.FlagStatus.Dismissed;
        _lots[tokenId].openFlags -= 1;
        if (upheld) _lots[tokenId].regulatorHold = true;
        else dismissedFlagsOf[f.raisedBy] += 1;

        _record(tokenId, PassportLib.EventType.FlagResolved, f.raisedBy, resolutionHash, flagId);
        emit PassportLib.FlagResolved(flagId, tokenId, f.status, resolutionHash);
    }

    /*//////////////////////////////////////////////////////////////
                CORRECTIONS: APPEND ONLY, NEVER OVERWRITE
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Corrects an earlier event by appending a new event that points to it. History is never overwritten.
     * @dev Only the actor who recorded the original event.
     * @param tokenId Lot.
     * @param eventIndex Index of the event to correct.
     * @param correctedHash Hash of the corrected data.
     * @custom:emits PassportEventRecorded (Correction)
     */
    function correctEvent(uint256 tokenId, uint256 eventIndex, bytes32 correctedHash)
        external
        whenNotPaused
        lotExists(tokenId)
    {
        PassportLib.PassportEvent[] storage log = _events[tokenId];
        if (eventIndex >= log.length) revert PassportLib.LotPassport__UnknownEvent(tokenId, eventIndex);
        if (log[eventIndex].actor != _msgSender()) {
            revert PassportLib.LotPassport__NotEventActor(tokenId, eventIndex, _msgSender());
        }
        _record(tokenId, PassportLib.EventType.Correction, address(0), correctedHash, eventIndex + 1);
    }

    /*//////////////////////////////////////////////////////////////
                                  VIEWS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns a lot.
     * @dev Reverts for an unknown lot.
     * @param tokenId Token id.
     * @return The lot.
     */
    function getLot(uint256 tokenId) external view lotExists(tokenId) returns (PassportLib.Lot memory) {
        return _lots[tokenId];
    }

    /**
     * @inheritdoc ILotPassport
     */
    function escrowLocked(uint256 tokenId) external view returns (bool) {
        return lockedBy[tokenId] != address(0);
    }

    /**
     * @inheritdoc ILotPassport
     */
    function custodyReachedAt(uint256 tokenId, bytes32 orgId) external view returns (uint64) {
        if (lockedBy[tokenId] == address(0) || orgId == bytes32(0)) return 0;
        return _custodyReachedAt[_custodyKey(tokenId, orgId)];
    }

    /**
     * @notice Whether a lot is frozen by a regulatory hold or an open flag.
     * @param tokenId Token id.
     * @return True if frozen.
     */
    function isFrozen(uint256 tokenId) public view returns (bool) {
        PassportLib.Lot storage lot = _lots[tokenId];
        return lot.regulatorHold || lot.openFlags > 0;
    }

    /**
     * @notice The account physically holding a lot.
     * @dev Reverts for an unknown lot.
     * @param tokenId Token id.
     * @return The custodian.
     */
    function custodianOf(uint256 tokenId) external view lotExists(tokenId) returns (address) {
        return _lots[tokenId].custodian;
    }

    /**
     * @notice Number of events in a lot's history.
     * @param tokenId Token id.
     * @return Event count.
     */
    function eventCount(uint256 tokenId) external view returns (uint256) {
        return _events[tokenId].length;
    }

    /**
     * @notice Paginated event history.
     * @param tokenId Token id.
     * @param offset First index.
     * @param limit Maximum number of events.
     * @return page Up to `limit` events starting at `offset` (empty if `offset` is past the end).
     */
    function getEvents(uint256 tokenId, uint256 offset, uint256 limit)
        external
        view
        returns (PassportLib.PassportEvent[] memory page)
    {
        PassportLib.PassportEvent[] storage log = _events[tokenId];
        if (offset >= log.length) return new PassportLib.PassportEvent[](0);
        uint256 end = offset + limit > log.length ? log.length : offset + limit;
        page = new PassportLib.PassportEvent[](end - offset);
        for (uint256 i = offset; i < end; ++i) {
            page[i - offset] = log[i];
        }
    }

    /**
     * @notice The input lots a derived lot was processed from.
     * @param tokenId Token id.
     * @return Parent token ids (empty for a mine lot).
     */
    function parentsOf(uint256 tokenId) external view returns (uint256[] memory) {
        return _parents[tokenId];
    }

    /**
     * @notice The derived lots made from a lot.
     * @param tokenId Token id.
     * @return Child token ids.
     */
    function childrenOf(uint256 tokenId) external view returns (uint256[] memory) {
        return _children[tokenId];
    }

    /**
     * @notice Returns a lot's pending direct custody handover.
     * @param tokenId Token id.
     * @return The pending handover (zero `to` if none).
     */
    function pendingCustody(uint256 tokenId) external view returns (PassportLib.PendingCustody memory) {
        return _pendingCustody[tokenId];
    }

    /**
     * @notice Returns a flag.
     * @param flagId Flag id.
     * @return The flag (status `None` if unknown).
     */
    function getFlag(uint256 flagId) external view returns (PassportLib.Flag memory) {
        return _flags[flagId];
    }

    /*//////////////////////////////////////////////////////////////
                                 INTERNAL
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Validates and stores a new lot and mints its token. Uses `_mint`, not `_safeMint`, so no external call
     * happens during processing.
     * @param lotId Internal lot id; non-zero and unused.
     * @param mineralType Mineral identifier.
     * @param quantity Quantity, in grams; non-zero.
     * @param lotOwner Initial owner.
     * @param custodian Initial custodian.
     * @return tokenId New token id.
     */
    function _createLot(bytes32 lotId, bytes32 mineralType, uint128 quantity, address lotOwner, address custodian)
        private
        returns (uint256 tokenId)
    {
        if (lotId == bytes32(0)) revert PassportLib.LotPassport__InvalidLotId();
        if (quantity == 0) revert PassportLib.LotPassport__InvalidQuantity();
        uint256 existing = tokenOfLot[lotId];
        if (existing != 0) revert PassportLib.LotPassport__LotAlreadyRegistered(lotId, existing);

        tokenId = _nextTokenId++;
        tokenOfLot[lotId] = tokenId;
        _lots[tokenId] = PassportLib.Lot({
            lotId: lotId,
            mineralType: mineralType,
            quantity: quantity,
            registeredAt: uint64(block.timestamp),
            status: PassportLib.LotStatus.Registered,
            regulatorHold: false,
            openFlags: 0,
            custodian: custodian
        });

        _mint(lotOwner, tokenId); // _mint, not _safeMint: no external call during processing
        emit PassportLib.LotStatusChanged(tokenId, PassportLib.LotStatus.Registered);
    }

    /**
     * @dev Opens a flag on a lot, which freezes it.
     * @param tokenId Lot.
     * @param raisedBy Account recorded as raising it.
     * @param evidenceHash Hash of the evidence.
     * @return flagId New flag id.
     */
    function _raiseFlag(uint256 tokenId, address raisedBy, bytes32 evidenceHash) private returns (uint256 flagId) {
        flagId = _nextFlagId++;
        _flags[flagId] = PassportLib.Flag(tokenId, raisedBy, evidenceHash, PassportLib.FlagStatus.Open);
        PassportLib.Lot storage lot = _lots[tokenId];
        lot.openFlags += 1;
        _recordAs(tokenId, PassportLib.EventType.FlagRaised, raisedBy, address(0), evidenceHash, flagId);
        emit PassportLib.FlagRaised(flagId, tokenId, raisedBy, evidenceHash);
    }

    /**
     * @dev Appends an event signed by the caller. `corrects` is overloaded per event type so all records share one
     * compact shape: Correction -> corrected index + 1; Inspection -> 1 pass / 0 fail; FlagRaised / FlagResolved ->
     * flag id.
     * @param tokenId Lot.
     * @param eventType Kind of event.
     * @param counterparty Other party (zero if none).
     * @param dataHash Hash of the evidence.
     * @param corrects Type-specific value (see above).
     */
    function _record(
        uint256 tokenId,
        PassportLib.EventType eventType,
        address counterparty,
        bytes32 dataHash,
        uint256 corrects
    ) private {
        _recordAs(tokenId, eventType, _msgSender(), counterparty, dataHash, corrects);
    }

    /**
     * @dev Appends an event with an explicit actor.
     * @param tokenId Lot.
     * @param eventType Kind of event.
     * @param actor Signing account.
     * @param counterparty Other party (zero if none).
     * @param dataHash Hash of the evidence.
     * @param corrects Type-specific value (see {_record}).
     */
    function _recordAs(
        uint256 tokenId,
        PassportLib.EventType eventType,
        address actor,
        address counterparty,
        bytes32 dataHash,
        uint256 corrects
    ) private {
        PassportLib.PassportEvent[] storage log = _events[tokenId];
        uint256 index = log.length;
        log.push(PassportLib.PassportEvent(eventType, uint64(block.timestamp), actor, counterparty, dataHash, corrects));
        emit PassportLib.PassportEventRecorded(tokenId, index, eventType, actor, counterparty, dataHash, corrects);
    }

    /**
     * @dev Sets a lot's status.
     * @param tokenId Lot.
     * @param status New status.
     */
    function _setStatus(uint256 tokenId, PassportLib.LotStatus status) private {
        _lots[tokenId].status = status;
        emit PassportLib.LotStatusChanged(tokenId, status);
    }

    /**
     * @dev Reverts unless `account` may perform `action`.
     * @param account The account.
     * @param action Required action.
     */
    function _requireAuthorized(address account, bytes32 action) private view {
        if (!registry.isAuthorized(account, action)) revert PassportLib.LotPassport__Unauthorized(account, action);
    }

    /**
     * @dev Reverts unless the caller is a {MineNetRegistry} admin. Kept out of the modifier so its code is not
     * repeated at every admin function.
     */
    function _onlyRegistryAdmin() private view {
        if (!registry.isAdmin(_msgSender())) revert PassportLib.LotPassport__NotRegistryAdmin(_msgSender());
    }

    /**
     * @dev Reverts unless lot `tokenId` exists.
     * @param tokenId Token id.
     */
    function _requireLot(uint256 tokenId) private view {
        if (_lots[tokenId].status == PassportLib.LotStatus.None) revert PassportLib.LotPassport__UnknownLot(tokenId);
    }

    /**
     * @dev Reverts unless the caller is a trusted module.
     */
    function _onlyModule() private view {
        if (!isModule[_msgSender()]) revert PassportLib.LotPassport__NotModule(_msgSender());
    }

    /**
     * @dev Reverts unless the caller is the (non-zero) escrow or an approved locker.
     * @return locker The caller.
     */
    function _onlyLocker() private view returns (address locker) {
        locker = _msgSender();
        if ((locker != escrow || locker == address(0)) && !isLocker[locker]) {
            revert PassportLib.LotPassport__NotEscrow(locker);
        }
    }

    /**
     * @dev Reverts unless the caller is the contract that locked `tokenId`.
     * @param tokenId Lot.
     */
    function _onlyLockerOf(uint256 tokenId) private view {
        address locker = lockedBy[tokenId];
        if (locker == address(0)) revert PassportLib.LotPassport__NotLocked(tokenId);
        if (_msgSender() != locker) revert PassportLib.LotPassport__NotEscrow(_msgSender());
    }

    /**
     * @dev While a lot is locked under a trade, records the first time custody reaches `custodian`'s organisation,
     * so a delivery stays proven even if the buyer passes the goods on before anyone confirms it.
     * @param tokenId Lot.
     * @param custodian New custodian.
     */
    function _trackCustody(uint256 tokenId, address custodian) private {
        if (lockedBy[tokenId] == address(0)) return;
        bytes32 orgId = registry.participant(custodian).orgId;
        if (orgId == bytes32(0)) return;
        bytes32 key = _custodyKey(tokenId, orgId);
        if (_custodyReachedAt[key] == 0) _custodyReachedAt[key] = uint64(block.timestamp);
    }

    /**
     * @dev Storage key of a custody record for the lot's current lock.
     * @param tokenId Lot.
     * @param orgId Organisation.
     * @return The key.
     */
    function _custodyKey(uint256 tokenId, bytes32 orgId) private view returns (bytes32) {
        return keccak256(abi.encode(tokenId, _lockNonce[tokenId], orgId));
    }

    /**
     * @dev Reverts if the lot is frozen.
     * @param tokenId Lot.
     */
    function _requireNotFrozen(uint256 tokenId) private view {
        if (isFrozen(tokenId)) revert PassportLib.LotPassport__LotFrozen(tokenId);
    }

    /**
     * @dev Whether an account may hold custody.
     * @param account The account.
     * @return True if authorised for `HOLD_CUSTODY`.
     */
    function _isCustodyRecipient(address account) private view returns (bool) {
        return registry.isAuthorized(account, Actions.HOLD_CUSTODY);
    }

    /**
     * @dev Base URI used by `tokenURI`.
     * @return The base URI.
     */
    function _baseURI() internal view override returns (string memory) {
        return _baseTokenURI;
    }
}
