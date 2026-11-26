// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MineNetFixture} from "test/utils/MineNetFixture.sol";
import {B2B} from "src/b2b/B2B.sol";
import {B2BLib} from "src/b2b/libraries/B2BLib.sol";
import {LotPassport} from "src/traceability/LotPassport.sol";
import {InspectionRegistry} from "src/compliance/InspectionRegistry.sol";

/**
 * @title SupplyHandler
 * @notice Drives random sequences of buyer and seller actions against one escrowed supply agreement: funding,
 * dispatching real lot passports, custody handover, acceptance, release, disputes and settlements, misses, defaults
 * and (rarely) termination.
 * @dev State-aware: each action targets a delivery that is in the state it needs, picked at random among those, so
 * the fuzzer reaches every part of the lifecycle instead of bouncing off reverts. Expected reverts are swallowed.
 */
contract SupplyHandler is Test {
    B2B internal immutable b2b;
    LotPassport internal immutable passport;
    InspectionRegistry internal immutable inspections;
    IERC20 internal immutable token;
    address internal immutable seller;
    address internal immutable buyer;
    address internal immutable inspector;
    uint256 internal immutable site;
    bytes32 internal immutable mineral;
    uint256 public immutable agreementId;
    uint32 internal immutable total;
    uint128 internal immutable quantity;

    uint256 internal nonce;
    /// Handler calls so far in this campaign.
    uint256 public calls;
    /// Every lot ever committed, to check the commitment map.
    uint256[] public lotsCreated;
    /// Successful calls per action, to confirm the fuzzer reaches every state.
    mapping(bytes32 action => uint256) public hits;

    constructor(
        B2B b2b_,
        LotPassport passport_,
        InspectionRegistry inspections_,
        IERC20 token_,
        address[3] memory actors,
        uint256 site_,
        bytes32 mineral_,
        uint256 agreementId_
    ) {
        b2b = b2b_;
        passport = passport_;
        inspections = inspections_;
        token = token_;
        seller = actors[0];
        buyer = actors[1];
        inspector = actors[2];
        site = site_;
        mineral = mineral_;
        agreementId = agreementId_;
        B2BLib.Agreement memory a = b2b_.getAgreement(agreementId_);
        total = a.supply.totalDeliveries;
        quantity = a.supply.quantityPerDelivery;
    }

    modifier counted() {
        ++calls;
        _;
    }

    function lotsCreatedCount() external view returns (uint256) {
        return lotsCreated.length;
    }

    /*//////////////////////////////////////////////////////////////
                                 ACTIONS
    //////////////////////////////////////////////////////////////*/

    function fund(uint256 seed) external counted {
        (bool ok, uint256 index) = _find(B2BLib.DeliveryStatus.Scheduled, seed);
        if (!ok) return;
        vm.prank(buyer);
        try b2b.fundDelivery(agreementId, index) {
            hits["fund"]++;
        } catch {}
    }

    /// The seller registers an inspected lot weighing within +/-2% of the quantity and dispatches it.
    function dispatch(uint256 seed, uint256 weightSeed) external counted {
        (bool ok, uint256 index) = _find(B2BLib.DeliveryStatus.Funded, seed);
        if (!ok) return;
        uint128 weight = uint128(bound(weightSeed, quantity * 98 / 100, quantity * 102 / 100));
        vm.prank(seller);
        uint256 tokenId =
            passport.registerLot(keccak256(abi.encode("inv-lot", ++nonce)), mineral, weight, site, keccak256("docs"));
        vm.prank(seller); // the platform assigns the inspector; the seller never chooses it
        address assigned = inspections.requestInspection(tokenId);
        vm.prank(assigned);
        passport.submitInspection(tokenId, true, keccak256("report"));
        uint256[] memory ids = new uint256[](1);
        ids[0] = tokenId;
        vm.prank(seller);
        try b2b.dispatchDelivery(agreementId, index, ids, 0, keccak256("note")) {
            lotsCreated.push(tokenId);
            hits["dispatch"]++;
        } catch {}
    }

    /// Hands the lots of a dispatched delivery over to the buyer and confirms arrival.
    function arrive(uint256 seed) external counted {
        (bool ok, uint256 index) = _find(B2BLib.DeliveryStatus.Dispatched, seed);
        if (!ok) return;
        uint256[] memory lots = b2b.lotsOf(agreementId, index);
        for (uint256 i; i < lots.length; ++i) {
            if (passport.custodianOf(lots[i]) != seller) continue;
            vm.prank(seller);
            passport.initiateCustodyTransfer(lots[i], buyer, keccak256("handover"));
            vm.prank(buyer);
            passport.confirmCustodyTransfer(lots[i], keccak256("receipt"));
        }
        try b2b.confirmArrival(agreementId, index) {
            hits["arrive"]++;
        } catch {}
    }

    function accept(uint256 seed) external counted {
        (bool ok, uint256 index) = _find(B2BLib.DeliveryStatus.Arrived, seed);
        if (!ok) return;
        vm.prank(buyer);
        try b2b.acceptDelivery(agreementId, index) {
            hits["accept"]++;
        } catch {}
    }

    function release(uint256 seed) external counted {
        (bool ok, uint256 index) = _find(B2BLib.DeliveryStatus.Arrived, seed);
        if (!ok) return;
        vm.warp(block.timestamp + 3 days + 1);
        try b2b.releaseAfterReview(agreementId, index) {
            hits["release"]++;
        } catch {}
    }

    function reject(uint256 seed) external counted {
        (bool ok, uint256 index) = _find(B2BLib.DeliveryStatus.Arrived, seed);
        if (!ok) return;
        vm.prank(buyer);
        try b2b.rejectDelivery(agreementId, index, keccak256("reason")) {
            hits["reject"]++;
        } catch {}
    }

    /// Both sides make offers on a disputed delivery; they settle when the buyer offers at least the seller's ask.
    function offer(uint256 seed, uint256 ask, uint256 bid) external counted {
        (bool ok, uint256 index) = _find(B2BLib.DeliveryStatus.Disputed, seed);
        if (!ok) return;
        B2BLib.Delivery memory d = b2b.getDelivery(agreementId, index);
        uint256 max = uint256(d.deliveredQty) * d.pricePerKg / 1_000;
        vm.prank(seller);
        try b2b.offerSettlement(agreementId, index, bound(ask, 0, max)) {} catch {}
        vm.prank(buyer);
        try b2b.offerSettlement(agreementId, index, bound(bid, 0, max)) {
            hits["offer"]++;
        } catch {}
    }

    function closeMissed(uint256 seed, bool bySeller) external counted {
        (bool ok, uint256 index) = _find(B2BLib.DeliveryStatus.Funded, seed);
        if (!ok) return;
        if (!bySeller) vm.warp(uint256(b2b.getDelivery(agreementId, index).dueAt) + 30 days + 1);
        vm.prank(bySeller ? seller : buyer);
        try b2b.closeMissed(agreementId, index) {
            hits["closeMissed"]++;
        } catch {}
    }

    function markDefaulted(uint256 seed) external counted {
        (bool ok, uint256 index) = _find(B2BLib.DeliveryStatus.Scheduled, seed);
        if (!ok) return;
        vm.prank(seller);
        try b2b.markDefaulted(agreementId, index) {
            hits["markDefaulted"]++;
        } catch {}
    }

    /// Mutual termination, only late in a campaign so most of it exercises the full delivery lifecycle.
    function terminate(uint256) external counted {
        if (calls < 40) return;
        vm.prank(buyer);
        try b2b.requestTermination(agreementId, keccak256("end")) {} catch {}
        vm.prank(seller);
        try b2b.confirmTermination(agreementId) {
            hits["terminate"]++;
        } catch {}
    }

    function withdraw(bool bySeller) external counted {
        vm.prank(bySeller ? seller : buyer);
        try b2b.withdraw(token) {
            hits["withdraw"]++;
        } catch {}
    }

    function warp(uint256 secondsAhead) external counted {
        vm.warp(block.timestamp + bound(secondsAhead, 1 hours, 10 days));
    }

    /*//////////////////////////////////////////////////////////////
                                 HELPERS
    //////////////////////////////////////////////////////////////*/

    /// A random delivery currently in `status`, if any.
    function _find(B2BLib.DeliveryStatus status, uint256 seed) internal view returns (bool found, uint256 index) {
        uint256 start = seed % total;
        for (uint256 k; k < total; ++k) {
            index = (start + k) % total;
            if (b2b.getDelivery(agreementId, index).status == status) return (true, index);
        }
    }
}

