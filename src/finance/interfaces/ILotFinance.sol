// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title ILotFinance
 * @author 0xEmmyb2
 * @notice What {EscrowManager} needs from {LotFinance} to sell a lot that is collateral for a loan: check that the
 * sale covers the lien, then pay the financier first.
 */
interface ILotFinance {
    /**
     * @notice Reverts unless a sale of `tokenId` paid in `token`, leaving `sellerNet` for the seller after fees,
     * covers its active lien. A lot without a lien always passes.
     * @param tokenId Lot.
     * @param token Payment token of the sale.
     * @param sellerNet Seller proceeds after platform fees, in `token` units.
     */
    function checkSale(uint256 tokenId, IERC20 token, uint256 sellerNet) external view;

    /**
     * @notice The escrow settles a sale of an encumbered lot: the financier is paid first, from the seller's
     * proceeds, and the lien is released so the title can pass.
     * @dev Only the passport's escrow. The escrow credits `repaid` to `payee` itself. A no-op (zero, zero) for a lot
     * without a lien.
     * @param tokenId Lot being sold.
     * @param token Payment token of the sale.
     * @param available Seller proceeds available to repay, in `token` units.
     * @return payee Account to credit (the financier's payout account).
     * @return repaid Amount owed to `payee` out of `available`.
     */
    function repayFromSale(uint256 tokenId, IERC20 token, uint256 available)
        external
        returns (address payee, uint256 repaid);

    /**
     * @notice The active loan secured on a lot (0 if none).
     * @param tokenId Lot.
     * @return loanId Loan id.
     */
    function activeLoanOf(uint256 tokenId) external view returns (uint256 loanId);
}
