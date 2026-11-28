// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

/**
 * @title WorkforceLib
 * @author 0xEmmyb2
 * @notice Shared types, events and custom errors of {WorkforceManager}.
 */
library WorkforceLib {
    /**
     * @notice Number of {PaymentMethod} values.
     */
    uint256 internal constant METHOD_COUNT = 5;

    /**
     * @notice How a payment was made. `BankTransfer` is e-banking; `Stablecoin` is paid on-chain through
     * {WorkforceManager}.
     */
    enum PaymentMethod {
        MobileMoney,
        BankTransfer, // e-banking
        Cash,
        Stablecoin, // paid on-chain through WorkforceManager
        Other
    }

    /**
     * @notice What a payment is for.
     */
    enum PaymentCategory {
        Salary,
        Supplier,
        Contractor,
        Other
    }

    /**
     * @notice Status of a recorded payment.
     * @dev `Confirmed`: electronic payment with a receipt, or paid on-chain. `PendingAck`: cash waiting for the
     * payee's acknowledgement. `Acknowledged`: cash acknowledged by the payee (or an attendance / biometric
     * device).
     * `Disputed`: the payee says it was not received or was wrong.
     */
    enum PaymentStatus {
        None,
        Confirmed, // electronic payment with a receipt, or paid on-chain
        PendingAck, // cash: waits for the payee's acknowledgement
        Acknowledged, // cash acknowledged by the payee (or an attendance / biometric device)
        Disputed // the payee says it was not received or was wrong
    }

    /**
     * @notice A company worker, identified by an opaque salted id (no personal data on-chain).
     * @param orgId Employer.
     * @param wallet Optional wallet for on-chain pay and acknowledgements.
     * @param siteId Current work site (0 = not assigned).
     * @param registeredAt When the worker was registered.
     * @param lastAttendanceDay Last day with recorded attendance (unix time / 1 day).
     * @param daysWorked Number of days with recorded attendance.
     * @param active Whether the worker is active.
     */
    struct Worker {
        bytes32 orgId;
        address wallet;
        uint256 siteId;
        uint64 registeredAt;
        uint64 lastAttendanceDay;
        uint32 daysWorked;
        bool active;
    }

    /**
     * @notice A recorded payment by a company.
     * @param orgId Payer.
     * @param payeeId Worker id, or an opaque supplier / contractor reference.
     * @param payeeWallet Account that can acknowledge or dispute (zero = nobody on-chain).
     * @param category What the payment is for.
     * @param method How it was paid.
     * @param status Current status.
     * @param cashRisk True for cash above the platform limit.
     * @param currency Pricing currency code, e.g. "RWF", "USD".
     * @param amount Amount, in `currency` units.
     * @param usdValue USD value at the time of payment, 6 decimals (0 if no rate was available).
     * @param paymentRef Hashed pay period, invoice or mobile-money transaction id.
     * @param receiptHash Hash of the receipt.
     * @param recordedBy Account that recorded it.
     * @param paidAt When it was recorded.
     */
    struct Payment {
        bytes32 orgId;
        bytes32 payeeId;
        address payeeWallet;
        PaymentCategory category;
        PaymentMethod method;
        PaymentStatus status;
        bool cashRisk;
        bytes32 currency;
        uint256 amount;
        uint256 usdValue;
        bytes32 paymentRef;
        bytes32 receiptHash;
        address recordedBy;
        uint64 paidAt;
    }

    /**
     * @notice Per-organisation payment totals for management reports. USD values use 6 decimals.
     * @param payments Number of payments.
     * @param totalUsd Total USD value.
     * @param usdByMethod USD value per {PaymentMethod}, indexed by the enum value.
     * @param cashPendingAck Cash payments not yet acknowledged.
     * @param cashRiskPayments Cash payments above the limit.
     * @param disputed Disputed payments.
     */
    struct OrgReport {
        uint256 payments;
        uint256 totalUsd;
        uint256[METHOD_COUNT] usdByMethod;
        uint256 cashPendingAck;
        uint256 cashRiskPayments;
        uint256 disputed;
    }

    /**
     * @notice Everything a caller supplies to record one off-chain payment.
     * @param payeeId Worker id or opaque payee reference.
     * @param payeeWallet Account that can acknowledge or dispute; ignored for salaries (the worker's wallet is
     * used).
     * @param category What the payment is for.
     * @param method How it was paid; not `Stablecoin` (use the on-chain pay functions).
     * @param currency Pricing currency code.
     * @param amount Amount, in `currency` units.
     * @param paymentRef Hashed pay period, invoice or transaction id.
     * @param receiptHash Hash of the receipt.
     */
    struct PaymentInput {
        bytes32 payeeId;
        address payeeWallet;
        PaymentCategory category;
        PaymentMethod method;
        bytes32 currency;
        uint256 amount;
        bytes32 paymentRef;
        bytes32 receiptHash;
    }

    /**
     * @notice Emitted when a company registers a worker.
     * @param workerId Opaque worker id.
     * @param orgId Employer.
     * @param wallet Worker wallet (zero if none).
     * @param siteId Work site.
     */
    event WorkerRegistered(bytes32 indexed workerId, bytes32 indexed orgId, address wallet, uint256 indexed siteId);

    /**
     * @notice Emitted when a worker's wallet changes.
     * @param workerId Worker id.
     * @param wallet New wallet (zero = removed).
     */
    event WorkerWalletChanged(bytes32 indexed workerId, address wallet);

    /**
     * @notice Emitted when the employer proposes a new wallet for a worker, pending the worker's confirmation.
     * @param workerId Worker id.
     * @param wallet Proposed wallet.
     * @param by Proposing account.
     */
    event WalletChangeProposed(bytes32 indexed workerId, address wallet, address indexed by);

    /**
     * @notice Emitted when a worker moves between sites.
     * @param workerId Worker id.
     * @param fromSite Previous site.
     * @param toSite New site.
     */
    event WorkerAssigned(bytes32 indexed workerId, uint256 indexed fromSite, uint256 indexed toSite);

    /**
     * @notice Emitted when a worker is activated or deactivated.
     * @param workerId Worker id.
     * @param active New state.
     */
    event WorkerStatusChanged(bytes32 indexed workerId, bool active);

    /**
     * @notice Emitted when a worker's attendance is recorded for a day.
     * @param workerId Worker id.
     * @param siteId Site worked at.
     * @param day Day number (unix time / 1 day).
     * @param by Recording account.
     */
    event AttendanceRecorded(bytes32 indexed workerId, uint256 indexed siteId, uint64 indexed day, address by);

    /**
     * @notice Emitted when a payment is recorded.
     * @param paymentId New payment id.
     * @param orgId Payer.
     * @param payeeId Payee.
     * @param category What the payment is for.
     * @param method How it was paid.
     * @param currency Pricing currency code.
     * @param amount Amount, in `currency` units.
     * @param usdValue USD value, 6 decimals.
     * @param paymentRef Hashed payment reference.
     */
    event PaymentRecorded(
        uint256 indexed paymentId,
        bytes32 indexed orgId,
        bytes32 indexed payeeId,
        PaymentCategory category,
        PaymentMethod method,
        bytes32 currency,
        uint256 amount,
        uint256 usdValue,
        bytes32 paymentRef
    );

    /**
     * @notice Emitted when a cash payment exceeds the platform limit.
     * @param paymentId Payment id.
     * @param orgId Payer.
     * @param usdValue USD value, 6 decimals.
     */
    event CashRiskFlagged(uint256 indexed paymentId, bytes32 indexed orgId, uint256 usdValue);

    /**
     * @notice Emitted when a payee acknowledges a cash payment.
     * @param paymentId Payment id.
     * @param by Acknowledging account.
     * @param receiptHash Hash of the acknowledgement evidence.
     */
    event PaymentAcknowledged(uint256 indexed paymentId, address indexed by, bytes32 receiptHash);

    /**
     * @notice Emitted when a payee disputes a payment.
     * @param paymentId Payment id.
     * @param by Disputing account.
     * @param reasonHash Hash of the reason.
     */
    event PaymentDisputed(uint256 indexed paymentId, address indexed by, bytes32 reasonHash);

    /**
     * @notice Emitted when the admin sets the cash policy.
     * @param cashLimitUsd Cash amount above which a payment is flagged, USD with 6 decimals.
     * @param ackWindow Time a payee has to acknowledge a cash payment, in seconds.
     */
    event CashPolicySet(uint256 cashLimitUsd, uint32 ackWindow);

    /**
     * @notice Emitted when the admin sets the {SiteOperations} contract.
     * @param siteOperations The contract (zero = hooks disabled).
     */
    event SiteOperationsSet(address siteOperations);

    /**
     * @notice Emitted when the admin sets the payroll engine.
     * @param engine The engine (zero = none).
     */
    event PayrollEngineSet(address engine);

    /**
     * @notice `account` is not an admin of {MineNetRegistry}.
     * @param account The account.
     */
    error WorkforceManager__NotRegistryAdmin(address account);

    /**
     * @notice `account` may not manage this company's workforce.
     * @param account The account.
     */
    error WorkforceManager__Unauthorized(address account);

    /**
     * @notice The worker id is zero.
     */
    error WorkforceManager__InvalidWorkerId();

    /**
     * @notice Worker `workerId` is already registered.
     * @param workerId The worker.
     */
    error WorkforceManager__WorkerExists(bytes32 workerId);

    /**
     * @notice No such wallet change is pending for worker `workerId`.
     * @param workerId Worker id.
     */
    error WorkforceManager__NoWalletChange(bytes32 workerId);

    /**
     * @notice Worker `workerId` does not exist.
     * @param workerId The worker.
     */
    error WorkforceManager__UnknownWorker(bytes32 workerId);

    /**
     * @notice Worker `workerId` belongs to another company.
     * @param workerId The worker.
     */
    error WorkforceManager__NotYourWorker(bytes32 workerId);

    /**
     * @notice Worker `workerId` is inactive.
     * @param workerId The worker.
     */
    error WorkforceManager__WorkerInactive(bytes32 workerId);

    /**
     * @notice Site `siteId` does not belong to the company.
     * @param siteId The site.
     */
    error WorkforceManager__SiteNotOfOrg(uint256 siteId);

    /**
     * @notice Worker `workerId` is not assigned to site `siteId`.
     * @param workerId The worker.
     * @param siteId The site.
     */
    error WorkforceManager__NotAtSite(bytes32 workerId, uint256 siteId);

    /**
     * @notice The amount is zero.
     */
    error WorkforceManager__InvalidAmount();

    /**
     * @notice `Stablecoin` payments must use the on-chain pay functions.
     */
    error WorkforceManager__InvalidMethod();

    /**
     * @notice `currency` is not an enabled currency.
     * @param currency The currency code.
     */
    error WorkforceManager__UnknownCurrency(bytes32 currency);

    /**
     * @notice Payee `payeeId` has no wallet to pay on-chain.
     * @param payeeId The payee.
     */
    error WorkforceManager__NoWallet(bytes32 payeeId);

    /**
     * @notice Input arrays have different lengths.
     */
    error WorkforceManager__LengthMismatch();

    /**
     * @notice Payment `paymentId` does not exist.
     * @param paymentId The payment.
     */
    error WorkforceManager__UnknownPayment(uint256 paymentId);

    /**
     * @notice Payment `paymentId` is in `status`, which does not allow the operation.
     * @param paymentId The payment.
     * @param status Its current status.
     */
    error WorkforceManager__InvalidPaymentStatus(uint256 paymentId, PaymentStatus status);

    /**
     * @notice `account` is not the payee of payment `paymentId`.
     * @param paymentId The payment.
     * @param account The account.
     */
    error WorkforceManager__NotPayee(uint256 paymentId, address account);

    /**
     * @notice The cash acknowledgement window is zero.
     */
    error WorkforceManager__InvalidPolicy();

    /**
     * @notice Attendance day `day` is in the future or further back than the allowed backdating.
     * @param day The day number.
     */
    error WorkforceManager__InvalidDay(uint64 day);
}
