// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {MineNetFixture} from "test/utils/MineNetFixture.sol";
import {PassportLib} from "src/traceability/libraries/PassportLib.sol";
import {MarketplaceLib} from "src/trade/libraries/MarketplaceLib.sol";
import {EscrowLib} from "src/trade/libraries/EscrowLib.sol";
import {Roles} from "src/access/libraries/Roles.sol";

/// Buy requests filled by several lots, and sales negotiated off-chain then settled with a signed offer.
contract MarketplaceNegotiationTest is MineNetFixture {
    uint256 constant PER_KG = 25e6; // 25 USDC per kg

    address signer;
    uint256 signerKey;
    bytes32 domainSeparator;

    function setUp() public override {
        super.setUp();
        (signer, signerKey) = makeAddrAndKey("keyed-buyer");
        vm.prank(admin);
        registry.onboard(signer, Roles.BUYER, "org-keyed-buyer", H, uint64(block.timestamp + 365 days));
        usdc.mint(signer, 1_000_000e6);
        vm.prank(signer);
        usdc.approve(address(market), type(uint256).max);
        domainSeparator = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256("MineNet Marketplace"),
                keccak256("1"),
                block.chainid,
                address(market)
            )
        );
    }

    // ---------------------------------------------------------------- helpers

    function _request(uint128 minQty, uint128 maxQty) internal returns (uint256 requestId) {
        vm.prank(buyer);
        requestId = market.createBuyRequest(
            MarketplaceLib.RequestParams({
                mineralType: TIN,
                paymentToken: usdc,
                minQty: minQty,
                maxQty: maxQty,
                maxPricePerKg: PER_KG,
                minGradeBps: 0,
                deliveryWindow: 14 days,
                expiresAt: uint64(block.timestamp + 30 days),
                termsHash: H
            })
        );
    }

    function _claim(uint256 requestId, uint128 qty, uint256 pricePerKg) internal returns (uint256 orderId) {
        uint256 id = _inspected(qty);
        vm.prank(miner);
        orderId = market.claimBuyRequest(requestId, id, pricePerKg);
    }

    function _offer(uint256 id, uint256 amount, uint256 nonce) internal view returns (MarketplaceLib.Offer memory) {
        return MarketplaceLib.Offer({
            tokenId: id,
            seller: miner,
            buyer: signer,
            paymentToken: usdc,
            amount: amount,
            deliveryWindow: 14 days,
            deadline: uint64(block.timestamp + 1 days),
            nonce: nonce,
            termsHash: keccak256("final counter-offer")
        });
    }

    /// The EIP-712 digest, built here independently of the contract (and without an external call, so a pending
    /// `vm.prank` is not consumed by signing).
    function _digest(MarketplaceLib.Offer memory o) internal view returns (bytes32) {
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256(
                    "Offer(uint256 tokenId,address seller,address buyer,address paymentToken,uint256 amount,uint32 deliveryWindow,uint64 deadline,uint256 nonce,bytes32 termsHash)"
                ),
                o.tokenId,
                o.seller,
                o.buyer,
                o.paymentToken,
                o.amount,
                o.deliveryWindow,
                o.deadline,
                o.nonce,
                o.termsHash
            )
        );
        return keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
    }

    function _sign(MarketplaceLib.Offer memory o, uint256 key) internal returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, _digest(o));
        return abi.encodePacked(r, s, v);
    }

    // ================================================================ partial fills

    function test_BuyRequest_FilledByThreeLots() public {
        uint256 requestId = _request(8_000, 30_000); // 30 kg in lots of at least 8 kg
        uint256 deposit = market.requestDeposit(PER_KG, 30_000);

        _claim(requestId, 10_000, 20e6);
        MarketplaceLib.BuyRequest memory r = market.getBuyRequest(requestId);
        assertEq(uint8(r.status), uint8(MarketplaceLib.RequestStatus.Open), "still open for the rest");
        assertEq(r.filledQty, 10_000);
        assertEq(r.fills, 1);
        assertEq(r.lockedAmount, market.requestDeposit(PER_KG, 20_000));

        _claim(requestId, 10_000, PER_KG);
        _claim(requestId, 10_000, PER_KG);
        r = market.getBuyRequest(requestId);
        assertEq(uint8(r.status), uint8(MarketplaceLib.RequestStatus.Filled));
        assertEq(r.filledQty, 30_000);
        assertEq(r.fills, 3);
        assertEq(r.lockedAmount, 0);

        uint256 paid = 200e6 + 250e6 + 250e6;
        assertEq(market.claimable(usdc, buyer), deposit - paid, "only the first fill's discount comes back");
        assertEq(usdc.balanceOf(address(market)), deposit - paid);
    }

    function test_BuyRequest_ClosesWhenLessThanMinimumIsLeft() public {
        uint256 requestId = _request(8_000, 20_000);
        _claim(requestId, 15_000, PER_KG); // 5 kg left, below the 8 kg minimum lot
        MarketplaceLib.BuyRequest memory r = market.getBuyRequest(requestId);
        assertEq(uint8(r.status), uint8(MarketplaceLib.RequestStatus.Filled));
        assertEq(market.claimable(usdc, buyer), market.requestDeposit(PER_KG, 20_000) - 375e6);
    }

    function test_BuyRequest_BiggerLotIsSplitToWhatIsLeft() public {
        uint256 requestId = _request(8_000, 20_000);
        _claim(requestId, 10_000, PER_KG);
        uint256 big = _inspected(12_000);
        vm.prank(miner);
        uint256 orderId = market.claimBuyRequest(requestId, big, PER_KG);

        // exactly the 10 kg left of the order is sold; the other 2 kg stay with the miner, still inspected
        uint256 sold = escrow.getOrder(orderId).tokenId;
        uint256[] memory kids = passport.childrenOf(big);
        assertEq(kids.length, 2);
        assertEq(sold, kids[0]);
        assertEq(supplyChain.lastWeight(sold), 10_000);
        assertEq(supplyChain.lastWeight(kids[1]), 2_000);
        assertEq(passport.ownerOf(kids[1]), miner);
        assertEq(uint8(passport.getLot(kids[1]).status), uint8(PassportLib.LotStatus.Inspected));
        assertEq(uint8(passport.getLot(big).status), uint8(PassportLib.LotStatus.Consumed));
        assertEq(passport.siteOf(sold), site);
        assertEq(uint8(market.getBuyRequest(requestId).status), uint8(MarketplaceLib.RequestStatus.Filled));
    }

    function test_BuyRequest_CancelAfterPartialFill_ReturnsTheRest() public {
        uint256 requestId = _request(8_000, 30_000);
        _claim(requestId, 10_000, PER_KG);
        uint256 locked = market.getBuyRequest(requestId).lockedAmount;
        uint256 before = usdc.balanceOf(buyer);
        vm.prank(buyer);
        market.cancelBuyRequest(requestId);
        assertEq(usdc.balanceOf(buyer) - before, locked);
        assertEq(uint8(market.getBuyRequest(requestId).status), uint8(MarketplaceLib.RequestStatus.Cancelled));
    }

    /// Deposit conservation over two fills of any size and price: escrowed + refunded + still locked = deposit.
    function testFuzz_BuyRequest_DepositConserved(uint128 maxQty, uint128 w1, uint128 w2, uint256 p1, uint256 p2)
        public
    {
        maxQty = uint128(bound(maxQty, 2_000, 200_000));
        uint128 minQty = 1_000;
        w1 = uint128(bound(w1, minQty, maxQty));
        p1 = bound(p1, 1, PER_KG);
        p2 = bound(p2, 1, PER_KG);
        uint256 requestId = _request(minQty, maxQty);
        uint256 deposit = market.requestDeposit(PER_KG, maxQty);

        uint256 escrowed = escrow.getOrder(_claim(requestId, w1, p1)).amount;
        uint128 left = maxQty - w1;
        if (left >= minQty) {
            w2 = uint128(bound(w2, minQty, left));
            escrowed += escrow.getOrder(_claim(requestId, w2, p2)).amount;
        }
        MarketplaceLib.BuyRequest memory r = market.getBuyRequest(requestId);
        assertEq(escrowed + market.claimable(usdc, buyer) + r.lockedAmount, deposit);
        if (r.status == MarketplaceLib.RequestStatus.Open) {
            assertEq(r.lockedAmount, market.requestDeposit(PER_KG, maxQty - r.filledQty), "rest fully funded");
        } else {
            assertEq(r.lockedAmount, 0);
        }
    }

    // ================================================================ signed offers

    function testFuzz_AcceptOffer_SellerSubmitsBuyerSignedOffer(uint256 amount) public {
        amount = bound(amount, 1, 500_000e6);
        uint256 id = _inspected(10_000);
        vm.prank(miner);
        uint256 listingId = market.createListing(_listingParams(id, _fixed(), PRICE));
        MarketplaceLib.Offer memory o = _offer(id, amount, 1);
        uint256 before = usdc.balanceOf(signer);

        vm.prank(miner);
        uint256 orderId = market.acceptOffer(o, _sign(o, signerKey));

        EscrowLib.Order memory order = escrow.getOrder(orderId);
        assertEq(order.amount, amount);
        assertEq(order.buyer, signer);
        assertEq(order.seller, miner);
        assertEq(order.termsHash, keccak256("final counter-offer"));
        assertEq(before - usdc.balanceOf(signer), amount);
        assertTrue(passport.escrowLocked(id));
        assertTrue(market.nonceUsed(signer, 1));
        assertEq(uint8(market.getListing(listingId).status), uint8(MarketplaceLib.ListingStatus.Delisted));
    }

    function test_HashOffer_MatchesEip712() public {
        MarketplaceLib.Offer memory o = _offer(1, 1_000e6, 1);
        assertEq(market.hashOffer(o), _digest(o));
    }

    function test_AcceptOffer_CannotReplay() public {
        uint256 id = _inspected(10_000);
        MarketplaceLib.Offer memory o = _offer(id, 1_000e6, 7);
        bytes memory sig = _sign(o, signerKey);
        vm.prank(miner);
        market.acceptOffer(o, sig);
        vm.prank(miner);
        vm.expectRevert(abi.encodeWithSelector(MarketplaceLib.Marketplace__NonceUsed.selector, signer, 7));
        market.acceptOffer(o, sig);
    }

    function test_AcceptOffer_CancelledNonce() public {
        uint256 id = _inspected(10_000);
        MarketplaceLib.Offer memory o = _offer(id, 1_000e6, 3);
        bytes memory sig = _sign(o, signerKey);
        vm.prank(signer);
        market.cancelOfferNonce(3);
        vm.prank(miner);
        vm.expectRevert(abi.encodeWithSelector(MarketplaceLib.Marketplace__NonceUsed.selector, signer, 3));
        market.acceptOffer(o, sig);
    }

    function test_AcceptOffer_RejectsWrongSignerExpiryAndOutsiders() public {
        uint256 id = _inspected(10_000);
        MarketplaceLib.Offer memory o = _offer(id, 1_000e6, 1);
        (, uint256 otherKey) = makeAddrAndKey("someone-else");

        vm.prank(miner);
        vm.expectRevert(MarketplaceLib.Marketplace__InvalidSignature.selector);
        market.acceptOffer(o, _sign(o, otherKey));

        vm.prank(outsider);
        vm.expectRevert(abi.encodeWithSelector(MarketplaceLib.Marketplace__NotOfferParty.selector, outsider));
        market.acceptOffer(o, _sign(o, signerKey));

        // the buyer cannot accept its own signature: the seller never agreed
        vm.prank(signer);
        vm.expectRevert(MarketplaceLib.Marketplace__InvalidSignature.selector);
        market.acceptOffer(o, _sign(o, signerKey));

        bytes memory sig = _sign(o, signerKey);
        vm.warp(o.deadline + 1);
        vm.prank(miner);
        vm.expectRevert(abi.encodeWithSelector(MarketplaceLib.Marketplace__OfferExpired.selector, o.deadline));
        market.acceptOffer(o, sig);
    }

    function test_AcceptOffer_TamperedTermsFail() public {
        uint256 id = _inspected(10_000);
        MarketplaceLib.Offer memory o = _offer(id, 1_000e6, 1);
        bytes memory sig = _sign(o, signerKey);
        o.amount = 1e6; // the seller tries to change the price after signing... or the buyer's signature is reused
        vm.prank(miner);
        vm.expectRevert(MarketplaceLib.Marketplace__InvalidSignature.selector);
        market.acceptOffer(o, sig);
    }

    function test_AcceptOffer_SellerMustOwnASellableLot() public {
        uint256 id = _register(10_000); // not inspected
        MarketplaceLib.Offer memory o = _offer(id, 1_000e6, 1);
        vm.prank(miner);
        vm.expectRevert(abi.encodeWithSelector(MarketplaceLib.Marketplace__LotNotInspected.selector, id));
        market.acceptOffer(o, _sign(o, signerKey));
    }
}
