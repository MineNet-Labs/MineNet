// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IStaffDirectory} from "src/workforce/interfaces/IStaffDirectory.sol";
import {WorkforceLib} from "src/workforce/libraries/WorkforceLib.sol";

/**
 * @title IWorkforce
 * @author 0xEmmyb2
 * @notice What {SiteOperations} needs from {WorkforceManager}: staff permissions, workers, and the hooks that
 * onboard approved hires and book the salaries paid from a site's payroll pool.
 */
interface IWorkforce is IStaffDirectory {
    /**
     * @notice Registers (or re-activates and moves) a worker whose hire the company approved.
     * @dev Only {SiteOperations}. A new worker is registered with `wallet`; an existing worker of the same
     * company keeps their wallet, is re-activated and assigned to `siteId`.
     * @param orgId Hiring company.
     * @param workerId Opaque worker id.
     * @param wallet Wallet of a new worker, or zero for none.
     * @param siteId Site the worker joins; one of the company's sites.
     */
    function onboardWorker(bytes32 orgId, bytes32 workerId, address wallet, uint256 siteId) external;

    /**
     * @notice Deactivates a worker whose employment ended.
     * @dev Only {SiteOperations}.
     * @param workerId Worker id.
     */
    function offboardWorker(bytes32 workerId) external;

    /**
     * @notice Books a stablecoin salary that {PayrollEngine} paid from the site's payer account.
     * @dev Only {PayrollEngine}. The worker must be a worker of `orgId` with a wallet (an inactive worker can
     * still receive arrears).
     * @param orgId Paying company.
     * @param workerId Worker paid.
     * @param token Settlement token.
     * @param amount Amount, in token units.
     * @param paymentRef Hashed pay-period reference.
     * @return paymentId New payment id.
     * @return wallet The worker's wallet.
     */
    function recordSiteSalary(bytes32 orgId, bytes32 workerId, IERC20 token, uint256 amount, bytes32 paymentRef)
        external
        returns (uint256 paymentId, address wallet);

    /**
     * @notice Which of `days_` consecutive days, starting at `fromDay`, a worker's attendance was recorded.
     * @param workerId Worker id.
     * @param fromDay First day (unix time / 1 day).
     * @param days_ Number of days; at most 256.
     * @return mask Bit `i` set if the worker attended on `fromDay + i`.
     */
    function attendanceMask(bytes32 workerId, uint64 fromDay, uint256 days_) external view returns (uint256 mask);

    /**
     * @notice The worker a wallet belongs to.
     * @param wallet Wallet.
     * @return workerId Worker id (zero if none).
     */
    function workerOfWallet(address wallet) external view returns (bytes32 workerId);

    /**
     * @notice Returns a worker.
     * @param workerId Worker id.
     * @return The worker (zero organisation if unknown).
     */
    function getWorker(bytes32 workerId) external view returns (WorkforceLib.Worker memory);
}
