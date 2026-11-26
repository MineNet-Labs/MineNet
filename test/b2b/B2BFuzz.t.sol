// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";
import {MineNetFixture} from "test/utils/MineNetFixture.sol";
import {B2BLib} from "src/b2b/libraries/B2BLib.sol";
import {ServicesLib} from "src/b2b/libraries/ServicesLib.sol";

/**
 * @title B2BMathFuzzTest
 * @notice Stateless fuzz tests of the B2B pricing maths.
 */
contract B2BMathFuzzTest is Test {
    function testFuzz_Bounds_ContainQuantity(uint128 quantity, uint16 toleranceBps) public pure {
        quantity = uint128(bound(quantity, 1, type(uint64).max));
        toleranceBps = uint16(bound(toleranceBps, 0, 2_000));
        (uint128 min, uint128 max) = B2BLib.bounds(quantity, toleranceBps);
        assertLe(min, quantity);
        assertGe(max, quantity);
        assertEq(uint256(quantity - min), uint256(max - quantity)); // symmetric band
    }

    function testFuzz_PriceOf_MonotonicInWeight(uint256 a, uint256 b, uint256 pricePerKg) public pure {
        a = bound(a, 0, 1e15);
        b = bound(b, a, 1e15);
        pricePerKg = bound(pricePerKg, 0, 1e24);
        assertLe(B2BLib.priceOf(a, pricePerKg), B2BLib.priceOf(b, pricePerKg));
    }

    function testFuzz_ServicesPriceOf_WeightKindsArePerKg(uint256 units, uint256 rate) public pure {
        units = bound(units, 0, 1e15);
        rate = bound(rate, 0, 1e24);
        assertEq(ServicesLib.priceOf(ServicesLib.ServiceKind.Haulage, units, rate), units * rate / 1_000);
        assertEq(ServicesLib.priceOf(ServicesLib.ServiceKind.Security, units, rate), units * rate);
    }
}

/**
 * @title B2BFlowFuzzTest
 * @notice Stateless fuzz tests of complete supply and service flows: whatever the inputs, payouts add up to the
 * escrow and the seller is paid exactly for what was delivered.
 */
