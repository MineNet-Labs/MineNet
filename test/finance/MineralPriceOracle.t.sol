// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {MockV3Aggregator} from "@chainlink/contracts/src/v0.8/shared/mocks/MockV3Aggregator.sol";
import {MineNetFixture} from "test/utils/MineNetFixture.sol";
import {MineralPriceOracle} from "src/finance/MineralPriceOracle.sol";

contract MineralPriceOracleTest is MineNetFixture {
    bytes32 constant GOLD = keccak256("GOLD");
    MockV3Aggregator xauUsd;

    function setUp() public override {
        super.setUp();
        vm.warp(30 days); // realistic clock so staleness maths is meaningful
        xauUsd = new MockV3Aggregator(8, 2_650e8); // Chainlink XAU / USD style feed: 8 decimals
        vm.prank(admin);
        prices.setFeed(GOLD, xauUsd, 1 days, "TROY_OUNCE");
    }

    function test_LatestPrice_ScalesTo18Decimals() public view {
        (uint256 price, bytes32 unit, uint256 updatedAt) = prices.latestPrice(GOLD);
        assertEq(price, 2_650e18);
        assertEq(unit, bytes32("TROY_OUNCE"));
        assertEq(updatedAt, block.timestamp);
        assertEq(prices.minerals().length, 1);
    }

    function test_LatestPrice_RejectsStaleAndBadAnswers() public {
        vm.warp(block.timestamp + 1 days + 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                MineralPriceOracle.MineralPriceOracle__Stale.selector, GOLD, block.timestamp - 1 days - 1
            )
        );
        prices.latestPrice(GOLD);

        xauUsd.updateAnswer(0);
        vm.expectRevert(
            abi.encodeWithSelector(MineralPriceOracle.MineralPriceOracle__InvalidAnswer.selector, GOLD, int256(0))
        );
        prices.latestPrice(GOLD);
    }

    function test_NoFeed() public {
        vm.expectRevert(abi.encodeWithSelector(MineralPriceOracle.MineralPriceOracle__NoFeed.selector, TIN));
        prices.latestPrice(TIN);
    }

    function test_SetFeed_OnlyAdminAndNoDuplicates() public {
        vm.prank(outsider);
        vm.expectRevert(
            abi.encodeWithSelector(MineralPriceOracle.MineralPriceOracle__NotRegistryAdmin.selector, outsider)
        );
        prices.setFeed(TIN, xauUsd, 1 days, "TONNE");

        vm.startPrank(admin);
        prices.setFeed(GOLD, MockV3Aggregator(address(0)), 0, bytes32(0)); // remove
        prices.setFeed(GOLD, xauUsd, 1 days, "TROY_OUNCE"); // re-add
        vm.stopPrank();
        assertEq(prices.minerals().length, 1);
    }

    /// MINENET's own OracleRateFeed works as a price feed where Chainlink has none (e.g. tin).
    function test_OracleRateFeedAsMineralFeed() public {
        vm.prank(admin);
        prices.setFeed(TIN, rwfFeed, 60 days, "TONNE");
        (uint256 price,,) = prices.latestPrice(TIN);
        assertEq(price, uint256(RWF_RATE) * 1e10);
    }
}
