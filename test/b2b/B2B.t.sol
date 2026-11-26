// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {MineNetFixture} from "test/utils/MineNetFixture.sol";
import {B2BLib} from "src/b2b/libraries/B2BLib.sol";
import {SupplyChainLib} from "src/traceability/libraries/SupplyChainLib.sol";
import {Roles} from "src/access/libraries/Roles.sol";

contract B2BTest is MineNetFixture {
    address arbiter = makeAddr("arbiter");
    address refinery2 = makeAddr("refinery2"); // a second account of the refinery company

    uint128 constant QTY = 1_000_000; // 1 tonne per delivery, in grams
    uint256 constant PRICE_KG = 20e6; // 20 USDC per kg -> 20,000 USDC per delivery
    uint256 constant GOODS_FUNDED = 20_400e6; // escrow at the +2% tolerance
    uint256 constant FEE = 500e6; // 100 km x 5 USDC

    function setUp() public override {
        super.setUp();
        vm.prank(admin);
        registry.onboard(refinery2, Roles.REFINERY, "org-refinery", H, uint64(block.timestamp + 365 days));
        usdc.mint(refinery, 10_000_000e6);
        vm.prank(refinery);
        usdc.approve(address(b2b), type(uint256).max);
        vm.prank(miner);
        passport.setApprovalForAll(address(b2b), true);
    }

    // ---------------------------------------------------------------- helpers

    /// Miner (proposer) sells tin concentrate to the refinery: 3 weekly deliveries of 1 t at 20 USDC/kg.
    function _terms() internal view returns (B2BLib.Terms memory t) {
        t.seller = B2BLib.Side.Proposer;
        t.supply = B2BLib.SupplyTerms({
            mineralType: TIN,
            quantityPerDelivery: QTY,
            quantityToleranceBps: 200,
            minGradeBps: 0,
            pricePerKg: PRICE_KG,
            totalDeliveries: 3,
            deliveryInterval: 7 days,
            firstDeliveryOffset: 7 days
        });
        t.paymentToken = usdc;
        t.reviewPeriod = 3 days;
        t.proposalExpiresAt = uint64(block.timestamp + 7 days);
        t.termsHash = keccak256("offtake-v1");
    }

    function _withTransporter(B2BLib.Terms memory t) internal view returns (B2BLib.Terms memory) {
        t.transport = B2BLib.TransportTerms({transporter: transporter, distanceKm: 100, feePerKm: 5e6});
        return t;
    }

    function _propose(B2BLib.Terms memory t) internal returns (uint256 id) {
        vm.prank(miner);
        id = b2b.propose(refinery, t);
    }

    function _active(B2BLib.Terms memory t) internal returns (uint256 id) {
        id = _propose(t);
        vm.prank(refinery);
        b2b.sign(id, 1);
        if (t.transport.transporter != address(0)) {
            vm.prank(transporter);
            b2b.acceptAsTransporter(id, 1);
        }
    }

    function _fund(uint256 id, uint256 index) internal {
        vm.prank(refinery);
        b2b.fundDelivery(id, index);
    }

    /// `n` inspected tin lots of `grams` each, owned and held by the miner.
    function _lotsOf(uint256 n, uint128 grams) internal returns (uint256[] memory ids) {
        ids = new uint256[](n);
        for (uint256 i; i < n; ++i) {
            ids[i] = _inspected(grams);
        }
    }

    function _ship(uint256[] memory ids) internal returns (uint256 sid) {
        vm.prank(miner);
        sid = delivery.createShipment(ids, transporter, refinery, uint64(block.timestamp + 3 days), SEAL, H);
    }

    function _pickUp(uint256 sid, uint256[] memory ids) internal {
        uint128[] memory ws = _exact(ids); // read before pranking: the call would consume the prank
        vm.prank(transporter);
        delivery.confirmPickup(sid, ws, SEAL, H);
    }

    /// Transporter picks up and delivers; the refinery confirms with exact weights and an intact seal.
    function _completeShipment(uint256 sid, uint256[] memory ids) internal {
        _pickUp(sid, ids);
        vm.prank(transporter);
        delivery.markArrived(sid, H);
        uint128[] memory ws = _exact(ids);
        vm.prank(refinery);
        delivery.confirmDelivery(sid, ws, SEAL, SupplyChainLib.Condition.Good, H);
    }

    function _exact(uint256[] memory ids) internal view returns (uint128[] memory ws) {
        ws = new uint128[](ids.length);
        for (uint256 i; i < ids.length; ++i) {
            ws[i] = supplyChain.lastWeight(ids[i]);
        }
    }

    function _dispatch(uint256 id, uint256 index, uint256[] memory ids, uint256 sid) internal {
        vm.prank(miner);
        b2b.dispatchDelivery(id, index, ids, sid, keccak256("delivery-note"));
    }

    /// Funded, dispatched through the transporter's shipment, and arrived at the refinery.
    function _arrivedViaTransporter(uint256 id, uint256 index) internal returns (uint256[] memory ids) {
        _fund(id, index);
        ids = _lotsOf(2, QTY / 2);
        uint256 sid = _ship(ids);
        _dispatch(id, index, ids, sid);
        _completeShipment(sid, ids);
        b2b.confirmArrival(id, index);
    }

    /// Funded, dispatched, and handed over directly on the passport (no transporter).
    function _arrivedDirect(uint256 id, uint256 index) internal returns (uint256[] memory ids) {
        _fund(id, index);
        ids = _lotsOf(1, QTY);
        _dispatch(id, index, ids, 0);
        _moveCustody(ids[0], miner, refinery);
        b2b.confirmArrival(id, index);
    }

    function _status(uint256 id) internal view returns (B2BLib.AgreementStatus) {
        return b2b.getAgreement(id).status;
    }

    function _dStatus(uint256 id, uint256 index) internal view returns (B2BLib.DeliveryStatus) {
        return b2b.getDelivery(id, index).status;
    }

    // ---------------------------------------------------------------- negotiation & schedule

    function test_Schedule_GeneratedAtActivation() public {
        uint256 id = _propose(_terms());
        assertEq(b2b.getDelivery(id, 0).dueAt, 0); // no schedule before activation

        uint256 t0 = block.timestamp;
        vm.expectEmit(address(b2b));
        emit B2BLib.AgreementActivated(id, 1, uint64(t0 + 7 days), uint64(t0 + 21 days));
        vm.prank(refinery);
        b2b.sign(id, 1);

        B2BLib.Delivery memory d2 = b2b.getDelivery(id, 2);
        assertEq(d2.dueAt, t0 + 21 days);
        assertEq(d2.quantity, QTY);
        assertEq(d2.pricePerKg, PRICE_KG);
        assertEq(uint8(d2.status), uint8(B2BLib.DeliveryStatus.Scheduled));
        assertEq(b2b.getDeliveries(id, 0, 10).length, 3);

        (uint256 goods, uint256 fee) = b2b.amountDue(id, 0);
        assertEq(goods, GOODS_FUNDED);
        assertEq(fee, 0);

        vm.expectRevert(abi.encodeWithSelector(B2BLib.B2B__UnknownDelivery.selector, id, 3));
        b2b.getDelivery(id, 3);
    }

    function test_Transporter_MustAcceptCurrentVersion() public {
        uint256 id = _propose(_withTransporter(_terms()));
        vm.prank(refinery);
        b2b.sign(id, 1);
        assertEq(uint8(_status(id)), uint8(B2BLib.AgreementStatus.Proposed)); // waits for the transporter

        vm.prank(outsider);
        vm.expectRevert(abi.encodeWithSelector(B2BLib.B2B__NotTransporter.selector, outsider));
        b2b.acceptAsTransporter(id, 1);

        vm.prank(transporter);
        b2b.acceptAsTransporter(id, 1);
        assertEq(uint8(_status(id)), uint8(B2BLib.AgreementStatus.Active));
        (, uint256 fee) = b2b.amountDue(id, 0);
        assertEq(fee, FEE);
    }

    function test_Transporter_CanDecline_AndAmendmentNeedsReacceptance() public {
        uint256 id = _propose(_withTransporter(_terms()));
        vm.prank(transporter);
        b2b.acceptAsTransporter(id, 1);

        B2BLib.Terms memory t = _withTransporter(_terms());
        t.supply.pricePerKg = 19e6; // the refinery counters
        vm.prank(refinery2);
        b2b.amend(id, t);
        assertFalse(b2b.getAgreement(id).transporterAccepted);
        assertEq(b2b.getAgreement(id).counterparty.account, refinery2);

        vm.prank(miner);
        b2b.sign(id, 2);
        assertEq(uint8(_status(id)), uint8(B2BLib.AgreementStatus.Proposed));

        vm.prank(transporter);
        b2b.declineAsTransporter(id, H);
        assertEq(uint8(_status(id)), uint8(B2BLib.AgreementStatus.Rejected));
    }

    function test_Propose_RejectsInvalidSchedulesAndParties() public {
        vm.startPrank(miner);
        B2BLib.Terms memory t = _terms();
        t.supply.quantityToleranceBps = 2_001;
        vm.expectRevert(B2BLib.B2B__InvalidSchedule.selector);
        b2b.propose(refinery, t);

        t = _terms();
        t.supply.totalDeliveries = 366;
        vm.expectRevert(B2BLib.B2B__InvalidSchedule.selector);
        b2b.propose(refinery, t);

        t = _terms();
        t.supply.deliveryInterval = 1 hours;
        vm.expectRevert(B2BLib.B2B__InvalidSchedule.selector);
        b2b.propose(refinery, t);

        t = _terms();
        t.supply.mineralType = bytes32(0);
        vm.expectRevert(B2BLib.B2B__InvalidSchedule.selector);
        b2b.propose(refinery, t);

        t = _terms(); // a transporter cannot be the buyer of lots (no OWN_LOT)
        vm.expectRevert(abi.encodeWithSelector(B2BLib.B2B__InvalidTradingRole.selector, transporter));
        b2b.propose(transporter, t);

        t = _withTransporter(_terms());
        t.transport.transporter = refinery2; // belongs to a party
        vm.expectRevert(abi.encodeWithSelector(B2BLib.B2B__InvalidTransporter.selector, refinery2));
        b2b.propose(refinery, t);

        vm.stopPrank();

        vm.prank(regulator);
        vm.expectRevert(abi.encodeWithSelector(B2BLib.B2B__NotAuthorized.selector, regulator));
        b2b.propose(refinery, _terms());
    }

    function test_Sign_WrongVersionOrExpired() public {
        uint256 id = _propose(_terms());
        vm.prank(refinery);
        vm.expectRevert(abi.encodeWithSelector(B2BLib.B2B__VersionMismatch.selector, 1, 2));
        b2b.sign(id, 2);

        vm.warp(block.timestamp + 7 days + 1);
        vm.prank(refinery);
        vm.expectRevert(abi.encodeWithSelector(B2BLib.B2B__ProposalExpired.selector, id));
        b2b.sign(id, 1);
    }

    // ---------------------------------------------------------------- a full delivery

    function test_Delivery_WithTransporter_PaysDeliveredWeightAndTransfersTitle() public {
        uint256 id = _active(_withTransporter(_terms()));
        _fund(id, 0);
        assertEq(usdc.balanceOf(address(b2b)), GOODS_FUNDED + FEE);

        uint256[] memory ids = new uint256[](2);
        ids[0] = _inspected(490_000);
        ids[1] = _inspected(500_000); // 990 kg: inside the 2% tolerance
        uint256 sid = _ship(ids);
        _dispatch(id, 0, ids, sid);
        assertTrue(b2b.lotCommitted(ids[0]));
        assertEq(b2b.getDelivery(id, 0).deliveredQty, 990_000);

        vm.expectRevert(abi.encodeWithSelector(B2BLib.B2B__NotArrived.selector, 0));
        b2b.confirmArrival(id, 0);

        _completeShipment(sid, ids);
        vm.prank(refinery);
        b2b.acceptDelivery(id, 0); // confirms arrival itself

        assertEq(b2b.claimable(usdc, miner), 19_800e6); // 990 kg x 20 USDC
        assertEq(b2b.claimable(usdc, refinery), GOODS_FUNDED - 19_800e6);
        assertEq(b2b.claimable(usdc, transporter), FEE);
        assertEq(passport.ownerOf(ids[0]), refinery);
        assertEq(passport.ownerOf(ids[1]), refinery);
        assertFalse(b2b.lotCommitted(ids[0]));

        B2BLib.Performance memory p = b2b.performanceOf("org-miner");
        assertEq(p.deliveriesMade, 1);
        assertEq(p.onTimeDeliveries, 1);
        assertEq(p.gramsSupplied, 990_000);

        vm.prank(transporter);
        b2b.withdraw(usdc);
        assertEq(usdc.balanceOf(transporter), FEE);
    }

    function test_Dispatch_EnforcesLotsQuantityGradeAndShipment() public {
        B2BLib.Terms memory t = _withTransporter(_terms());
        t.supply.minGradeBps = 6_000;
        uint256 id = _active(t);
        _fund(id, 0);

        uint256[] memory small = _lotsOf(1, 900_000); // 10% short
        _grade(small[0], 7_000);
        uint256 sid = _ship(small);
        vm.prank(miner);
        vm.expectRevert(
            abi.encodeWithSelector(B2BLib.B2B__QuantityOutOfTolerance.selector, 900_000, 980_000, 1_020_000)
        );
        b2b.dispatchDelivery(id, 0, small, sid, H);

        uint256[] memory low = _lotsOf(1, QTY);
        _grade(low[0], 5_500);
        vm.prank(miner);
        vm.expectRevert(abi.encodeWithSelector(B2BLib.B2B__GradeTooLow.selector, low[0], 5_500, 6_000));
        b2b.dispatchDelivery(id, 0, low, 0, H);

        uint256[] memory good = _lotsOf(1, QTY);
        _grade(good[0], 6_500);
        vm.prank(miner); // a named transporter means the lots must travel in its shipment
        vm.expectRevert(abi.encodeWithSelector(B2BLib.B2B__InvalidShipment.selector, 0));
        b2b.dispatchDelivery(id, 0, good, 0, H);

        vm.prank(refinery); // only the seller dispatches
        vm.expectRevert(abi.encodeWithSelector(B2BLib.B2B__WrongSide.selector, id, refinery));
        b2b.dispatchDelivery(id, 0, good, 0, H);

        _dispatch(id, 0, good, _ship(good));

        _fund(id, 1); // the same lot cannot fill a second delivery
        vm.prank(miner);
        vm.expectRevert(abi.encodeWithSelector(B2BLib.B2B__InvalidLot.selector, good[0]));
        b2b.dispatchDelivery(id, 1, good, 0, H);
    }

    function test_Dispatch_RequiresFundingAndApproval() public {
        uint256 id = _active(_terms());
        uint256[] memory ids = _lotsOf(1, QTY);
        vm.prank(miner);
        vm.expectRevert(
            abi.encodeWithSelector(B2BLib.B2B__InvalidDeliveryStatus.selector, 0, B2BLib.DeliveryStatus.Scheduled)
        );
        b2b.dispatchDelivery(id, 0, ids, 0, H);

        _fund(id, 0);
        vm.prank(miner);
        passport.setApprovalForAll(address(b2b), false);
        vm.prank(miner);
        vm.expectRevert(abi.encodeWithSelector(B2BLib.B2B__InvalidLot.selector, ids[0]));
        b2b.dispatchDelivery(id, 0, ids, 0, H);
    }

    function test_DirectHandover_ReleasedAfterReview() public {
        uint256 id = _active(_terms());
        uint256[] memory ids = _arrivedDirect(id, 0);

        uint64 ends = uint64(block.timestamp + 3 days);
        vm.expectRevert(abi.encodeWithSelector(B2BLib.B2B__ReviewPeriodOpen.selector, 0, ends));
        b2b.releaseAfterReview(id, 0);

        vm.warp(ends + 1);
        vm.prank(outsider);
        b2b.releaseAfterReview(id, 0);
        assertEq(b2b.claimable(usdc, miner), 20_000e6);
        assertEq(b2b.claimable(usdc, refinery), 400e6);
        assertEq(passport.ownerOf(ids[0]), refinery);
        assertEq(uint8(_dStatus(id, 0)), uint8(B2BLib.DeliveryStatus.Accepted));
    }

    // ---------------------------------------------------------------- inspection

    function test_Inspector_GatesAutomaticRelease() public {
        B2BLib.Terms memory t = _terms();
        t.inspectionRequired = true; // destination inspection by a platform-assigned inspector
        t.supply.minGradeBps = 6_000;
        uint256 id = _active(t);
        _fund(id, 0);
        uint256[] memory ids = _lotsOf(1, QTY);
        _grade(ids[0], 6_500); // pre-shipment assay (does not count as the destination inspection)
        vm.warp(block.timestamp + 1 hours);
        _dispatch(id, 0, ids, 0);
        _moveCustody(ids[0], miner, refinery);
        b2b.confirmArrival(id, 0);

        vm.warp(block.timestamp + 3 days + 1);
        uint64 grace = b2b.getDelivery(id, 0).arrivedAt + 14 days;
        vm.expectRevert(abi.encodeWithSelector(B2BLib.B2B__InspectionPending.selector, 0, grace));
        b2b.releaseAfterReview(id, 0);

        _grade(ids[0], 6_200); // the platform-assigned inspector clears it at destination
        b2b.releaseAfterReview(id, 0);
        assertEq(uint8(_dStatus(id, 0)), uint8(B2BLib.DeliveryStatus.Accepted));
    }

    function test_Inspector_BelowGrade_BlocksReleaseAndAllowsLateRejection() public {
        B2BLib.Terms memory t = _terms();
        t.inspectionRequired = true; // destination inspection by a platform-assigned inspector
        t.supply.minGradeBps = 6_000;
        uint256 id = _active(t);
        _fund(id, 0);
        uint256[] memory ids = _lotsOf(1, QTY);
        _grade(ids[0], 6_500);
        vm.warp(block.timestamp + 1 hours);
        _dispatch(id, 0, ids, 0);
        _moveCustody(ids[0], miner, refinery);
        b2b.confirmArrival(id, 0);
        vm.warp(block.timestamp + 5 days); // review period over
        _grade(ids[0], 5_000); // destination assay: below contract grade

        vm.expectRevert(abi.encodeWithSelector(B2BLib.B2B__LotNotReleasable.selector, ids[0]));
        b2b.releaseAfterReview(id, 0);

        vm.prank(refinery);
        b2b.rejectDelivery(id, 0, keccak256("grade 50% < 60%"));
        assertEq(uint8(_dStatus(id, 0)), uint8(B2BLib.DeliveryStatus.Disputed));
    }

    // ---------------------------------------------------------------- disputes & flags

    function test_Dispute_SettledByOffers_TitlePasses() public {
        uint256 id = _active(_withTransporter(_terms()));
        uint256[] memory ids = _arrivedViaTransporter(id, 0);
        vm.prank(refinery);
        b2b.rejectDelivery(id, 0, keccak256("moisture"));

        vm.prank(miner);
        vm.expectRevert(abi.encodeWithSelector(B2BLib.B2B__InvalidSettlement.selector, 20_000e6 + 1, 20_000e6));
        b2b.offerSettlement(id, 0, 20_000e6 + 1);

        vm.prank(miner);
        b2b.offerSettlement(id, 0, 18_000e6);
        vm.prank(refinery);
        b2b.offerSettlement(id, 0, 18_500e6); // offers cross: settles at the seller's ask

        assertEq(b2b.claimable(usdc, miner), 18_000e6);
        assertEq(b2b.claimable(usdc, refinery), GOODS_FUNDED - 18_000e6);
        assertEq(b2b.claimable(usdc, transporter), FEE);
        assertEq(passport.ownerOf(ids[0]), refinery);
        assertEq(b2b.performanceOf("org-miner").disputesLost, 1);
    }

    function test_Dispute_ArbiterAwardsNothing_TitleStays() public {
        B2BLib.Terms memory t = _terms();
        t.arbiter = arbiter;
        uint256 id = _active(t);
        uint256[] memory ids = _arrivedDirect(id, 0);
        vm.prank(refinery);
        b2b.rejectDelivery(id, 0, H);

        uint64 until = uint64(block.timestamp + 14 days);
        vm.prank(arbiter);
        vm.expectRevert(abi.encodeWithSelector(B2BLib.B2B__NegotiationPeriod.selector, until));
        b2b.arbitrate(id, 0, 0, H);

        vm.warp(until + 1);
        vm.prank(arbiter);
        b2b.arbitrate(id, 0, 0, keccak256("award"));
        assertEq(b2b.claimable(usdc, refinery), GOODS_FUNDED);
        assertEq(passport.ownerOf(ids[0]), miner); // nothing paid: the lot stays the seller's
        assertFalse(b2b.lotCommitted(ids[0]));
    }

    function test_RejectFlagged_AfterPickup_PaysTransporter() public {
        uint256 id = _active(_withTransporter(_terms()));
        _fund(id, 0);
        uint256[] memory ids = _lotsOf(1, QTY);
        uint256 sid = _ship(ids);
        _dispatch(id, 0, ids, sid);
        _pickUp(sid, ids);

        vm.prank(refinery);
        vm.expectRevert(abi.encodeWithSelector(B2BLib.B2B__NotFlagged.selector, 0));
        b2b.rejectFlaggedDelivery(id, 0);

        vm.prank(auditor);
        supplyChain.flagLot(ids[0], keccak256("tag mismatch at border"));

        vm.prank(refinery);
        b2b.rejectFlaggedDelivery(id, 0);
        assertEq(b2b.claimable(usdc, refinery), GOODS_FUNDED);
        assertEq(b2b.claimable(usdc, transporter), FEE);
        assertEq(uint8(_dStatus(id, 0)), uint8(B2BLib.DeliveryStatus.Rejected));
        assertEq(b2b.performanceOf("org-miner").deliveriesRejected, 1);
        assertEq(passport.ownerOf(ids[0]), miner);
    }

    // ---------------------------------------------------------------- missed, defaults, adjustments

    function test_Missed_BuyerRefundedAfterGrace_SellerCanGiveUp() public {
        uint256 id = _active(_terms());
        _fund(id, 0);
        uint64 due = b2b.getDelivery(id, 0).dueAt;

        vm.prank(refinery);
        vm.expectRevert(abi.encodeWithSelector(B2BLib.B2B__TooEarly.selector, 0, due + 30 days));
        b2b.closeMissed(id, 0);

        vm.warp(due + 30 days + 1);
        vm.prank(refinery);
        b2b.closeMissed(id, 0);
        assertEq(b2b.claimable(usdc, refinery), GOODS_FUNDED);
        assertEq(uint8(_dStatus(id, 0)), uint8(B2BLib.DeliveryStatus.Missed));

        vm.prank(miner); // the seller gives up delivery 1 early
        b2b.closeMissed(id, 1);
        assertEq(b2b.performanceOf("org-miner").deliveriesMissed, 2);
        assertEq(b2b.getAgreement(id).progress.missed, 2);
    }

    function test_Default_UnfundedPastDue() public {
        uint256 id = _active(_terms());
        uint64 due = b2b.getDelivery(id, 0).dueAt;
        vm.prank(miner);
        vm.expectRevert(abi.encodeWithSelector(B2BLib.B2B__TooEarly.selector, 0, due));
        b2b.markDefaulted(id, 0);

        vm.warp(due + 1);
        vm.prank(miner);
        b2b.markDefaulted(id, 0);
        assertEq(uint8(_dStatus(id, 0)), uint8(B2BLib.DeliveryStatus.Defaulted));
        assertEq(b2b.performanceOf("org-refinery").fundingDefaults, 1);
    }

    function test_Adjustment_RequestConfirm_ChangesAmountDue() public {
        uint256 id = _active(_terms());
        uint64 newDue = uint64(block.timestamp + 20 days);

        vm.prank(miner); // rainy season: half a tonne, a bit later
        b2b.requestAdjustment(id, 1, QTY / 2, PRICE_KG, newDue);

        vm.prank(miner);
        vm.expectRevert(abi.encodeWithSelector(B2BLib.B2B__InvalidAdjustment.selector, 1));
        b2b.confirmAdjustment(id, 1); // the requester cannot confirm

        vm.prank(refinery);
        b2b.confirmAdjustment(id, 1);
        B2BLib.Delivery memory d = b2b.getDelivery(id, 1);
        assertEq(d.quantity, QTY / 2);
        assertEq(d.dueAt, newDue);
        (uint256 goods,) = b2b.amountDue(id, 1);
        assertEq(goods, GOODS_FUNDED / 2);

        _fund(id, 1); // funded deliveries cannot be adjusted any more
        vm.prank(refinery);
        vm.expectRevert(
            abi.encodeWithSelector(B2BLib.B2B__InvalidDeliveryStatus.selector, 1, B2BLib.DeliveryStatus.Funded)
        );
        b2b.requestAdjustment(id, 1, QTY, PRICE_KG, newDue);
    }

    // ---------------------------------------------------------------- ending

    function test_Completes_WhenEveryDeliveryResolved() public {
        B2BLib.Terms memory t = _terms();
        t.supply.totalDeliveries = 2;
        uint256 id = _active(t);
        _arrivedDirect(id, 0);
        vm.prank(refinery);
        b2b.acceptDelivery(id, 0);
        vm.prank(miner);
        b2b.closeMissed(id, 1);
        assertEq(uint8(_status(id)), uint8(B2BLib.AgreementStatus.Completed));
    }

    function test_MutualTermination_RefundsFundedAndCancelsRest() public {
        uint256 id = _active(_terms());
        _fund(id, 0);

        vm.prank(refinery);
        b2b.requestTermination(id, H);
        vm.prank(refinery);
        vm.expectRevert(abi.encodeWithSelector(B2BLib.B2B__InvalidTermination.selector, id));
        b2b.confirmTermination(id); // the requester cannot confirm

        vm.prank(miner);
        b2b.confirmTermination(id);
        assertEq(uint8(_status(id)), uint8(B2BLib.AgreementStatus.Terminated));
        assertEq(b2b.claimable(usdc, refinery), GOODS_FUNDED);
        assertEq(uint8(_dStatus(id, 0)), uint8(B2BLib.DeliveryStatus.Cancelled));
        assertEq(uint8(_dStatus(id, 2)), uint8(B2BLib.DeliveryStatus.Cancelled));
        assertEq(b2b.getAgreement(id).progress.cancelled, 3);
    }

    function test_Termination_BlockedWhileInFlight() public {
        uint256 id = _active(_terms());
        _fund(id, 0);
        _dispatch(id, 0, _lotsOf(1, QTY), 0);
        vm.prank(miner);
        b2b.requestTermination(id, H);
        vm.prank(refinery);
        vm.expectRevert(abi.encodeWithSelector(B2BLib.B2B__DeliveriesInFlight.selector, 1));
        b2b.confirmTermination(id);
    }

    function test_TerminateForCause_AfterRepeatedMisses() public {
        B2BLib.Terms memory t = _terms();
        t.maxMissed = 2;
        uint256 id = _active(t);

        vm.prank(miner);
        b2b.closeMissed(id, 0);
        vm.prank(refinery);
        vm.expectRevert(abi.encodeWithSelector(B2BLib.B2B__NoCause.selector, 1, 2));
        b2b.terminateForCause(id, H);

        vm.prank(miner);
        b2b.closeMissed(id, 1);
        vm.prank(refinery);
        b2b.terminateForCause(id, keccak256("notice"));
        assertEq(uint8(_status(id)), uint8(B2BLib.AgreementStatus.Terminated));
    }

    // ---------------------------------------------------------------- off-chain payment & pause

    function test_OffChainPayment_RecordsWithoutEscrow() public {
        B2BLib.Terms memory t = _terms();
        t.paymentToken = IERC20(address(0));
        uint256 id = _active(t);

        vm.prank(refinery);
        vm.expectRevert(B2BLib.B2B__NotEscrowed.selector);
        b2b.fundDelivery(id, 0);

        uint256[] memory ids = _lotsOf(1, QTY);
        _dispatch(id, 0, ids, 0); // no funding step
        _moveCustody(ids[0], miner, refinery);
        vm.prank(refinery);
        b2b.acceptDelivery(id, 0);
        assertEq(passport.ownerOf(ids[0]), refinery);
        assertEq(b2b.claimable(usdc, miner), 0);
    }

    function test_Pause_StopsNewBusinessNotPayments() public {
        uint256 id = _active(_terms());
        _arrivedDirect(id, 0);

        vm.prank(admin);
        b2b.pause();
        vm.prank(refinery);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        b2b.fundDelivery(id, 1);

        vm.prank(refinery);
        b2b.acceptDelivery(id, 0);
        vm.prank(miner);
        b2b.withdraw(usdc);
        assertEq(usdc.balanceOf(miner), 20_000e6);
    }
}
