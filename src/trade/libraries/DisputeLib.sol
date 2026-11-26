// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {SupplyChainLib} from "src/traceability/libraries/SupplyChainLib.sol";

/**
 * @title DisputeLib
 * @author 0xEmmyb2
 * @notice The judge: a pure function that decides an escrow dispute from the evidence both parties put forward.
 * No regulator, admin or arbiter is involved (project.md 8.4).
 * @dev Evidence is on-chain facts: {SupplyChain} checkpoints for the lot recorded after the sale (weights, seal
 * and condition checks, inspections and grades, audits, oracle reports). Each fact is either:
 * - independent: signed by someone outside both parties' organisations (an oracle device, an inspector,
 *   customs, a third-party warehouse...), so it is decisive; or
 * - party-signed: signed by the buyer's or seller's own organisation (e.g. the buyer reporting a broken seal at
 *   arrival). It counts unless the other side rebuts it with a LATER independent fact showing the opposite.
 *
 * Verdict, first rule that applies:
 * 1. `NoResponse`: the seller never responded or submitted evidence. Buyer refunded in full.
 * 2. `ComplianceFailure`: a required certificate is no longer valid. Buyer refunded in full.
 * 3. `IntegrityFailure`: proven broken seal, damage, failed audit or failed oracle report. Buyer refunded in full.
 * 4. `NotDelivered`: the buyer never got custody and the deadline passed. Buyer refunded in full.
 *    (`Pending`: the buyer has no custody yet and the deadline has not passed: wait.)
 * 5. `QualityShortfall`: proven missing weight and/or a lower average grade than attested at sale. Partial
 *    refund in proportion (weight % + grade %); the buyer keeps the lot.
 * 6. `SellerWins`: nothing proven. Seller paid in full.
 */
