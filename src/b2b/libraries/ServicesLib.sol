// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {B2BLib} from "src/b2b/libraries/B2BLib.sol";

/**
 * @title ServicesLib
 * @author 0xEmmyb2
 * @notice Shared types, events and custom errors of {B2BServices}: recurring service agreements between
 * MineNet companies (haulage, storage, toll processing and refining, inspection and assay, audit, customs
 * clearing, and general services).
 * @dev Parties, sides, agreement statuses, disputes and the shared errors come from {B2BLib}.
 */
library ServicesLib {
    /*//////////////////////////////////////////////////////////////
                                  ENUMS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice What a service agreement is for, which decides how each job is verified and billed.
     * @dev Verified on-chain:
     * - `Haulage`: delivered {DeliveryManager} shipments carried by the provider for the client; per kg.
     * - `Storage`: the client's lots in the provider's custody at the end of each billing period; per kg.
     * - `TollProcessing` / `TollRefining`: the client's lots the provider consumed in `processLots`; per kg of
     *   input.
     * - `InspectionAssay` / `Audit`: `Inspection` / `Audit` checkpoints the provider signed on the client's lots;
     *   per checkpoint.
     * - `CustomsClearing`: `CustomsDeclared` checkpoints the provider signed on the client's lots that customs
     *   has since released; per lot.
     * Claimed with evidence (accepted or disputed by the client): `EquipmentRental`, `Maintenance`, `Security`,
     * `Consulting`, `Labour`, `Other`; per unit agreed in the contract (day, hour, shift...).
     */
    enum ServiceKind {
        Haulage,
        Storage,
        TollProcessing,
        TollRefining,
        InspectionAssay,
        Audit,
        CustomsClearing,
        EquipmentRental,
        Maintenance,
        Security,
        Consulting,
        Labour,
        Other
    }

    /**
     * @notice Lifecycle status of one scheduled job (or billing period).
     * @dev `Scheduled`: not funded (the default). `Funded`: budget escrowed. `Claimed`: the provider billed its
     * work; the client reviews it. `Accepted`: paid. `Disputed`: the client rejected the claim. `Settled`: a
     * dispute was closed. `Missed`: the provider did not perform. `Defaulted`: the client did not fund it by its
     * due date. `Cancelled`: dropped by termination. The last five are final, with `Accepted`.
     */
    enum JobStatus {
        Scheduled,
        Funded,
        Claimed,
        Accepted,
        Disputed,
        Settled,
        Missed,
        Defaulted,
        Cancelled
    }

    /*//////////////////////////////////////////////////////////////
                                 STRUCTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice The service schedule and its commercial terms.
     * @param kind What the service is.
     * @param provider Which side performs the service; the other side is the client and pays.
     * @param ratePerUnit Price per unit: per kg for weight-based kinds, per checkpoint or lot for count-based
     * kinds, per agreed unit for claimed kinds (payment-token units, or off-chain currency units).
     * @param maxUnitsPerJob Budget of one job, in units (grams for weight-based kinds); billing is capped at it.
     * @param totalJobs Number of jobs or billing periods.
     * @param jobInterval Time between two consecutive due dates, in seconds.
     * @param firstJobOffset Time from activation to the first due date, in seconds.
     */
    struct ServiceTerms {
        ServiceKind kind;
        B2BLib.Side provider;
        uint256 ratePerUnit;
        uint128 maxUnitsPerJob;
        uint32 totalJobs;
        uint32 jobInterval;
        uint32 firstJobOffset;
    }

    /**
     * @notice Job counters of an agreement.
     * @param accepted Jobs accepted and paid.
     * @param settled Jobs closed through a dispute settlement.
     * @param missed Jobs the provider did not perform.
     * @param defaulted Jobs the client did not fund.
     * @param cancelled Jobs dropped by termination.
     * @param funded Jobs currently funded but not claimed.
     * @param inFlight Jobs currently claimed or disputed.
     * @param unitsBilled Units of all accepted and settled jobs.
     */
    struct Progress {
        uint32 accepted;
        uint32 settled;
        uint32 missed;
        uint32 defaulted;
        uint32 cancelled;
        uint32 funded;
        uint32 inFlight;
        uint256 unitsBilled;
    }

    /**
     * @notice A recurring service agreement between two companies.
     * @param status Current status.
     * @param version Bumped on every amendment; signatures are per version.
     * @param proposerSigned Whether the proposer signed the current version.
     * @param counterpartySigned Whether the counterparty signed the current version.
     * @param terminationRequested Whether a mutual termination is pending.
     * @param terminationRequestedBy Side that requested it.
     * @param reviewPeriod Time the client has to accept or dispute a claim.
     * @param maxMissed Missed (or defaulted) jobs after which the other side may terminate for cause (0 = never).
     * @param proposalExpiresAt Deadline for signatures.
     * @param activatedAt When the agreement became Active (0 = not yet); the schedule and billable work start.
     * @param proposer The company that proposed the agreement.
     * @param counterparty The company it was proposed to.
     * @param service The service schedule and commercial terms.
     * @param arbiter Optional neutral arbiter both sides agreed on (zero = none).
     * @param paymentToken Settlement token held in escrow, or zero when payment happens off-chain.
     * @param progress Job counters.
     * @param termsHash Hash of the full contract document held off-chain.
     */
    struct Agreement {
        B2BLib.AgreementStatus status;
        uint32 version;
        bool proposerSigned;
        bool counterpartySigned;
        bool terminationRequested;
        B2BLib.Side terminationRequestedBy;
        uint32 reviewPeriod;
        uint16 maxMissed;
        uint64 proposalExpiresAt;
        uint64 activatedAt;
        B2BLib.Party proposer;
        B2BLib.Party counterparty;
        ServiceTerms service;
        address arbiter;
        IERC20 paymentToken;
        Progress progress;
        bytes32 termsHash;
    }

    /**
     * @notice The negotiable terms of a service agreement, supplied in a proposal or amendment.
     * @param service The service schedule and commercial terms.
     * @param arbiter Optional neutral arbiter (zero = none); must not belong to either party.
     * @param paymentToken Settlement token to escrow payments in, or zero for off-chain payment.
     * @param reviewPeriod Time the client has to review a claim.
     * @param maxMissed Missed jobs allowing termination for cause (0 = never).
     * @param proposalExpiresAt Deadline for signatures.
     * @param termsHash Hash of the full contract document; non-zero.
     */
    struct Terms {
        ServiceTerms service;
        address arbiter;
        IERC20 paymentToken;
        uint32 reviewPeriod;
        uint16 maxMissed;
        uint64 proposalExpiresAt;
        bytes32 termsHash;
    }

    /**
     * @notice State of one scheduled job. Jobs are stored lazily: an untouched job is `Scheduled`.
     * @param status Current status.
     * @param claimedAt When the provider billed it.
     * @param units Units billed (capped at the job budget).
     * @param amount Amount billed for those units.
     * @param funded Budget held in escrow.
     * @param evidenceHash Hash of the provider's evidence (job card, timesheet, report...).
     */
    struct Job {
        JobStatus status;
        uint64 claimedAt;
        uint128 units;
        uint256 amount;
        uint256 funded;
        bytes32 evidenceHash;
    }

    /**
     * @notice A provider's track record across all its service agreements.
     * @param jobsCompleted Jobs accepted or settled.
     * @param jobsMissed Jobs it did not perform.
     * @param fundingDefaults Jobs it failed to fund as a client.
     * @param disputesLost Disputes settled with less than the billed amount paid to it.
     * @param unitsDelivered Units of all its completed jobs.
     */
    struct Performance {
        uint32 jobsCompleted;
        uint32 jobsMissed;
        uint32 fundingDefaults;
        uint32 disputesLost;
        uint256 unitsDelivered;
    }

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Emitted when a company proposes a service agreement to another company.
     * @param agreementId New agreement id.
     * @param proposerOrg Proposing company.
     * @param counterpartyOrg Company it is proposed to.
     * @param service The service schedule and commercial terms.
     * @param termsHash Hash of the contract document.
     */
    event ServiceProposed(
        uint256 indexed agreementId,
        bytes32 indexed proposerOrg,
        bytes32 indexed counterpartyOrg,
        ServiceTerms service,
        bytes32 termsHash
    );

    /**
     * @notice Emitted when either side amends a proposal (a counter-offer).
     * @param agreementId Agreement id.
     * @param version New version.
     * @param by Amending account.
     * @param service The amended service terms.
     * @param termsHash Hash of the amended contract document.
     */
    event ServiceAmended(
        uint256 indexed agreementId, uint32 version, address indexed by, ServiceTerms service, bytes32 termsHash
    );

    /**
     * @notice Emitted when the agreement becomes Active.
     * @param agreementId Agreement id.
     * @param version Version in force.
     * @param firstDueAt Due date of the first job.
     * @param lastDueAt Due date of the last job.
     */
    event ServiceActivated(uint256 indexed agreementId, uint32 version, uint64 firstDueAt, uint64 lastDueAt);

    /**
     * @notice Emitted when the client funds a job into escrow.
     * @param agreementId Agreement id.
     * @param index Job index (0-based).
     * @param amount Budget escrowed.
     */
    event JobFunded(uint256 indexed agreementId, uint256 indexed index, uint256 amount);

    /**
     * @notice Emitted when the provider bills a job.
     * @param agreementId Agreement id.
     * @param index Job index.
     * @param refs On-chain work referenced (shipment ids, lot ids...), empty for claimed kinds.
     * @param units Units billed.
     * @param amount Amount billed.
     * @param evidenceHash Hash of the provider's evidence.
     */
    event JobClaimed(
        uint256 indexed agreementId,
        uint256 indexed index,
        uint256[] refs,
        uint128 units,
        uint256 amount,
        bytes32 evidenceHash
    );

    /**
     * @notice Emitted when a claim is accepted and paid.
     * @param agreementId Agreement id.
     * @param index Job index.
     * @param amount Amount paid to the provider.
     * @param refund Unused budget refunded to the client.
     * @param automatic True if released after the review period.
     */
    event JobAccepted(
        uint256 indexed agreementId, uint256 indexed index, uint256 amount, uint256 refund, bool automatic
    );

    /**
     * @notice Emitted when the client disputes a claim.
     * @param agreementId Agreement id.
     * @param index Job index.
     * @param reasonHash Hash of the reasons.
     */
    event JobDisputed(uint256 indexed agreementId, uint256 indexed index, bytes32 reasonHash);

    /**
     * @notice Emitted when a disputed job is settled.
     * @param agreementId Agreement id.
     * @param index Job index.
     * @param amount Amount paid to the provider.
     * @param refund Amount refunded to the client.
     * @param arbiter The arbiter who decided, or zero when the parties agreed.
     * @param awardHash Hash of the arbitral award (zero when the parties agreed).
     */
    event JobSettled(
        uint256 indexed agreementId,
        uint256 indexed index,
        uint256 amount,
        uint256 refund,
        address arbiter,
        bytes32 awardHash
    );

    /**
     * @notice Emitted when a job ends without being performed.
     * @param agreementId Agreement id.
     * @param index Job index.
     * @param status `Missed`, `Defaulted` or `Cancelled`.
     * @param refund Amount refunded to the client.
     */
    event JobClosed(uint256 indexed agreementId, uint256 indexed index, JobStatus status, uint256 refund);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice `account` lacks the permission the service kind requires of its provider (e.g. `CARRY` for
     * haulage).
     * @param account The account.
     */
    error B2BServices__ProviderNotQualified(address account);

    /**
     * @notice The service schedule is invalid (rate, budget, count or timing out of range).
     */
    error B2BServices__InvalidSchedule();

    /**
     * @notice Job `index` is in `status`, which does not allow the operation.
     * @param index Job index.
     * @param status Its current status.
     */
    error B2BServices__InvalidJobStatus(uint256 index, JobStatus status);

    /**
     * @notice The claim's references do not prove billable work (wrong provider or client, not completed,
     * before activation, already billed, or malformed).
     * @param ref The offending reference.
     */
    error B2BServices__InvalidWork(uint256 ref);

    /**
     * @notice The claim bills nothing.
     */
    error B2BServices__NothingToBill();

    /*//////////////////////////////////////////////////////////////
                                 HELPERS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Whether a kind is billed per kilogram (units are grams).
     * @param kind Service kind.
     * @return True for haulage, storage, toll processing and toll refining.
     */
    function isWeightBased(ServiceKind kind) internal pure returns (bool) {
        return uint8(kind) <= uint8(ServiceKind.TollRefining);
    }

    /**
     * @notice Whether a kind is billed on units claimed with evidence rather than verified on-chain.
     * @param kind Service kind.
     * @return True for equipment rental, maintenance, security, consulting, labour and other.
     */
    function isClaimed(ServiceKind kind) internal pure returns (bool) {
        return uint8(kind) >= uint8(ServiceKind.EquipmentRental);
    }

    /**
     * @notice The price of a number of units.
     * @param kind Service kind (weight-based kinds price grams per kilogram).
     * @param units Units.
     * @param ratePerUnit Price per unit (per kg for weight-based kinds).
     * @return The price, rounded down.
     */
    function priceOf(ServiceKind kind, uint256 units, uint256 ratePerUnit) internal pure returns (uint256) {
        return isWeightBased(kind) ? (units * ratePerUnit) / B2BLib.GRAMS_PER_KG : units * ratePerUnit;
    }
}
