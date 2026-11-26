// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {IVRFCoordinatorV2Plus} from "@chainlink/contracts/src/v0.8/vrf/interfaces/IVRFCoordinatorV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/libraries/VRFV2PlusClient.sol";
import {PassportLib} from "src/traceability/libraries/PassportLib.sol";
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
 * An assignment closes as soon as the inspector submits its pass / fail result to {LotPassport}: the inspector
 * cannot inspect the lot again, and cannot revise its result. A lot that failed inspection is re-inspected only on
 * a regulator's order, so an operator cannot keep requesting inspections until one passes.
 *
 * {SupplyChain} (inspection checkpoints) and {LotPassport} (pass / fail inspections) only accept the inspector
 * assigned here, and {MineSiteRegistry} only accepts site safety inspections and reserve verifications from
 * inspectors deployed to the site's district.
 *
 * ## Randomness
 * When Chainlink VRF v2.5 is configured ({setVrfConfig}), every draw uses verifiable randomness: a request records a
 * pending draw and the assignment is made when the coordinator fulfils it, so nobody (requester, sequencer or block
 * producer) can predict or steer which inspector is drawn. Without VRF the registry falls back to
 * `block.prevrandao`, which removes the requester's choice but is predictable on a sequencer-ordered L2 such as
 * Base; configure VRF for production.
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

    /**
     * @notice Time after which an unfulfilled VRF draw can be replaced by a new request.
     */
    uint64 public constant DRAW_TIMEOUT = 1 days;

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

    /**
     * @notice Chainlink VRF settings (zero coordinator = `block.prevrandao` fallback).
     */
    InspectionLib.VrfConfig public vrfConfig;

    /**
     * @dev Lot => random draw awaiting VRF fulfilment.
     */
    mapping(uint256 tokenId => InspectionLib.PendingDraw) private _pendingDraws;

    /**
     * @dev VRF request id => lot.
     */
    mapping(uint256 requestId => uint256 tokenId) private _drawOf;

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
     * @notice Sets the Chainlink VRF v2.5 settings used to draw inspectors.
     * @dev Only a registry admin. A zero coordinator switches back to the `block.prevrandao` fallback. The registry
     * must be added as a consumer of the subscription.
     * @param config VRF settings.
     * @custom:emits VrfConfigSet
     */
    function setVrfConfig(InspectionLib.VrfConfig calldata config) external {
        if (!registry.isAdmin(msg.sender)) revert InspectionLib.InspectionRegistry__NotRegistryAdmin(msg.sender);
        if (
            config.coordinator != address(0)
                && (config.keyHash == bytes32(0) || config.subId == 0 || config.callbackGasLimit == 0)
        ) revert InspectionLib.InspectionRegistry__InvalidVrfConfig();
        vrfConfig = config;
        emit InspectionLib.VrfConfigSet(config.coordinator, config.keyHash, config.subId);
    }

    /**
     * @notice Requests an inspection of a lot: the platform assigns an independent inspector at random.
     * @dev The lot's owner or custodian, or a regulator (unannounced inspection). Not while an assignment is open or
     * a draw is pending. A lot that failed inspection is re-inspected only on a regulator's order. With VRF
     * configured the assignment is made on fulfilment and this returns zero.
     * @param tokenId The lot.
     * @return inspector The assigned inspector (zero while a VRF draw is pending).
     * @custom:emits InspectionAssigned
     * @custom:emits DrawRequested
     */
    function requestInspection(uint256 tokenId) external returns (address inspector) {
        address owner = passport.ownerOf(tokenId);
        address custodian = passport.custodianOf(tokenId);
        bool regulator = registry.isAuthorized(msg.sender, Actions.REGULATE);
        if (msg.sender != owner && msg.sender != custodian && !regulator) {
            revert InspectionLib.InspectionRegistry__NotAllowedToRequest(tokenId, msg.sender);
        }
        if (!regulator && passport.getLot(tokenId).status == PassportLib.LotStatus.Rejected) {
            revert InspectionLib.InspectionRegistry__ReinspectionNeedsRegulator(tokenId);
        }
        InspectionLib.Assignment storage current = _assignments[tokenId];
        if (!current.closed && current.inspector != address(0) && block.timestamp <= current.dueBy) {
            revert InspectionLib.InspectionRegistry__AssignmentOpen(tokenId, current.dueBy);
        }
        // A completed round may draw the same inspector again; an expired one may not.
        address excluded = current.completed ? address(0) : current.inspector;
        inspector = _requestDraw(tokenId, excluded);
    }

    /**
     * @notice The assigned inspector declines a lot (e.g. a conflict of interest); the lot is reassigned at once.
     * @dev Only the inspector holding the open assignment.
     * @param tokenId The lot.
     * @param reasonHash Hash of the reason.
     * @return inspector The newly assigned inspector (zero while a VRF draw is pending).
     * @custom:emits InspectionDeclined
     * @custom:emits InspectionAssigned
     */
    function declineInspection(uint256 tokenId, bytes32 reasonHash) external returns (address inspector) {
        if (!isAssignmentOpen(tokenId, msg.sender)) {
            revert InspectionLib.InspectionRegistry__NotAssigned(tokenId, msg.sender);
        }
        emit InspectionLib.InspectionDeclined(tokenId, msg.sender, reasonHash);
        inspector = _requestDraw(tokenId, msg.sender);
    }

    /**
     * @inheritdoc IInspectionRegistry
     */
    function completeInspection(uint256 tokenId, address inspector) external {
        if (msg.sender != address(passport)) revert InspectionLib.InspectionRegistry__NotPassport(msg.sender);
        if (!isAssignmentOpen(tokenId, inspector)) {
            revert InspectionLib.InspectionRegistry__NotAssigned(tokenId, inspector);
        }
        InspectionLib.Assignment storage a = _assignments[tokenId];
        a.completed = true;
        emit InspectionLib.InspectionCompleted(tokenId, inspector, a.round);
        _closeCurrent(tokenId);
    }

    /**
     * @notice Receives verifiable randomness from the Chainlink VRF coordinator and makes the pending assignment.
     * @dev Only the configured coordinator. Never reverts on a missing inspector (VRF does not retry): the draw is
     * cleared and the lot can be requested again.
     * @param requestId VRF request id.
     * @param randomWords Random words (the first is used).
     * @custom:emits InspectionAssigned
     * @custom:emits DrawFailed
     */
    function rawFulfillRandomWords(uint256 requestId, uint256[] calldata randomWords) external {
        if (msg.sender != vrfConfig.coordinator) revert InspectionLib.InspectionRegistry__NotCoordinator(msg.sender);
        uint256 tokenId = _drawOf[requestId];
        InspectionLib.PendingDraw memory p = _pendingDraws[tokenId];
        delete _drawOf[requestId];
        if (p.requestId != requestId || requestId == 0) return; // superseded by a newer request
        delete _pendingDraws[tokenId];
        if (_assign(tokenId, randomWords[0], p.excluded, p.requestedBy) == address(0)) {
            emit InspectionLib.DrawFailed(tokenId, requestId);
        }
    }

    /*//////////////////////////////////////////////////////////////
                     USER-FACING READ-ONLY FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice The inspector last assigned to a lot.
     * @param tokenId The lot.
     * @return inspector The inspector (zero if never assigned); see {isAssignmentOpen} for whether it may inspect.
     */
    function assignedInspector(uint256 tokenId) external view returns (address inspector) {
        inspector = _assignments[tokenId].inspector;
    }

    /**
     * @inheritdoc IInspectionRegistry
     */
    function isAssignmentOpen(uint256 tokenId, address inspector) public view returns (bool) {
        InspectionLib.Assignment storage a = _assignments[tokenId];
        return inspector != address(0) && a.inspector == inspector && !a.closed && block.timestamp <= a.dueBy;
    }

    /**
     * @notice Returns the random draw of a lot still awaiting VRF fulfilment.
     * @param tokenId The lot.
     * @return The pending draw (zero request id if none).
     */
    function pendingDraw(uint256 tokenId) external view returns (InspectionLib.PendingDraw memory) {
        return _pendingDraws[tokenId];
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
     * @dev Starts a draw for a lot: requests VRF randomness when configured (the assignment follows on
     * fulfilment), otherwise draws at once with the `block.prevrandao` fallback and reverts if nobody is eligible.
     * @param tokenId The lot.
     * @param excluded Inspector that may not be drawn.
     * @return inspector The assigned inspector, or zero while a VRF draw is pending.
     */
    function _requestDraw(uint256 tokenId, address excluded) private returns (address inspector) {
        InspectionLib.PendingDraw storage pending = _pendingDraws[tokenId];
        if (pending.requestId != 0 && block.timestamp <= pending.requestedAt + DRAW_TIMEOUT) {
            revert InspectionLib.InspectionRegistry__DrawPending(tokenId);
        }
        InspectionLib.VrfConfig memory c = vrfConfig;
        if (c.coordinator == address(0)) {
            // slither-disable-next-line weak-prng (documented fallback; production uses Chainlink VRF)
            uint256 seed =
                uint256(keccak256(abi.encode(block.prevrandao, block.timestamp, tokenId, _assignments[tokenId].round)));
            inspector = _assign(tokenId, seed, excluded, msg.sender);
            if (inspector == address(0)) revert InspectionLib.InspectionRegistry__NoInspectorAvailable(tokenId);
            return inspector;
        }
        _closeCurrent(tokenId);
        uint256 requestId = IVRFCoordinatorV2Plus(c.coordinator)
            .requestRandomWords(
                VRFV2PlusClient.RandomWordsRequest({
                    keyHash: c.keyHash,
                    subId: c.subId,
                    requestConfirmations: c.confirmations,
                    callbackGasLimit: c.callbackGasLimit,
                    numWords: 1,
                    extraArgs: VRFV2PlusClient._argsToBytes(
                        VRFV2PlusClient.ExtraArgsV1({nativePayment: c.nativePayment})
                    )
                })
            );
        _pendingDraws[tokenId] = InspectionLib.PendingDraw({
            requestId: requestId, requestedBy: msg.sender, requestedAt: uint64(block.timestamp), excluded: excluded
        });
        _drawOf[requestId] = tokenId;
        emit InspectionLib.DrawRequested(tokenId, requestId, msg.sender);
    }

    /**
     * @dev Draws an eligible inspector (district pool first, then national), excluding `excluded`, and records the
     * assignment, moving the checkpoint right in {SupplyChain} from the previous inspector to the new one. Owner
     * and custodian are read at draw time, so a VRF fulfilment uses the lot's current parties.
     * @param tokenId The lot.
     * @param seed Randomness.
     * @param excluded Inspector that may not be drawn.
     * @param requestedBy Account that requested the inspection.
     * @return inspector The assigned inspector, or zero if nobody is eligible (nothing changes then).
     */
    function _assign(uint256 tokenId, uint256 seed, address excluded, address requestedBy)
        private
        returns (address inspector)
    {
        bytes32 ownerOrg = registry.participant(passport.ownerOf(tokenId)).orgId;
        bytes32 custodianOrg = registry.participant(passport.custodianOf(tokenId)).orgId;
        uint256 siteId = passport.siteOf(tokenId);
        bytes32 coverage =
            siteId == 0 ? InspectionLib.NATIONAL : InspectionLib.districtKey(sites.getSiteLocation(siteId).district);
        inspector = _draw(coverage, seed, excluded, ownerOrg, custodianOrg);
        if (inspector == address(0) && coverage != InspectionLib.NATIONAL) {
            coverage = InspectionLib.NATIONAL;
            inspector = _draw(coverage, seed, excluded, ownerOrg, custodianOrg);
        }
        if (inspector == address(0)) return address(0);

        _closeCurrent(tokenId);
        InspectionLib.Assignment storage a = _assignments[tokenId];
        _inspectors[inspector].activeAssignments += 1;
        uint64 dueBy = uint64(block.timestamp) + inspectionWindow;
        uint32 round = a.round + 1;
        a.inspector = inspector;
        a.requestedBy = requestedBy;
        a.assignedAt = uint64(block.timestamp);
        a.dueBy = dueBy;
        a.round = round;
        a.coverage = coverage;
        a.completed = false;
        a.closed = false;
        emit InspectionLib.InspectionAssigned(tokenId, inspector, requestedBy, coverage, dueBy, round);

        supplyChain.assignInspector(tokenId, inspector);
    }

    /**
     * @dev Ends the lot's current assignment if it is still open (declined or lapsed): frees the inspector's slot
     * and withdraws its checkpoint right in {SupplyChain}.
     * @param tokenId The lot.
     */
    function _closeCurrent(uint256 tokenId) private {
        InspectionLib.Assignment storage a = _assignments[tokenId];
        address previous = a.inspector;
        if (previous == address(0) || a.closed) return;
        a.closed = true;
        if (_inspectors[previous].activeAssignments != 0) _inspectors[previous].activeAssignments -= 1;
        supplyChain.unassignInspector(tokenId, previous);
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
        // slither-disable-next-line weak-prng (the seed is VRF output when configured)
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