contract B2BFlowFuzzTest is MineNetFixture {
    function setUp() public override {
        super.setUp();
        usdc.mint(refinery, type(uint128).max);
        vm.prank(refinery);
        usdc.approve(address(b2b), type(uint256).max);
        usdc.mint(miner, type(uint128).max);
        vm.prank(miner);
        usdc.approve(address(services), type(uint256).max);
        vm.prank(miner);
        passport.setApprovalForAll(address(b2b), true);
    }

    function _supplyTerms(uint128 quantity, uint16 toleranceBps, uint256 pricePerKg)
        internal
        view
        returns (B2BLib.Terms memory t)
    {
        t.seller = B2BLib.Side.Proposer;
        t.supply = B2BLib.SupplyTerms({
            mineralType: TIN,
            quantityPerDelivery: quantity,
            quantityToleranceBps: toleranceBps,
            minGradeBps: 0,
            pricePerKg: pricePerKg,
            totalDeliveries: 1,
            deliveryInterval: 0,
            firstDeliveryOffset: 7 days
        });
        t.paymentToken = usdc;
        t.reviewPeriod = 3 days;
        t.proposalExpiresAt = uint64(block.timestamp + 7 days);
        t.termsHash = keccak256("fuzz");
    }

    /// Any weight inside the tolerance band is paid at exactly price x weight, and seller + refund == escrow.
    function testFuzz_SupplyDelivery_PaysDeliveredWeight(
        uint128 quantity,
        uint16 toleranceBps,
        uint256 pricePerKg,
        uint256 weightSeed
    ) public {
        quantity = uint128(bound(quantity, 1_000, 100_000_000)); // 1 kg .. 100 t
        toleranceBps = uint16(bound(toleranceBps, 0, 2_000));
        pricePerKg = bound(pricePerKg, 1, 1_000_000e6);
        (uint128 min, uint128 max) = B2BLib.bounds(quantity, toleranceBps);
        uint128 weight = uint128(bound(weightSeed, min, max));

        vm.prank(miner);
        uint256 id = b2b.propose(refinery, _supplyTerms(quantity, toleranceBps, pricePerKg));
        vm.prank(refinery);
        b2b.sign(id, 1);
        vm.prank(refinery);
        b2b.fundDelivery(id, 0);
        (uint256 goodsFunded,) = b2b.amountDue(id, 0);

        uint256[] memory ids = new uint256[](1);
        ids[0] = _inspected(weight);
        vm.prank(miner);
        b2b.dispatchDelivery(id, 0, ids, 0, keccak256("note"));
        _moveCustody(ids[0], miner, refinery);
        vm.prank(refinery);
        b2b.acceptDelivery(id, 0);

        uint256 expected = uint256(weight) * pricePerKg / 1_000;
        assertEq(b2b.claimable(usdc, miner), expected);
        assertEq(b2b.claimable(usdc, miner) + b2b.claimable(usdc, refinery), goodsFunded);
        assertEq(usdc.balanceOf(address(b2b)), goodsFunded);
        assertEq(passport.ownerOf(ids[0]), refinery);
    }

    /// A weight outside the tolerance band can never be dispatched.
    function testFuzz_SupplyDelivery_RejectsWeightOutsideBand(uint128 quantity, uint16 toleranceBps, bool above)
        public
    {
        quantity = uint128(bound(quantity, 10_000, 100_000_000));
        toleranceBps = uint16(bound(toleranceBps, 0, 2_000));
        (uint128 min, uint128 max) = B2BLib.bounds(quantity, toleranceBps);
        uint128 weight = above ? max + 1 : min - 1;

        vm.prank(miner);
        uint256 id = b2b.propose(refinery, _supplyTerms(quantity, toleranceBps, 20e6));
        vm.prank(refinery);
        b2b.sign(id, 1);
        vm.prank(refinery);
        b2b.fundDelivery(id, 0);
        uint256[] memory ids = new uint256[](1);
        ids[0] = _inspected(weight);
        vm.prank(miner);
        vm.expectRevert(abi.encodeWithSelector(B2BLib.B2B__QuantityOutOfTolerance.selector, weight, min, max));
        b2b.dispatchDelivery(id, 0, ids, 0, keccak256("note"));
    }

    /// A claimed service is capped at its budget, and provider + refund == budget.
    function testFuzz_ServiceClaim_CappedAndConserved(uint128 maxUnits, uint256 rate, uint128 claimed) public {
        maxUnits = uint128(bound(maxUnits, 1, 10_000));
        rate = bound(rate, 1, 1_000_000e6);
        claimed = uint128(bound(claimed, 1, type(uint64).max));

        ServicesLib.Terms memory t;
        t.service = ServicesLib.ServiceTerms({
            kind: ServicesLib.ServiceKind.Consulting,
            provider: B2BLib.Side.Counterparty,
            ratePerUnit: rate,
            maxUnitsPerJob: maxUnits,
            totalJobs: 1,
            jobInterval: 0,
            firstJobOffset: 7 days
        });
        t.paymentToken = usdc;
        t.reviewPeriod = 3 days;
        t.proposalExpiresAt = uint64(block.timestamp + 7 days);
        t.termsHash = keccak256("fuzz");
        vm.prank(miner);
        uint256 id = services.propose(auditor, t);
        vm.prank(auditor);
        services.sign(id, 1);
        vm.prank(miner);
        services.fundJob(id, 0);
        uint256 budget = services.budgetOf(id);

        uint256[] memory none;
        vm.warp(services.dueAt(id, 0));
        vm.prank(auditor);
        services.claimJob(id, 0, none, none, claimed, keccak256("timesheet"));
        vm.prank(miner);
        services.acceptJob(id, 0);

        uint256 billed = uint256(claimed < maxUnits ? claimed : maxUnits) * rate;
        assertEq(services.claimable(usdc, auditor), billed);
        assertEq(services.claimable(usdc, auditor) + services.claimable(usdc, miner), budget);
    }
}
