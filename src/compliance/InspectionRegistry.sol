// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {IMineNetRegistry} from "src/access/interfaces/IMineNetRegistry.sol";
import {IInspectionRegistry} from "src/compliance/interfaces/IInspectionRegistry.sol";
import {ISiteRegistry} from "src/compliance/interfaces/ISiteRegistry.sol";
import {ILotPassport} from "src/traceability/interfaces/ILotPassport.sol";
import {ISupplyChain} from "src/traceability/interfaces/ISupplyChain.sol";
import {Actions} from "src/access/libraries/Actions.sol";
import {Roles} from "src/access/libraries/Roles.sol";
import {InspectionLib} from "src/compliance/libraries/InspectionLib.sol";

/**
 * @title InspectionRegistry
 * @author 0xEmmyb2
 * @notice The inspector roster and the platform's assignment of inspectors to lots. Inspectors are deployed by the
 * inspectorate, never chosen by the operator whose minerals they inspect.
 * @dev Mirrors how inspection works in Rwanda: the Rwanda Mines, Petroleum and Gas Board (RMB) employs and deploys
 * mine inspectors (mining engineers, geologists, environmental specialists) under Law n° 072/2024 to licensed
 * concessions, processing plants and quarries, on scheduled or unannounced visits; traceability programmes (ITSCI,
 * RCS Global Better Mining) deploy their own field agents to monitor pits and tag minerals. Operators have no say in
 * which inspector checks their site or lot.
 *
 * ## Roster
 * Regulators of the institution that licenses the INSPECTOR role ({MineNetRegistry-roleAuthority}, e.g. RMB)
 * approve inspectorate bodies (state inspectorate or traceability operator), and enrol their vetted inspectors with
 * the districts they are deployed to (or the {InspectionLib.NATIONAL} pool). Inspectors set their own availability.
 *
 * ## Assignment
 * The owner or custodian of a lot, or a regulator (unannounced inspection), requests an inspection. The platform
 * draws an inspector at random among those deployed to the district of the lot's mine site who are available,
 * authorised and independent of both the owner's and the custodian's organisation, falling back to the national
 * pool. The inspector has {inspectionWindow} to inspect. It may decline (e.g. a conflict of interest), and once the
 * window has passed the lot can be reassigned; the previous inspector is never drawn again for that round.
 *
 * {SupplyChain} (inspection checkpoints) and {LotPassport} (pass / fail inspections) only accept the inspector
 * assigned here, and {MineSiteRegistry} only accepts site safety inspections and reserve verifications from
 * inspectors deployed to the site's district.
 *
 * Randomness uses `block.prevrandao`, which removes any choice by the requester; it is not bias-proof against the
 * block producer. A verifiable randomness source (e.g. Chainlink VRF) can replace it without changing the interface.
 */
