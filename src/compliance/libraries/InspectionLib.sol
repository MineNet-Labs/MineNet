// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

/**
 * @title InspectionLib
 * @author 0xEmmyb2
 * @notice Shared types, events and custom errors of {InspectionRegistry}.
 */
library InspectionLib {
    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Coverage key of the national pool: inspectors deployed nationwide, used when no inspector covering
     * the lot's district is eligible, and for derived lots (no mine site).
     */
    bytes32 internal constant NATIONAL = keccak256("NATIONAL");

    /*//////////////////////////////////////////////////////////////
                                  ENUMS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Kind of body that employs inspectors.
     * @dev `StateInspectorate`: a public inspectorate (e.g. the Rwanda Mines, Petroleum and Gas Board, whose
     * inspectors are civil servants under Law n° 072/2024). `TraceabilityOperator`: a traceability programme whose
     * field agents monitor pits and tag minerals (e.g. ITSCI, RCS Global Better Mining). `None` = not approved.
     */
    enum InspectorateKind {
        None,
        StateInspectorate,
        TraceabilityOperator
    }

    /*//////////////////////////////////////////////////////////////
                                 STRUCTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice An inspector on the roster.
     * @param enrolled Whether the inspector is on the roster.
     * @param available Whether the inspector currently takes new assignments (leave, workload...).
     * @param inspectorateOrg The inspectorate body that employs the inspector.
     * @param activeAssignments Assignments currently open with the inspector.
     */
    struct Inspector {
        bool enrolled;
        bool available;
        bytes32 inspectorateOrg;
        uint32 activeAssignments;
    }

    /**
     * @notice The current inspection assignment of a lot.
     * @param inspector Assigned inspector (zero = never assigned).
     * @param requestedBy Account that requested the inspection.
     * @param assignedAt When the inspector was assigned.
     * @param dueBy Deadline for the inspection; after it the lot can be reassigned.
     * @param round Number of assignments made for the lot so far.
     * @param coverage Coverage key the inspector was drawn from (a district key or {NATIONAL}).
     * @param completed Whether the inspector submitted its result.
     * @param closed Whether the assignment is closed (result submitted, declined, or replaced after its window).
     */
    struct Assignment {
        address inspector;
        address requestedBy;
        uint64 assignedAt;
        uint64 dueBy;
        uint32 round;
        bytes32 coverage;
        bool completed;
        bool closed;
    }

    /**
     * @notice A random draw requested from Chainlink VRF and not yet fulfilled.
     * @param requestId VRF request id (zero = none).
     * @param requestedBy Account that requested the inspection.
     * @param requestedAt When the draw was requested.
     * @param excluded Inspector that may not be drawn (the one that declined or let its window lapse).
     */
    struct PendingDraw {
        uint256 requestId;
        address requestedBy;
        uint64 requestedAt;
        address excluded;
    }

    /**
     * @notice Chainlink VRF v2.5 settings. A zero coordinator means the on-chain fallback (`block.prevrandao`).
     * @param coordinator VRF coordinator.
     * @param keyHash Gas lane key hash.
     * @param subId Funded VRF subscription id.
     * @param confirmations Block confirmations before fulfilment.
     * @param callbackGasLimit Gas for the fulfilment callback.
     * @param nativePayment Whether the subscription pays in the native token rather than LINK.
     */
    struct VrfConfig {
        address coordinator;
        bytes32 keyHash;
        uint256 subId;
        uint16 confirmations;
        uint32 callbackGasLimit;
        bool nativePayment;
    }

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Emitted when an inspectorate body is approved, changed or removed.
     * @param orgId The inspectorate body.
     * @param kind Its kind (`None` = removed).
     * @param by Approving regulator.
     */
    event InspectorateSet(bytes32 indexed orgId, InspectorateKind kind, address indexed by);

    /**
     * @notice Emitted when an inspector is enrolled on the roster or redeployed.
     * @param inspector The inspector.
     * @param inspectorateOrg Its inspectorate body.
     * @param coverage District keys (and/or {NATIONAL}) the inspector is deployed to.
     * @param by Enrolling regulator.
     */
    event InspectorDeployed(
        address indexed inspector, bytes32 indexed inspectorateOrg, bytes32[] coverage, address indexed by
    );

    /**
     * @notice Emitted when an inspector is removed from the roster.
     * @param inspector The inspector.
     * @param by Removing regulator.
     * @param reasonHash Hash of the reason.
     */
    event InspectorRemoved(address indexed inspector, address indexed by, bytes32 reasonHash);

    /**
     * @notice Emitted when an inspector changes availability.
     * @param inspector The inspector.
     * @param available Whether it takes new assignments.
     */
    event AvailabilitySet(address indexed inspector, bool available);

    /**
     * @notice Emitted when the platform assigns an inspector to a lot.
     * @param tokenId The lot.
     * @param inspector Assigned inspector.
     * @param requestedBy Requesting account.
     * @param coverage Coverage key the inspector was drawn from.
     * @param dueBy Inspection deadline.
     * @param round Assignment round for the lot.
     */
    event InspectionAssigned(
        uint256 indexed tokenId,
        address indexed inspector,
        address indexed requestedBy,
        bytes32 coverage,
        uint64 dueBy,
        uint32 round
    );

    /**
     * @notice Emitted when an inspector declines an assignment (conflict of interest, unavailability).
     * @param tokenId The lot.
     * @param inspector Declining inspector.
     * @param reasonHash Hash of the reason.
     */
    event InspectionDeclined(uint256 indexed tokenId, address indexed inspector, bytes32 reasonHash);

    /**
     * @notice Emitted when an inspector submits its result, closing the assignment.
     * @param tokenId The lot.
     * @param inspector The inspector.
     * @param round Assignment round.
     */
    event InspectionCompleted(uint256 indexed tokenId, address indexed inspector, uint32 round);

    /**
     * @notice Emitted when a random draw is requested from Chainlink VRF.
     * @param tokenId The lot.
     * @param requestId VRF request id.
     * @param requestedBy Requesting account.
     */
    event DrawRequested(uint256 indexed tokenId, uint256 indexed requestId, address indexed requestedBy);

    /**
     * @notice Emitted when a VRF draw found no eligible inspector; the lot can be requested again.
     * @param tokenId The lot.
     * @param requestId VRF request id.
     */
    event DrawFailed(uint256 indexed tokenId, uint256 indexed requestId);

    /**
     * @notice Emitted when the registry admin sets the Chainlink VRF settings.
     * @param coordinator VRF coordinator (zero = on-chain fallback).
     * @param keyHash Gas lane key hash.
     * @param subId Subscription id.
     */
    event VrfConfigSet(address indexed coordinator, bytes32 keyHash, uint256 subId);

    /**
     * @notice Emitted when the regulator sets the inspection deadline.
     * @param inspectionWindow Time an assigned inspector has to inspect, in seconds.
     */
    event InspectionWindowSet(uint32 inspectionWindow);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice `account` is not a regulator of the institution that licenses inspectors.
     * @param account The account.
     */
    error InspectionRegistry__NotInspectorAuthority(address account);

    /**
     * @notice Organisation `orgId` is not an approved inspectorate body.
     * @param orgId The organisation.
     */
    error InspectionRegistry__NotInspectorate(bytes32 orgId);

    /**
     * @notice `account` cannot be enrolled: not an authorised inspector, or not employed by an approved
     * inspectorate.
     * @param account The account.
     */
    error InspectionRegistry__InvalidInspector(address account);

    /**
     * @notice `account` is not on the roster.
     * @param account The account.
     */
    error InspectionRegistry__NotEnrolled(address account);

    /**
     * @notice The coverage list is empty, too long, or contains a zero key.
     */
    error InspectionRegistry__InvalidCoverage();

    /**
     * @notice `account` may not request an inspection of lot `tokenId` (not its owner, custodian or a regulator).
     * @param tokenId The lot.
     * @param account The account.
     */
    error InspectionRegistry__NotAllowedToRequest(uint256 tokenId, address account);

    /**
     * @notice Lot `tokenId` already has an inspector assigned until `dueBy`.
     * @param tokenId The lot.
     * @param dueBy Deadline of the current assignment.
     */
    error InspectionRegistry__AssignmentOpen(uint256 tokenId, uint64 dueBy);

    /**
     * @notice No available, independent inspector covers lot `tokenId`'s district or the national pool.
     * @param tokenId The lot.
     */
    error InspectionRegistry__NoInspectorAvailable(uint256 tokenId);

    /**
     * @notice `account` is not the inspector currently assigned to lot `tokenId`.
     * @param tokenId The lot.
     * @param account The account.
     */
    error InspectionRegistry__NotAssigned(uint256 tokenId, address account);

    /**
     * @notice The inspection window is outside the allowed range.
     */
    error InspectionRegistry__InvalidWindow();

    /**
     * @notice Lot `tokenId` failed inspection: only a regulator may order a re-inspection.
     * @param tokenId The lot.
     */
    error InspectionRegistry__ReinspectionNeedsRegulator(uint256 tokenId);

    /**
     * @notice A random draw for lot `tokenId` is still awaiting Chainlink VRF.
     * @param tokenId The lot.
     */
    error InspectionRegistry__DrawPending(uint256 tokenId);

    /**
     * @notice `account` is not the lot passport (only it reports completed inspections).
     * @param account The account.
     */
    error InspectionRegistry__NotPassport(address account);

    /**
     * @notice `account` is not the configured VRF coordinator.
     * @param account The account.
     */
    error InspectionRegistry__NotCoordinator(address account);

    /**
     * @notice `account` is not a registry admin.
     * @param account The account.
     */
    error InspectionRegistry__NotRegistryAdmin(address account);

    /**
     * @notice The VRF settings are incomplete.
     */
    error InspectionRegistry__InvalidVrfConfig();

    /*//////////////////////////////////////////////////////////////
                                 HELPERS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice The coverage key of a district name, as recorded in a mine site's location.
     * @dev Names are hashed exactly as written; use the official district name (e.g. "Rutsiro").
     * @param district District name.
     * @return The coverage key.
     */
    function districtKey(string memory district) internal pure returns (bytes32) {
        return keccak256(bytes(district));
    }
}
