// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title LotFinanceLib
 * @author 0xEmmyb2
 * @notice Types, events and custom errors of {LotFinance}: loans secured on lot passports (liens) and insurance
 * cover bound on lots.
 */
library LotFinanceLib {
    /*//////////////////////////////////////////////////////////////
                                 TYPES
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Lifecycle of a loan secured on a lot.
     */
    enum LoanStatus {
        None,
        Requested, // the lot owner asked a financier; no lien yet
        Active, // funded: the lot is collateral (lien recorded on the passport)
        Repaid, // repaid in full on-chain; lien released
        SettledFromSale, // the lot was sold through escrow and the financier was paid first; lien released
        Released, // the financier released the lien (repaid off-chain, restructured or forgiven)
        Declined, // the financier declined the request
        Cancelled // the owner withdrew the request
    }

    /**
     * @notice Lifecycle of an insurance cover request.
     */
    enum CoverStatus {
        None,
        Requested,
        Bound,
        Declined,
        Cancelled
    }

    /**
     * @notice A loan secured on a lot.
     * @param tokenId Collateral lot.
     * @param borrower Lot owner who requested the loan.
     * @param lender Financier.
     * @param token Settlement token the debt is denominated and repaid in.
     * @param principal Amount lent, in token units.
     * @param amountDue Principal plus agreed interest and fees, in token units; the debt the lien secures.
     * @param repaid Amount repaid so far, in token units.
     * @param term Seconds from funding to the due date.
     * @param requestedAt When the owner requested it.
     * @param fundedAt When the financier funded it (0 until then).
     * @param dueDate Repayment due date (0 until funded).
     * @param status Current status.
     * @param termsHash Hash of the off-chain loan agreement.
     */
    struct Loan {
        uint256 tokenId;
        address borrower;
        address lender;
        IERC20 token;
        uint256 principal;
        uint256 amountDue;
        uint256 repaid;
        uint32 term;
        uint64 requestedAt;
        uint64 fundedAt;
        uint64 dueDate;
        LoanStatus status;
        bytes32 termsHash;
    }

    /**
     * @notice Insurance cover on a lot.
     * @param tokenId Insured lot.
     * @param holder Owner or custodian who requested the cover.
     * @param insurer Insurer.
     * @param requestedAt When it was requested.
     * @param coverUntil End of cover (0 until bound).
     * @param status Current status.
     * @param requestHash Hash of the cover request (cover type, sum insured, route or warehouse).
     * @param policyHash Hash of the bound policy (0 until bound).
     */
    struct Cover {
        uint256 tokenId;
        address holder;
        address insurer;
        uint64 requestedAt;
        uint64 coverUntil;
        CoverStatus status;
        bytes32 requestHash;
        bytes32 policyHash;
    }

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Emitted when a lot owner requests a loan secured on the lot.
     * @param loanId Loan id.
     * @param tokenId Collateral lot.
     * @param borrower Lot owner.
     * @param lender Financier asked.
     * @param token Settlement token.
     * @param principal Amount requested.
     * @param amountDue Debt the lien will secure.
     * @param term Seconds from funding to the due date.
     */
    event LoanRequested(
        uint256 indexed loanId,
        uint256 indexed tokenId,
        address indexed borrower,
        address lender,
        IERC20 token,
        uint256 principal,
        uint256 amountDue,
        uint32 term
    );

    /**
     * @notice Emitted when a financier funds a loan and the lien is recorded on the passport.
     * @param loanId Loan id.
     * @param dueDate Repayment due date.
     * @param disbursedOnChain Whether the principal was paid on-chain (false: paid off-chain, e.g. bank transfer).
     */
    event LoanFunded(uint256 indexed loanId, uint64 dueDate, bool disbursedOnChain);

    /**
     * @notice Emitted when a financier declines, or the owner withdraws, a loan request.
     * @param loanId Loan id.
     * @param status `Declined` or `Cancelled`.
     */
    event LoanRequestClosed(uint256 indexed loanId, LoanStatus status);

    /**
     * @notice Emitted for an on-chain repayment.
     * @param loanId Loan id.
     * @param payer Paying account.
     * @param amount Amount repaid.
     * @param outstanding Debt left after the repayment.
     */
    event LoanRepayment(uint256 indexed loanId, address indexed payer, uint256 amount, uint256 outstanding);

    /**
     * @notice Emitted when an escrow sale of the collateral pays the financier first.
     * @param loanId Loan id.
     * @param repaid Amount paid to the financier from the sale.
     * @param shortfall Debt the sale did not cover (now unsecured).
     */
    event LoanSettledFromSale(uint256 indexed loanId, uint256 repaid, uint256 shortfall);

    /**
     * @notice Emitted when the lien is released (any reason).
     * @param loanId Loan id.
     * @param tokenId Lot freed.
     * @param status Final loan status.
     * @param proofHash Hash of the release proof (0 when repaid on-chain or from a sale).
     */
    event LienReleased(uint256 indexed loanId, uint256 indexed tokenId, LoanStatus status, bytes32 proofHash);

    /**
     * @notice Emitted when an owner or custodian requests cover on a lot.
     * @param coverId Cover id.
     * @param tokenId Lot.
     * @param holder Requesting owner or custodian.
     * @param insurer Insurer asked.
     * @param requestHash Hash of the request.
     */
    event CoverRequested(
        uint256 indexed coverId, uint256 indexed tokenId, address indexed holder, address insurer, bytes32 requestHash
    );

    /**
     * @notice Emitted when an insurer binds cover and it is recorded on the passport.
     * @param coverId Cover id.
     * @param policyHash Hash of the policy.
     * @param coverUntil End of cover.
     */
    event CoverBound(uint256 indexed coverId, bytes32 policyHash, uint64 coverUntil);

    /**
     * @notice Emitted when an insurer declines, or the holder withdraws, a cover request.
     * @param coverId Cover id.
     * @param status `Declined` or `Cancelled`.
     */
    event CoverRequestClosed(uint256 indexed coverId, CoverStatus status);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice The caller is not a {MineNetRegistry} admin.
     * @param account The caller.
     */
    error LotFinance__NotRegistryAdmin(address account);

    /**
     * @notice `account` may not perform `action`.
     * @param account The account.
     * @param action The required action.
     */
    error LotFinance__Unauthorized(address account, bytes32 action);

    /**
     * @notice The caller is not the lot's owner (or, for cover, its owner or custodian).
     * @param tokenId The lot.
     * @param account The caller.
     */
    error LotFinance__NotLotHolder(uint256 tokenId, address account);

    /**
     * @notice The financier or insurer belongs to the borrower's or holder's own organisation.
     * @param counterparty The financier or insurer.
     */
    error LotFinance__NotIndependent(address counterparty);

    /**
     * @notice `token` is not an approved settlement token.
     * @param token The token.
     */
    error LotFinance__TokenNotAllowed(IERC20 token);

    /**
     * @notice Principal, amount due or term out of range.
     */
    error LotFinance__InvalidTerms();

    /**
     * @notice Lot `tokenId` cannot serve as collateral now: not inspected, frozen, locked under a trade, or
     * already under a lien.
     * @param tokenId The lot.
     */
    error LotFinance__InvalidCollateral(uint256 tokenId);

    /**
     * @notice Loan `loanId` is unknown or not in the required status.
     * @param loanId The loan.
     */
    error LotFinance__InvalidLoanStatus(uint256 loanId);

    /**
     * @notice The caller is not the party this step belongs to.
     * @param account The caller.
     */
    error LotFinance__NotParty(address account);

    /**
     * @notice Zero repayment.
     */
    error LotFinance__InvalidAmount();

    /**
     * @notice The caller is not the escrow.
     * @param account The caller.
     */
    error LotFinance__NotEscrow(address account);

    /**
     * @notice A sale of encumbered lot `tokenId` must be paid in the loan's token and its proceeds, after fees,
     * must cover the outstanding debt.
     * @param tokenId The lot.
     * @param outstanding Outstanding debt, in the loan's token.
     */
    error LotFinance__SaleDoesNotCoverLien(uint256 tokenId, uint256 outstanding);

    /**
     * @notice Cover `coverId` is unknown or not in the required status.
     * @param coverId The cover.
     */
    error LotFinance__InvalidCoverStatus(uint256 coverId);

    /**
     * @notice The end of cover is not in the future, or too far ahead.
     * @param coverUntil The requested end.
     */
    error LotFinance__InvalidCoverPeriod(uint64 coverUntil);
}
