// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title B2BLib
 * @author 0xEmmyb2
 * @notice Shared types, events, custom errors and pricing maths of {B2B}.
 */
library B2BLib {
    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice 100%, in basis points.
     */
    uint16 internal constant BPS = 10_000;

    /**
     * @notice Time after the negotiation period within which the agreed arbiter must rule; after it (or at once when
     * no arbiter was agreed), the platform (registry admin) decides the dispute so escrowed funds never stay locked.
     */
    uint64 internal constant ARBITRATION_PERIOD = 30 days;

    /**
     * @notice Grams per kilogram: quantities are in grams, prices per kilogram.
     */
    uint256 internal constant GRAMS_PER_KG = 1_000;

    /*//////////////////////////////////////////////////////////////
                                  ENUMS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Lifecycle status of an agreement.
     * @dev `Proposed`: being negotiated; both parties must sign, and a named transporter accept, the same
     * version. `Active`: the delivery schedule runs. `Completed`: every delivery is resolved. `Terminated`:
     * ended early by mutual consent or for cause. `Rejected`: declined by the counterparty or the named
     * transporter. `Withdrawn`: withdrawn by the proposer.
     */
    enum AgreementStatus {
        None,
        Proposed,
        Active,
        Completed,
        Terminated,
        Rejected,
        Withdrawn
    }

    /**
     * @notice One of the two companies in an agreement.
     */
    enum Side {
        Proposer,
        Counterparty
    }

    /**
     * @notice Lifecycle status of one scheduled delivery.
     * @dev `Scheduled`: not funded yet (the default of every delivery). `Funded`: payment escrowed.
     * `Dispatched`: lots committed and on their way. `Arrived`: the buyer holds custody; the review period
     * runs. `Accepted`: paid and title transferred. `Disputed`: the buyer rejected an arrived delivery.
     * `Settled`: a dispute was closed. `Rejected`: refused because a lot was flagged before arrival.
     * `Missed`: the seller did not deliver. `Defaulted`: the buyer did not fund it by its due date.
     * `Cancelled`: dropped by termination. The last six are final.
     */
    enum DeliveryStatus {
        Scheduled,
        Funded,
        Dispatched,
        Arrived,
        Accepted,
        Disputed,
        Settled,
        Rejected,
        Missed,
        Defaulted,
        Cancelled
    }

    /*//////////////////////////////////////////////////////////////
                                 STRUCTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice A company that is party to an agreement.
     * @param orgId Organisation id in {MineNetRegistry}.
     * @param account Account of record: the company account that last proposed, amended or signed for it.
     * Payments and refunds for this side are credited to it, and lots are transferred to it.
     */
    struct Party {
        bytes32 orgId;
        address account;
    }

    /**
     * @notice The recurring supply schedule and its commercial terms.
     * @param mineralType Mineral supplied, e.g. `keccak256("CASSITERITE")`; every lot must match.
     * @param quantityPerDelivery Quantity of each delivery, in grams.
     * @param quantityToleranceBps Accepted deviation of a delivery's weight from its quantity (e.g. 200 = +/-2%).
     * @param minGradeBps Minimum attested grade of every lot, in basis points (0 = no grade requirement).
     * @param pricePerKg Price per kilogram, in payment-token units (or `currency` units when paid off-chain).
     * @param totalDeliveries Number of deliveries.
     * @param deliveryInterval Time between two consecutive due dates, in seconds.
     * @param firstDeliveryOffset Time from activation to the first due date, in seconds.
     */
    struct SupplyTerms {
        bytes32 mineralType;
        uint128 quantityPerDelivery;
        uint16 quantityToleranceBps;
        uint16 minGradeBps;
        uint256 pricePerKg;
        uint32 totalDeliveries;
        uint32 deliveryInterval;
        uint32 firstDeliveryOffset;
    }

    /**
     * @notice The transport leg of an agreement: a named transporter paid per delivery.
     * @param transporter Transporter account (zero = no named transporter).
     * @param distanceKm Agreed haulage distance, in kilometres.
     * @param feePerKm Fee per kilometre, in payment-token units.
     */
    struct TransportTerms {
        address transporter;
        uint32 distanceKm;
        uint256 feePerKm;
    }

    /**
     * @notice Delivery counters of an agreement.
     * @param accepted Deliveries accepted and paid in full.
     * @param settled Deliveries closed through a dispute settlement.
     * @param rejected Deliveries refused because a lot was flagged.
     * @param missed Deliveries the seller did not make.
     * @param defaulted Deliveries the buyer did not fund.
     * @param cancelled Deliveries dropped by termination.
     * @param onTime Deliveries that arrived by their due date.
     * @param funded Deliveries currently funded but not dispatched.
     * @param inFlight Deliveries currently dispatched, arrived or disputed.
     * @param gramsDelivered Trusted weight of all accepted and settled deliveries, in grams.
     */
    struct Progress {
        uint32 accepted;
        uint32 settled;
        uint32 rejected;
        uint32 missed;
        uint32 defaulted;
        uint32 cancelled;
        uint32 onTime;
        uint32 funded;
        uint32 inFlight;
        uint256 gramsDelivered;
    }

    /**
     * @notice A recurring mineral supply agreement between two companies.
     * @param status Current status.
     * @param seller Which side supplies the mineral; the other side buys and pays.
     * @param version Bumped on every amendment; signatures and the transporter's acceptance are per version.
     * @param proposerSigned Whether the proposer signed the current version.
     * @param counterpartySigned Whether the counterparty signed the current version.
     * @param transporterAccepted Whether the named transporter accepted the current version.
     * @param terminationRequested Whether a mutual termination is pending.
     * @param terminationRequestedBy Side that requested it.
     * @param reviewPeriod Time the buyer has to accept or reject an arrived delivery.
     * @param maxMissed Missed (or defaulted) deliveries after which the other side may terminate for cause
     * (0 = never).
     * @param proposalExpiresAt Deadline for the signatures and the transporter's acceptance.
     * @param activatedAt When the agreement became Active (0 = not yet); the schedule starts from it.
     * @param proposer The company that proposed the agreement.
     * @param counterparty The company it was proposed to.
     * @param supply The supply schedule and commercial terms.
     * @param transport The transport leg.
     * @param inspectionRequired Whether automatic payment waits for an inspection of every lot at destination by an
     * inspector the platform assigned ({InspectionRegistry}); the parties never choose the inspector.
     * @param arbiter Optional neutral arbiter both sides agreed on (zero = none).
     * @param paymentToken Settlement token held in escrow, or zero when payment happens off-chain.
     * @param progress Delivery counters.
     * @param termsHash Hash of the full contract document held off-chain.
     */
    struct Agreement {
        AgreementStatus status;
        Side seller;
        uint32 version;
        bool proposerSigned;
        bool counterpartySigned;
        bool transporterAccepted;
        bool terminationRequested;
        Side terminationRequestedBy;
        uint32 reviewPeriod;
        uint16 maxMissed;
        uint64 proposalExpiresAt;
        uint64 activatedAt;
        Party proposer;
        Party counterparty;
        SupplyTerms supply;
        TransportTerms transport;
        bool inspectionRequired;
        address arbiter;
        IERC20 paymentToken;
        Progress progress;
        bytes32 termsHash;
    }

    /**
     * @notice The negotiable terms of an agreement, supplied in a proposal or amendment.
     * @param seller Which side supplies the mineral.
     * @param supply The supply schedule and commercial terms.
     * @param transport The transport leg (zero transporter = none).
     * @param inspectionRequired Whether automatic payment waits for a platform-assigned inspection at destination.
     * @param arbiter Optional neutral arbiter (zero = none); must not belong to either party.
     * @param paymentToken Settlement token to escrow payments in, or zero for off-chain payment.
     * @param reviewPeriod Time the buyer has to review an arrived delivery.
     * @param maxMissed Missed deliveries allowing termination for cause (0 = never).
     * @param proposalExpiresAt Deadline for signatures.
     * @param termsHash Hash of the full contract document; non-zero.
     */
    struct Terms {
        Side seller;
        SupplyTerms supply;
        TransportTerms transport;
        bool inspectionRequired;
        address arbiter;
        IERC20 paymentToken;
        uint32 reviewPeriod;
        uint16 maxMissed;
        uint64 proposalExpiresAt;
        bytes32 termsHash;
    }

    /**
     * @notice State of one scheduled delivery. Deliveries are stored lazily: an untouched delivery is
     * `Scheduled` with the agreement's default quantity, price and due date.
     * @param status Current status.
     * @param adjusted Whether quantity, price and due date were changed by a confirmed adjustment.
     * @param onTime Whether it arrived by its due date.
     * @param dueAt Due date (meaningful when `adjusted`; see {B2B-getDelivery} for the effective value).
     * @param dispatchedAt When the seller committed lots to it.
     * @param arrivedAt When the buyer's custody of every lot was confirmed.
     * @param quantity Quantity in grams (meaningful when `adjusted`).
     * @param deliveredQty Trusted weight of the dispatched lots, in grams.
     * @param pricePerKg Price per kilogram (meaningful when `adjusted`).
     * @param goodsFunded Goods payment held in escrow (covers the upper quantity tolerance).
     * @param feeFunded Transport fee held in escrow.
     * @param shipmentId {DeliveryManager} shipment carrying the lots (0 = direct custody handover).
     * @param evidenceHash Hash of the dispatch documents (delivery note, assay, export papers...).
     */
    struct Delivery {
        DeliveryStatus status;
        bool adjusted;
        bool onTime;
        uint64 dueAt;
        uint64 dispatchedAt;
        uint64 arrivedAt;
        uint128 quantity;
        uint128 deliveredQty;
        uint256 pricePerKg;
        uint256 goodsFunded;
        uint256 feeFunded;
        uint256 shipmentId;
        bytes32 evidenceHash;
    }

    /**
     * @notice A pending one-off change to one scheduled delivery, awaiting the other side's confirmation.
     * @param pending Whether an adjustment is pending.
     * @param by Side that requested it.
     * @param dueAt New due date.
     * @param quantity New quantity, in grams.
     * @param pricePerKg New price per kilogram.
     */
    struct Adjustment {
        bool pending;
        Side by;
        uint64 dueAt;
        uint128 quantity;
        uint256 pricePerKg;
    }

    /**
     * @notice A dispute over a rejected delivery.
     * @param openedAt When the buyer rejected the delivery.
     * @param payerOffered Whether the buyer has made a settlement offer.
     * @param payeeOffered Whether the seller has made a settlement offer.
     * @param payerOffer Amount the buyer offers to pay for the goods.
     * @param payeeOffer Amount the seller asks for the goods.
     * @param reasonHash Hash of the buyer's reasons.
     */
    struct DeliveryDispute {
        uint64 openedAt;
        bool payerOffered;
        bool payeeOffered;
        uint256 payerOffer;
        uint256 payeeOffer;
        bytes32 reasonHash;
    }

    /**
     * @notice A company's track record across all its B2B agreements, for counterparties and investors.
     * @param deliveriesMade Deliveries it made as seller that were accepted or settled.
     * @param onTimeDeliveries Of those, deliveries that arrived by their due date.
     * @param deliveriesMissed Deliveries it missed as seller.
     * @param deliveriesRejected Deliveries refused because one of its lots was flagged.
     * @param fundingDefaults Deliveries it failed to fund as buyer.
     * @param disputesLost Disputes settled with less than the full price paid to it as seller.
     * @param gramsSupplied Trusted weight it supplied, in grams.
     */
    struct Performance {
        uint32 deliveriesMade;
        uint32 onTimeDeliveries;
        uint32 deliveriesMissed;
        uint32 deliveriesRejected;
        uint32 fundingDefaults;
        uint32 disputesLost;
        uint256 gramsSupplied;
    }

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Emitted when a company proposes a supply agreement to another company.
     * @param agreementId New agreement id.
     * @param proposerOrg Proposing company.
     * @param counterpartyOrg Company it is proposed to.
     * @param seller Which side supplies.
     * @param supply The supply schedule and commercial terms.
     * @param termsHash Hash of the contract document.
     */
    event AgreementProposed(
        uint256 indexed agreementId,
        bytes32 indexed proposerOrg,
        bytes32 indexed counterpartyOrg,
        Side seller,
        SupplyTerms supply,
        bytes32 termsHash
    );

    /**
     * @notice Emitted when either side amends a proposal (a counter-offer).
     * @param agreementId Agreement id.
     * @param version New version.
     * @param by Amending account.
     * @param supply The amended supply schedule and commercial terms.
     * @param termsHash Hash of the amended contract document.
     */
    event AgreementAmended(
        uint256 indexed agreementId, uint32 version, address indexed by, SupplyTerms supply, bytes32 termsHash
    );

    /**
     * @notice Emitted when a party signs a version of the agreement.
     * @param agreementId Agreement id.
     * @param version Version signed.
     * @param side Signing side.
     * @param signer Signing account.
     */
    event AgreementSigned(uint256 indexed agreementId, uint32 version, Side side, address indexed signer);

    /**
     * @notice Emitted when the named transporter accepts a version of the agreement.
     * @param agreementId Agreement id.
     * @param version Version accepted.
     * @param transporter Transporter account.
     */
    event TransporterAccepted(uint256 indexed agreementId, uint32 version, address indexed transporter);

    /**
     * @notice Emitted when the agreement becomes Active and its delivery schedule starts.
     * @param agreementId Agreement id.
     * @param version Version in force.
     * @param firstDueAt Due date of the first delivery.
     * @param lastDueAt Due date of the last delivery.
     */
    event AgreementActivated(uint256 indexed agreementId, uint32 version, uint64 firstDueAt, uint64 lastDueAt);

    /**
     * @notice Emitted when a proposal is withdrawn, or rejected by the counterparty or the transporter.
     * @param agreementId Agreement id.
     * @param status `Withdrawn` or `Rejected`.
     * @param by Declining account.
     * @param reasonHash Hash of the reason.
     */
    event AgreementDeclined(
        uint256 indexed agreementId, AgreementStatus status, address indexed by, bytes32 reasonHash
    );

    /**
     * @notice Emitted when the buyer funds a delivery into escrow.
     * @param agreementId Agreement id.
     * @param index Delivery index (0-based).
     * @param goodsAmount Goods payment escrowed (covering the upper quantity tolerance).
     * @param transportFee Transport fee escrowed.
     */
    event DeliveryFunded(uint256 indexed agreementId, uint256 indexed index, uint256 goodsAmount, uint256 transportFee);

    /**
     * @notice Emitted when the seller commits lots to a delivery.
     * @param agreementId Agreement id.
     * @param index Delivery index.
     * @param tokenIds Lot passports filling it.
     * @param deliveredQty Their total trusted weight, in grams.
     * @param shipmentId {DeliveryManager} shipment carrying them (0 = direct handover).
     * @param evidenceHash Hash of the dispatch documents.
     */
    event DeliveryDispatched(
        uint256 indexed agreementId,
        uint256 indexed index,
        uint256[] tokenIds,
        uint128 deliveredQty,
        uint256 shipmentId,
        bytes32 evidenceHash
    );

    /**
     * @notice Emitted when the buyer's custody of every lot of a delivery is confirmed.
     * @param agreementId Agreement id.
     * @param index Delivery index.
     * @param onTime Whether it arrived by its due date.
     */
    event DeliveryArrived(uint256 indexed agreementId, uint256 indexed index, bool onTime);

    /**
     * @notice Emitted when a delivery is accepted: the seller and transporter are paid and title passes.
     * @param agreementId Agreement id.
     * @param index Delivery index.
     * @param goodsPaid Amount paid to the seller for the delivered weight.
     * @param buyerRefund Unused escrow refunded to the buyer.
     * @param transportFee Fee paid to the transporter.
     * @param automatic True if released after the review period rather than by the buyer.
     */
    event DeliveryAccepted(
        uint256 indexed agreementId,
        uint256 indexed index,
        uint256 goodsPaid,
        uint256 buyerRefund,
        uint256 transportFee,
        bool automatic
    );

    /**
     * @notice Emitted when the buyer rejects an arrived delivery, opening a dispute.
     * @param agreementId Agreement id.
     * @param index Delivery index.
     * @param by Rejecting account.
     * @param reasonHash Hash of the reasons.
     */
    event DeliveryDisputed(uint256 indexed agreementId, uint256 indexed index, address indexed by, bytes32 reasonHash);

    /**
     * @notice Emitted when a side makes a settlement offer on a disputed delivery.
     * @param agreementId Agreement id.
     * @param index Delivery index.
     * @param side Offering side.
     * @param goodsAmount Amount the offer would pay the seller for the goods.
     */
    event SettlementOffered(uint256 indexed agreementId, uint256 indexed index, Side side, uint256 goodsAmount);

    /**
     * @notice Emitted when a disputed delivery is settled.
     * @param agreementId Agreement id.
     * @param index Delivery index.
     * @param goodsPaid Amount paid to the seller.
     * @param buyerRefund Amount refunded to the buyer.
     * @param titleTransferred Whether the lots' ownership passed to the buyer.
     * @param arbiter The arbiter who decided, or zero when the parties agreed.
     * @param awardHash Hash of the arbitral award (zero when the parties agreed).
     */
    event DeliverySettled(
        uint256 indexed agreementId,
        uint256 indexed index,
        uint256 goodsPaid,
        uint256 buyerRefund,
        bool titleTransferred,
        address arbiter,
        bytes32 awardHash
    );

    /**
     * @notice Emitted when the buyer refuses a dispatched delivery whose lot was flagged before arrival.
     * @param agreementId Agreement id.
     * @param index Delivery index.
     * @param tokenId The flagged lot.
     * @param feePaid Whether the transporter was paid (it had picked the lots up).
     */
    event DeliveryRejected(uint256 indexed agreementId, uint256 indexed index, uint256 tokenId, bool feePaid);

    /**
     * @notice Emitted when a delivery ends without being made.
     * @param agreementId Agreement id.
     * @param index Delivery index.
     * @param status `Missed`, `Defaulted` or `Cancelled`.
     * @param refund Amount refunded to the buyer.
     */
    event DeliveryClosed(uint256 indexed agreementId, uint256 indexed index, DeliveryStatus status, uint256 refund);

    /**
     * @notice Emitted when a side requests a change to one scheduled delivery.
     * @param agreementId Agreement id.
     * @param index Delivery index.
     * @param side Requesting side.
     * @param quantity New quantity, in grams.
     * @param pricePerKg New price per kilogram.
     * @param dueAt New due date.
     */
    event AdjustmentRequested(
        uint256 indexed agreementId,
        uint256 indexed index,
        Side side,
        uint128 quantity,
        uint256 pricePerKg,
        uint64 dueAt
    );

    /**
     * @notice Emitted when the other side confirms a delivery adjustment.
     * @param agreementId Agreement id.
     * @param index Delivery index.
     */
    event AdjustmentConfirmed(uint256 indexed agreementId, uint256 indexed index);

    /**
     * @notice Emitted when a pending delivery adjustment is rejected or withdrawn.
     * @param agreementId Agreement id.
     * @param index Delivery index.
     * @param by Account that cleared it.
     */
    event AdjustmentCleared(uint256 indexed agreementId, uint256 indexed index, address indexed by);

    /**
     * @notice Emitted when a side requests mutual termination.
     * @param agreementId Agreement id.
     * @param side Requesting side.
     * @param reasonHash Hash of the reason.
     */
    event TerminationRequested(uint256 indexed agreementId, Side side, bytes32 reasonHash);

    /**
     * @notice Emitted when a pending termination request is withdrawn.
     * @param agreementId Agreement id.
     */
    event TerminationRequestWithdrawn(uint256 indexed agreementId);

    /**
     * @notice Emitted when an agreement ends.
     * @param agreementId Agreement id.
     * @param status `Completed` or `Terminated`.
     * @param forCause True when terminated unilaterally after the other side's repeated defaults.
     */
    event AgreementClosed(uint256 indexed agreementId, AgreementStatus status, bool forCause);

    /**
     * @notice Emitted when an account withdraws its credited balance.
     * @param token Token withdrawn.
     * @param account Withdrawing account.
     * @param amount Amount withdrawn.
     */
    event Withdrawn(IERC20 indexed token, address indexed account, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice `account` is not an admin of {MineNetRegistry}.
     * @param account The account.
     */
    error B2B__NotRegistryAdmin(address account);

    /**
     * @notice `account` may not enter agreements (it lacks `ENTER_AGREEMENT`).
     * @param account The account.
     */
    error B2B__NotAuthorized(address account);

    /**
     * @notice `account` cannot take the seller or buyer role (it lacks `SELL_LOT` or `OWN_LOT`).
     * @param account The account.
     */
    error B2B__InvalidTradingRole(address account);

    /**
     * @notice `account` does not act for either party of agreement `agreementId`.
     * @param agreementId The agreement.
     * @param account The account.
     */
    error B2B__NotParty(uint256 agreementId, address account);

    /**
     * @notice `account` does not act for the side required by the operation.
     * @param agreementId The agreement.
     * @param account The account.
     */
    error B2B__WrongSide(uint256 agreementId, address account);

    /**
     * @notice `counterparty` is not a valid counterparty (unauthorised, or in the proposer's organisation).
     * @param counterparty The counterparty account.
     */
    error B2B__InvalidCounterparty(address counterparty);

    /**
     * @notice `transporter` cannot be named (not an authorised carrier, or belongs to a party).
     * @param transporter The transporter.
     */
    error B2B__InvalidTransporter(address transporter);

    /**
     * @notice `arbiter` belongs to one of the parties.
     * @param arbiter The arbiter.
     */
    error B2B__InvalidArbiter(address arbiter);

    /**
     * @notice The terms are invalid (missing terms hash, review period or deadline out of range).
     */
    error B2B__InvalidTerms();

    /**
     * @notice The supply schedule is invalid (quantity, tolerance, grade, price, count or timing out of range).
     */
    error B2B__InvalidSchedule();

    /**
     * @notice `token` is not an accepted settlement token.
     * @param token The token.
     */
    error B2B__TokenNotAllowed(IERC20 token);

    /**
     * @notice Agreement `agreementId` does not exist.
     * @param agreementId The agreement.
     */
    error B2B__UnknownAgreement(uint256 agreementId);

    /**
     * @notice Agreement `agreementId` is in `status`, which does not allow the operation.
     * @param agreementId The agreement.
     * @param status Its current status.
     */
    error B2B__InvalidStatus(uint256 agreementId, AgreementStatus status);

    /**
     * @notice The signature is for `given`, but the current version is `current`.
     * @param current Current version.
     * @param given Version signed.
     */
    error B2B__VersionMismatch(uint32 current, uint32 given);

    /**
     * @notice The signing deadline of agreement `agreementId` has passed.
     * @param agreementId The agreement.
     */
    error B2B__ProposalExpired(uint256 agreementId);

    /**
     * @notice `account` is not the agreement's named transporter.
     * @param account The account.
     */
    error B2B__NotTransporter(address account);

    /**
     * @notice Agreement `agreementId` has no delivery at `index`.
     * @param agreementId The agreement.
     * @param index Delivery index.
     */
    error B2B__UnknownDelivery(uint256 agreementId, uint256 index);

    /**
     * @notice Delivery `index` is in `status`, which does not allow the operation.
     * @param index Delivery index.
     * @param status Its current status.
     */
    error B2B__InvalidDeliveryStatus(uint256 index, DeliveryStatus status);

    /**
     * @notice The agreement's payments are off-chain, so nothing can be escrowed.
     */
    error B2B__NotEscrowed();

    /**
     * @notice A delivery needs between 1 and the maximum number of lots, without duplicates.
     */
    error B2B__InvalidLots();

    /**
     * @notice Lot `tokenId` cannot fill the delivery: wrong mineral, not inspected, frozen, locked, not owned
     * by the seller, already committed elsewhere, or the contract is not approved to transfer it.
     * @param tokenId The lot.
     */
    error B2B__InvalidLot(uint256 tokenId);

    /**
     * @notice Lot `tokenId`'s attested grade is below the agreed minimum.
     * @param tokenId The lot.
     * @param gradeBps Its attested grade.
     * @param minGradeBps The agreed minimum.
     */
    error B2B__GradeTooLow(uint256 tokenId, uint16 gradeBps, uint16 minGradeBps);

    /**
     * @notice The lots' total weight is outside the delivery's quantity tolerance.
     * @param weight Total trusted weight, in grams.
     * @param min Lowest accepted weight.
     * @param max Highest accepted weight.
     */
    error B2B__QuantityOutOfTolerance(uint128 weight, uint128 min, uint128 max);

    /**
     * @notice Shipment `shipmentId` does not match the delivery (wrong carrier, parties, lots or status).
     * @param shipmentId The shipment.
     */
    error B2B__InvalidShipment(uint256 shipmentId);

    /**
     * @notice The buyer does not yet hold custody of every lot (or the shipment is not delivered).
     * @param index Delivery index.
     */
    error B2B__NotArrived(uint256 index);

    /**
     * @notice The review period of delivery `index` runs until `endsAt`.
     * @param index Delivery index.
     * @param endsAt End of the review period.
     */
    error B2B__ReviewPeriodOpen(uint256 index, uint64 endsAt);

    /**
     * @notice The review period of delivery `index` is over and no lot is flagged, so it can only be released.
     * @param index Delivery index.
     */
    error B2B__ReviewPeriodOver(uint256 index);

    /**
     * @notice No assigned inspector has cleared delivery `index` and the inspection grace period runs until `until`.
     * @param index Delivery index.
     * @param until End of the inspection grace period.
     */
    error B2B__InspectionPending(uint256 index, uint64 until);

    /**
     * @notice A lot of the delivery is flagged, below grade on inspection, or otherwise not releasable.
     * @param tokenId The lot.
     */
    error B2B__LotNotReleasable(uint256 tokenId);

    /**
     * @notice No lot of the delivery is flagged.
     * @param index Delivery index.
     */
    error B2B__NotFlagged(uint256 index);

    /**
     * @notice Delivery `index` cannot be closed before `availableAt`.
     * @param index Delivery index.
     * @param availableAt When it can be closed.
     */
    error B2B__TooEarly(uint256 index, uint64 availableAt);

    /**
     * @notice A settlement amount exceeds the payable amount.
     * @param amount Offered amount.
     * @param max Payable amount.
     */
    error B2B__InvalidSettlement(uint256 amount, uint256 max);

    /**
     * @notice `account` may not decide this dispute: not the agreed arbiter, nor the platform once the arbiter's
     * time has run out (or when no arbiter was agreed).
     * @param account The account.
     */
    error B2B__NotArbiter(address account);

    /**
     * @notice The parties may still negotiate the dispute until `until`.
     * @param until End of the negotiation period.
     */
    error B2B__NegotiationPeriod(uint64 until);

    /**
     * @notice No adjustment is pending, or the caller requested it and cannot confirm it.
     * @param index Delivery index.
     */
    error B2B__InvalidAdjustment(uint256 index);

    /**
     * @notice A termination request is already pending, none is pending, or the caller cannot confirm it.
     * @param agreementId The agreement.
     */
    error B2B__InvalidTermination(uint256 agreementId);

    /**
     * @notice Deliveries are still dispatched, arrived or disputed and must be resolved first.
     * @param inFlight Number of such deliveries.
     */
    error B2B__DeliveriesInFlight(uint32 inFlight);

    /**
     * @notice The other side has not missed enough deliveries to allow termination for cause.
     * @param count Its misses or defaults.
     * @param required The agreed threshold.
     */
    error B2B__NoCause(uint32 count, uint16 required);

    /**
     * @notice The caller has no balance to withdraw.
     */
    error B2B__NothingToWithdraw();

    /*//////////////////////////////////////////////////////////////
                                 HELPERS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice The other side of an agreement.
     * @param side A side.
     * @return The opposite side.
     */
    function other(Side side) internal pure returns (Side) {
        return side == Side.Proposer ? Side.Counterparty : Side.Proposer;
    }

    /**
     * @notice Whether a delivery status is final.
     * @param status Delivery status.
     * @return True for `Accepted`, `Settled`, `Rejected`, `Missed`, `Defaulted` and `Cancelled`.
     */
    function isFinal(DeliveryStatus status) internal pure returns (bool) {
        return uint8(status) >= uint8(DeliveryStatus.Accepted) && status != DeliveryStatus.Disputed;
    }

    /**
     * @notice The price of a weight at a price per kilogram, rounded down.
     * @param grams Weight, in grams.
     * @param pricePerKg Price per kilogram.
     * @return The price.
     */
    function priceOf(uint256 grams, uint256 pricePerKg) internal pure returns (uint256) {
        return (grams * pricePerKg) / GRAMS_PER_KG;
    }

    /**
     * @notice The upper and lower accepted weights of a delivery.
     * @param quantity Scheduled quantity, in grams.
     * @param toleranceBps Tolerance, in basis points.
     * @return min Lowest accepted weight.
     * @return max Highest accepted weight.
     */
    function bounds(uint128 quantity, uint16 toleranceBps) internal pure returns (uint128 min, uint128 max) {
        uint256 band = (uint256(quantity) * toleranceBps) / BPS;
        min = uint128(quantity - band);
        max = uint128(quantity + band);
    }
}
