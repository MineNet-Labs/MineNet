// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {MineNetFixture} from "test/utils/MineNetFixture.sol";
import {Marketplace} from "src/trade/Marketplace.sol";
import {EscrowManager} from "src/trade/EscrowManager.sol";
import {SupplyChain} from "src/traceability/SupplyChain.sol";
import {EscrowLib} from "src/trade/libraries/EscrowLib.sol";
import {MarketplaceLib} from "src/trade/libraries/MarketplaceLib.sol";
import {CurrencyLib} from "src/finance/libraries/CurrencyLib.sol";
import {SupplyChainLib} from "src/traceability/libraries/SupplyChainLib.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MarketplaceTest is MineNetFixture {
    uint256 constant PER_KG = 25e6; // 25 USDC per kg

    function _request(uint128 minQty, uint128 maxQty, uint16 minGrade) internal returns (uint256 requestId) {
        vm.prank(buyer);
        requestId = market.createBuyRequest(
            MarketplaceLib.RequestParams({
                mineralType: TIN,
                paymentToken: usdc,
                minQty: minQty,
                maxQty: maxQty,
                maxPricePerKg: PER_KG,
                minGradeBps: minGrade,
                deliveryWindow: 14 days,
                expiresAt: uint64(block.timestamp + 30 days),
                termsHash: H
            })
        );
    }

    function _weigh(uint256 id, uint128 grams) internal {
        vm.prank(oracle);
        supplyChain.recordCheckpoint(
            SupplyChainLib.CheckpointInput(
                id, SupplyChainLib.CheckpointType.Weighing, grams, SupplyChainLib.Condition.Good, 0, H, 0
            )
        );
    }

    // ================================================================ listings

    function test_CreateListing() public {
        (uint256 id, uint256 listingId) = _listed(10_000);
        MarketplaceLib.Listing memory l = market.getListing(listingId);
        assertEq(l.tokenId, id);
        assertEq(l.seller, miner);
        assertEq(l.price, PRICE);
        assertEq(l.version, 1);
        assertEq(uint8(l.status), uint8(MarketplaceLib.ListingStatus.Active));
        assertEq(market.listingOf(id), listingId);
        assertTrue(market.isListingLive(listingId));
        assertEq(market.quoteListing(listingId), PRICE);
        assertEq(passport.ownerOf(id), miner, "the lot stays in the seller's wallet");
    }

    function test_CreateListing_Guards() public {
        uint256 registered = _register(10_000); // not inspected
        vm.prank(miner);
        vm.expectRevert(abi.encodeWithSelector(MarketplaceLib.Marketplace__LotNotInspected.selector, registered));
        market.createListing(_listingParams(registered, _fixed(), PRICE));

        uint256 id = _inspected(10_000);
        vm.prank(buyer); // not the owner
        vm.expectRevert(abi.encodeWithSelector(MarketplaceLib.Marketplace__NotLotOwner.selector, id, buyer));
        market.createListing(_listingParams(id, _fixed(), PRICE));

        vm.prank(transporter); // no seller role
        vm.expectRevert(abi.encodeWithSelector(MarketplaceLib.Marketplace__NotSeller.selector, transporter));
        market.createListing(_listingParams(id, _fixed(), PRICE));

        MarketplaceLib.ListingParams memory p = _listingParams(id, _fixed(), 0);
        vm.prank(miner);
        vm.expectRevert(MarketplaceLib.Marketplace__InvalidPrice.selector);
        market.createListing(p);

        p = _listingParams(id, _fixed(), PRICE);
        p.paymentToken = IERC20(address(0xdead));
        vm.prank(miner);
        vm.expectRevert(
            abi.encodeWithSelector(MarketplaceLib.Marketplace__TokenNotAllowed.selector, IERC20(address(0xdead)))
        );
        market.createListing(p);

        p = _listingParams(id, _fixed(), PRICE);
        p.expiresAt = uint64(block.timestamp + 91 days);
        vm.prank(miner);
        vm.expectRevert(abi.encodeWithSelector(MarketplaceLib.Marketplace__InvalidExpiry.selector, p.expiresAt));
        market.createListing(p);

        p = _listingParams(id, _fixed(), PRICE);
        p.deliveryWindow = 10 minutes;
        vm.prank(miner);
        vm.expectRevert(MarketplaceLib.Marketplace__InvalidWindow.selector);
        market.createListing(p);
    }

    function test_CreateListing_RequiresEscrowApproval() public {
        uint256 id = _inspected(10_000);
        vm.prank(miner);
        passport.setApprovalForAll(address(escrow), false);
        vm.prank(miner);
        vm.expectRevert(abi.encodeWithSelector(MarketplaceLib.Marketplace__EscrowNotApproved.selector, id));
        market.createListing(_listingParams(id, _fixed(), PRICE));
    }

    function test_CreateListing_FrozenLotRejected() public {
        uint256 id = _inspected(10_000);
        vm.prank(regulator);
        passport.freezeLot(id, H);
        vm.prank(miner);
        vm.expectRevert(abi.encodeWithSelector(MarketplaceLib.Marketplace__LotFrozen.selector, id));
        market.createListing(_listingParams(id, _fixed(), PRICE));
    }

    function test_OneLiveListingPerLot_ExpiredCanBeReplaced() public {
        (uint256 id, uint256 listingId) = _listed(10_000);
        vm.prank(miner);
        vm.expectRevert(abi.encodeWithSelector(MarketplaceLib.Marketplace__AlreadyListed.selector, id, listingId));
        market.createListing(_listingParams(id, _fixed(), PRICE));

        vm.warp(block.timestamp + 31 days);
        assertFalse(market.isListingLive(listingId));
        vm.prank(miner);
        uint256 relisted = market.createListing(_listingParams(id, _fixed(), PRICE));
        assertEq(market.listingOf(id), relisted);
    }

    // ================================================================ updates & delisting

    function test_UpdatePrice() public {
        (, uint256 listingId) = _listed(10_000);
        vm.expectEmit(true, false, false, true, address(market));
        emit MarketplaceLib.ListingUpdated(
            listingId,
            2,
            USD,
            MarketplaceLib.PriceModel.FixedTotal,
            PRICE,
            45_000e6,
            14 days,
            uint64(block.timestamp + 30 days),
            H
        );
        vm.prank(miner);
        market.updatePrice(listingId, 45_000e6);

        MarketplaceLib.Listing memory l = market.getListing(listingId);
        assertEq(l.price, 45_000e6);
        assertEq(l.version, 2);
        assertEq(market.quoteListing(listingId), 45_000e6);
    }

    function test_UpdateListing_AllTerms() public {
        (, uint256 listingId) = _listed(10_000);
        uint64 newExpiry = uint64(block.timestamp + 60 days);
        vm.prank(miner);
        market.updateListing(
            listingId,
            MarketplaceLib.ListingUpdate({
                priceCurrency: bytes32(0),
                priceModel: MarketplaceLib.PriceModel.PerKilogram,
                price: PER_KG,
                deliveryWindow: 21 days,
                expiresAt: newExpiry,
                termsHash: keccak256("FOB Kigali")
            })
        );
        MarketplaceLib.Listing memory l = market.getListing(listingId);
        assertEq(uint8(l.priceModel), uint8(MarketplaceLib.PriceModel.PerKilogram));
        assertEq(l.deliveryWindow, 21 days);
        assertEq(l.expiresAt, newExpiry);
        assertEq(l.termsHash, keccak256("FOB Kigali"));
        assertEq(market.quoteListing(listingId), (PER_KG * 10_000) / 1_000); // 10 kg x 25 USDC
    }

    function test_Update_OnlySellerAndOnlyLive() public {
        (, uint256 listingId) = _listed(10_000);
        vm.prank(buyer);
        vm.expectRevert(abi.encodeWithSelector(MarketplaceLib.Marketplace__NotSeller.selector, buyer));
        market.updatePrice(listingId, 1);

        vm.prank(miner);
        vm.expectRevert(MarketplaceLib.Marketplace__InvalidPrice.selector);
        market.updatePrice(listingId, 0);

        vm.warp(block.timestamp + 31 days);
        vm.prank(miner);
        vm.expectRevert(abi.encodeWithSelector(MarketplaceLib.Marketplace__ListingNotLive.selector, listingId));
        market.updatePrice(listingId, 1);
    }

    function test_Delist() public {
        (uint256 id, uint256 listingId) = _listed(10_000);
        vm.prank(buyer);
        vm.expectRevert(abi.encodeWithSelector(MarketplaceLib.Marketplace__NotSeller.selector, buyer));
        market.delist(listingId);

        vm.prank(miner);
        market.delist(listingId);
        assertEq(uint8(market.getListing(listingId).status), uint8(MarketplaceLib.ListingStatus.Delisted));
        assertEq(market.listingOf(id), 0);

        vm.prank(buyer);
        vm.expectRevert(abi.encodeWithSelector(MarketplaceLib.Marketplace__ListingNotLive.selector, listingId));
        market.buyListing(listingId, type(uint256).max);

        vm.prank(miner); // can list again
        market.createListing(_listingParams(id, _fixed(), PRICE));
    }

    // ================================================================ purchases

    function test_Buy_OpensEscrowOrder() public {
        (uint256 id, uint256 listingId) = _listed(10_000);
        uint256 before = usdc.balanceOf(buyer);
        uint256 orderId = _buy(buyer, listingId);

        assertEq(usdc.balanceOf(buyer), before - PRICE);
        assertEq(usdc.balanceOf(address(escrow)), PRICE);
        assertEq(usdc.balanceOf(address(market)), 0, "the marketplace never keeps sale funds");
        MarketplaceLib.Listing memory l = market.getListing(listingId);
        assertEq(uint8(l.status), uint8(MarketplaceLib.ListingStatus.Sold));
        assertEq(l.orderId, orderId);
        assertEq(escrow.getOrder(orderId).buyer, buyer);
        assertTrue(passport.escrowLocked(id));

        vm.prank(buyer2);
        vm.expectRevert(abi.encodeWithSelector(MarketplaceLib.Marketplace__ListingNotLive.selector, listingId));
        market.buyListing(listingId, type(uint256).max);
    }

    function test_Buy_PerKilogram_UsesTrustedWeight() public {
        uint256 id = _inspected(10_000);
        _weigh(id, 9_900); // weighbridge: 9.9 kg (within tolerance)
        vm.prank(miner);
        uint256 listingId = market.createListing(_listingParams(id, MarketplaceLib.PriceModel.PerKilogram, PER_KG));

        uint256 expected = (PER_KG * 9_900) / 1_000;
        assertEq(market.quoteListing(listingId), expected);
        uint256 orderId = _buy(buyer, listingId);
        assertEq(escrow.getOrder(orderId).amount, expected);
    }

    function test_Buy_MaxTotalProtectsAgainstReprice() public {
        (, uint256 listingId) = _listed(10_000);
        vm.prank(miner); // front-runs the buyer with a higher price
        market.updatePrice(listingId, PRICE * 2);

        vm.prank(buyer);
        vm.expectRevert(abi.encodeWithSelector(MarketplaceLib.Marketplace__PriceAboveMax.selector, PRICE * 2, PRICE));
        market.buyListing(listingId, PRICE);
    }

    function test_Buy_Guards() public {
        (uint256 id, uint256 listingId) = _listed(10_000);

        vm.prank(miner);
        vm.expectRevert(abi.encodeWithSelector(MarketplaceLib.Marketplace__NotBuyer.selector, miner));
        market.buyListing(listingId, type(uint256).max);

        vm.prank(miner); // the seller sold the lot directly: the listing is stale
        passport.transferFrom(miner, buyer2, id);
        vm.prank(buyer);
        vm.expectRevert(abi.encodeWithSelector(MarketplaceLib.Marketplace__ListingStale.selector, listingId));
        market.buyListing(listingId, type(uint256).max);
    }

    function test_Buy_SelfTradeBlocked_ForTraderReselling() public {
        (uint256 id, uint256 orderId) = _acceptedOrder();
        _deliver(id, miner, buyer);
        vm.prank(buyer);
        escrow.releaseFunds(orderId);

        // the buyer now resells as a trader
        vm.startPrank(buyer);
        passport.setApprovalForAll(address(escrow), true);
        uint256 resale = market.createListing(_listingParams(id, _fixed(), PRICE + 5_000e6));
        vm.expectRevert(MarketplaceLib.Marketplace__SelfTrade.selector);
        market.buyListing(resale, type(uint256).max);
        vm.stopPrank();

        uint256 order2 = _buy(buyer2, resale);
        assertEq(escrow.getOrder(order2).seller, buyer);
    }

    // ================================================================ buy requests

    function test_BuyRequest_LocksDeposit() public {
        uint256 before = usdc.balanceOf(buyer);
        uint256 requestId = _request(8_000, 12_000, 0);
        uint256 deposit = market.requestDeposit(PER_KG, 12_000);
        assertEq(deposit, 300e6); // 12 kg x 25 USDC
        assertEq(usdc.balanceOf(buyer), before - deposit);
        assertEq(market.getBuyRequest(requestId).lockedAmount, deposit);
    }

    function test_ClaimBuyRequest_LowerPrice_RefundsDifference() public {
        uint256 requestId = _request(8_000, 12_000, 0);
        uint256 id = _inspected(10_000);
        (, uint256 listingId) = (0, 0);

        vm.prank(miner);
        listingId = market.createListing(_listingParams(id, _fixed(), PRICE));

        uint256 offer = 20e6; // 20 USDC/kg, under the buyer's 25 max
        vm.prank(miner);
        uint256 orderId = market.claimBuyRequest(requestId, id, offer);

        uint256 total = (offer * 10_000) / 1_000; // 200 USDC
        uint256 refund = 300e6 - total;
        EscrowLib.Order memory o = escrow.getOrder(orderId);
        assertEq(o.amount, total);
        assertEq(o.buyer, buyer);
        assertEq(o.seller, miner);
        assertEq(market.claimable(usdc, buyer), refund);
        assertEq(usdc.balanceOf(address(market)), refund, "only the refund stays behind");
        assertTrue(passport.escrowLocked(id));

        MarketplaceLib.BuyRequest memory r = market.getBuyRequest(requestId);
        assertEq(uint8(r.status), uint8(MarketplaceLib.RequestStatus.Filled));
        assertEq(r.filledTokenId, id);
        assertEq(uint8(market.getListing(listingId).status), uint8(MarketplaceLib.ListingStatus.Delisted));

        uint256 before = usdc.balanceOf(buyer);
        vm.prank(buyer);
        market.withdraw(usdc);
        assertEq(usdc.balanceOf(buyer), before + refund);
    }

    function test_ClaimBuyRequest_Matching() public {
        uint256 requestId = _request(8_000, 12_000, 6_000);
        uint256 small = _inspected(5_000);

        vm.startPrank(miner); // a heavier lot is split instead (see MarketplaceNegotiation.t.sol)
        vm.expectRevert(
            abi.encodeWithSelector(MarketplaceLib.Marketplace__WeightOutOfRange.selector, 5_000, 8_000, 12_000)
        );
        market.claimBuyRequest(requestId, small, PER_KG);
        vm.stopPrank();

        uint256 id = _inspected(10_000);
        vm.prank(miner); // ungraded lot vs a 60% minimum
        vm.expectRevert(abi.encodeWithSelector(MarketplaceLib.Marketplace__GradeTooLow.selector, 0, 6_000));
        market.claimBuyRequest(requestId, id, PER_KG);

        _grade(id, 5_500);
        vm.prank(miner);
        vm.expectRevert(abi.encodeWithSelector(MarketplaceLib.Marketplace__GradeTooLow.selector, 5_500, 6_000));
        market.claimBuyRequest(requestId, id, PER_KG);

        _grade(id, 6_500);
        vm.prank(miner);
        vm.expectRevert(MarketplaceLib.Marketplace__InvalidPrice.selector);
        market.claimBuyRequest(requestId, id, PER_KG + 1); // above the buyer's max

        vm.prank(miner);
        market.claimBuyRequest(requestId, id, PER_KG);
    }

    function test_ClaimBuyRequest_MineralMismatch() public {
        uint256 requestId = _request(8_000, 12_000, 0);
        vm.prank(miner);
        uint256 id = passport.registerLot(keccak256("coltan-lot"), keccak256("COLTAN"), 10_000, site, H);
        _assignTo(id, inspector);
        vm.prank(inspector);
        passport.submitInspection(id, true, H);

        vm.prank(miner);
        vm.expectRevert(
            abi.encodeWithSelector(MarketplaceLib.Marketplace__MineralMismatch.selector, TIN, keccak256("COLTAN"))
        );
        market.claimBuyRequest(requestId, id, PER_KG);
    }

    function test_ClaimBuyRequest_ExpiredOrFilledOrSelf() public {
        uint256 requestId = _request(8_000, 12_000, 0);
        uint256 id = _inspected(10_000);

        vm.prank(buyer);
        vm.expectRevert(MarketplaceLib.Marketplace__SelfTrade.selector);
        market.claimBuyRequest(requestId, id, PER_KG);

        vm.warp(block.timestamp + 31 days);
        vm.prank(miner);
        vm.expectRevert(abi.encodeWithSelector(MarketplaceLib.Marketplace__RequestExpired.selector, requestId));
        market.claimBuyRequest(requestId, id, PER_KG);
    }

    function test_CancelBuyRequest() public {
        uint256 requestId = _request(8_000, 12_000, 0);
        uint256 before = usdc.balanceOf(buyer);

        vm.prank(buyer2);
        vm.expectRevert(abi.encodeWithSelector(MarketplaceLib.Marketplace__NotBuyer.selector, buyer2));
        market.cancelBuyRequest(requestId);

        vm.prank(buyer);
        market.cancelBuyRequest(requestId);
        assertEq(usdc.balanceOf(buyer), before + 300e6);

        uint256 id = _inspected(10_000);
        vm.prank(miner);
        vm.expectRevert(abi.encodeWithSelector(MarketplaceLib.Marketplace__RequestNotOpen.selector, requestId));
        market.claimBuyRequest(requestId, id, PER_KG);

        vm.prank(buyer);
        vm.expectRevert(abi.encodeWithSelector(MarketplaceLib.Marketplace__RequestNotOpen.selector, requestId));
        market.cancelBuyRequest(requestId);
    }

    function test_Pause() public {
        vm.prank(outsider);
        vm.expectRevert(abi.encodeWithSelector(MarketplaceLib.Marketplace__NotRegistryAdmin.selector, outsider));
        market.pause();

        uint256 requestId = _request(8_000, 12_000, 0);
        vm.prank(admin);
        market.pause();
        uint256 id = _inspected(10_000);
        vm.prank(miner);
        vm.expectRevert();
        market.createListing(_listingParams(id, _fixed(), PRICE));
        vm.prank(buyer); // cancelling (refunds) still works while paused
        market.cancelBuyRequest(requestId);
    }

    // ================================================================ currencies

    function _rwfListing(uint256 id, uint256 priceRwf) internal returns (uint256 listingId) {
        MarketplaceLib.ListingParams memory p = _listingParams(id, _fixed(), priceRwf);
        p.priceCurrency = RWF;
        vm.prank(miner);
        listingId = market.createListing(p);
    }

    function test_PriceInRwf_PayInUsdc_AtLiveRate() public {
        uint256 id = _inspected(10_000);
        uint256 listingId = _rwfListing(id, 62_500_000); // 62.5M RWF = 50,000 USD at 1,250 RWF/USD

        (bytes32 ccy, uint256 inCcy, uint256 usd, uint256 tokenAmount) = market.quoteListingDetailed(listingId);
        assertEq(ccy, RWF);
        assertEq(inCcy, 62_500_000);
        assertEq(usd, 50_000e6, "shown in USD for general use");
        assertEq(tokenAmount, 50_000e6);

        uint256 orderId = _buy(buyer, listingId);
        assertEq(escrow.getOrder(orderId).amount, 50_000e6);
        assertEq(escrow.getOrder(orderId).usdValue, 50_000e6);
    }

    function test_PreferredCurrency_IsTheDefault() public {
        vm.prank(miner);
        market.setPreferredCurrency(RWF);
        uint256 id = _inspected(10_000);
        MarketplaceLib.ListingParams memory p = _listingParams(id, _fixed(), 1_000_000);
        p.priceCurrency = bytes32(0); // use my preference
        vm.prank(miner);
        uint256 listingId = market.createListing(p);
        assertEq(market.getListing(listingId).priceCurrency, RWF);

        vm.prank(miner);
        vm.expectRevert(abi.encodeWithSelector(MarketplaceLib.Marketplace__UnknownCurrency.selector, bytes32("XYZ")));
        market.setPreferredCurrency("XYZ");
    }

    function test_PayInLocalStablecoin() public {
        uint256 id = _inspected(10_000);
        MarketplaceLib.ListingParams memory p = _listingParams(id, _fixed(), 50_000e6); // priced in USD
        p.paymentToken = rwfCoin; // ... settled in RWF stablecoin
        vm.prank(miner);
        uint256 listingId = market.createListing(p);
        assertEq(market.quoteListing(listingId), 62_500_000);

        rwfCoin.mint(buyer2, 62_500_000);
        vm.startPrank(buyer2);
        rwfCoin.approve(address(market), type(uint256).max);
        uint256 orderId = market.buyListing(listingId, 62_500_000);
        vm.stopPrank();
        assertEq(rwfCoin.balanceOf(address(escrow)), 62_500_000);
        assertEq(escrow.getOrder(orderId).usdValue, 50_000e6);
    }

    function test_RateMove_ProtectedByMaxTotal() public {
        uint256 id = _inspected(10_000);
        uint256 listingId = _rwfListing(id, 62_500_000);
        uint256 quoted = market.quoteListing(listingId);

        vm.prank(oracle); // the franc strengthens 4%: the USDC price rises
        rwfFeed.postRate(83_200);
        vm.prank(buyer);
        vm.expectRevert(abi.encodeWithSelector(MarketplaceLib.Marketplace__PriceAboveMax.selector, 52_000e6, quoted));
        market.buyListing(listingId, quoted);
    }

    function test_StaleRate_BlocksRwfPurchase() public {
        uint256 id = _inspected(10_000);
        uint256 listingId = _rwfListing(id, 62_500_000);
        (,,, uint256 postedAt,) = rwfFeed.latestRoundData();
        vm.warp(block.timestamp + 2 days);
        vm.prank(buyer);
        vm.expectRevert(abi.encodeWithSelector(CurrencyLib.CurrencyManager__StaleRate.selector, RWF, postedAt));
        market.buyListing(listingId, type(uint256).max);

        vm.prank(oracle);
        rwfFeed.postRate(RWF_RATE);
        _buy(buyer, listingId);
    }

    function test_UnknownCurrencyRejected() public {
        uint256 id = _inspected(10_000);
        MarketplaceLib.ListingParams memory p = _listingParams(id, _fixed(), 1);
        p.priceCurrency = "XYZ";
        vm.prank(miner);
        vm.expectRevert(abi.encodeWithSelector(MarketplaceLib.Marketplace__UnknownCurrency.selector, bytes32("XYZ")));
        market.createListing(p);
    }

    // ================================================================ fuzz

    /// The deposit always covers any valid claim, and deposit = escrowed total + refund, exactly.
    function testFuzz_BuyRequestAccounting(uint128 maxQty, uint256 maxPrice, uint256 offer, uint128 weight) public {
        maxQty = uint128(bound(maxQty, 1_000, 50_000_000));
        weight = uint128(bound(weight, 1_000, maxQty));
        maxPrice = bound(maxPrice, 1e6, 100_000e6);
        offer = bound(offer, 1e6, maxPrice);

        usdc.mint(buyer, market.requestDeposit(maxPrice, maxQty));
        vm.prank(buyer);
        uint256 requestId = market.createBuyRequest(
            MarketplaceLib.RequestParams(
                TIN, usdc, 1_000, maxQty, maxPrice, 0, 14 days, uint64(block.timestamp + 1 days), H
            )
        );
        uint256 deposit = market.getBuyRequest(requestId).lockedAmount;
        uint256 id = _inspected(weight);
        vm.prank(miner);
        uint256 orderId = market.claimBuyRequest(requestId, id, offer);

        // what is left of a partly filled request stays locked for the rest
        uint256 stillLocked = market.getBuyRequest(requestId).lockedAmount;
        assertEq(escrow.getOrder(orderId).amount + market.claimable(usdc, buyer) + stillLocked, deposit);
        assertEq(usdc.balanceOf(address(market)), market.claimable(usdc, buyer) + stillLocked);
    }
}
