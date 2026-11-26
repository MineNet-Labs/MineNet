// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {MineNetFixture} from "test/utils/MineNetFixture.sol";
import {SupplyChain} from "src/traceability/SupplyChain.sol";
import {EscrowManager} from "src/trade/EscrowManager.sol";
import {DeliveryManager} from "src/traceability/DeliveryManager.sol";
import {DeliveryLib} from "src/traceability/libraries/DeliveryLib.sol";
import {EscrowLib} from "src/trade/libraries/EscrowLib.sol";
import {MarketplaceLib} from "src/trade/libraries/MarketplaceLib.sol";
import {SupplyChainLib} from "src/traceability/libraries/SupplyChainLib.sol";
import {Marketplace} from "src/trade/Marketplace.sol";

/// project.md 6.4 lot lifecycle, end to end:
/// registered → weighed → inspected → warehoused (check-in weight) → graded + certified → listed per kg
/// on the marketplace → bought (escrow)
/// → check-out weight → transported (two-party pickup, weighed, sealed) → customs declared / released / exit
/// → delivered (two-party, weighed, seal checked) → buyer releases funds → payouts.
contract IntegrationTest is MineNetFixture {
    function _cp(uint256 id, SupplyChainLib.CheckpointType t, uint128 qty)
        internal
        pure
        returns (SupplyChainLib.CheckpointInput memory)
    {
        return SupplyChainLib.CheckpointInput(
            id, t, qty, SupplyChainLib.Condition.Good, 0, keccak256("ticket"), bytes32(0)
        );
    }

    function test_DemoJourney() public {
        bytes32[] memory req = new bytes32[](2);
        req[0] = EXPORT_PERMIT;
        req[1] = CONFLICT_FREE;
        vm.startPrank(admin);
        escrow.setRequiredCertTypes(req);
        supplyChain.setCustomsRequiredCerts(req);
        vm.stopPrank();

        // 1. Registered (25 t) and weighed by the mine-site weighbridge oracle
        uint256 id = _register(25_000_000);
        vm.prank(oracle);
        supplyChain.recordCheckpoint(_cp(id, SupplyChainLib.CheckpointType.Weighing, 24_950_000));

        // 2. Inspected
        _assignTo(id, inspector);
        vm.prank(inspector);
        passport.submitInspection(id, true, keccak256("inspection-report"));

        // 3. Warehoused: two-party delivery into the warehouse, then the check-in weight
        _deliver(id, miner, warehouse);
        vm.prank(warehouse);
        supplyChain.recordCheckpoint(_cp(id, SupplyChainLib.CheckpointType.WarehouseIn, 24_900_000));

        // 4. Graded, certified and listed at 25 USDC per kg of trusted weight
        _grade(id, 6_800); // 68% Sn
        vm.prank(regulator);
        certs.issue(id, EXPORT_PERMIT, uint64(block.timestamp + 90 days), keccak256("permit"));
        vm.prank(auditor);
        certs.issue(id, CONFLICT_FREE, 0, keccak256("oecd-dd"));
        vm.prank(miner);
        uint256 listingId = market.createListing(_listingParams(id, MarketplaceLib.PriceModel.PerKilogram, 25e6));
        uint256 price = market.quoteListing(listingId);
        assertEq(price, 24_900 * 25e6, "24.9 t trusted weight x 25 USDC/kg");

        // 5. Bought: funds locked in escrow, lot locked to the order
        vm.prank(buyer);
        uint256 orderId = market.buyListing(listingId, price);
        assertEq(escrow.getOrder(orderId).gradeAtSale, 6_800);

        // 6. Check-out weight, then a shipment to the buyer
        vm.prank(warehouse);
        supplyChain.recordCheckpoint(_cp(id, SupplyChainLib.CheckpointType.WarehouseOut, 24_880_000));
        uint256[] memory ids = new uint256[](1);
        ids[0] = id;
        vm.prank(warehouse);
        uint256 sid = delivery.createShipment(ids, transporter, buyer, uint64(block.timestamp + 3 days), SEAL, H);
        vm.prank(transporter);
        assertTrue(delivery.confirmPickup(sid, _weights(1, 24_870_000), SEAL, H));

        // 7. Customs: agent assigned by the owner, declares, oracle confirms RRA release, border exit
        vm.prank(miner);
        supplyChain.assign(id, customs);
        vm.prank(customs);
        supplyChain.recordCheckpoint(_cp(id, SupplyChainLib.CheckpointType.CustomsDeclared, 24_870_000));
        vm.prank(oracle);
        supplyChain.recordCheckpoint(_cp(id, SupplyChainLib.CheckpointType.CustomsReleased, 0));
        vm.prank(customs);
        supplyChain.recordCheckpoint(_cp(id, SupplyChainLib.CheckpointType.BorderExit, 0));

        // 8. Delivered: carrier arrives, buyer weighs and checks the seal
        vm.prank(transporter);
        delivery.markArrived(sid, H);
        vm.prank(buyer);
        assertTrue(
            delivery.confirmDelivery(
                sid, _weights(1, 24_860_000), SEAL, SupplyChainLib.Condition.Good, keccak256("pod")
            )
        );

        // 9. Accepted: buyer releases funds; ownership settles atomically
        vm.prank(buyer);
        escrow.releaseFunds(orderId);

        assertEq(passport.ownerOf(id), buyer);
        assertEq(passport.custodianOf(id), buyer);
        assertFalse(passport.isFrozen(id));
        assertEq(uint8(escrow.getOrder(orderId).status), uint8(EscrowLib.OrderStatus.Settled));
        assertEq(uint8(delivery.getShipment(sid).status), uint8(DeliveryLib.ShipmentStatus.Delivered));
        assertEq(uint8(supplyChain.customsStatus(id)), uint8(SupplyChainLib.CustomsStatus.Exited));

        // mass balance: 25 t registered -> 24.86 t delivered = 0.56% total loss, every hop in tolerance
        assertEq(supplyChain.lastWeight(id), 24_860_000);
        uint256 n = supplyChain.checkpointCount(id);
        assertEq(n, 11);
        for (uint256 i; i < n; ++i) {
            assertTrue(supplyChain.getCheckpoint(id, i).withinTolerance);
        }

        // 10. Payouts
        uint256 fee = (price * FEE_BPS) / 10_000;
        vm.prank(miner);
        escrow.withdraw(usdc);
        vm.prank(treasury);
        escrow.withdraw(usdc);
        assertEq(usdc.balanceOf(miner), price - fee);
        assertEq(usdc.balanceOf(treasury), fee);
        assertEq(usdc.balanceOf(address(escrow)), 0);
    }
}
