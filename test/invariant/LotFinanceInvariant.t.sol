// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MineNetFixture} from "test/utils/MineNetFixture.sol";
import {LotPassport} from "src/traceability/LotPassport.sol";
import {LotFinance} from "src/finance/LotFinance.sol";
import {LotFinanceLib} from "src/finance/libraries/LotFinanceLib.sol";
import {Marketplace} from "src/trade/Marketplace.sol";
import {EscrowManager} from "src/trade/EscrowManager.sol";
import {MineSiteRegistry} from "src/compliance/MineSiteRegistry.sol";
import {MarketplaceLib} from "src/trade/libraries/MarketplaceLib.sol";

/**
 * @title FinanceHandler
 * @notice Drives random sequences of loans on a pool of inspected lots (fund, repay in parts, release, sell the
 * collateral through escrow, try to move it directly) and of extraction and lot registration at one site.
 * @dev State-aware: each action picks a lot or loan in the state it needs. Expected reverts are swallowed, except
 * that a direct transfer of a lot under an active lien succeeding is recorded as a violation.
 */
contract FinanceHandler is Test {
    struct Deps {
        LotPassport passport;
        LotFinance finance;
        Marketplace market;
        EscrowManager escrow;
        MineSiteRegistry sites;
        IERC20 token;
    }

    LotPassport internal immutable passport;
    LotFinance internal immutable finance;
    Marketplace internal immutable market;
    EscrowManager internal immutable escrow;
    MineSiteRegistry internal immutable sites;
    IERC20 internal immutable token;
    address internal immutable borrower;
    address internal immutable lender;
    address internal immutable buyer;
    uint256 internal immutable site;
    bytes32 public constant GOLD = keccak256("GOLD");
    uint256 public constant PRICE = 50_000e6;

    uint256[] public lots;
    uint256[] public loans;
    uint256 internal nonce;
    /// A direct transfer of a lot under an active lien went through (must stay false).
    bool public encumberedTransferSucceeded;
    mapping(bytes32 action => uint256) public hits;

    constructor(Deps memory d, address[3] memory actors, uint256 site_, uint256[] memory lots_) {
        passport = d.passport;
        finance = d.finance;
        market = d.market;
        escrow = d.escrow;
        sites = d.sites;
        token = d.token;
        borrower = actors[0];
        lender = actors[1];
        buyer = actors[2];
        site = site_;
        lots = lots_;
    }

    function loanCount() external view returns (uint256) {
        return loans.length;
    }

    function lotCount() external view returns (uint256) {
        return lots.length;
    }

    // ---------------------------------------------------------------- loans

    function fund(uint256 lotSeed, uint256 principal, uint256 interest) external {
        uint256 id = lots[lotSeed % lots.length];
        principal = bound(principal, 1, 30_000e6);
        interest = bound(interest, 0, 10_000e6);
        vm.prank(borrower);
        try finance.requestLoan(
            id, lender, token, principal, principal + interest, 90 days, keccak256("terms")
        ) returns (
            uint256 loanId
        ) {
            vm.prank(lender);
            try finance.fundLoan(loanId, false) {
                loans.push(loanId);
                ++hits["fund"];
            } catch {}
        } catch {}
    }

    function repay(uint256 loanSeed, uint256 amount) external {
        if (loans.length == 0) return;
        uint256 loanId = loans[loanSeed % loans.length];
        amount = bound(amount, 1, 50_000e6);
        vm.prank(borrower);
        try finance.repay(loanId, amount) {
            ++hits["repay"];
        } catch {}
    }

    function release(uint256 loanSeed) external {
        if (loans.length == 0) return;
        uint256 loanId = loans[loanSeed % loans.length];
        vm.prank(lender);
        try finance.releaseLien(loanId, keccak256("receipt")) {
            ++hits["release"];
        } catch {}
    }

    /// Sells a lot through the marketplace: list, buy, hand custody to the buyer, buyer releases the funds.
    function sell(uint256 lotSeed) external {
        uint256 id = lots[lotSeed % lots.length];
        if (passport.ownerOf(id) != borrower) return;
        vm.prank(borrower);
        try market.createListing(
            MarketplaceLib.ListingParams({
                tokenId: id,
                paymentToken: token,
                priceCurrency: "USD",
                priceModel: MarketplaceLib.PriceModel.FixedTotal,
                price: PRICE,
                deliveryWindow: 14 days,
                expiresAt: uint64(block.timestamp + 30 days),
                termsHash: keccak256("listing")
            })
        ) returns (
            uint256 listingId
        ) {
            vm.prank(buyer);
            try market.buyListing(listingId, type(uint256).max) returns (uint256 orderId) {
                vm.prank(borrower);
                passport.initiateCustodyTransfer(id, buyer, keccak256("handover"));
                vm.prank(buyer);
                passport.confirmCustodyTransfer(id, keccak256("receipt"));
                vm.prank(buyer);
                escrow.releaseFunds(orderId);
                ++hits["sell"];
            } catch {
                vm.prank(borrower);
                market.delist(listingId);
            }
        } catch {}
    }

    /// The owner tries to move the lot directly; must fail while it is collateral.
    function transfer(uint256 lotSeed) external {
        uint256 id = lots[lotSeed % lots.length];
        address owner = passport.ownerOf(id);
        if (owner != borrower) return;
        bool encumbered = finance.activeLoanOf(id) != 0;
        vm.prank(borrower);
        try passport.transferFrom(borrower, buyer, id) {
            if (encumbered) encumberedTransferSucceeded = true;
            ++hits["transfer"];
        } catch {}
    }

    // ---------------------------------------------------------------- production

    function extract(uint128 qty) external {
        qty = uint128(bound(qty, 1, 1e9));
        vm.prank(borrower);
        sites.recordExtraction(site, GOLD, qty, keccak256("shift log"));
        ++hits["extract"];
    }

    function register(uint128 qty) external {
        qty = uint128(bound(qty, 1, 2e9));
        vm.prank(borrower);
        try passport.registerLot(keccak256(abi.encode("inv-gold", ++nonce)), GOLD, qty, site, keccak256("docs")) {
            ++hits["register"];
        } catch {}
    }
}

