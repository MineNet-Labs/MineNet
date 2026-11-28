// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {IMineNetRegistry} from "src/access/interfaces/IMineNetRegistry.sol";
import {ILotPassport} from "src/traceability/interfaces/ILotPassport.sol";
import {ICurrencyManager} from "src/finance/interfaces/ICurrencyManager.sol";
import {ILotFinance} from "src/finance/interfaces/ILotFinance.sol";
import {Actions} from "src/access/libraries/Actions.sol";
import {PassportLib} from "src/traceability/libraries/PassportLib.sol";
import {LotFinanceLib} from "src/finance/libraries/LotFinanceLib.sol";

/**
 * @title LotFinance
 * @author 0xEmmyb2
 * @notice Lot-backed trade finance and insurance cover.
 * @dev Loans (liens):
 * 1. The lot's owner asks a licensed financier (`FINANCE_LOT`, outside its organisation) for a loan on an
 *    inspected lot ({requestLoan}).
 * 2. The financier funds it ({fundLoan}), paying the principal on-chain or off-chain (bank transfer, mobile
 *    money). A `Lien` event is recorded on the passport and the lot becomes collateral: it cannot be transferred,
 *    processed or committed to a B2B delivery until the lien is released.
 * 3. The lien ends when:
 *    - the debt is repaid on-chain ({repay}), by anyone;
 *    - the financier releases it ({releaseLien}), e.g. after an off-chain repayment;
 *    - the lot is sold through {EscrowManager}: the sale must be in the loan's token and cover the debt
 *      ({checkSale}), and at settlement the financier is paid first from the seller's proceeds ({repayFromSale}).
 * The debt is a fixed `amountDue` (principal plus agreed interest) set when the owner requests the loan, so no
 * interest maths runs on-chain. A loan past its due date stays a lien until it is released ({isOverdue}).
 *
 * Insurance: the owner or custodian requests cover from a licensed insurer (`INSURE_LOT`, outside its
 * organisation) ({requestCover}); the insurer binds it ({bindCover}), which records an `Insured` event on the
 * passport. Premiums and claims are settled off-chain; only the request and policy hashes go on-chain.
 *
 * The admin can pause new business only. Repayments, releases and sale settlements always work.
 */