library DisputeLib {
    /**
     * @notice Outcome of judging a dispute, in rule order (see the library documentation).
     */
    enum Verdict {
        Pending,
        NoResponse,
        ComplianceFailure,
        IntegrityFailure,
        NotDelivered,
        QualityShortfall,
        SellerWins
    }

    /**
     * @notice Which side a verdict favours. `Split` is a partial refund.
     */
    enum Winner {
        None,
        Buyer,
        Seller,
        Split
    }

    /**
     * @notice The judged content of one checkpoint.
     * @param cpType Checkpoint type.
     * @param condition Observed condition.
     * @param withinTolerance Weights: within tolerance. Audit / OracleReport: passed.
     * @param independent True if signed by someone outside both parties' organisations.
     * @param gradeBps Attested grade, in basis points (0 = not graded).
     * @param timestamp When the checkpoint was recorded.
     * @param measuredQty Measured weight in grams (0 = not weighed).
     * @param referenceQty Trusted weight it was compared with.
     */
    struct Fact {
        SupplyChainLib.CheckpointType cpType;
        SupplyChainLib.Condition condition;
        bool withinTolerance;
        bool independent;
        uint16 gradeBps;
        uint64 timestamp;
        uint128 measuredQty;
        uint128 referenceQty;
    }

    /**
     * @notice Everything the judge needs to decide.
     * @param amount Order amount.
     * @param gradeAtSale Grade attested at sale, in basis points (0 = ungraded).
     * @param deliveryDeadline Delivery deadline.
     * @param now_ Current time.
     * @param sellerResponded Whether the seller responded or submitted evidence.
     * @param delivered Whether the buyer holds custody on the passport.
     * @param certificatesValid Whether every required certificate is still valid.
     * @param buyerFacts Facts put forward by the buyer.
     * @param sellerFacts Facts put forward by the seller.
     */
    struct Case {
        uint256 amount;
        uint16 gradeAtSale;
        uint64 deliveryDeadline;
        uint64 now_;
        bool sellerResponded;
        bool delivered;
        bool certificatesValid;
        Fact[] buyerFacts;
        Fact[] sellerFacts;
    }

    /**
     * @notice 100%, in basis points.
     */
    uint16 internal constant BPS = 10_000;

    /**
     * @notice Grade gap (absolute, in basis points) treated as assay noise.
     */
    uint16 internal constant GRADE_TOLERANCE_BPS = 100;

    /**
     * @notice Decides a dispute.
     * @param c The case.
     * @return verdict The verdict.
     * @return buyerRefund Amount refunded to the buyer.
     * @return lotToBuyer Whether the lot goes to the buyer.
     */
    function judge(Case memory c) internal pure returns (Verdict verdict, uint256 buyerRefund, bool lotToBuyer) {
        if (!c.sellerResponded) return (Verdict.NoResponse, c.amount, false);
        if (!c.certificatesValid) return (Verdict.ComplianceFailure, c.amount, false);
        if (_integrityProven(c)) return (Verdict.IntegrityFailure, c.amount, false);
        if (!c.delivered) {
            if (c.now_ <= c.deliveryDeadline) return (Verdict.Pending, 0, false);
            return (Verdict.NotDelivered, c.amount, false);
        }

        uint256 shortBps = weightShortfallBps(c) + gradeShortfallBps(c);
        if (shortBps > BPS) shortBps = BPS;
        if (shortBps != 0) return (Verdict.QualityShortfall, (c.amount * shortBps) / BPS, true);
        return (Verdict.SellerWins, 0, true);
    }

    /**
     * @notice Which side a verdict favours.
     * @param verdict The verdict.
     * @param buyerRefund Amount refunded to the buyer.
     * @param amount Order amount.
     * @return The winning side.
     */
    function winnerOf(Verdict verdict, uint256 buyerRefund, uint256 amount) internal pure returns (Winner) {
        if (verdict == Verdict.Pending) return Winner.None;
        if (verdict == Verdict.SellerWins) return Winner.Seller;
        if (verdict == Verdict.QualityShortfall && buyerRefund < amount) return Winner.Split;
        return Winner.Buyer;
    }

    /**
     * @notice The largest proven weight loss among the buyer's facts.
     * @dev A party-signed weighing counts unless rebutted by a later independent weighing within tolerance.
     * @param c The case.
     * @return maxShort Shortfall, in basis points of the reference weight.
     */
    function weightShortfallBps(Case memory c) internal pure returns (uint256 maxShort) {
        for (uint256 i; i < c.buyerFacts.length; ++i) {
            Fact memory f = c.buyerFacts[i];
            if (f.measuredQty == 0 || f.withinTolerance || f.measuredQty >= f.referenceQty) continue;
            if (!f.independent && _weightRebutted(f, c.sellerFacts)) continue;
            uint256 short = ((f.referenceQty - f.measuredQty) * BPS) / f.referenceQty;
            if (short > maxShort) maxShort = short;
        }
    }

    /**
     * @notice The grade shortfall against the grade attested at sale.
     * @dev Uses the average of all independent post-sale grade attestations either side put forward. Returns 0
     * when within {GRADE_TOLERANCE_BPS} or when there is no sale grade or no attestation.
     * @param c The case.
     * @return Shortfall, in basis points of the sale grade.
     */
    function gradeShortfallBps(Case memory c) internal pure returns (uint256) {
        if (c.gradeAtSale == 0) return 0;
        (uint256 sum, uint256 n) = _gradeSum(c.buyerFacts);
        (uint256 sum2, uint256 n2) = _gradeSum(c.sellerFacts);
        sum += sum2;
        n += n2;
        if (n == 0) return 0;
        uint256 avg = sum / n;
        if (avg + GRADE_TOLERANCE_BPS >= c.gradeAtSale) return 0;
        return ((c.gradeAtSale - avg) * BPS) / c.gradeAtSale;
    }

    /**
     * @dev Whether the buyer proved a broken seal, damage, failed audit or failed oracle report.
     * @param c The case.
     * @return True if an independent, or unrebutted party-signed, integrity failure exists.
     */
    function _integrityProven(Case memory c) private pure returns (bool) {
        for (uint256 i; i < c.buyerFacts.length; ++i) {
            Fact memory f = c.buyerFacts[i];
            if (!_isIntegrityFailure(f)) continue;
            if (f.independent || !_integrityRebutted(f, c.sellerFacts)) return true;
        }
        return false;
    }

    /**
     * @dev Whether a fact shows a broken seal, damage, a failed audit or a failed oracle report.
     * @param f The fact.
     * @return True for an integrity failure.
     */
    function _isIntegrityFailure(Fact memory f) private pure returns (bool) {
        if (f.condition == SupplyChainLib.Condition.SealBroken || f.condition == SupplyChainLib.Condition.Damaged) {
            return true;
        }
        return (f.cpType == SupplyChainLib.CheckpointType.Audit
                || f.cpType == SupplyChainLib.CheckpointType.OracleReport) && !f.withinTolerance;
    }

    /**
     * @dev A party-signed integrity claim is rebutted by a later independent check that found the lot in good
     * condition.
     * @param claim The party-signed claim.
     * @param counter The other side's facts.
     * @return True if rebutted.
     */
    function _integrityRebutted(Fact memory claim, Fact[] memory counter) private pure returns (bool) {
        for (uint256 i; i < counter.length; ++i) {
            Fact memory r = counter[i];
            if (
                r.independent && r.timestamp >= claim.timestamp && r.condition == SupplyChainLib.Condition.Good
                    && !_isIntegrityFailure(r)
            ) return true;
        }
        return false;
    }

    /**
     * @dev A party-signed weight claim is rebutted by a later independent weighing within tolerance.
     * @param claim The party-signed claim.
     * @param counter The other side's facts.
     * @return True if rebutted.
     */
    function _weightRebutted(Fact memory claim, Fact[] memory counter) private pure returns (bool) {
        for (uint256 i; i < counter.length; ++i) {
            Fact memory r = counter[i];
            if (r.independent && r.timestamp >= claim.timestamp && r.measuredQty != 0 && r.withinTolerance) {
                return true;
            }
        }
        return false;
    }

    /**
     * @dev Sums the independent inspection grades among `facts`.
     * @param facts Facts to scan.
     * @return sum Sum of the grades, in basis points.
     * @return n Number of grades summed.
     */
    function _gradeSum(Fact[] memory facts) private pure returns (uint256 sum, uint256 n) {
        for (uint256 i; i < facts.length; ++i) {
            Fact memory f = facts[i];
            if (f.independent && f.cpType == SupplyChainLib.CheckpointType.Inspection && f.gradeBps != 0) {
                sum += f.gradeBps;
                n += 1;
            }
        }
    }
}