contract InspectionRegistry is IInspectionRegistry {
    using EnumerableSet for EnumerableSet.AddressSet;

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Maximum number of coverage keys (districts) per inspector.
     */
    uint256 public constant MAX_COVERAGE = 30;

    /**
     * @notice Maximum number of inspectors scanned per pool when drawing one (bounds gas).
     */
    uint256 public constant MAX_POOL_SCAN = 200;

    /**
     * @notice Shortest inspection window.
     */
    uint32 public constant MIN_INSPECTION_WINDOW = 1 days;

    /**
     * @notice Longest inspection window.
     */
    uint32 public constant MAX_INSPECTION_WINDOW = 60 days;

    /*//////////////////////////////////////////////////////////////
                                 STORAGE
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Participant, role and permission registry.
     */
    IMineNetRegistry public immutable registry;

    /**
     * @notice Lot passports (owner, custodian, mine site).
     */
    ILotPassport public immutable passport;

    /**
     * @notice Mine sites (district of a lot's origin).
     */
    ISiteRegistry public immutable sites;

    /**
     * @notice Supply-chain ledger, where assigned inspectors record inspection checkpoints.
     */
    ISupplyChain public immutable supplyChain;

    /**
     * @notice Time an assigned inspector has to inspect before the lot can be reassigned.
     */
    uint32 public inspectionWindow = 7 days;

    /**
     * @notice Approved inspectorate bodies and their kind.
     */
    mapping(bytes32 orgId => InspectionLib.InspectorateKind) public inspectorateOf;

    /**
     * @dev Inspector => roster record.
     */
    mapping(address inspector => InspectionLib.Inspector) private _inspectors;

    /**
     * @dev Inspector => coverage keys it is deployed to.
     */
    mapping(address inspector => bytes32[]) private _coverageOf;

    /**
     * @dev Coverage key (district or national) => inspectors deployed there.
     */
    mapping(bytes32 coverage => EnumerableSet.AddressSet) private _pools;

    /**
     * @dev Lot => current inspection assignment.
     */
    mapping(uint256 tokenId => InspectionLib.Assignment) private _assignments;

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @param registry_ Participant, role and permission registry.
     * @param passport_ Lot passport.
     * @param sites_ Mine site registry.
     * @param supplyChain_ Supply-chain ledger.
     */
    constructor(IMineNetRegistry registry_, ILotPassport passport_, ISiteRegistry sites_, ISupplyChain supplyChain_) {
        registry = registry_;
        passport = passport_;
        sites = sites_;
        supplyChain = supplyChain_;
    }

    /*//////////////////////////////////////////////////////////////
                  USER-FACING STATE-CHANGING FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Approves, changes or removes an inspectorate body (state inspectorate or traceability operator).
     * @dev Only a regulator of the institution that licenses inspectors. Removing a body stops its inspectors from
     * being drawn.
     * @param orgId The body's organisation id.
     * @param kind Its kind (`None` to remove).
     * @custom:emits InspectorateSet
     */
    function setInspectorate(bytes32 orgId, InspectionLib.InspectorateKind kind) external {
        _onlyInspectorAuthority();
        inspectorateOf[orgId] = kind;
        emit InspectionLib.InspectorateSet(orgId, kind, msg.sender);
    }

    /**
     * @notice Enrols a vetted inspector on the roster, or redeploys one, to districts and/or the national pool.
     * @dev Only a regulator of the institution that licenses inspectors. The inspector must hold the INSPECTOR role
     * and belong to an approved inspectorate body. Replaces any previous deployment; the inspector starts available.
     * @param inspector The inspector's account.
     * @param coverage District keys ({InspectionLib-districtKey}) and/or {InspectionLib.NATIONAL}.
     * @custom:emits InspectorDeployed
     */
    function deployInspector(address inspector, bytes32[] calldata coverage) external {
        _onlyInspectorAuthority();
        if (coverage.length == 0 || coverage.length > MAX_COVERAGE) {
            revert InspectionLib.InspectionRegistry__InvalidCoverage();
        }
        bytes32 org = registry.participant(inspector).orgId;
        if (
            !registry.isActive(inspector, Roles.INSPECTOR) || inspectorateOf[org] == InspectionLib.InspectorateKind.None
        ) {
            revert InspectionLib.InspectionRegistry__InvalidInspector(inspector);
        }

        _withdrawCoverage(inspector);
        for (uint256 i; i < coverage.length; ++i) {
            if (coverage[i] == bytes32(0)) revert InspectionLib.InspectionRegistry__InvalidCoverage();
            // slither-disable-next-line unused-return (re-adding an existing key is a no-op)
            _pools[coverage[i]].add(inspector);
        }
        _coverageOf[inspector] = coverage;
        InspectionLib.Inspector storage ins = _inspectors[inspector];
        ins.enrolled = true;
        ins.available = true;
        ins.inspectorateOrg = org;
        emit InspectionLib.InspectorDeployed(inspector, org, coverage, msg.sender);
    }

    /**
     * @notice Removes an inspector from the roster. Its current assignments stay until they are reassigned.
     * @dev Only a regulator of the institution that licenses inspectors.
     * @param inspector The inspector.
     * @param reasonHash Hash of the reason.
     * @custom:emits InspectorRemoved
     */
    function removeInspector(address inspector, bytes32 reasonHash) external {
        _onlyInspectorAuthority();
        if (!_inspectors[inspector].enrolled) revert InspectionLib.InspectionRegistry__NotEnrolled(inspector);
        _withdrawCoverage(inspector);
        delete _coverageOf[inspector];
        _inspectors[inspector].enrolled = false;
        _inspectors[inspector].available = false;
        emit InspectionLib.InspectorRemoved(inspector, msg.sender, reasonHash);
    }

    /**
     * @notice An inspector on the roster sets whether it takes new assignments (leave, workload...).
     * @param available Whether it takes new assignments.
     * @custom:emits AvailabilitySet
     */
    function setAvailability(bool available) external {
        if (!_inspectors[msg.sender].enrolled) revert InspectionLib.InspectionRegistry__NotEnrolled(msg.sender);
        _inspectors[msg.sender].available = available;
        emit InspectionLib.AvailabilitySet(msg.sender, available);
    }

    /**
     * @notice Sets the time an assigned inspector has to inspect.
     * @dev Only a regulator of the institution that licenses inspectors.
     * @param window Inspection window, in seconds.
     * @custom:emits InspectionWindowSet
     */
    function setInspectionWindow(uint32 window) external {
        _onlyInspectorAuthority();
        if (window < MIN_INSPECTION_WINDOW || window > MAX_INSPECTION_WINDOW) {
            revert InspectionLib.InspectionRegistry__InvalidWindow();
        }
        inspectionWindow = window;
        emit InspectionLib.InspectionWindowSet(window);
    }

    /**
     * @notice Requests an inspection of a lot: the platform assigns an independent inspector at random.
     * @dev The lot's owner or custodian, or a regulator (unannounced inspection). Not while the current assignment
     * is still within its window; after it, the lot is reassigned to a different inspector.
     * @param tokenId The lot.
     * @return inspector The assigned inspector.
     * @custom:emits InspectionAssigned
     */
    function requestInspection(uint256 tokenId) external returns (address inspector) {
        address owner = passport.ownerOf(tokenId);
        address custodian = passport.custodianOf(tokenId);
        if (msg.sender != owner && msg.sender != custodian && !registry.isAuthorized(msg.sender, Actions.REGULATE)) {
            revert InspectionLib.InspectionRegistry__NotAllowedToRequest(tokenId, msg.sender);
        }
        InspectionLib.Assignment storage current = _assignments[tokenId];
        if (current.inspector != address(0) && block.timestamp <= current.dueBy) {
            revert InspectionLib.InspectionRegistry__AssignmentOpen(tokenId, current.dueBy);
        }
        inspector = _assign(tokenId, owner, custodian);
    }

    /**
     * @notice The assigned inspector declines a lot (e.g. a conflict of interest); the lot is reassigned at once.
     * @dev Only the inspector currently assigned to the lot.
     * @param tokenId The lot.
     * @param reasonHash Hash of the reason.
     * @return inspector The newly assigned inspector.
     * @custom:emits InspectionDeclined
     * @custom:emits InspectionAssigned
     */
    function declineInspection(uint256 tokenId, bytes32 reasonHash) external returns (address inspector) {
        if (_assignments[tokenId].inspector != msg.sender) {
            revert InspectionLib.InspectionRegistry__NotAssigned(tokenId, msg.sender);
        }
        emit InspectionLib.InspectionDeclined(tokenId, msg.sender, reasonHash);
        inspector = _assign(tokenId, passport.ownerOf(tokenId), passport.custodianOf(tokenId));
    }

    /*//////////////////////////////////////////////////////////////
                     USER-FACING READ-ONLY FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc IInspectionRegistry
     */
    function assignedInspector(uint256 tokenId) external view returns (address inspector) {
        inspector = _assignments[tokenId].inspector;
    }

    /**
     * @inheritdoc IInspectionRegistry
     */
    function coversSite(address inspector, uint256 siteId) external view returns (bool) {
        if (!_inspectors[inspector].enrolled) return false;
        if (_pools[InspectionLib.NATIONAL].contains(inspector)) return true;
        return _pools[InspectionLib.districtKey(sites.getSiteLocation(siteId).district)].contains(inspector);
    }

    /**
     * @notice Returns a lot's current inspection assignment.
     * @param tokenId The lot.
     * @return The assignment (zero inspector if none).
     */
    function getAssignment(uint256 tokenId) external view returns (InspectionLib.Assignment memory) {
        return _assignments[tokenId];
    }

    /**
     * @notice Returns an inspector's roster record.
     * @param inspector The inspector.
     * @return The record.
     */
    function getInspector(address inspector) external view returns (InspectionLib.Inspector memory) {
        return _inspectors[inspector];
    }

    /**
     * @notice Returns the coverage keys an inspector is deployed to.
     * @param inspector The inspector.
     * @return Coverage keys.
     */
    function coverageOf(address inspector) external view returns (bytes32[] memory) {
        return _coverageOf[inspector];
    }

    /**
     * @notice Returns the inspectors deployed to a coverage key (district or national).
     * @param coverage Coverage key.
     * @return Inspector accounts.
     */
    function inspectorsIn(bytes32 coverage) external view returns (address[] memory) {
        return _pools[coverage].values();
    }

    /*//////////////////////////////////////////////////////////////
                    INTERNAL STATE-CHANGING FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Draws an eligible inspector (district pool first, then national), excluding the current one, and records
     * the assignment, moving the checkpoint right in {SupplyChain} from the previous inspector to the new one.
     * @param tokenId The lot.
     * @param owner The lot's owner.
     * @param custodian The lot's custodian.
     * @return inspector The assigned inspector.
     */
    function _assign(uint256 tokenId, address owner, address custodian) private returns (address inspector) {
        InspectionLib.Assignment storage a = _assignments[tokenId];
        address previous = a.inspector;
        bytes32 ownerOrg = registry.participant(owner).orgId;
        bytes32 custodianOrg = registry.participant(custodian).orgId;
        uint256 seed = uint256(keccak256(abi.encode(block.prevrandao, block.timestamp, tokenId, a.round)));

        uint256 siteId = passport.siteOf(tokenId);
        bytes32 coverage =
            siteId == 0 ? InspectionLib.NATIONAL : InspectionLib.districtKey(sites.getSiteLocation(siteId).district);
        inspector = _draw(coverage, seed, previous, ownerOrg, custodianOrg);
        if (inspector == address(0) && coverage != InspectionLib.NATIONAL) {
            coverage = InspectionLib.NATIONAL;
            inspector = _draw(coverage, seed, previous, ownerOrg, custodianOrg);
        }
        if (inspector == address(0)) revert InspectionLib.InspectionRegistry__NoInspectorAvailable(tokenId);

        // effects
        if (previous != address(0) && _inspectors[previous].activeAssignments != 0) {
            _inspectors[previous].activeAssignments -= 1;
        }
        _inspectors[inspector].activeAssignments += 1;
        uint64 dueBy = uint64(block.timestamp) + inspectionWindow;
        uint32 round = a.round + 1;
        a.inspector = inspector;
        a.requestedBy = msg.sender;
        a.assignedAt = uint64(block.timestamp);
        a.dueBy = dueBy;
        a.round = round;
        a.coverage = coverage;
        emit InspectionLib.InspectionAssigned(tokenId, inspector, msg.sender, coverage, dueBy, round);

        // interactions: move the checkpoint right in SupplyChain
        if (previous != address(0)) supplyChain.unassignInspector(tokenId, previous);
        supplyChain.assignInspector(tokenId, inspector);
    }

    /**
     * @dev Removes an inspector from every pool it is deployed to.
     * @param inspector The inspector.
     */
    function _withdrawCoverage(address inspector) private {
        bytes32[] storage coverage = _coverageOf[inspector];
        for (uint256 i; i < coverage.length; ++i) {
            // slither-disable-next-line unused-return (removing an absent key is a no-op)
            _pools[coverage[i]].remove(inspector);
        }
    }

    /*//////////////////////////////////////////////////////////////
                      INTERNAL READ-ONLY FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Draws an eligible inspector from a pool, uniformly at random among the eligible ones: on the roster,
     * available, authorised to inspect, not `excluded`, and outside both the owner's and the custodian's
     * organisation.
     * @param coverage Pool key.
     * @param seed Randomness seed.
     * @param excluded Inspector that may not be drawn (the previous one).
     * @param ownerOrg Owner's organisation.
     * @param custodianOrg Custodian's organisation.
     * @return The drawn inspector, or zero if none is eligible.
     */
    function _draw(bytes32 coverage, uint256 seed, address excluded, bytes32 ownerOrg, bytes32 custodianOrg)
        private
        view
        returns (address)
    {
        EnumerableSet.AddressSet storage pool = _pools[coverage];
        uint256 n = pool.length();
        if (n > MAX_POOL_SCAN) n = MAX_POOL_SCAN;
        address[] memory eligible = new address[](n);
        uint256 count;
        for (uint256 i; i < n; ++i) {
            address candidate = pool.at(i);
            if (candidate == excluded || !_inspectors[candidate].available) continue;
            bytes32 org = registry.participant(candidate).orgId;
            if (org == ownerOrg || org == custodianOrg) continue;
            if (!registry.isAuthorized(candidate, Actions.INSPECT_LOT)) continue;
            if (inspectorateOf[org] == InspectionLib.InspectorateKind.None) continue;
            eligible[count++] = candidate;
        }
        // block.prevrandao removes the requester's choice; it is not bias-proof against the block producer (documented
        // trade-off; Chainlink VRF can replace it behind the same interface).
        // slither-disable-next-line weak-prng
        return count == 0 ? address(0) : eligible[seed % count];
    }

    /**
     * @dev Reverts unless the caller is an authorised regulator of the institution that licenses inspectors.
     */
    function _onlyInspectorAuthority() private view {
        bytes32 authority = registry.roleAuthority(Roles.INSPECTOR);
        if (
            authority == bytes32(0) || !registry.isAuthorized(msg.sender, Actions.REGULATE)
                || registry.participant(msg.sender).orgId != authority
        ) revert InspectionLib.InspectionRegistry__NotInspectorAuthority(msg.sender);
    }
}
