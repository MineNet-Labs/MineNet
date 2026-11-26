// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";
import {MineNetRegistry} from "src/access/MineNetRegistry.sol";
import {LotPassport} from "src/traceability/LotPassport.sol";
import {Roles} from "src/access/libraries/Roles.sol";
import {Actions} from "src/access/libraries/Actions.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {PassportLib} from "src/traceability/libraries/PassportLib.sol";
import {RegistryLib} from "src/access/libraries/RegistryLib.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {LicenceRegistry} from "src/compliance/LicenceRegistry.sol";
import {MineSiteRegistry} from "src/compliance/MineSiteRegistry.sol";
import {SiteLib} from "src/compliance/libraries/SiteLib.sol";

contract LotPassportTest is Test {
    MineNetRegistry registry;
    LotPassport passport;
    LicenceRegistry licences;
    MineSiteRegistry sites;
    uint256 site;

    address admin = makeAddr("admin");
    address miner = makeAddr("miner");
    address refinery = makeAddr("refinery");
    address transporter = makeAddr("transporter");
    address buyer = makeAddr("buyer");
    address warehouse = makeAddr("warehouse");
    address inspector = makeAddr("inspector");
    address auditor = makeAddr("auditor");
    address regulator = makeAddr("regulator");
    address oracle = makeAddr("oracle");
    address outsider = makeAddr("outsider");

    bytes32 constant LOT_A = keccak256("lot-A");
    bytes32 constant LOT_B = keccak256("lot-B");
    bytes32 constant TIN = keccak256("CASSITERITE");
    bytes32 constant H = keccak256("evidence");

    function setUp() public {
        registry = new MineNetRegistry(1 days, admin);
        passport = new LotPassport(registry);

        vm.startPrank(admin);
        uint64 exp = uint64(block.timestamp + 365 days);
        registry.onboard(miner, Roles.MINER, "org-miner", H, exp);
        registry.onboard(refinery, Roles.REFINERY, "org-refinery", H, exp);
        registry.onboard(transporter, Roles.TRANSPORTER, "org-transport", H, exp);
        registry.onboard(buyer, Roles.BUYER, "org-buyer", H, exp);
        registry.onboard(warehouse, Roles.WAREHOUSE, "org-warehouse", H, exp);
        registry.onboard(inspector, Roles.INSPECTOR, "org-inspect", H, exp);
        registry.onboard(auditor, Roles.AUDITOR, "org-audit", H, exp);
        registry.onboard(regulator, Roles.REGULATOR, "org-rmb", H, 0);
        registry.onboard(oracle, Roles.ORACLE, "org-oracle", H, 0);
        // This test contract acts as a module (like SupplyChain / DeliveryManager) to exercise the hooks.
        passport.setModule(address(this), true);
        licences = new LicenceRegistry(registry);
        sites = new MineSiteRegistry(registry, licences);
        passport.setSiteRegistry(sites);
        vm.stopPrank();

        // the miner's licence, concession and an active site (lots are registered from it)
        vm.startPrank(regulator);
        uint256 lic =
            licences.issueLicence("org-miner", SiteLib.MINING_LICENCE, H, 0, uint64(block.timestamp + 3650 days), H);
        uint256 concession = sites.grantConcession("org-miner", lic, H, H);
        vm.stopPrank();
        vm.prank(miner);
        site = sites.registerSite(concession, "site-1", _siteLocation(), H);
    }

    // ---------------------------------------------------------------- helpers

    function _siteLocation() internal pure returns (SiteLib.SiteLocation memory) {
        return SiteLib.SiteLocation({
            latitude: -1_939_100,
            longitude: 29_366_200,
            elevation: 2_150,
            province: "Western Province",
            district: "Rutsiro",
            sector: "Nyabirasi",
            cell: "",
            village: ""
        });
    }

    function _register(bytes32 lotId, uint128 qty) internal returns (uint256 id) {
        vm.prank(miner);
        id = passport.registerLot(lotId, TIN, qty, site, H);
    }

    function _inspected(bytes32 lotId, uint128 qty) internal returns (uint256 id) {
        id = _register(lotId, qty);
        vm.prank(inspector);
        passport.submitInspection(id, true, H);
    }

    function _moveCustody(uint256 id, address from, address to) internal {
        vm.prank(from);
        passport.initiateCustodyTransfer(id, to, H);
        vm.prank(to);
        passport.confirmCustodyTransfer(id, H);
    }

    // ---------------------------------------------------------------- registry

    function test_Registry_OnlyAdminOnboards() public {
        bytes32 adminRole = registry.DEFAULT_ADMIN_ROLE();
        vm.prank(outsider);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, outsider, adminRole)
        );
        registry.onboard(outsider, Roles.MINER, "x", H, 0);
    }

    function test_Registry_RejectsUnknownRole() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(RegistryLib.MineNetRegistry__UnknownRole.selector, bytes32("BOGUS")));
        registry.onboard(outsider, bytes32("BOGUS"), "x", H, 0);
    }

    function test_Registry_OrgIsSticky() public {
        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(
                RegistryLib.MineNetRegistry__OrgMismatch.selector, bytes32("org-miner"), bytes32("other")
            )
        );
        registry.onboard(miner, Roles.BUYER, "other", H, 0);
    }

    function test_Registry_SuspensionAndExpiryBlockActions() public {
        vm.prank(regulator);
        registry.suspend(miner, H);
        assertFalse(registry.isActive(miner, Roles.MINER));

        vm.prank(miner);
        vm.expectRevert(
            abi.encodeWithSelector(PassportLib.LotPassport__Unauthorized.selector, miner, Actions.REGISTER_LOT)
        );
        passport.registerLot(LOT_A, TIN, 1000, site, H);

        vm.prank(regulator);
        registry.reinstate(miner, H);
        assertTrue(registry.isActive(miner, Roles.MINER));

        vm.warp(block.timestamp + 366 days); // licence expired
        assertFalse(registry.isActive(miner, Roles.MINER));
    }

    function test_Registry_RegulatorCannotSuspendSelf() public {
        vm.prank(regulator);
        vm.expectRevert(RegistryLib.MineNetRegistry__CannotSuspendSelf.selector);
        registry.suspend(regulator, H);
    }

    // ---------------------------------------------------------------- registration

    function test_Register_MintsToMinerAsOwnerAndCustodian() public {
        uint256 id = _register(LOT_A, 1000);
        assertEq(id, 1);
        assertEq(passport.ownerOf(id), miner);
        assertEq(passport.custodianOf(id), miner);
        assertEq(passport.tokenOfLot(LOT_A), id);
        assertEq(uint8(passport.getLot(id).status), uint8(PassportLib.LotStatus.Registered));
        assertEq(passport.eventCount(id), 1);
        vm.prank(admin);
        passport.setBaseURI("https://api.minenet.rw/passport/");
        assertEq(passport.tokenURI(id), "https://api.minenet.rw/passport/1");
    }

    function test_Register_IsIdempotentPerLotId() public {
        uint256 id = _register(LOT_A, 1000);
        vm.prank(miner);
        vm.expectRevert(abi.encodeWithSelector(PassportLib.LotPassport__LotAlreadyRegistered.selector, LOT_A, id));
        passport.registerLot(LOT_A, TIN, 1000, site, H);
    }

    function test_Register_OnlyMiner() public {
        vm.prank(buyer);
        vm.expectRevert(
            abi.encodeWithSelector(PassportLib.LotPassport__Unauthorized.selector, buyer, Actions.REGISTER_LOT)
        );
        passport.registerLot(LOT_A, TIN, 1000, site, H);
    }

    function test_Register_RejectsZeroInputs() public {
        vm.startPrank(miner);
        vm.expectRevert(PassportLib.LotPassport__InvalidLotId.selector);
        passport.registerLot(bytes32(0), TIN, 1000, site, H);
        vm.expectRevert(PassportLib.LotPassport__InvalidQuantity.selector);
        passport.registerLot(LOT_A, TIN, 0, site, H);
        vm.stopPrank();
    }

    // ---------------------------------------------------------------- inspection & listing

    function test_Inspection_RequiredBeforeSale() public {
        uint256 id = _register(LOT_A, 1000);

        vm.prank(miner);
        vm.expectRevert(
            abi.encodeWithSelector(
                PassportLib.LotPassport__InvalidStatus.selector, id, PassportLib.LotStatus.Registered
            )
        );
        passport.transferFrom(miner, buyer, id);
    }

    function test_Inspection_FailedRejects() public {
        uint256 id = _inspected(LOT_A, 1000);

        vm.prank(inspector);
        passport.submitInspection(id, false, H);
        assertEq(uint8(passport.getLot(id).status), uint8(PassportLib.LotStatus.Rejected));
    }

    function test_Inspection_InspectorMustBeIndependent() public {
        // An inspector who also holds the lot (custodian) cannot inspect it.
        vm.prank(admin);
        registry.onboard(transporter, Roles.INSPECTOR, "org-transport", H, 0);
        uint256 id = _register(LOT_A, 1000);
        _moveCustody(id, miner, transporter);

        vm.prank(transporter);
        vm.expectRevert(abi.encodeWithSelector(PassportLib.LotPassport__InspectorConflict.selector, id, transporter));
        passport.submitInspection(id, true, H);
    }

    // ---------------------------------------------------------------- ownership

    function test_Ownership_TransferDoesNotMoveCustody() public {
        uint256 id = _inspected(LOT_A, 1000);

        vm.prank(miner);
        passport.transferFrom(miner, buyer, id);

        assertEq(passport.ownerOf(id), buyer);
        assertEq(passport.custodianOf(id), miner, "custody is separate from ownership");
        assertEq(uint8(passport.getLot(id).status), uint8(PassportLib.LotStatus.Inspected));

        PassportLib.PassportEvent memory e = passport.getEvent(id, passport.eventCount(id) - 1);
        assertEq(uint8(e.eventType), uint8(PassportLib.EventType.OwnershipTransfer));
        assertEq(e.actor, miner);
        assertEq(e.counterparty, buyer);
    }

    function test_Ownership_RecipientMustBeBuyerOrRefinery() public {
        uint256 id = _inspected(LOT_A, 1000);
        vm.startPrank(miner);
        vm.expectRevert(abi.encodeWithSelector(PassportLib.LotPassport__InvalidRecipient.selector, transporter));
        passport.transferFrom(miner, transporter, id);
        vm.expectRevert(abi.encodeWithSelector(PassportLib.LotPassport__InvalidRecipient.selector, outsider));
        passport.transferFrom(miner, outsider, id);
        vm.stopPrank();
    }

    // ---------------------------------------------------------------- custody

    function test_Custody_RequiresBothParties() public {
        uint256 id = _register(LOT_A, 1000);

        vm.prank(miner);
        passport.initiateCustodyTransfer(id, transporter, H);
        assertEq(passport.custodianOf(id), miner, "not moved until receiver confirms");

        vm.prank(outsider);
        vm.expectRevert(abi.encodeWithSelector(PassportLib.LotPassport__NotPendingParty.selector, id, outsider));
        passport.confirmCustodyTransfer(id, H);

        vm.prank(transporter);
        passport.confirmCustodyTransfer(id, H);
        assertEq(passport.custodianOf(id), transporter);
    }

    function test_Custody_OnlyCustodianInitiates_EvenOwnerCannot() public {
        uint256 id = _register(LOT_A, 1000);
        _moveCustody(id, miner, warehouse);
        vm.prank(miner); // still owner, no longer custodian
        vm.expectRevert(abi.encodeWithSelector(PassportLib.LotPassport__NotCustodian.selector, id, miner));
        passport.initiateCustodyTransfer(id, transporter, H);
    }

    function test_Custody_OnePendingAtATime_AndCancel() public {
        uint256 id = _register(LOT_A, 1000);
        vm.startPrank(miner);
        passport.initiateCustodyTransfer(id, transporter, H);
        vm.expectRevert(abi.encodeWithSelector(PassportLib.LotPassport__CustodyPending.selector, id));
        passport.initiateCustodyTransfer(id, warehouse, H);
        vm.stopPrank();

        vm.prank(transporter); // receiver rejects
        passport.cancelCustodyTransfer(id, H);
        assertEq(passport.pendingCustody(id).to, address(0));
    }

    function test_Custody_ReceiverSuspendedBeforeConfirm() public {
        uint256 id = _register(LOT_A, 1000);
        vm.prank(miner);
        passport.initiateCustodyTransfer(id, transporter, H);
        vm.prank(regulator);
        registry.suspend(transporter, H);

        vm.prank(transporter);
        vm.expectRevert(abi.encodeWithSelector(PassportLib.LotPassport__InvalidRecipient.selector, transporter));
        passport.confirmCustodyTransfer(id, H);
    }

    function test_Custody_InvalidRecipients() public {
        uint256 id = _register(LOT_A, 1000);
        vm.startPrank(miner);
        vm.expectRevert(abi.encodeWithSelector(PassportLib.LotPassport__InvalidRecipient.selector, inspector));
        passport.initiateCustodyTransfer(id, inspector, H);
        vm.expectRevert(abi.encodeWithSelector(PassportLib.LotPassport__InvalidRecipient.selector, outsider));
        passport.initiateCustodyTransfer(id, outsider, H);
        vm.stopPrank();
    }

    function test_ModuleHandover_EnforcesCustodyRules() public {
        uint256 id = _register(LOT_A, 1000);

        vm.expectRevert(abi.encodeWithSelector(PassportLib.LotPassport__NotCustodian.selector, id, transporter));
        passport.moduleHandover(id, transporter, warehouse, H);
        vm.expectRevert(abi.encodeWithSelector(PassportLib.LotPassport__InvalidRecipient.selector, inspector));
        passport.moduleHandover(id, miner, inspector, H);

        passport.moduleHandover(id, miner, transporter, H);
        assertEq(passport.custodianOf(id), transporter);
        PassportLib.PassportEvent memory e = passport.getEvent(id, passport.eventCount(id) - 1);
        assertEq(uint8(e.eventType), uint8(PassportLib.EventType.CustodyConfirmed));
        assertEq(e.actor, transporter, "receiver signs the handover");
        assertEq(e.counterparty, miner);

        vm.prank(regulator);
        passport.freezeLot(id, H);
        vm.expectRevert(abi.encodeWithSelector(PassportLib.LotPassport__LotFrozen.selector, id));
        passport.moduleHandover(id, transporter, warehouse, H);
    }

    function test_Module_RevokedByAdmin() public {
        uint256 id = _register(LOT_A, 1000);
        vm.prank(admin);
        passport.setModule(address(this), false);
        vm.expectRevert(abi.encodeWithSelector(PassportLib.LotPassport__NotModule.selector, address(this)));
        passport.moduleFlag(id, oracle, H);
    }

    // ---------------------------------------------------------------- processing

    function _outputs(bytes32 a, uint128 qa, bytes32 b, uint128 qb)
        internal
        pure
        returns (PassportLib.LotOutput[] memory o)
    {
        o = new PassportLib.LotOutput[](2);
        o[0] = PassportLib.LotOutput(a, keccak256("TIN_INGOT"), qa, keccak256("assay-a"));
        o[1] = PassportLib.LotOutput(b, keccak256("TIN_INGOT"), qb, keccak256("assay-b"));
    }

    function test_Processing_MergeAndSplit() public {
        uint256 a = _inspected(LOT_A, 1000);
        uint256 b = _inspected(LOT_B, 500);
        _moveCustody(a, miner, refinery);
        _moveCustody(b, miner, refinery);

        uint256[] memory inputs = new uint256[](2);
        inputs[0] = a;
        inputs[1] = b;

        vm.prank(refinery);
        uint256[] memory outs = passport.processLots(inputs, _outputs("out-1", 700, "out-2", 600), H);

        assertEq(outs.length, 2);
        for (uint256 i; i < 2; ++i) {
            assertEq(passport.ownerOf(outs[i]), miner, "owner of inputs owns outputs");
            assertEq(passport.custodianOf(outs[i]), refinery);
            assertEq(uint8(passport.getLot(outs[i]).status), uint8(PassportLib.LotStatus.Registered));
            assertEq(passport.parentsOf(outs[i]), inputs);
        }
        assertEq(uint8(passport.getLot(a).status), uint8(PassportLib.LotStatus.Consumed));
        assertEq(passport.childrenOf(a), outs);

        // Consumed lots cannot be sold or moved.
        vm.prank(miner);
        vm.expectRevert(
            abi.encodeWithSelector(PassportLib.LotPassport__InvalidStatus.selector, a, PassportLib.LotStatus.Consumed)
        );
        passport.transferFrom(miner, buyer, a);
    }

    function test_Processing_CannotCreateMass() public {
        uint256 a = _inspected(LOT_A, 1000);
        _moveCustody(a, miner, refinery);
        uint256[] memory inputs = new uint256[](1);
        inputs[0] = a;

        vm.prank(refinery);
        vm.expectRevert(abi.encodeWithSelector(PassportLib.LotPassport__QuantityExceeded.selector, 1000, 1001));
        passport.processLots(inputs, _outputs("o1", 500, "o2", 501), H);
    }

    function test_Processing_DuplicateInputRejected() public {
        uint256 a = _inspected(LOT_A, 1000);
        _moveCustody(a, miner, refinery);
        uint256[] memory inputs = new uint256[](2);
        inputs[0] = a;
        inputs[1] = a;

        vm.prank(refinery);
        vm.expectRevert(
            abi.encodeWithSelector(PassportLib.LotPassport__InvalidStatus.selector, a, PassportLib.LotStatus.Consumed)
        );
        passport.processLots(inputs, _outputs("o1", 1000, "o2", 1000), H);
    }

    function test_Processing_RequiresCustody() public {
        uint256 a = _inspected(LOT_A, 1000);
        uint256[] memory inputs = new uint256[](1);
        inputs[0] = a;
        vm.prank(refinery);
        vm.expectRevert(abi.encodeWithSelector(PassportLib.LotPassport__NotCustodian.selector, a, refinery));
        passport.processLots(inputs, _outputs("o1", 1, "o2", 1), H);
    }

    function test_Processing_MixedOwnersRejected() public {
        uint256 a = _inspected(LOT_A, 1000);
        uint256 b = _inspected(LOT_B, 1000);
        vm.prank(miner);
        passport.transferFrom(miner, buyer, b);
        _moveCustody(a, miner, refinery);
        _moveCustody(b, miner, refinery);

        uint256[] memory inputs = new uint256[](2);
        inputs[0] = a;
        inputs[1] = b;
        vm.prank(refinery);
        vm.expectRevert(abi.encodeWithSelector(PassportLib.LotPassport__MixedOwnership.selector, b));
        passport.processLots(inputs, _outputs("o1", 1, "o2", 1), H);
    }

    // ---------------------------------------------------------------- oracle, audit, regulator

    function test_Flag_FreezesUntilResolved() public {
        uint256 id = _inspected(LOT_A, 1000);

        uint256 flagId = passport.moduleFlag(id, oracle, H); // e.g. an oracle mismatch via SupplyChain
        assertTrue(passport.isFrozen(id));
        assertEq(passport.getFlag(flagId).raisedBy, oracle, "attributed to the reporter");

        vm.prank(miner);
        vm.expectRevert(abi.encodeWithSelector(PassportLib.LotPassport__LotFrozen.selector, id));
        passport.transferFrom(miner, buyer, id);

        vm.prank(regulator);
        passport.resolveFlag(flagId, false, H); // dismissed
        assertFalse(passport.isFrozen(id));
    }

    function test_Flag_UpheldLeavesRegulatorHold() public {
        uint256 id = _register(LOT_A, 1000);
        uint256 flagId = passport.moduleFlag(id, auditor, H);

        vm.startPrank(regulator);
        passport.resolveFlag(flagId, true, H);
        assertTrue(passport.isFrozen(id), "upheld -> hold");
        vm.expectRevert(abi.encodeWithSelector(PassportLib.LotPassport__FlagNotOpen.selector, flagId));
        passport.resolveFlag(flagId, true, H);
        passport.unfreezeLot(id, H);
        vm.stopPrank();
        assertFalse(passport.isFrozen(id));
    }

    function test_Regulator_FreezeBlocksCustody() public {
        uint256 id = _register(LOT_A, 1000);
        vm.prank(regulator);
        passport.freezeLot(id, H);

        vm.prank(miner);
        vm.expectRevert(abi.encodeWithSelector(PassportLib.LotPassport__LotFrozen.selector, id));
        passport.initiateCustodyTransfer(id, transporter, H);
    }

    function test_Regulator_OnlyRegulatorFreezes() public {
        uint256 id = _register(LOT_A, 1000);
        vm.prank(auditor);
        vm.expectRevert(
            abi.encodeWithSelector(PassportLib.LotPassport__Unauthorized.selector, auditor, Actions.REGULATE)
        );
        passport.freezeLot(id, H);
    }

    // ---------------------------------------------------------------- append-only history

    function test_Correction_AppendsAndLinks() public {
        uint256 id = _register(LOT_A, 1000);
        vm.prank(inspector);
        passport.submitInspection(id, true, keccak256("typo"));
        uint256 idx = passport.eventCount(id) - 1;

        vm.prank(miner);
        vm.expectRevert(abi.encodeWithSelector(PassportLib.LotPassport__NotEventActor.selector, id, idx, miner));
        passport.correctEvent(id, idx, H);

        vm.prank(inspector);
        passport.correctEvent(id, idx, keccak256("fixed"));

        assertEq(passport.getEvent(id, idx).dataHash, keccak256("typo"), "original never overwritten");
        PassportLib.PassportEvent memory c = passport.getEvent(id, idx + 1);
        assertEq(uint8(c.eventType), uint8(PassportLib.EventType.Correction));
        assertEq(c.corrects, idx + 1);
    }

    function test_Burn_Impossible_And_PauseBlocksTransfers() public {
        uint256 id = _inspected(LOT_A, 1000);
        vm.prank(outsider);
        vm.expectRevert(abi.encodeWithSelector(PassportLib.LotPassport__NotRegistryAdmin.selector, outsider));
        passport.pause();

        vm.prank(admin);
        passport.pause();
        vm.prank(miner);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        passport.transferFrom(miner, buyer, id);
    }

    // ---------------------------------------------------------------- full demo journey

    /// Miner registers → inspector signs → sold to buyer (direct deal) → custody: miner → transporter
    /// → warehouse → transporter → buyer (dual-signed every hop).
    function test_FullJourney() public {
        uint256 id = _register(LOT_A, 2500);
        vm.prank(miner);
        passport.anchorDocument(id, keccak256("export-permit"));
        vm.prank(inspector);
        passport.submitInspection(id, true, keccak256("inspection"));
        vm.prank(miner);
        passport.safeTransferFrom(miner, buyer, id); // direct deal; marketplace sales go through escrow

        _moveCustody(id, miner, transporter);
        _moveCustody(id, transporter, warehouse);
        _moveCustody(id, warehouse, transporter);
        _moveCustody(id, transporter, buyer);

        assertEq(passport.ownerOf(id), buyer);
        assertEq(passport.custodianOf(id), buyer);
        assertFalse(passport.isFrozen(id));

        PassportLib.PassportEvent[] memory history = passport.getEvents(id, 0, 100);
        assertEq(history.length, passport.eventCount(id));
        assertEq(history.length, 12);
        assertEq(uint8(history[0].eventType), uint8(PassportLib.EventType.Registration));
        assertEq(uint8(history[11].eventType), uint8(PassportLib.EventType.CustodyConfirmed));

        // Pagination
        assertEq(passport.getEvents(id, 10, 10).length, 2);
        assertEq(passport.getEvents(id, 99, 10).length, 0);
    }

    // ---------------------------------------------------------------- fuzz

    function testFuzz_ProcessingConservesMass(uint128 inQty, uint128 outA, uint128 outB) public {
        inQty = uint128(bound(inQty, 2, type(uint64).max));
        outA = uint128(bound(outA, 1, type(uint64).max));
        outB = uint128(bound(outB, 1, type(uint64).max));
        uint256 a = _inspected(LOT_A, inQty);
        _moveCustody(a, miner, refinery);
        uint256[] memory inputs = new uint256[](1);
        inputs[0] = a;

        vm.prank(refinery);
        if (uint256(outA) + outB > inQty) {
            vm.expectRevert(
                abi.encodeWithSelector(PassportLib.LotPassport__QuantityExceeded.selector, inQty, uint256(outA) + outB)
            );
        }
        passport.processLots(inputs, _outputs("o1", outA, "o2", outB), H);
    }
}
