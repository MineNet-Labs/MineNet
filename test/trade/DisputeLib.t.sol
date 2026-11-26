// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";
import {DisputeLib} from "src/trade/libraries/DisputeLib.sol";
import {SupplyChainLib} from "src/traceability/libraries/SupplyChainLib.sol";

/// Unit tests of the judge alone: pure inputs in, verdict out. This is where the dispute rules are
/// debugged, without deploying anything.
contract DisputeLibTest is Test {
    uint256 constant AMOUNT = 100_000e6;
    uint64 constant NOW = 1_000_000;
    uint64 constant DEADLINE = 2_000_000;

    function _case() internal pure returns (DisputeLib.Case memory c) {
        c.amount = AMOUNT;
        c.gradeAtSale = 6_500;
        c.deliveryDeadline = DEADLINE;
        c.now_ = NOW;
        c.sellerResponded = true;
        c.delivered = true;
        c.certificatesValid = true;
        c.buyerFacts = new DisputeLib.Fact[](0);
        c.sellerFacts = new DisputeLib.Fact[](0);
    }

    function _fact(SupplyChainLib.CheckpointType t, bool independent, uint64 at)
        internal
        pure
        returns (DisputeLib.Fact memory f)
    {
        f.cpType = t;
        f.condition = SupplyChainLib.Condition.Good;
        f.withinTolerance = true;
        f.independent = independent;
        f.timestamp = at;
    }

    function _seal(bool independent, uint64 at) internal pure returns (DisputeLib.Fact memory f) {
        f = _fact(SupplyChainLib.CheckpointType.Arrival, independent, at);
        f.condition = SupplyChainLib.Condition.SealBroken;
    }

    function _weight(bool independent, uint64 at, uint128 measured, uint128 ref)
        internal
        pure
        returns (DisputeLib.Fact memory f)
    {
        f = _fact(SupplyChainLib.CheckpointType.Weighing, independent, at);
        f.measuredQty = measured;
        f.referenceQty = ref;
        f.withinTolerance = measured * 100 >= ref * 98; // 2% tolerance
    }

    function _grade(bool independent, uint16 g) internal pure returns (DisputeLib.Fact memory f) {
        f = _fact(SupplyChainLib.CheckpointType.Inspection, independent, 10);
        f.gradeBps = g;
    }

    function _one(DisputeLib.Fact memory f) internal pure returns (DisputeLib.Fact[] memory a) {
        a = new DisputeLib.Fact[](1);
        a[0] = f;
    }

    function _judge(DisputeLib.Case memory c) internal pure returns (DisputeLib.Verdict v, uint256 refund, bool lot) {
        return DisputeLib.judge(c);
    }

    // ---------------------------------------------------------------- order of rules

    function test_NoResponse_FirstRule() public pure {
        DisputeLib.Case memory c = _case();
        c.sellerResponded = false;
        c.certificatesValid = false;
        (DisputeLib.Verdict v, uint256 refund, bool lot) = _judge(c);
        assertEq(uint8(v), uint8(DisputeLib.Verdict.NoResponse));
        assertEq(refund, AMOUNT);
        assertFalse(lot);
    }

    function test_NotDelivered_PendingThenRefund() public pure {
        DisputeLib.Case memory c = _case();
        c.delivered = false;
        (DisputeLib.Verdict v,,) = _judge(c);
        assertEq(uint8(v), uint8(DisputeLib.Verdict.Pending));
        c.now_ = DEADLINE + 1;
        (v,,) = _judge(c);
        assertEq(uint8(v), uint8(DisputeLib.Verdict.NotDelivered));
    }

    function test_IntegrityBeatsNonDelivery() public pure {
        DisputeLib.Case memory c = _case();
        c.delivered = false; // the seal broke, so custody never moved
        c.buyerFacts = _one(_seal(true, 100));
        (DisputeLib.Verdict v, uint256 refund,) = _judge(c);
        assertEq(uint8(v), uint8(DisputeLib.Verdict.IntegrityFailure));
        assertEq(refund, AMOUNT);
    }

    // ---------------------------------------------------------------- independence & rebuttal

    function test_IndependentIntegrity_CannotBeRebutted() public pure {
        DisputeLib.Case memory c = _case();
        c.buyerFacts = _one(_seal(true, 100));
        c.sellerFacts = _one(_fact(SupplyChainLib.CheckpointType.Inspection, true, 200)); // "looks fine"
        (DisputeLib.Verdict v,,) = _judge(c);
        assertEq(uint8(v), uint8(DisputeLib.Verdict.IntegrityFailure));
    }

    /// The party holding the goods could write anything: its own records prove nothing by themselves.
    function test_PartyIntegrityClaim_ProvesNothing() public pure {
        DisputeLib.Case memory c = _case();
        c.buyerFacts = _one(_seal(false, 100)); // the buyer's own word
        (DisputeLib.Verdict v,,) = _judge(c);
        assertEq(uint8(v), uint8(DisputeLib.Verdict.SellerWins), "a self-reported broken seal is not proof");

        c.buyerFacts = _one(_seal(true, 100)); // the same finding by an independent inspector
        (v,,) = _judge(c);
        assertEq(uint8(v), uint8(DisputeLib.Verdict.IntegrityFailure));
    }

    function test_PartyWeightClaim_ProvesNothing() public pure {
        DisputeLib.Case memory c = _case();
        c.buyerFacts = _one(_weight(false, 100, 9_000, 10_000)); // buyer's own scale: 10% short
        (DisputeLib.Verdict v, uint256 refund,) = _judge(c);
        assertEq(uint8(v), uint8(DisputeLib.Verdict.SellerWins));
        assertEq(refund, 0);

        c.buyerFacts = _one(_weight(true, 100, 9_000, 10_000)); // independent weighbridge: 10% short
        bool lot;
        (v, refund, lot) = _judge(c);
        assertEq(uint8(v), uint8(DisputeLib.Verdict.QualityShortfall));
        assertEq(refund, AMOUNT / 10);
        assertTrue(lot);
    }

    // ---------------------------------------------------------------- quality maths

    function test_GradeAverage_IgnoresPartyAssays() public pure {
        DisputeLib.Case memory c = _case();
        c.buyerFacts = _one(_grade(true, 5_850));
        DisputeLib.Fact[] memory s = new DisputeLib.Fact[](2);
        s[0] = _grade(true, 6_300);
        s[1] = _grade(false, 9_999); // the seller's own lab: ignored
        c.sellerFacts = s;
        assertEq(DisputeLib.gradeShortfallBps(c), uint256((6_500 - 6_075) * 10_000) / 6_500);
    }

    function test_WeightAndGrade_AddUp_CappedAtFullRefund() public pure {
        DisputeLib.Case memory c = _case();
        DisputeLib.Fact[] memory b = new DisputeLib.Fact[](2);
        b[0] = _weight(true, 100, 5_000, 10_000); // 50% short
        b[1] = _grade(true, 1_000); // grade collapsed
        c.buyerFacts = b;
        (DisputeLib.Verdict v, uint256 refund,) = _judge(c);
        assertEq(uint8(v), uint8(DisputeLib.Verdict.QualityShortfall));
        assertEq(refund, AMOUNT);
        assertEq(uint8(DisputeLib.winnerOf(v, refund, AMOUNT)), uint8(DisputeLib.Winner.Buyer));
    }

    function test_WinnerMapping() public pure {
        assertEq(uint8(DisputeLib.winnerOf(DisputeLib.Verdict.Pending, 0, AMOUNT)), uint8(DisputeLib.Winner.None));
        assertEq(uint8(DisputeLib.winnerOf(DisputeLib.Verdict.SellerWins, 0, AMOUNT)), uint8(DisputeLib.Winner.Seller));
        assertEq(
            uint8(DisputeLib.winnerOf(DisputeLib.Verdict.QualityShortfall, 1, AMOUNT)), uint8(DisputeLib.Winner.Split)
        );
        assertEq(
            uint8(DisputeLib.winnerOf(DisputeLib.Verdict.NotDelivered, AMOUNT, AMOUNT)), uint8(DisputeLib.Winner.Buyer)
        );
    }

    /// The refund never exceeds the escrowed amount, whatever the evidence.
    function testFuzz_RefundBounded(uint128 measured, uint128 ref, uint16 grade, uint256 amount) public pure {
        ref = uint128(bound(ref, 1, type(uint64).max));
        measured = uint128(bound(measured, 1, ref));
        grade = uint16(bound(grade, 1, 10_000));
        DisputeLib.Case memory c = _case();
        c.amount = bound(amount, 0, type(uint128).max);
        DisputeLib.Fact[] memory b = new DisputeLib.Fact[](2);
        b[0] = _weight(true, 100, measured, ref);
        b[1] = _grade(true, grade);
        c.buyerFacts = b;
        (, uint256 refund,) = DisputeLib.judge(c);
        assertLe(refund, c.amount);
    }
}
