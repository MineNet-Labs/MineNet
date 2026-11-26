// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {MineNetFixture} from "test/utils/MineNetFixture.sol";
import {InspectionLib} from "src/compliance/libraries/InspectionLib.sol";
import {EscrowLib} from "src/trade/libraries/EscrowLib.sol";
import {DisputeLib} from "src/trade/libraries/DisputeLib.sol";
import {PassportLib} from "src/traceability/libraries/PassportLib.sol";
import {SupplyChainLib} from "src/traceability/libraries/SupplyChainLib.sol";
import {Roles} from "src/access/libraries/Roles.sol";

contract EscrowManagerTest is MineNetFixture {
    uint256 constant FEE = (PRICE * FEE_BPS) / 10_000;
    address inspector2 = makeAddr("inspector2");

    function setUp() public override {
        super.setUp();
        vm.prank(admin);
        registry.onboard(inspector2, Roles.INSPECTOR, "org-inspect-2", H, 0);
        // a second inspectorate (e.g. a traceability operator) with its own field agent on the roster
        vm.prank(regulator);
        inspections.setInspectorate("org-inspect-2", InspectionLib.InspectorateKind.TraceabilityOperator);
        _deployInspector(inspector2);
    }

    // ---------------------------------------------------------------- helpers

    function _sold(uint16 gradeBps, uint256 price) internal returns (uint256 id, uint256 orderId) {
        id = _inspected(10_000);
        if (gradeBps != 0) _grade(id, gradeBps);
        vm.warp(block.timestamp + 1 hours); // the sale happens after the pre-sale assay
        vm.prank(miner);
        uint256 listingId = market.createListing(_listingParams(id, _fixed(), price));
        orderId = _buy(buyer, listingId);
    }

    function _delivered(uint16 gradeBps) internal returns (uint256 id, uint256 orderId) {
        (id, orderId) = _sold(gradeBps, PRICE);
        _deliver(id, miner, buyer);
    }

    function _open(uint256 orderId) internal {
        vm.prank(buyer);
        escrow.openDispute(orderId, keccak256("claim"));
    }

    /// Cite the lot's latest checkpoint as evidence.
    function _cite(address who, uint256 orderId, uint256 id) internal {
        uint32 index = uint32(supplyChain.checkpointCount(id) - 1);
        vm.prank(who);
        escrow.submitEvidence(orderId, true, index, H);
    }

    function _respond(uint256 orderId) internal {
        vm.prank(miner);
        escrow.respondToDispute(orderId, keccak256("response"));
    }

    function _weigh(uint256 id, uint128 grams) internal {
        vm.prank(oracle);
        supplyChain.recordCheckpoint(
            SupplyChainLib.CheckpointInput(
                id, SupplyChainLib.CheckpointType.Weighing, grams, SupplyChainLib.Condition.Good, 0, H, 0
            )
        );
    }

    function _gradeBy(address who, uint256 id, uint16 gradeBps) internal {
        _assignTo(id, who);
        vm.prank(who);
        supplyChain.recordCheckpoint(
            SupplyChainLib.CheckpointInput(
                id, SupplyChainLib.CheckpointType.Inspection, 0, SupplyChainLib.Condition.Good, gradeBps, H, 0
            )
        );
    }

    function _afterEvidence() internal {
        vm.warp(block.timestamp + escrow.EVIDENCE_PERIOD() + 1);
    }

    function _status(uint256 orderId) internal view returns (uint8) {
        return uint8(escrow.getOrder(orderId).status);
    }

    // ================================================================ opening & settlement

    function test_OnlyMarketplaceOpensOrders() public {
        uint256 id = _inspected(10_000);
        EscrowLib.OpenParams memory p = EscrowLib.OpenParams(id, buyer, miner, usdc, PRICE, 14 days, H);
        vm.prank(buyer);
        vm.expectRevert(abi.encodeWithSelector(EscrowLib.EscrowManager__NotMarketplace.selector, buyer));
        escrow.openOrder(p);
    }

    function test_Open_LocksLot_RecordsUsdValue() public {
        (uint256 id, uint256 orderId) = _sold(6_500, PRICE);
        EscrowLib.Order memory o = escrow.getOrder(orderId);
        assertEq(o.amount, PRICE);
        assertEq(o.usdValue, PRICE, "USDC: 1 token unit = 1 micro-dollar");
        assertEq(o.gradeAtSale, 6_500);
        assertTrue(passport.escrowLocked(id));

        vm.prank(miner);
        vm.expectRevert(abi.encodeWithSelector(PassportLib.LotPassport__LotLocked.selector, id));
        passport.transferFrom(miner, buyer2, id);
    }

    function test_ReleaseFunds_AfterDelivery() public {
        (uint256 id, uint256 orderId) = _acceptedOrder();
        vm.prank(buyer);
        vm.expectRevert(abi.encodeWithSelector(EscrowLib.EscrowManager__NotDelivered.selector, orderId));
        escrow.releaseFunds(orderId);

        _deliver(id, miner, buyer);
        vm.prank(buyer);
        escrow.releaseFunds(orderId);
        assertEq(passport.ownerOf(id), buyer);
        assertEq(escrow.claimable(usdc, miner), PRICE - FEE);
        assertEq(escrow.claimable(usdc, treasury), FEE);
        assertEq(_status(orderId), uint8(EscrowLib.OrderStatus.Settled));
    }

    function test_Settle_AnyoneAfterDisputeWindow() public {
        (uint256 id, uint256 orderId) = _acceptedOrder();
        _deliver(id, miner, buyer);
        escrow.confirmDelivery(orderId);
        vm.expectRevert(abi.encodeWithSelector(EscrowLib.EscrowManager__DisputeWindowOpen.selector, orderId));
        escrow.settle(orderId);
        vm.warp(block.timestamp + 3 days);
        vm.prank(outsider);
        escrow.settle(orderId);
        assertEq(passport.ownerOf(id), buyer);
    }

    function test_CancelForNonDelivery() public {
        (uint256 id, uint256 orderId) = _acceptedOrder();
        vm.prank(buyer);
        vm.expectRevert(abi.encodeWithSelector(EscrowLib.EscrowManager__DeadlineNotReached.selector, orderId));
        escrow.cancelForNonDelivery(orderId);
        vm.warp(block.timestamp + 14 days + 1);
        vm.prank(buyer);
        escrow.cancelForNonDelivery(orderId);
        assertEq(escrow.claimable(usdc, buyer), PRICE);
        assertFalse(passport.escrowLocked(id));
    }

    // ================================================================ dispute process

    function test_Dispute_OnlyBuyerOpens_OnePerOrder() public {
        (, uint256 orderId) = _delivered(0);
        vm.prank(miner);
        vm.expectRevert(abi.encodeWithSelector(EscrowLib.EscrowManager__Unauthorized.selector, miner));
        escrow.openDispute(orderId, H);

        _open(orderId);
        vm.prank(buyer);
        escrow.withdrawDispute(orderId);
        vm.prank(buyer);
        vm.expectRevert(abi.encodeWithSelector(EscrowLib.EscrowManager__AlreadyDisputed.selector, orderId));
        escrow.openDispute(orderId, H);
    }

    function test_Evidence_Validation() public {
        (uint256 id, uint256 orderId) = _sold(6_500, PRICE); // grade checkpoint 0 is from before the sale
        _deliver(id, miner, buyer);
        _open(orderId);

        vm.startPrank(buyer);
        vm.expectRevert(abi.encodeWithSelector(EscrowLib.EscrowManager__EvidenceBeforeSale.selector, orderId, 0));
        escrow.submitEvidence(orderId, true, 0, H);
        vm.expectRevert(abi.encodeWithSelector(EscrowLib.EscrowManager__UnknownCheckpoint.selector, id, 99));
        escrow.submitEvidence(orderId, true, 99, H);
        vm.expectRevert(EscrowLib.EscrowManager__EmptyEvidence.selector);
        escrow.submitEvidence(orderId, false, 0, bytes32(0));

        escrow.submitEvidence(orderId, true, 1, H); // pickup weighing after the sale
        vm.expectRevert(abi.encodeWithSelector(EscrowLib.EscrowManager__DuplicateEvidence.selector, orderId, 1));
        escrow.submitEvidence(orderId, true, 1, H);
        escrow.submitEvidence(orderId, false, 0, keccak256("photos.zip")); // document for the record
        vm.stopPrank();

        vm.prank(outsider);
        vm.expectRevert(abi.encodeWithSelector(EscrowLib.EscrowManager__Unauthorized.selector, outsider));
        escrow.submitEvidence(orderId, false, 0, H);

        _afterEvidence();
        vm.prank(buyer);
        vm.expectRevert(abi.encodeWithSelector(EscrowLib.EscrowManager__EvidencePeriodClosed.selector, orderId));
        escrow.submitEvidence(orderId, false, 0, H);

        EscrowLib.Evidence[] memory ev = escrow.getEvidence(orderId);
        assertEq(ev.length, 2);
        assertTrue(ev[0].onChain);
        assertTrue(ev[0].fact.independent, "the pickup is signed by the carrier, outside both parties");
    }

    function test_Evidence_IndependenceClassification() public {
        (uint256 id, uint256 orderId) = _delivered(0);
        _open(orderId);
        _weigh(id, 10_000); // oracle weighbridge: outside both parties' organisations
        _cite(buyer, orderId, id);
        // arrival weighing signed by the buyer itself (consignee)
        vm.prank(buyer);
        escrow.submitEvidence(orderId, true, 1, H);

        EscrowLib.Evidence[] memory ev = escrow.getEvidence(orderId);
        assertTrue(ev[0].fact.independent);
        assertFalse(ev[1].fact.independent);
    }

    function test_Dispute_VerdictWaitsForEvidencePeriod() public {
        (, uint256 orderId) = _delivered(0);
        _open(orderId);
        uint64 deadline = escrow.getDispute(orderId).evidenceDeadline;
        vm.expectRevert(abi.encodeWithSelector(EscrowLib.EscrowManager__EvidencePeriodOpen.selector, orderId, deadline));
        escrow.resolveDispute(orderId);
    }

    // ================================================================ verdicts

    function test_Verdict_NoResponse_BuyerWins() public {
        (uint256 id, uint256 orderId) = _delivered(0);
        _open(orderId);
        _afterEvidence();

        (DisputeLib.Verdict v, DisputeLib.Winner w,,) = escrow.evaluateDispute(orderId);
        assertEq(uint8(v), uint8(DisputeLib.Verdict.NoResponse));
        assertEq(uint8(w), uint8(DisputeLib.Winner.Buyer));

        escrow.resolveDispute(orderId);
        assertEq(escrow.claimable(usdc, buyer), PRICE);
        assertEq(passport.ownerOf(id), miner);
        assertFalse(passport.escrowLocked(id));
        assertEq(uint8(escrow.getDispute(orderId).winner), uint8(DisputeLib.Winner.Buyer));
    }

    function test_Verdict_NothingProven_SellerWins() public {
        (uint256 id, uint256 orderId) = _delivered(0);
        _open(orderId);
        _respond(orderId);
        _afterEvidence();

        vm.prank(outsider); // anyone triggers the judgement: no arbiter, no regulator, no admin
        assertEq(uint8(escrow.resolveDispute(orderId)), uint8(DisputeLib.Verdict.SellerWins));
        assertEq(passport.ownerOf(id), buyer);
        assertEq(escrow.claimable(usdc, miner), PRICE - FEE);
        assertEq(uint8(escrow.getDispute(orderId).winner), uint8(DisputeLib.Winner.Seller));
    }

    function test_Verdict_IndependentOracleMismatch_BuyerWins() public {
        (uint256 id, uint256 orderId) = _delivered(0);
        _open(orderId);
        _respond(orderId);
        vm.prank(oracle); // RRA record disagrees with the passport
        supplyChain.submitOracleReport(id, keccak256("rra"), false);
        _cite(buyer, orderId, id);
        _afterEvidence();

        assertEq(uint8(escrow.resolveDispute(orderId)), uint8(DisputeLib.Verdict.IntegrityFailure));
        assertEq(escrow.claimable(usdc, buyer), PRICE);
        assertEq(passport.ownerOf(id), miner, "the lot goes back to the seller");
        assertFalse(passport.escrowLocked(id));
    }

    function test_Verdict_WeightShortfall_PaysOut_TitleWaitsForUnfreeze() public {
        (uint256 id, uint256 orderId) = _delivered(0);
        _open(orderId);
        _respond(orderId);
        _weigh(id, 9_000); // independent weighbridge: 10% short -> also flags (freezes) the lot
        _cite(buyer, orderId, id);
        _afterEvidence();

        assertEq(uint8(escrow.resolveDispute(orderId)), uint8(DisputeLib.Verdict.QualityShortfall));
        uint256 refund = PRICE / 10;
        uint256 sellerGross = PRICE - refund;
        assertEq(escrow.claimable(usdc, buyer), refund);
        assertEq(escrow.claimable(usdc, miner), sellerGross - (sellerGross * FEE_BPS) / 10_000);
        assertEq(uint8(escrow.getDispute(orderId).winner), uint8(DisputeLib.Winner.Split));

        // the money is settled; the title waits for the compliance flag to clear
        assertTrue(escrow.getOrder(orderId).titlePending);
        assertTrue(passport.escrowLocked(id));
        vm.expectRevert(abi.encodeWithSelector(PassportLib.LotPassport__LotFrozen.selector, id));
        escrow.finalizeTitle(orderId);

        vm.prank(regulator);
        passport.resolveFlag(1, false, H);
        escrow.finalizeTitle(orderId);
        assertEq(passport.ownerOf(id), buyer);
        assertFalse(passport.escrowLocked(id));
    }

    function test_Verdict_GradeShortfall_AveragesBothSides() public {
        (uint256 id, uint256 orderId) = _delivered(6_500); // 65% attested at sale
        _open(orderId);
        _gradeBy(inspector, id, 5_850); // buyer's assay: 58.5%
        _cite(buyer, orderId, id);
        _gradeBy(inspector2, id, 6_300); // seller's counter-assay: 63%
        _cite(miner, orderId, id); // seller evidence also counts as a response
        _afterEvidence();

        (DisputeLib.Verdict v, DisputeLib.Winner w, uint256 refund, bool lotToBuyer) = escrow.evaluateDispute(orderId);
        assertEq(uint8(v), uint8(DisputeLib.Verdict.QualityShortfall));
        assertEq(uint8(w), uint8(DisputeLib.Winner.Split));
        assertTrue(lotToBuyer);
        // average 60.75% vs 65% -> (6500 - 6075) / 6500 = 653 bps
        assertEq(refund, (PRICE * 653) / 10_000);

        escrow.resolveDispute(orderId);
        assertEq(passport.ownerOf(id), buyer);
        assertEq(escrow.claimable(usdc, buyer), refund);
    }

    function test_Verdict_GradeWithinTolerance_SellerWins() public {
        (uint256 id, uint256 orderId) = _delivered(6_500);
        _open(orderId);
        _gradeBy(inspector2, id, 6_420); // 0.8 points: assay noise
        _cite(buyer, orderId, id);
        _respond(orderId);
        _afterEvidence();
        assertEq(uint8(escrow.resolveDispute(orderId)), uint8(DisputeLib.Verdict.SellerWins));
    }

    function test_Verdict_NotDelivered_PendingUntilDeadline() public {
        (, uint256 orderId) = _sold(0, PRICE);
        _open(orderId);
        _respond(orderId);
        _afterEvidence(); // day 7 of a 14-day delivery window
        vm.expectRevert(abi.encodeWithSelector(EscrowLib.EscrowManager__VerdictPending.selector, orderId));
        escrow.resolveDispute(orderId);

        vm.warp(block.timestamp + 14 days);
        assertEq(uint8(escrow.resolveDispute(orderId)), uint8(DisputeLib.Verdict.NotDelivered));
        assertEq(escrow.claimable(usdc, buyer), PRICE);
    }

    function test_Verdict_ComplianceFailure() public {
        bytes32[] memory req = new bytes32[](1);
        req[0] = EXPORT_PERMIT;
        vm.prank(admin);
        escrow.setRequiredCertTypes(req);

        uint256 id = _inspected(10_000);
        vm.prank(regulator);
        uint256 certId = certs.issue(id, EXPORT_PERMIT, uint64(block.timestamp + 60 days), H);
        vm.prank(miner);
        uint256 orderId = _buy(buyer, market.createListing(_listingParams(id, _fixed(), PRICE)));
        _deliver(id, miner, buyer);
        vm.prank(regulator);
        certs.revoke(certId, keccak256("fraudulent permit"));

        _open(orderId);
        _respond(orderId);
        _afterEvidence();
        assertEq(uint8(escrow.resolveDispute(orderId)), uint8(DisputeLib.Verdict.ComplianceFailure));
        assertEq(escrow.claimable(usdc, buyer), PRICE);
    }

    // ================================================================ admin

    function test_Admin_FeeBoundsAndSnapshot() public {
        vm.prank(admin);
        vm.expectRevert(EscrowLib.EscrowManager__InvalidFee.selector);
        escrow.setFee(501, treasury);

        (uint256 id, uint256 orderId) = _acceptedOrder();
        vm.prank(admin);
        escrow.setFee(500, treasury);
        _deliver(id, miner, buyer);
        vm.prank(buyer);
        escrow.releaseFunds(orderId);
        assertEq(escrow.claimable(usdc, treasury), FEE);
    }

    function test_Pause_DoesNotTrapRefunds() public {
        (, uint256 orderId) = _acceptedOrder();
        vm.prank(admin);
        escrow.pause();
        vm.warp(block.timestamp + 15 days);
        vm.prank(buyer);
        escrow.cancelForNonDelivery(orderId);
        vm.prank(buyer);
        escrow.withdraw(usdc);
    }

    // ================================================================ fuzz

    /// Whatever the destination grade, the escrowed amount is paid out exactly: buyer + seller + fee.
    function testFuzz_GradeVerdictConservesFunds(uint16 saleGrade, uint16 destGrade, uint256 price) public {
        saleGrade = uint16(bound(saleGrade, 200, 10_000));
        destGrade = uint16(bound(destGrade, 1, saleGrade));
        price = bound(price, 1e6, 1_000_000e6);

        (uint256 id, uint256 orderId) = _sold(saleGrade, price);
        _deliver(id, miner, buyer);
        _open(orderId);
        _gradeBy(inspector2, id, destGrade);
        _cite(buyer, orderId, id);
        _respond(orderId);
        _afterEvidence();
        escrow.resolveDispute(orderId);

        uint256 total = escrow.claimable(usdc, buyer) + escrow.claimable(usdc, miner) + escrow.claimable(usdc, treasury);
        assertEq(total, price);
        assertEq(usdc.balanceOf(address(escrow)), price);
        uint256 expected = uint256(destGrade) + 100 < saleGrade
            ? (price * (((uint256(saleGrade) - destGrade) * 10_000) / saleGrade)) / 10_000
            : 0;
        assertEq(escrow.claimable(usdc, buyer), expected);
    }
}