contract LotFinance is ReentrancyGuardTransient, Pausable, ILotFinance {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                                 STORAGE
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Longest loan term.
     */
    uint32 public constant MAX_TERM = 730 days;

    /**
     * @notice Longest insurance cover period.
     */
    uint64 public constant MAX_COVER_PERIOD = 400 days;

    /**
     * @notice Participant, role and permission registry.
     */
    IMineNetRegistry public immutable registry;

    /**
     * @notice Lot passport on which liens and cover are recorded.
     */
    ILotPassport public immutable passport;

    /**
     * @notice Settlement tokens loans may be denominated in.
     */
    ICurrencyManager public immutable currencies;

    /**
     * @dev Next loan id; ids start at 1 so that 0 means "none".
     */
    uint256 private _nextLoanId = 1;

    /**
     * @dev Next cover id; ids start at 1 so that 0 means "none".
     */
    uint256 private _nextCoverId = 1;

    /**
     * @dev Loan id => loan.
     */
    mapping(uint256 loanId => LotFinanceLib.Loan) private _loans;

    /**
     * @dev Cover id => cover.
     */
    mapping(uint256 coverId => LotFinanceLib.Cover) private _covers;

    /**
     * @inheritdoc ILotFinance
     */
    mapping(uint256 tokenId => uint256 loanId) public activeLoanOf;

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @param registry_ Participant, role and permission registry.
     * @param passport_ Lot passport.
     * @param currencies_ Currency manager.
     */
    constructor(IMineNetRegistry registry_, ILotPassport passport_, ICurrencyManager currencies_) {
        registry = registry_;
        passport = passport_;
        currencies = currencies_;
    }

    /*//////////////////////////////////////////////////////////////
                                  ADMIN
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Pauses new loan and cover business.
     * @dev Only a {MineNetRegistry} admin. Repayments, releases and sale settlements keep working.
     */
    function pause() external {
        _onlyAdmin();
        _pause();
    }

    /**
     * @notice Resumes new loan and cover business.
     * @dev Only a {MineNetRegistry} admin.
     */
    function unpause() external {
        _onlyAdmin();
        _unpause();
    }

    /*//////////////////////////////////////////////////////////////
                                  LOANS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice The lot's owner asks a financier for a loan secured on the lot.
     * @dev The caller must own the lot and hold `SELL_LOT` (in good standing). The financier needs `FINANCE_LOT`
     * and must be outside the caller's organisation. The lot must be inspected and free (see {fundLoan}).
     * @param tokenId Collateral lot.
     * @param lender Financier.
     * @param token Settlement token of the loan.
     * @param principal Amount to borrow, in token units; non-zero.
     * @param amountDue Principal plus agreed interest and fees, in token units; at least `principal`.
     * @param term Seconds from funding to the due date; in `(0, MAX_TERM]`.
     * @param termsHash Hash of the off-chain loan agreement.
     * @return loanId New loan id.
     * @custom:emits LoanRequested
     */
    function requestLoan(
        uint256 tokenId,
        address lender,
        IERC20 token,
        uint256 principal,
        uint256 amountDue,
        uint32 term,
        bytes32 termsHash
    ) external whenNotPaused returns (uint256 loanId) {
        address borrower = msg.sender;
        if (passport.ownerOf(tokenId) != borrower) revert LotFinanceLib.LotFinance__NotLotHolder(tokenId, borrower);
        _requireAction(borrower, Actions.SELL_LOT);
        _requireCounterparty(borrower, lender, Actions.FINANCE_LOT);
        if (!currencies.isSettlementToken(token)) revert LotFinanceLib.LotFinance__TokenNotAllowed(token);
        if (principal == 0 || amountDue < principal || term == 0 || term > MAX_TERM) {
            revert LotFinanceLib.LotFinance__InvalidTerms();
        }
        _requireFreeCollateral(tokenId);

        loanId = _nextLoanId++;
        _loans[loanId] = LotFinanceLib.Loan({
            tokenId: tokenId,
            borrower: borrower,
            lender: lender,
            token: token,
            principal: principal,
            amountDue: amountDue,
            repaid: 0,
            term: term,
            requestedAt: uint64(block.timestamp),
            fundedAt: 0,
            dueDate: 0,
            status: LotFinanceLib.LoanStatus.Requested,
            termsHash: termsHash
        });
        emit LotFinanceLib.LoanRequested(loanId, tokenId, borrower, lender, token, principal, amountDue, term);
    }

    /**
     * @notice The financier funds a requested loan; the lien is recorded on the passport.
     * @dev Only the named financier, still holding `FINANCE_LOT`. The borrower must still own the lot, which must
     * be inspected, not frozen, not locked under a trade and not already under a lien. With `disburseOnChain`, the
     * principal is pulled from the financier (approve this contract first) and paid to the borrower's
     * organisation payout account; otherwise it was paid off-chain.
     * @param loanId Requested loan.
     * @param disburseOnChain Whether to pay the principal on-chain now.
     * @custom:emits LoanFunded
     * @custom:emits PassportEventRecorded (Lien)
     */
    function fundLoan(uint256 loanId, bool disburseOnChain) external nonReentrant whenNotPaused {
        LotFinanceLib.Loan storage l = _loanIn(loanId, LotFinanceLib.LoanStatus.Requested);
        if (msg.sender != l.lender) revert LotFinanceLib.LotFinance__NotParty(msg.sender);
        _requireAction(msg.sender, Actions.FINANCE_LOT);
        uint256 tokenId = l.tokenId;
        if (passport.ownerOf(tokenId) != l.borrower) revert LotFinanceLib.LotFinance__InvalidCollateral(tokenId);
        _requireFreeCollateral(tokenId);

        uint64 dueDate = uint64(block.timestamp) + l.term;
        l.status = LotFinanceLib.LoanStatus.Active;
        l.fundedAt = uint64(block.timestamp);
        l.dueDate = dueDate;
        activeLoanOf[tokenId] = loanId;

        passport.recordFinancing(tokenId, PassportLib.EventType.Lien, msg.sender, l.termsHash);
        if (disburseOnChain) l.token.safeTransferFrom(msg.sender, registry.payoutOf(l.borrower), l.principal);
        emit LotFinanceLib.LoanFunded(loanId, dueDate, disburseOnChain);
    }

    /**
     * @notice The financier declines a loan request.
     * @param loanId Requested loan.
     * @custom:emits LoanRequestClosed
     */
    function declineLoan(uint256 loanId) external {
        LotFinanceLib.Loan storage l = _loanIn(loanId, LotFinanceLib.LoanStatus.Requested);
        if (msg.sender != l.lender) revert LotFinanceLib.LotFinance__NotParty(msg.sender);
        l.status = LotFinanceLib.LoanStatus.Declined;
        emit LotFinanceLib.LoanRequestClosed(loanId, LotFinanceLib.LoanStatus.Declined);
    }

    /**
     * @notice The borrower withdraws a loan request before it is funded.
     * @param loanId Requested loan.
     * @custom:emits LoanRequestClosed
     */
    function cancelLoanRequest(uint256 loanId) external {
        LotFinanceLib.Loan storage l = _loanIn(loanId, LotFinanceLib.LoanStatus.Requested);
        if (msg.sender != l.borrower) revert LotFinanceLib.LotFinance__NotParty(msg.sender);
        l.status = LotFinanceLib.LoanStatus.Cancelled;
        emit LotFinanceLib.LoanRequestClosed(loanId, LotFinanceLib.LoanStatus.Cancelled);
    }

    /**
     * @notice Repays an active loan on-chain, in the loan's token. Anyone may pay (the borrower, its buyer...).
     * @dev Pulls up to the outstanding debt from the caller (approve this contract first) and pays it to the
     * financier's organisation payout account. Full repayment releases the lien. Works while paused.
     * @param loanId Active loan.
     * @param amount Amount to repay; capped at the outstanding debt; non-zero.
     * @custom:emits LoanRepayment
     * @custom:emits LienReleased (on full repayment)
     */
    function repay(uint256 loanId, uint256 amount) external nonReentrant {
        LotFinanceLib.Loan storage l = _loanIn(loanId, LotFinanceLib.LoanStatus.Active);
        if (amount == 0) revert LotFinanceLib.LotFinance__InvalidAmount();
        uint256 outstanding = l.amountDue - l.repaid;
        if (amount > outstanding) amount = outstanding;

        l.repaid += amount;
        outstanding -= amount;
        if (outstanding == 0) _releaseLien(loanId, l, LotFinanceLib.LoanStatus.Repaid, bytes32(0));
        l.token.safeTransferFrom(msg.sender, registry.payoutOf(l.lender), amount);
        emit LotFinanceLib.LoanRepayment(loanId, msg.sender, amount, outstanding);
    }

    /**
     * @notice The financier releases the lien: repaid off-chain, restructured or forgiven.
     * @dev Only the loan's financier. Works while paused.
     * @param loanId Active loan.
     * @param proofHash Hash of the release proof (e.g. the bank receipt).
     * @custom:emits LienReleased
     */
    function releaseLien(uint256 loanId, bytes32 proofHash) external {
        LotFinanceLib.Loan storage l = _loanIn(loanId, LotFinanceLib.LoanStatus.Active);
        if (msg.sender != l.lender) revert LotFinanceLib.LotFinance__NotParty(msg.sender);
        _releaseLien(loanId, l, LotFinanceLib.LoanStatus.Released, proofHash);
    }

    /**
     * @inheritdoc ILotFinance
     * @custom:emits LoanSettledFromSale
     * @custom:emits LienReleased
     */
    function repayFromSale(uint256 tokenId, IERC20 token, uint256 available)
        external
        returns (address payee, uint256 repaid)
    {
        address escrow = passport.escrow();
        if (msg.sender != escrow || escrow == address(0)) revert LotFinanceLib.LotFinance__NotEscrow(msg.sender);
        uint256 loanId = activeLoanOf[tokenId];
        if (loanId == 0) return (address(0), 0);
        LotFinanceLib.Loan storage l = _loans[loanId];
        uint256 outstanding = l.amountDue - l.repaid;
        if (address(token) != address(l.token)) {
            revert LotFinanceLib.LotFinance__SaleDoesNotCoverLien(tokenId, outstanding);
        }

        repaid = available < outstanding ? available : outstanding;
        payee = registry.payoutOf(l.lender);
        l.repaid += repaid;
        _releaseLien(loanId, l, LotFinanceLib.LoanStatus.SettledFromSale, bytes32(0));
        emit LotFinanceLib.LoanSettledFromSale(loanId, repaid, outstanding - repaid);
    }

    /*//////////////////////////////////////////////////////////////
                             INSURANCE COVER
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice The lot's owner or custodian asks an insurer for cover (storage, transit or both).
     * @dev The insurer needs `INSURE_LOT` and must be outside the caller's organisation.
     * @param tokenId Lot.
     * @param insurer Insurer.
     * @param requestHash Hash of the request (cover type, sum insured, route or warehouse).
     * @return coverId New cover id.
     * @custom:emits CoverRequested
     */
    function requestCover(uint256 tokenId, address insurer, bytes32 requestHash)
        external
        whenNotPaused
        returns (uint256 coverId)
    {
        address holder = msg.sender;
        if (passport.ownerOf(tokenId) != holder && passport.custodianOf(tokenId) != holder) {
            revert LotFinanceLib.LotFinance__NotLotHolder(tokenId, holder);
        }
        _requireCounterparty(holder, insurer, Actions.INSURE_LOT);

        coverId = _nextCoverId++;
        _covers[coverId] = LotFinanceLib.Cover({
            tokenId: tokenId,
            holder: holder,
            insurer: insurer,
            requestedAt: uint64(block.timestamp),
            coverUntil: 0,
            status: LotFinanceLib.CoverStatus.Requested,
            requestHash: requestHash,
            policyHash: bytes32(0)
        });
        emit LotFinanceLib.CoverRequested(coverId, tokenId, holder, insurer, requestHash);
    }

    /**
     * @notice The insurer binds the requested cover; an `Insured` event is recorded on the passport.
     * @dev Only the named insurer, still holding `INSURE_LOT`.
     * @param coverId Requested cover.
     * @param policyHash Hash of the policy.
     * @param coverUntil End of cover; in the future and at most `MAX_COVER_PERIOD` ahead.
     * @custom:emits CoverBound
     * @custom:emits PassportEventRecorded (Insured)
     */
    function bindCover(uint256 coverId, bytes32 policyHash, uint64 coverUntil) external whenNotPaused {
        LotFinanceLib.Cover storage c = _coverIn(coverId);
        if (msg.sender != c.insurer) revert LotFinanceLib.LotFinance__NotParty(msg.sender);
        _requireAction(msg.sender, Actions.INSURE_LOT);
        if (coverUntil <= block.timestamp || coverUntil > block.timestamp + MAX_COVER_PERIOD) {
            revert LotFinanceLib.LotFinance__InvalidCoverPeriod(coverUntil);
        }
        c.status = LotFinanceLib.CoverStatus.Bound;
        c.policyHash = policyHash;
        c.coverUntil = coverUntil;
        passport.recordFinancing(c.tokenId, PassportLib.EventType.Insured, msg.sender, policyHash);
        emit LotFinanceLib.CoverBound(coverId, policyHash, coverUntil);
    }

    /**
     * @notice The insurer declines, or the holder withdraws, a cover request.
     * @param coverId Requested cover.
     * @custom:emits CoverRequestClosed
     */
    function closeCoverRequest(uint256 coverId) external {
        LotFinanceLib.Cover storage c = _coverIn(coverId);
        LotFinanceLib.CoverStatus status;
        if (msg.sender == c.insurer) status = LotFinanceLib.CoverStatus.Declined;
        else if (msg.sender == c.holder) status = LotFinanceLib.CoverStatus.Cancelled;
        else revert LotFinanceLib.LotFinance__NotParty(msg.sender);
        c.status = status;
        emit LotFinanceLib.CoverRequestClosed(coverId, status);
    }

    /*//////////////////////////////////////////////////////////////
                                  VIEWS
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc ILotFinance
     */
    function checkSale(uint256 tokenId, IERC20 token, uint256 sellerNet) external view {
        uint256 loanId = activeLoanOf[tokenId];
        if (loanId == 0) return;
        LotFinanceLib.Loan storage l = _loans[loanId];
        uint256 outstanding = l.amountDue - l.repaid;
        if (address(token) != address(l.token) || sellerNet < outstanding) {
            revert LotFinanceLib.LotFinance__SaleDoesNotCoverLien(tokenId, outstanding);
        }
    }

    /**
     * @notice Returns a loan.
     * @param loanId Loan id.
     * @return The loan (status `None` if unknown).
     */
    function getLoan(uint256 loanId) external view returns (LotFinanceLib.Loan memory) {
        return _loans[loanId];
    }

    /**
     * @notice Debt still owed on a loan.
     * @param loanId Loan id.
     * @return Outstanding amount, in the loan's token (0 unless active).
     */
    function outstandingOf(uint256 loanId) external view returns (uint256) {
        LotFinanceLib.Loan storage l = _loans[loanId];
        return l.status == LotFinanceLib.LoanStatus.Active ? l.amountDue - l.repaid : 0;
    }

    /**
     * @notice Whether an active loan is past its due date.
     * @param loanId Loan id.
     * @return True if overdue.
     */
    function isOverdue(uint256 loanId) external view returns (bool) {
        LotFinanceLib.Loan storage l = _loans[loanId];
        return l.status == LotFinanceLib.LoanStatus.Active && block.timestamp > l.dueDate;
    }

    /**
     * @notice Returns a cover.
     * @param coverId Cover id.
     * @return The cover (status `None` if unknown).
     */
    function getCover(uint256 coverId) external view returns (LotFinanceLib.Cover memory) {
        return _covers[coverId];
    }

    /**
     * @notice Whether a cover is bound and still running.
     * @param coverId Cover id.
     * @return True while in force.
     */
    function isCovered(uint256 coverId) external view returns (bool) {
        LotFinanceLib.Cover storage c = _covers[coverId];
        return c.status == LotFinanceLib.CoverStatus.Bound && block.timestamp <= c.coverUntil;
    }

    /*//////////////////////////////////////////////////////////////
                    INTERNAL STATE-CHANGING FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Closes an active loan with `status` and releases its lien on the passport.
     * @param loanId Loan id.
     * @param l The loan.
     * @param status Final status.
     * @param proofHash Hash of the release proof.
     */
    function _releaseLien(
        uint256 loanId,
        LotFinanceLib.Loan storage l,
        LotFinanceLib.LoanStatus status,
        bytes32 proofHash
    ) private {
        uint256 tokenId = l.tokenId;
        l.status = status;
        delete activeLoanOf[tokenId];
        passport.recordFinancing(tokenId, PassportLib.EventType.LienReleased, l.lender, proofHash);
        emit LotFinanceLib.LienReleased(loanId, tokenId, status, proofHash);
    }

    /*//////////////////////////////////////////////////////////////
                     INTERNAL READ-ONLY FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Returns a loan, reverting unless it is in `status`.
     * @param loanId Loan id.
     * @param status Required status.
     * @return l Storage pointer to the loan.
     */
    function _loanIn(uint256 loanId, LotFinanceLib.LoanStatus status)
        private
        view
        returns (LotFinanceLib.Loan storage l)
    {
        l = _loans[loanId];
        if (l.status != status) revert LotFinanceLib.LotFinance__InvalidLoanStatus(loanId);
    }

    /**
     * @dev Returns a cover, reverting unless it is `Requested`.
     * @param coverId Cover id.
     * @return c Storage pointer to the cover.
     */
    function _coverIn(uint256 coverId) private view returns (LotFinanceLib.Cover storage c) {
        c = _covers[coverId];
        if (c.status != LotFinanceLib.CoverStatus.Requested) {
            revert LotFinanceLib.LotFinance__InvalidCoverStatus(coverId);
        }
    }

    /**
     * @dev Reverts unless the lot is inspected, not frozen, not locked under a trade and has no active lien.
     * @param tokenId Lot.
     */
    function _requireFreeCollateral(uint256 tokenId) private view {
        if (
            passport.getLot(tokenId).status != PassportLib.LotStatus.Inspected || passport.isFrozen(tokenId)
                || passport.escrowLocked(tokenId) || activeLoanOf[tokenId] != 0
        ) revert LotFinanceLib.LotFinance__InvalidCollateral(tokenId);
    }

    /**
     * @dev Reverts unless `counterparty` may perform `action` and is outside `party`'s organisation.
     * @param party Borrower or cover holder.
     * @param counterparty Financier or insurer.
     * @param action Required action.
     */
    function _requireCounterparty(address party, address counterparty, bytes32 action) private view {
        _requireAction(counterparty, action);
        if (registry.sameOrg(party, counterparty)) revert LotFinanceLib.LotFinance__NotIndependent(counterparty);
    }

    /**
     * @dev Reverts unless `account` may perform `action`.
     * @param account The account.
     * @param action Required action.
     */
    function _requireAction(address account, bytes32 action) private view {
        if (!registry.isAuthorized(account, action)) revert LotFinanceLib.LotFinance__Unauthorized(account, action);
    }

    /**
     * @dev Reverts unless the caller is a {MineNetRegistry} admin.
     */
    function _onlyAdmin() private view {
        if (!registry.isAdmin(msg.sender)) revert LotFinanceLib.LotFinance__NotRegistryAdmin(msg.sender);
    }
}
