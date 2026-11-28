// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {MineNetFixture} from "test/utils/MineNetFixture.sol";
import {Roles} from "src/access/libraries/Roles.sol";
import {Actions} from "src/access/libraries/Actions.sol";
import {PassportLib} from "src/traceability/libraries/PassportLib.sol";
import {LotFinanceLib} from "src/finance/libraries/LotFinanceLib.sol";
import {EscrowLib} from "src/trade/libraries/EscrowLib.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract LotFinanceTest is MineNetFixture {
    uint256 constant PRINCIPAL = 18_000e6;
    uint256 constant DUE = 20_000e6;
    uint32 constant TERM = 90 days;

    function setUp() public override {
        super.setUp();
        usdc.mint(financier, 1_000_000e6);
        vm.prank(financier);
        usdc.approve(address(finance), type(uint256).max);
        usdc.mint(miner, 1_000_000e6);
        vm.prank(miner);
        usdc.approve(address(finance), type(uint256).max);
    }

    // ---------------------------------------------------------------- helpers

    function _request(uint256 id, uint256 principal, uint256 due) internal returns (uint256 loanId) {
        vm.prank(miner);
        loanId = finance.requestLoan(id, financier, usdc, principal, due, TERM, H);
    }

    function _funded(uint256 principal, uint256 due) internal returns (uint256 id, uint256 loanId) {
        id = _inspected(10_000);
        loanId = _request(id, principal, due);
        vm.prank(financier);
        finance.fundLoan(loanId, true);
    }

    function _lastEvent(uint256 id) internal view returns (PassportLib.PassportEvent memory) {
        return passport.getEvents(id, passport.eventCount(id) - 1, 1)[0];
    }

    // ================================================================ roles

    function test_Roles_FinancierAndInsurerAreParticipants() public view {
        assertTrue(registry.isAuthorized(financier, Actions.FINANCE_LOT));
        assertTrue(registry.isAuthorized(insurer, Actions.INSURE_LOT));
        assertFalse(registry.isAuthorized(miner, Actions.FINANCE_LOT));
        assertFalse(registry.isAuthorized(financier, Actions.OWN_LOT), "lenders never take title");
    }

    // ================================================================ requesting

    function testFuzz_FundLoan_RecordsLien_PaysBorrower(uint256 principal, uint256 interest) public {
        principal = bound(principal, 1, 500_000e6);
        interest = bound(interest, 0, 100_000e6);
        uint256 id = _inspected(10_000);
        uint256 loanId = _request(id, principal, principal + interest);
        uint256 before = usdc.balanceOf(miner);

        vm.prank(financier);
        finance.fundLoan(loanId, true);

        assertEq(usdc.balanceOf(miner) - before, principal, "principal disbursed to the borrower");
        assertEq(finance.activeLoanOf(id), loanId);
        assertEq(finance.outstandingOf(loanId), principal + interest);
        LotFinanceLib.Loan memory l = finance.getLoan(loanId);
        assertEq(uint8(l.status), uint8(LotFinanceLib.LoanStatus.Active));
        assertEq(l.dueDate, block.timestamp + TERM);
        PassportLib.PassportEvent memory e = _lastEvent(id);
        assertEq(uint8(e.eventType), uint8(PassportLib.EventType.Lien));
        assertEq(e.actor, financier);
    }

    function test_FundLoan_OffChainDisbursement_MovesNoTokens() public {
        uint256 id = _inspected(10_000);
        uint256 loanId = _request(id, PRINCIPAL, DUE);
        uint256 before = usdc.balanceOf(financier);
        vm.prank(financier);
        finance.fundLoan(loanId, false);
        assertEq(usdc.balanceOf(financier), before);
        assertEq(finance.activeLoanOf(id), loanId);
    }

    function test_RequestLoan_Validation() public {
        uint256 id = _inspected(10_000);
        uint256 raw = _register(1_000);

        vm.prank(outsider);
        vm.expectRevert(abi.encodeWithSelector(LotFinanceLib.LotFinance__NotLotHolder.selector, id, outsider));
        finance.requestLoan(id, financier, usdc, PRINCIPAL, DUE, TERM, H);

        vm.startPrank(miner);
        vm.expectRevert(
            abi.encodeWithSelector(LotFinanceLib.LotFinance__Unauthorized.selector, buyer, Actions.FINANCE_LOT)
        );
        finance.requestLoan(id, buyer, usdc, PRINCIPAL, DUE, TERM, H);

        vm.expectRevert(LotFinanceLib.LotFinance__InvalidTerms.selector);
        finance.requestLoan(id, financier, usdc, PRINCIPAL, PRINCIPAL - 1, TERM, H); // due below principal
        uint32 tooLong = finance.MAX_TERM() + 1;
        vm.expectRevert(LotFinanceLib.LotFinance__InvalidTerms.selector);
        finance.requestLoan(id, financier, usdc, PRINCIPAL, DUE, tooLong, H);
        vm.expectRevert(LotFinanceLib.LotFinance__InvalidTerms.selector);
        finance.requestLoan(id, financier, usdc, 0, DUE, TERM, H);

        vm.expectRevert(abi.encodeWithSelector(LotFinanceLib.LotFinance__TokenNotAllowed.selector, IERC20(outsider)));
        finance.requestLoan(id, financier, IERC20(outsider), PRINCIPAL, DUE, TERM, H);

        vm.expectRevert(abi.encodeWithSelector(LotFinanceLib.LotFinance__InvalidCollateral.selector, raw));
        finance.requestLoan(raw, financier, usdc, PRINCIPAL, DUE, TERM, H); // not inspected
        vm.stopPrank();
    }

    function test_RequestLoan_LenderMustBeIndependent() public {
        address inHouse = makeAddr("in-house-lender");
        vm.prank(admin);
        registry.onboard(inHouse, Roles.FINANCIER, "org-miner", H, 0);
        uint256 id = _inspected(10_000);
        vm.prank(miner);
        vm.expectRevert(abi.encodeWithSelector(LotFinanceLib.LotFinance__NotIndependent.selector, inHouse));
        finance.requestLoan(id, inHouse, usdc, PRINCIPAL, DUE, TERM, H);
    }

    function test_OneLienPerLot() public {
        (uint256 id,) = _funded(PRINCIPAL, DUE);
        vm.prank(miner);
        vm.expectRevert(abi.encodeWithSelector(LotFinanceLib.LotFinance__InvalidCollateral.selector, id));
        finance.requestLoan(id, financier, usdc, PRINCIPAL, DUE, TERM, H);
    }

    function test_FundLoan_RechecksCollateral() public {
        uint256 id = _inspected(10_000);
        uint256 first = _request(id, PRINCIPAL, DUE);
        uint256 second = _request(id, PRINCIPAL, DUE);
        vm.prank(financier);
        finance.fundLoan(first, true);
        vm.prank(financier);
        vm.expectRevert(abi.encodeWithSelector(LotFinanceLib.LotFinance__InvalidCollateral.selector, id));
        finance.fundLoan(second, true); // the lot is already collateral

        uint256 other = _inspected(10_000);
        uint256 loanId = _request(other, PRINCIPAL, DUE);
        vm.prank(regulator);
        passport.freezeLot(other, H);
        vm.prank(financier);
        vm.expectRevert(abi.encodeWithSelector(LotFinanceLib.LotFinance__InvalidCollateral.selector, other));
        finance.fundLoan(loanId, true);
    }

    function test_DeclineAndCancel_OnlyTheRightParty() public {
        uint256 id = _inspected(10_000);
        uint256 a = _request(id, PRINCIPAL, DUE);
        uint256 b = _request(id, PRINCIPAL, DUE);

        vm.prank(miner);
        vm.expectRevert(abi.encodeWithSelector(LotFinanceLib.LotFinance__NotParty.selector, miner));
        finance.declineLoan(a);
        vm.prank(financier);
        finance.declineLoan(a);
        vm.prank(financier);
        vm.expectRevert(abi.encodeWithSelector(LotFinanceLib.LotFinance__InvalidLoanStatus.selector, a));
        finance.fundLoan(a, true);

        vm.prank(financier);
        vm.expectRevert(abi.encodeWithSelector(LotFinanceLib.LotFinance__NotParty.selector, financier));
        finance.cancelLoanRequest(b);
        vm.prank(miner);
        finance.cancelLoanRequest(b);
        assertEq(uint8(finance.getLoan(b).status), uint8(LotFinanceLib.LoanStatus.Cancelled));
    }

    // ================================================================ the lien

    function test_EncumberedLot_CannotTransfer() public {
        (uint256 id,) = _funded(PRINCIPAL, DUE);
        vm.prank(miner);
        vm.expectRevert(abi.encodeWithSelector(PassportLib.LotPassport__LotEncumbered.selector, id));
        passport.transferFrom(miner, buyer, id);
    }

    function test_EncumberedLot_CannotBeProcessed() public {
        (uint256 id,) = _funded(PRINCIPAL, DUE);
        _moveCustody(id, miner, refinery); // custody still moves: storage and transport go on
        vm.prank(miner);
        passport.approve(refinery, id);
        uint256[] memory inputs = new uint256[](1);
        inputs[0] = id;
        PassportLib.LotOutput[] memory outs = new PassportLib.LotOutput[](1);
        outs[0] = PassportLib.LotOutput("ingot", TIN, 900, H);
        vm.prank(refinery);
        vm.expectRevert(abi.encodeWithSelector(PassportLib.LotPassport__LotEncumbered.selector, id));
        passport.processLots(inputs, outs, H);
    }

    function test_EncumberedLot_OnlyEscrowMayLock() public {
        (uint256 id,) = _funded(PRINCIPAL, DUE);
        vm.prank(miner);
        passport.setApprovalForAll(address(b2b), true);
        vm.prank(address(b2b));
        vm.expectRevert(abi.encodeWithSelector(PassportLib.LotPassport__LotEncumbered.selector, id));
        passport.lockForEscrow(id);
    }

    function test_RecordFinancing_OnlyFinanceContract() public {
        uint256 id = _inspected(10_000);
        vm.prank(miner);
        vm.expectRevert(abi.encodeWithSelector(PassportLib.LotPassport__NotFinancing.selector, miner));
        passport.recordFinancing(id, PassportLib.EventType.LienReleased, miner, H);

        vm.prank(address(finance));
        vm.expectRevert(
            abi.encodeWithSelector(
                PassportLib.LotPassport__InvalidFinanceEvent.selector, PassportLib.EventType.Inspection
            )
        );
        passport.recordFinancing(id, PassportLib.EventType.Inspection, miner, H);
    }

    function test_SetFinancing_OnlyOnce() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(PassportLib.LotPassport__FinancingAlreadySet.selector, address(finance)));
        passport.setFinancing(outsider);
    }

    // ================================================================ repaying

    function testFuzz_Repay_InParts_ReleasesWhenPaid(uint256 first) public {
        (uint256 id, uint256 loanId) = _funded(PRINCIPAL, DUE);
        first = bound(first, 1, DUE - 1);
        uint256 lenderBefore = usdc.balanceOf(financier);

        vm.prank(miner);
        finance.repay(loanId, first);
        assertEq(finance.outstandingOf(loanId), DUE - first);
        assertEq(finance.activeLoanOf(id), loanId, "still encumbered");

        vm.prank(miner);
        finance.repay(loanId, type(uint256).max); // capped at what is owed
        assertEq(usdc.balanceOf(financier) - lenderBefore, DUE);
        assertEq(uint8(finance.getLoan(loanId).status), uint8(LotFinanceLib.LoanStatus.Repaid));
        assertEq(finance.activeLoanOf(id), 0);
        assertEq(uint8(_lastEvent(id).eventType), uint8(PassportLib.EventType.LienReleased));

        vm.prank(miner);
        passport.transferFrom(miner, buyer, id); // free again
        assertEq(passport.ownerOf(id), buyer);
    }

    function test_Repay_WorksWhilePaused() public {
        (, uint256 loanId) = _funded(PRINCIPAL, DUE);
        vm.prank(admin);
        finance.pause();
        vm.prank(miner);
        finance.repay(loanId, DUE);
        assertEq(uint8(finance.getLoan(loanId).status), uint8(LotFinanceLib.LoanStatus.Repaid));
    }

    function test_ReleaseLien_OnlyLender() public {
        (uint256 id, uint256 loanId) = _funded(PRINCIPAL, DUE);
        vm.prank(miner);
        vm.expectRevert(abi.encodeWithSelector(LotFinanceLib.LotFinance__NotParty.selector, miner));
        finance.releaseLien(loanId, H);
        vm.prank(financier);
        finance.releaseLien(loanId, keccak256("bank-receipt"));
        assertEq(uint8(finance.getLoan(loanId).status), uint8(LotFinanceLib.LoanStatus.Released));
        assertEq(finance.activeLoanOf(id), 0);
    }

    function test_IsOverdue() public {
        (, uint256 loanId) = _funded(PRINCIPAL, DUE);
        assertFalse(finance.isOverdue(loanId));
        vm.warp(block.timestamp + TERM + 1);
        assertTrue(finance.isOverdue(loanId));
    }

    // ================================================================ selling the collateral

    function test_Sale_PaysFinancierFirst_ThenTitlePasses() public {
        (uint256 id, uint256 loanId) = _funded(PRINCIPAL, DUE);
        vm.prank(miner);
        uint256 listingId = market.createListing(_listingParams(id, _fixed(), PRICE));
        uint256 orderId = _buy(buyer, listingId);
        _deliver(id, miner, buyer);
        vm.prank(buyer);
        escrow.releaseFunds(orderId);

        uint256 fee = (PRICE * FEE_BPS) / 10_000;
        assertEq(escrow.claimable(usdc, financier), DUE, "financier repaid from the sale");
        assertEq(escrow.claimable(usdc, miner), PRICE - fee - DUE, "seller gets the rest");
        assertEq(passport.ownerOf(id), buyer);
        assertEq(uint8(finance.getLoan(loanId).status), uint8(LotFinanceLib.LoanStatus.SettledFromSale));
        assertEq(finance.activeLoanOf(id), 0);
    }

    function test_Sale_MustCoverTheLien() public {
        (uint256 id,) = _funded(PRINCIPAL, PRICE); // proceeds after the 1% fee fall short of the debt
        vm.prank(miner);
        uint256 listingId = market.createListing(_listingParams(id, _fixed(), PRICE));
        vm.prank(buyer);
        vm.expectRevert(abi.encodeWithSelector(LotFinanceLib.LotFinance__SaleDoesNotCoverLien.selector, id, PRICE));
        market.buyListing(listingId, type(uint256).max);
    }

    function test_Sale_MustBeInTheLoanToken() public {
        uint256 id = _inspected(10_000);
        vm.prank(miner);
        uint256 loanId = finance.requestLoan(id, financier, rwfCoin, 1e18, 1e18, TERM, H);
        vm.prank(financier);
        finance.fundLoan(loanId, false);
        vm.prank(miner);
        uint256 listingId = market.createListing(_listingParams(id, _fixed(), PRICE)); // priced in USDC
        vm.prank(buyer);
        vm.expectRevert(abi.encodeWithSelector(LotFinanceLib.LotFinance__SaleDoesNotCoverLien.selector, id, 1e18));
        market.buyListing(listingId, type(uint256).max);
    }

    function test_Refund_KeepsTheLien() public {
        (uint256 id, uint256 loanId) = _funded(PRINCIPAL, DUE);
        vm.prank(miner);
        uint256 listingId = market.createListing(_listingParams(id, _fixed(), PRICE));
        uint256 orderId = _buy(buyer, listingId);
        vm.warp(block.timestamp + 14 days + 1);
        vm.prank(buyer);
        escrow.cancelForNonDelivery(orderId);

        assertEq(passport.ownerOf(id), miner);
        assertEq(finance.activeLoanOf(id), loanId, "the collateral is still pledged");
        vm.prank(miner);
        vm.expectRevert(abi.encodeWithSelector(PassportLib.LotPassport__LotEncumbered.selector, id));
        passport.transferFrom(miner, buyer, id);
    }

    function test_RepayFromSale_OnlyEscrow() public {
        (uint256 id,) = _funded(PRINCIPAL, DUE);
        vm.prank(miner);
        vm.expectRevert(abi.encodeWithSelector(LotFinanceLib.LotFinance__NotEscrow.selector, miner));
        finance.repayFromSale(id, usdc, PRICE);
    }

    // ================================================================ insurance

    function test_Cover_RequestBind_RecordedOnPassport() public {
        uint256 id = _inspected(10_000);
        vm.prank(miner);
        uint256 coverId = finance.requestCover(id, insurer, keccak256("transit cover, USD 50,000"));
        uint64 until = uint64(block.timestamp + 30 days);
        vm.prank(insurer);
        finance.bindCover(coverId, keccak256("policy"), until);

        assertTrue(finance.isCovered(coverId));
        PassportLib.PassportEvent memory e = _lastEvent(id);
        assertEq(uint8(e.eventType), uint8(PassportLib.EventType.Insured));
        assertEq(e.actor, insurer);
        assertEq(e.dataHash, keccak256("policy"));
        vm.warp(until + 1);
        assertFalse(finance.isCovered(coverId));
    }

    function test_Cover_CustodianMayRequest() public {
        uint256 id = _inspected(10_000);
        _moveCustody(id, miner, warehouse);
        vm.prank(warehouse);
        uint256 coverId = finance.requestCover(id, insurer, H);
        assertEq(finance.getCover(coverId).holder, warehouse);
    }

    function test_Cover_Validation() public {
        uint256 id = _inspected(10_000);
        vm.prank(outsider);
        vm.expectRevert(abi.encodeWithSelector(LotFinanceLib.LotFinance__NotLotHolder.selector, id, outsider));
        finance.requestCover(id, insurer, H);
        vm.prank(miner);
        vm.expectRevert(
            abi.encodeWithSelector(LotFinanceLib.LotFinance__Unauthorized.selector, financier, Actions.INSURE_LOT)
        );
        finance.requestCover(id, financier, H);

        vm.prank(miner);
        uint256 coverId = finance.requestCover(id, insurer, H);
        vm.prank(outsider);
        vm.expectRevert(abi.encodeWithSelector(LotFinanceLib.LotFinance__NotParty.selector, outsider));
        finance.bindCover(coverId, H, uint64(block.timestamp + 1 days));
        vm.startPrank(insurer);
        vm.expectRevert(
            abi.encodeWithSelector(LotFinanceLib.LotFinance__InvalidCoverPeriod.selector, uint64(block.timestamp))
        );
        finance.bindCover(coverId, H, uint64(block.timestamp));
        uint64 tooLong = uint64(block.timestamp + finance.MAX_COVER_PERIOD() + 1);
        vm.expectRevert(abi.encodeWithSelector(LotFinanceLib.LotFinance__InvalidCoverPeriod.selector, tooLong));
        finance.bindCover(coverId, H, tooLong);
        finance.closeCoverRequest(coverId); // declined
        vm.stopPrank();
        assertEq(uint8(finance.getCover(coverId).status), uint8(LotFinanceLib.CoverStatus.Declined));

        vm.prank(outsider);
        vm.expectRevert(abi.encodeWithSelector(LotFinanceLib.LotFinance__InvalidCoverStatus.selector, coverId));
        finance.closeCoverRequest(coverId);
    }

    // ================================================================ pause

    function test_Pause_BlocksNewBusinessOnly() public {
        (, uint256 loanId) = _funded(PRINCIPAL, DUE);
        uint256 id = _inspected(10_000);
        vm.prank(miner);
        vm.expectRevert(abi.encodeWithSelector(LotFinanceLib.LotFinance__NotRegistryAdmin.selector, miner));
        finance.pause();
        vm.prank(admin);
        finance.pause();

        vm.prank(miner);
        vm.expectRevert(bytes4(keccak256("EnforcedPause()")));
        finance.requestLoan(id, financier, usdc, PRINCIPAL, DUE, TERM, H);
        vm.prank(financier);
        finance.releaseLien(loanId, H); // releases always work
    }

    function test_EscrowOrderUnaffectedWithoutLien() public {
        (uint256 id, uint256 orderId) = _acceptedOrder();
        _deliver(id, miner, buyer);
        vm.prank(buyer);
        escrow.releaseFunds(orderId);
        assertEq(uint8(escrow.getOrder(orderId).status), uint8(EscrowLib.OrderStatus.Settled));
        assertEq(escrow.claimable(usdc, financier), 0);
    }
}
