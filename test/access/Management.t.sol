// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {MineNetFixture, MockUSDC} from "test/utils/MineNetFixture.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {Actions} from "src/access/libraries/Actions.sol";
import {Roles} from "src/access/libraries/Roles.sol";
import {RegistryLib} from "src/access/libraries/RegistryLib.sol";
import {CurrencyLib} from "src/finance/libraries/CurrencyLib.sol";
import {DeliveryLib} from "src/traceability/libraries/DeliveryLib.sol";

/// Role & permission management, currencies and rate feeds, and party-resolved shipment holds.
contract ManagementTest is MineNetFixture {
    // ================================================================ actions & roles

    function test_DefaultActionTable() public view {
        assertTrue(registry.isAuthorized(miner, Actions.REGISTER_LOT));
        assertTrue(registry.isAuthorized(miner, Actions.SELL_LOT));
        assertFalse(registry.isAuthorized(miner, Actions.BUY_LOT));
        assertTrue(registry.isAuthorized(refinery, Actions.BUY_LOT));
        assertTrue(registry.isAuthorized(processor, Actions.PROCESS_LOTS));
        assertTrue(registry.isAuthorized(transporter, Actions.CARRY));
        assertFalse(registry.isAuthorized(transporter, Actions.OWN_LOT));
        assertEq(registry.actionRoles(Actions.HOLD_CUSTODY).length, 5);
    }

    function test_AdminRemapsAnAction_NoRedeploy() public {
        // processors may now buy lots on the marketplace
        assertFalse(registry.isAuthorized(processor, Actions.BUY_LOT));
        bytes32[] memory roles = new bytes32[](3);
        roles[0] = Roles.BUYER;
        roles[1] = Roles.REFINERY;
        roles[2] = Roles.PROCESSOR;
        vm.prank(admin);
        registry.setActionRoles(Actions.BUY_LOT, roles);
        assertTrue(registry.isAuthorized(processor, Actions.BUY_LOT));

        vm.prank(outsider);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, outsider, bytes32(0))
        );
        registry.setActionRoles(Actions.BUY_LOT, roles);
    }

    function test_ChangeRole_MovesPermissions() public {
        vm.prank(admin);
        registry.changeRole(buyer2, Roles.BUYER, Roles.REFINERY);
        assertTrue(registry.isAuthorized(buyer2, Actions.PROCESS_LOTS));
        assertFalse(registry.isActive(buyer2, Roles.BUYER));
        assertEq(registry.participant(buyer2).orgId, "org-buyer2", "organisation kept");

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(RegistryLib.MineNetRegistry__RoleNotHeld.selector, buyer2, Roles.BUYER));
        registry.changeRole(buyer2, Roles.BUYER, Roles.MINER);
    }

    function test_NewRole_CanBeAddedAndMapped() public {
        bytes32 insurer = keccak256("INSURER_ROLE");
        address axa = makeAddr("insurer");
        vm.startPrank(admin);
        vm.expectRevert(abi.encodeWithSelector(RegistryLib.MineNetRegistry__UnknownRole.selector, insurer));
        registry.onboard(axa, insurer, "org-insurer", H, 0);

        registry.setParticipantRole(insurer, true);
        registry.onboard(axa, insurer, "org-insurer", H, 0);
        bytes32[] memory roles = new bytes32[](2);
        roles[0] = Roles.AUDITOR;
        roles[1] = insurer;
        registry.setActionRoles(Actions.AUDIT, roles);
        vm.stopPrank();
        assertTrue(registry.isAuthorized(axa, Actions.AUDIT));

        vm.prank(admin); // retiring the role removes every permission at once
        registry.setParticipantRole(insurer, false);
        assertFalse(registry.isAuthorized(axa, Actions.AUDIT));
    }

    function test_SuspensionBlocksAllActions() public {
        vm.prank(regulator);
        registry.suspend(miner, H);
        assertFalse(registry.isAuthorized(miner, Actions.REGISTER_LOT));
        assertFalse(registry.isAuthorized(miner, Actions.SELL_LOT));

        vm.prank(buyer);
        vm.expectRevert(abi.encodeWithSelector(RegistryLib.MineNetRegistry__NotRegulator.selector, buyer));
        registry.reinstate(miner, H);
    }

    function test_SameOrg() public {
        address minerWallet2 = makeAddr("miner-wallet-2");
        vm.prank(admin);
        registry.onboard(minerWallet2, Roles.ORACLE, "org-miner", H, 0);
        assertTrue(registry.sameOrg(miner, minerWallet2));
        assertFalse(registry.sameOrg(miner, buyer));
        assertFalse(registry.sameOrg(outsider, makeAddr("other-outsider")), "unregistered accounts share no org");
    }

    // ================================================================ currencies

    function test_Conversions() public view {
        assertEq(currencies.usdRate(USD), 1e18);
        assertEq(currencies.usdRate(RWF), 0.0008e18);
        assertEq(currencies.convert(1_250, RWF, USD, false), 1e6); // 1,250 RWF = 1 USD
        assertEq(currencies.convert(1e6, USD, RWF, false), 1_250);
        assertEq(currencies.toUsd(62_500_000, RWF), 50_000e6);
        assertEq(currencies.toTokenAmount(62_500_000, RWF, usdc, true), 50_000e6);
        assertEq(currencies.toTokenAmount(50_000e6, USD, rwfCoin, true), 62_500_000);
        assertEq(currencies.tokenToUsd(rwfCoin, 1_250), 1e6);
        assertEq(currencies.currencyOf(rwfCoin), RWF);
    }

    function test_CurrencyAdmin() public {
        vm.startPrank(admin);
        vm.expectRevert(CurrencyLib.CurrencyManager__InvalidConfig.selector);
        currencies.setCurrency(USD, 2, rwfFeed, 1 days, true); // USD is fixed
        vm.expectRevert(CurrencyLib.CurrencyManager__InvalidConfig.selector);
        currencies.setCurrency("KES", 2, AggregatorV3Interface(address(0)), 1 days, true); // no feed
        MockUSDC unknown = new MockUSDC();
        vm.expectRevert(abi.encodeWithSelector(CurrencyLib.CurrencyManager__UnknownCurrency.selector, bytes32("KES")));
        currencies.setSettlementToken(unknown, "KES", true);

        currencies.setCurrency(RWF, 0, rwfFeed, 1 days, false); // disable RWF
        vm.stopPrank();
        vm.expectRevert(abi.encodeWithSelector(CurrencyLib.CurrencyManager__UnknownCurrency.selector, RWF));
        currencies.usdRate(RWF);

        vm.prank(outsider);
        vm.expectRevert(abi.encodeWithSelector(CurrencyLib.CurrencyManager__NotRegistryAdmin.selector, outsider));
        currencies.setCurrency("KES", 2, rwfFeed, 1 days, true);
    }

    function test_RateFeed_OnlyOraclesAndDeviationGuard() public {
        vm.prank(miner);
        vm.expectRevert(abi.encodeWithSelector(CurrencyLib.OracleRateFeed__Unauthorized.selector, miner));
        rwfFeed.postRate(80_000);

        vm.prank(oracle); // a 10% jump in one update is refused (max 5%)
        vm.expectRevert(
            abi.encodeWithSelector(CurrencyLib.OracleRateFeed__DeviationTooLarge.selector, RWF_RATE, int256(88_000))
        );
        rwfFeed.postRate(88_000);

        vm.prank(oracle);
        rwfFeed.postRate(83_000);
        (, int256 answer,,,) = rwfFeed.latestRoundData();
        assertEq(answer, 83_000);
    }

    // ================================================================ shipment holds: parties decide

    function _heldShipment() internal returns (uint256 id, uint256 sid) {
        id = _register(1_000);
        uint256[] memory ids = new uint256[](1);
        ids[0] = id;
        vm.prank(miner);
        sid = delivery.createShipment(ids, transporter, warehouse, uint64(block.timestamp + 1 days), SEAL, H);
        vm.prank(transporter);
        delivery.reportException(sid, DeliveryLib.ExceptionKind.Loss, H);
    }

    function test_Hold_BothPartiesAgreeToCancel() public {
        (uint256 id, uint256 sid) = _heldShipment();
        vm.prank(miner);
        delivery.chooseHoldOutcome(sid, DeliveryLib.HoldChoice.Cancel);
        assertTrue(delivery.getShipment(sid).onHold, "one side alone decides nothing");

        vm.prank(warehouse);
        delivery.chooseHoldOutcome(sid, DeliveryLib.HoldChoice.Cancel);
        assertEq(uint8(delivery.getShipment(sid).status), uint8(DeliveryLib.ShipmentStatus.Cancelled));
        assertEq(delivery.activeShipmentOf(id), 0);
    }

    function test_Hold_AgreeToContinue() public {
        (, uint256 sid) = _heldShipment();
        vm.prank(miner);
        delivery.chooseHoldOutcome(sid, DeliveryLib.HoldChoice.Continue);
        vm.prank(warehouse);
        delivery.chooseHoldOutcome(sid, DeliveryLib.HoldChoice.Continue);
        DeliveryLib.Shipment memory s = delivery.getShipment(sid);
        assertFalse(s.onHold);
        assertEq(uint8(s.status), uint8(DeliveryLib.ShipmentStatus.Created));
    }

    function test_Hold_DisagreementExpires() public {
        (, uint256 sid) = _heldShipment();
        vm.prank(miner);
        delivery.chooseHoldOutcome(sid, DeliveryLib.HoldChoice.Continue);
        vm.prank(warehouse);
        delivery.chooseHoldOutcome(sid, DeliveryLib.HoldChoice.Cancel);

        vm.prank(transporter); // the carrier has no say
        vm.expectRevert(abi.encodeWithSelector(DeliveryLib.DeliveryManager__Unauthorized.selector, transporter));
        delivery.chooseHoldOutcome(sid, DeliveryLib.HoldChoice.Cancel);

        vm.expectRevert(
            abi.encodeWithSelector(
                DeliveryLib.DeliveryManager__HoldNotExpired.selector, sid, uint64(block.timestamp + 14 days)
            )
        );
        delivery.expireHold(sid);

        vm.warp(block.timestamp + 14 days + 1);
        vm.prank(outsider); // anyone can end it after the timeout
        delivery.expireHold(sid);
        assertEq(uint8(delivery.getShipment(sid).status), uint8(DeliveryLib.ShipmentStatus.Cancelled));
    }
}