/**
 * @title LotFinanceInvariantTest
 * @notice Stateful invariants of liens and the production ledger: collateral never moves while pledged, loan and
 * lien state agree, the financier receives exactly what loans record as repaid, and no site lots more than it
 * extracted.
 */
contract LotFinanceInvariantTest is MineNetFixture {
    FinanceHandler internal handler;
    uint256 internal lenderStart;

    function setUp() public override {
        super.setUp();
        usdc.mint(miner, 10_000_000e6);
        vm.prank(miner);
        usdc.approve(address(finance), type(uint256).max);
        usdc.mint(buyer, 100_000_000e6);

        uint256[] memory pool = new uint256[](6);
        for (uint256 i; i < pool.length; ++i) {
            pool[i] = _inspected(10_000);
        }
        handler = new FinanceHandler(
            FinanceHandler.Deps(passport, finance, market, escrow, sites, usdc), [miner, financier, buyer], site, pool
        );
        lenderStart = usdc.balanceOf(financier);
        targetContract(address(handler));
    }

    /**
     * @notice A lot under an active lien is never transferred directly.
     */
    function invariant_PledgedLotsNeverMoveDirectly() public view {
        assertFalse(handler.encumberedTransferSucceeded());
    }

    /**
     * @notice A loan is active exactly when it is the lot's active loan, its lot is still the borrower's, and it
     * never records more repaid than owed.
     */
    function invariant_LoanAndLienAgree() public view {
        for (uint256 i; i < handler.loanCount(); ++i) {
            uint256 loanId = handler.loans(i);
            LotFinanceLib.Loan memory l = finance.getLoan(loanId);
            bool active = l.status == LotFinanceLib.LoanStatus.Active;
            assertEq(finance.activeLoanOf(l.tokenId) == loanId, active);
            if (active) assertEq(passport.ownerOf(l.tokenId), l.borrower, "collateral stays with the borrower");
            assertLe(l.repaid, l.amountDue);
        }
    }

    /**
     * @notice The financier received (on-chain or as escrow credit) exactly what the loans record as repaid.
     */
    function invariant_LenderReceiptsMatchRepayments() public view {
        uint256 repaid;
        for (uint256 i; i < handler.loanCount(); ++i) {
            repaid += finance.getLoan(handler.loans(i)).repaid;
        }
        assertEq(usdc.balanceOf(financier) - lenderStart + escrow.claimable(usdc, financier), repaid);
    }

    /**
     * @notice A site never lots more of a mineral than it recorded extracting.
     */
    function invariant_LottedNeverExceedsExtracted() public view {
        bytes32 gold = handler.GOLD();
        assertLe(sites.productionOf(site, gold).lotted, sites.productionOf(site, gold).extracted);
    }

    /**
     * @notice Logs how often each action succeeded, to confirm the fuzzer reaches liens, repayments and sales.
     */
    function invariant_callSummary() public view {
        console.log("fund", handler.hits("fund"), "repay", handler.hits("repay"));
        console.log("release", handler.hits("release"), "sell", handler.hits("sell"));
        console.log("transfer", handler.hits("transfer"), "register", handler.hits("register"));
    }
}