/**
 * @title B2BInvariantTest
 * @notice Stateful invariants of {B2B}: exact escrow solvency, consistent delivery accounting, lot commitment and
 * title transfer.
 */
contract B2BInvariantTest is MineNetFixture {
    SupplyHandler internal handler;
    uint256 internal id;

    function setUp() public override {
        super.setUp();
        usdc.mint(refinery, 1_000_000_000e6);
        vm.prank(refinery);
        usdc.approve(address(b2b), type(uint256).max);
        vm.prank(miner);
        passport.setApprovalForAll(address(b2b), true);

        B2BLib.Terms memory t;
        t.seller = B2BLib.Side.Proposer;
        t.supply = B2BLib.SupplyTerms({
            mineralType: TIN,
            quantityPerDelivery: 1_000_000,
            quantityToleranceBps: 200,
            minGradeBps: 0,
            pricePerKg: 20e6,
            totalDeliveries: 8,
            deliveryInterval: 7 days,
            firstDeliveryOffset: 7 days
        });
        t.paymentToken = usdc;
        t.reviewPeriod = 3 days;
        t.proposalExpiresAt = uint64(block.timestamp + 7 days);
        t.termsHash = keccak256("offtake");
        vm.prank(miner);
        id = b2b.propose(refinery, t);
        vm.prank(refinery);
        b2b.sign(id, 1);

        handler = new SupplyHandler(b2b, passport, inspections, usdc, [miner, refinery, inspector], site, TIN, id);
        targetContract(address(handler));
    }

    /**
     * @notice The contract holds exactly the escrow of open deliveries plus every credited balance.
     */
    function invariant_EscrowSolvencyIsExact() public view {
        uint256 escrowed;
        uint32 total = b2b.getAgreement(id).supply.totalDeliveries;
        for (uint256 i; i < total; ++i) {
            B2BLib.Delivery memory d = b2b.getDelivery(id, i);
            if (
                d.status == B2BLib.DeliveryStatus.Funded || d.status == B2BLib.DeliveryStatus.Dispatched
                    || d.status == B2BLib.DeliveryStatus.Arrived || d.status == B2BLib.DeliveryStatus.Disputed
            ) escrowed += d.goodsFunded + d.feeFunded;
        }
        uint256 credited = b2b.claimable(usdc, miner) + b2b.claimable(usdc, refinery);
        assertEq(usdc.balanceOf(address(b2b)), escrowed + credited);
    }

    /**
     * @notice The agreement's counters always match the deliveries' actual statuses.
     */
    function invariant_ProgressMatchesDeliveries() public view {
        B2BLib.Agreement memory a = b2b.getAgreement(id);
        uint32 funded;
        uint32 inFlight;
        uint32 finals;
        for (uint256 i; i < a.supply.totalDeliveries; ++i) {
            B2BLib.DeliveryStatus s = b2b.getDelivery(id, i).status;
            if (s == B2BLib.DeliveryStatus.Funded) {
                ++funded;
            } else if (
                s == B2BLib.DeliveryStatus.Dispatched || s == B2BLib.DeliveryStatus.Arrived
                    || s == B2BLib.DeliveryStatus.Disputed
            ) {
                ++inFlight;
            } else if (s != B2BLib.DeliveryStatus.Scheduled) {
                ++finals;
            }
        }
        assertEq(a.progress.funded, funded);
        assertEq(a.progress.inFlight, inFlight);
        if (a.status == B2BLib.AgreementStatus.Completed || a.status == B2BLib.AgreementStatus.Terminated) {
            assertEq(finals, a.supply.totalDeliveries);
        }
    }

    /**
     * @notice A lot is committed exactly while it sits in an open delivery, and the lots of an accepted delivery
     * belong to the buyer.
     */
    function invariant_LotCommitmentAndTitle() public view {
        uint32 total = b2b.getAgreement(id).supply.totalDeliveries;
        uint256 openLots;
        for (uint256 i; i < total; ++i) {
            B2BLib.DeliveryStatus s = b2b.getDelivery(id, i).status;
            uint256[] memory lots = b2b.lotsOf(id, i);
            bool open = s == B2BLib.DeliveryStatus.Dispatched || s == B2BLib.DeliveryStatus.Arrived
                || s == B2BLib.DeliveryStatus.Disputed;
            for (uint256 k; k < lots.length; ++k) {
                assertEq(b2b.lotCommitted(lots[k]), open);
                if (s == B2BLib.DeliveryStatus.Accepted) assertEq(passport.ownerOf(lots[k]), refinery);
            }
            if (open) openLots += lots.length;
        }
        uint256 committed;
        for (uint256 k; k < handler.lotsCreatedCount(); ++k) {
            if (b2b.lotCommitted(handler.lotsCreated(k))) ++committed;
        }
        assertEq(committed, openLots);
    }

    /**
     * @notice Logs how often each action succeeded in the last campaign (coverage check, always passes).
     */
    function invariant_callSummary() public view {
        string[11] memory names = [
            "fund",
            "dispatch",
            "arrive",
            "accept",
            "release",
            "reject",
            "offer",
            "closeMissed",
            "markDefaulted",
            "terminate",
            "withdraw"
        ];
        for (uint256 i; i < names.length; ++i) {
            console.log(names[i], handler.hits(bytes32(bytes(names[i]))));
        }
    }
}
