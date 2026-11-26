// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {MineNetFixture} from "test/utils/MineNetFixture.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/libraries/VRFV2PlusClient.sol";
import {EscrowLib} from "src/trade/libraries/EscrowLib.sol";
import {MarketplaceLib} from "src/trade/libraries/MarketplaceLib.sol";
import {B2BLib} from "src/b2b/libraries/B2BLib.sol";
import {PassportLib} from "src/traceability/libraries/PassportLib.sol";
import {SupplyChainLib} from "src/traceability/libraries/SupplyChainLib.sol";
import {InspectionLib} from "src/compliance/libraries/InspectionLib.sol";
import {AuditLib} from "src/compliance/libraries/AuditLib.sol";
import {WorkforceLib} from "src/workforce/libraries/WorkforceLib.sol";
import {InspectionRegistry} from "src/compliance/InspectionRegistry.sol";
import {Roles} from "src/access/libraries/Roles.sol";
import {Actions} from "src/access/libraries/Actions.sol";

/**
 * @title MockVRFCoordinator
 * @notice Minimal stand-in for the Chainlink VRF v2.5 coordinator: hands out request ids and fulfils on demand.
 */
contract MockVRFCoordinator {
    uint256 public nextRequestId = 1;

    function requestRandomWords(VRFV2PlusClient.RandomWordsRequest calldata) external returns (uint256 id) {
        id = nextRequestId++;
    }

    function fulfill(InspectionRegistry consumer, uint256 requestId, uint256 word) external {
        uint256[] memory words = new uint256[](1);
        words[0] = word;
        consumer.rawFulfillRandomWords(requestId, words);
    }
}

/**
 * @title LogicFixesTest
 * @notice Regression tests for the logic review: each test is an attack or failure that used to work, and must
 * now be blocked (or the safe path that replaced it).
 */
contract LogicFixesTest is MineNetFixture {
    uint256 constant FEE = PRICE * FEE_BPS / 10_000;

    // ================================================================ H1: escrow delivery

    /// The buyer receives the goods, forwards them to a warehouse, then claims non-delivery: refused, and the
    /// seller can still settle.
    function test_Escrow_ForwardingCustodyIsStillDelivery() public {
        (uint256 id, uint256 orderId) = _acceptedOrder();
        _moveCustody(id, miner, buyer);
        _moveCustody(id, buyer, warehouse);
        vm.warp(block.timestamp + 14 days + 1);

        vm.prank(buyer);
        vm.expectRevert(
            abi.encodeWithSelector(
                EscrowLib.EscrowManager__InvalidState.selector, orderId, EscrowLib.OrderStatus.Active
            )
        );
        escrow.cancelForNonDelivery(orderId);

        escrow.settle(orderId); // anyone: the delivery is on the passport record
        assertEq(escrow.claimable(usdc, miner), PRICE - FEE);
        assertEq(passport.ownerOf(id), buyer);
    }

    /// Proceeds go to the company's payout account once the admin sets one.
    function test_Escrow_ProceedsGoToCompanyPayout() public {
        address minerTreasury = makeAddr("minerTreasury");
        vm.prank(admin);
        registry.setOrgPayout("org-miner", minerTreasury);
        (uint256 id, uint256 orderId) = _acceptedOrder();
        _moveCustody(id, miner, buyer);
        vm.prank(buyer);
        escrow.releaseFunds(orderId);
        assertEq(escrow.claimable(usdc, minerTreasury), PRICE - FEE);
        assertEq(escrow.claimable(usdc, miner), 0);
    }

    /// A seller whose company was suspended cannot sell through an old listing.
    function test_Escrow_SuspendedSellerCannotSell() public {
        (, uint256 listingId) = _listed(10_000);
        vm.prank(regulator);
        registry.suspendOrg("org-miner", H);
        vm.prank(buyer);
        vm.expectRevert(abi.encodeWithSelector(EscrowLib.EscrowManager__Unauthorized.selector, miner));
        market.buyListing(listingId, type(uint256).max);
    }

    // ================================================================ H5: inspections

    function test_Inspection_RejectedLotNeedsRegulatorOrder() public {
        address second = _secondInspector();
        uint256 id = _register(1_000);
        _assignTo(id, inspector);
        vm.prank(inspector);
        passport.submitInspection(id, false, H);

        vm.prank(miner); // the operator cannot shop for another inspector
        vm.expectRevert(
            abi.encodeWithSelector(InspectionLib.InspectionRegistry__ReinspectionNeedsRegulator.selector, id)
        );
        inspections.requestInspection(id);

        _assignTo(id, second); // the regulator orders a re-inspection
        assertEq(inspections.getAssignment(id).requestedBy, regulator);
    }

    function test_Inspection_ResultCannotBeRevised() public {
        (uint256 id, uint256 orderId) = _acceptedOrder();
        _moveCustody(id, miner, buyer);
        assertFalse(inspections.isAssignmentOpen(id, inspector));
        vm.prank(inspector);
        vm.expectRevert(abi.encodeWithSelector(PassportLib.LotPassport__NotAssignedInspector.selector, id, inspector));
        passport.submitInspection(id, false, H);

        vm.prank(buyer); // the order settles normally
        escrow.releaseFunds(orderId);
        assertEq(passport.ownerOf(id), buyer);
    }

    function test_Inspection_ActiveAssignmentsFreedOnCompletion() public {
        uint256 before = inspections.getInspector(inspector).activeAssignments;
        _inspected(1_000);
        assertEq(inspections.getInspector(inspector).activeAssignments, before);
    }

    function test_Inspection_VrfDrawsTheInspector() public {
        MockVRFCoordinator vrf = new MockVRFCoordinator();
        vm.prank(admin);
        inspections.setVrfConfig(
            InspectionLib.VrfConfig({
                coordinator: address(vrf),
                keyHash: H,
                subId: 1,
                confirmations: 3,
                callbackGasLimit: 500_000,
                nativePayment: false
            })
        );
        uint256 id = _register(1_000);
        vm.prank(miner);
        assertEq(inspections.requestInspection(id), address(0)); // pending until fulfilment
        uint256 requestId = inspections.pendingDraw(id).requestId;
        assertTrue(requestId != 0);

        vm.prank(miner);
        vm.expectRevert(abi.encodeWithSelector(InspectionLib.InspectionRegistry__DrawPending.selector, id));
        inspections.requestInspection(id);

        vm.expectRevert(
            abi.encodeWithSelector(InspectionLib.InspectionRegistry__NotCoordinator.selector, address(this))
        );
        inspections.rawFulfillRandomWords(requestId, new uint256[](1));

        vrf.fulfill(inspections, requestId, 42);
        assertEq(inspections.assignedInspector(id), inspector);
        assertTrue(inspections.isAssignmentOpen(id, inspector));
        assertEq(inspections.getAssignment(id).requestedBy, miner);
    }

    // ================================================================ H3 / H4: B2B

    function test_B2B_DispatchedLotIsLocked_AndTitleCannotBeBlocked() public {
        (uint256 agr, uint256 lot) = _dispatched(address(0));

        vm.prank(miner);
        passport.setApprovalForAll(address(escrow), true);
        vm.prank(miner); // cannot be sold a second time
        vm.expectRevert(abi.encodeWithSelector(MarketplaceLib.Marketplace__LotLocked.selector, lot));
        market.createListing(_listingParams(lot, MarketplaceLib.PriceModel.FixedTotal, PRICE));

        vm.prank(miner); // revoking the approval no longer stops the buyer's title
        passport.setApprovalForAll(address(b2b), false);
        _moveCustody(lot, miner, refinery);
        vm.prank(refinery);
        b2b.acceptDelivery(agr, 0);
        assertEq(passport.ownerOf(lot), refinery);
        assertFalse(passport.escrowLocked(lot));
    }

    function test_B2B_PlatformDecidesWhenNoArbiter() public {
        (uint256 agr, uint256 lot) = _dispatched(address(0));
        _moveCustody(lot, miner, refinery);
        b2b.confirmArrival(agr, 0);
        vm.prank(refinery);
        b2b.rejectDelivery(agr, 0, H);
        vm.prank(miner); // the seller refuses to settle
        b2b.offerSettlement(agr, 0, 200_000e6);

        vm.warp(block.timestamp + 14 days + 1);
        vm.prank(admin);
        b2b.arbitrate(agr, 0, 100_000e6, keccak256("platform award"));
        assertEq(b2b.claimable(usdc, miner), 100_000e6);
        assertEq(b2b.claimable(usdc, refinery), 100_000e6);
    }

    function test_B2B_PlatformWaitsForAgreedArbiter() public {
        address arbiter = makeAddr("arbiter");
        (uint256 agr, uint256 lot) = _dispatched(arbiter);
        _moveCustody(lot, miner, refinery);
        b2b.confirmArrival(agr, 0);
        vm.prank(refinery);
        b2b.rejectDelivery(agr, 0, H);
        uint256 opened = block.timestamp;

        vm.warp(opened + 14 days + 1);
        vm.prank(admin); // the agreed arbiter still has time
        vm.expectRevert(abi.encodeWithSelector(B2BLib.B2B__NotArbiter.selector, admin));
        b2b.arbitrate(agr, 0, 0, H);

        vm.warp(opened + 44 days + 1); // the arbiter never ruled
        vm.prank(admin);
        b2b.arbitrate(agr, 0, 0, H);
        assertEq(b2b.claimable(usdc, refinery), 200_000e6);
        assertFalse(passport.escrowLocked(lot));
    }

    function test_B2B_UnauthorisedEmployeeCannotActForCompany() public {
        (uint256 agr,) = _dispatched(address(0));
        address guard = makeAddr("guard"); // in the miner's organisation, but not a trading role
        vm.prank(admin);
        registry.onboard(guard, Roles.ORACLE, "org-miner", H, 0);
        vm.prank(guard);
        vm.expectRevert(abi.encodeWithSelector(B2BLib.B2B__NotParty.selector, agr, guard));
        b2b.offerSettlement(agr, 0, 0);
    }

    // ================================================================ registry, customs, flags, processing

    function test_Registry_OrgSuspensionBlocksEveryAccount() public {
        address second = makeAddr("minerSecondAccount");
        vm.prank(admin);
        registry.onboard(second, Roles.MINER, "org-miner", H, 0);
        vm.prank(regulator);
        registry.suspendOrg("org-miner", H);
        assertFalse(registry.isAuthorized(miner, Actions.SELL_LOT));
        assertFalse(registry.isAuthorized(second, Actions.SELL_LOT));
        vm.prank(regulator);
        registry.reinstateOrg("org-miner", H);
        assertTrue(registry.isAuthorized(second, Actions.SELL_LOT));
    }

    function test_Customs_OnlyTheCustomsAuthorityOracleReleases() public {
        address otherOracle = makeAddr("otherOracle");
        vm.prank(admin);
        registry.onboard(otherOracle, Roles.ORACLE, "org-oracle-2", H, 0);
        uint256 id = _inspected(1_000);
        vm.prank(otherOracle);
        vm.expectRevert(
            abi.encodeWithSelector(
                SupplyChainLib.SupplyChain__Unauthorized.selector,
                otherOracle,
                SupplyChainLib.CheckpointType.CustomsReleased
            )
        );
        supplyChain.recordCheckpoint(
            SupplyChainLib.CheckpointInput({
                tokenId: id,
                cpType: SupplyChainLib.CheckpointType.CustomsReleased,
                measuredQty: 0,
                condition: SupplyChainLib.Condition.Good,
                gradeBps: 0,
                evidenceHash: H,
                locationHash: bytes32(0)
            })
        );
    }

    function test_Flags_DismissedFlagsCountAgainstReporter() public {
        uint256 id = _inspected(1_000);
        vm.prank(auditor);
        uint256 flagId = supplyChain.flagLot(id, keccak256("suspicion"));
        assertTrue(passport.isFrozen(id));
        vm.prank(regulator);
        passport.resolveFlag(flagId, false, H);
        assertEq(passport.dismissedFlagsOf(auditor), 1);
        assertFalse(passport.isFrozen(id));
    }

    function test_Processing_NeedsOwnerConsent() public {
        uint256 id = _inspected(1_000);
        _moveCustody(id, miner, refinery);
        uint256[] memory inputs = new uint256[](1);
        inputs[0] = id;
        PassportLib.LotOutput[] memory outs = new PassportLib.LotOutput[](1);
        outs[0] = PassportLib.LotOutput("ingot", TIN, 900, H);
        vm.prank(refinery);
        vm.expectRevert(abi.encodeWithSelector(PassportLib.LotPassport__NoOwnerConsent.selector, id, refinery));
        passport.processLots(inputs, outs, H);

        vm.prank(miner);
        passport.approve(refinery, id);
        vm.prank(refinery);
        passport.processLots(inputs, outs, H);
        assertEq(uint8(passport.getLot(id).status), uint8(PassportLib.LotStatus.Consumed));
    }

    // ================================================================ audits

    function test_Audit_LapsesAndThirdPartyRequestsDoNotBlock() public {
        address icglr = makeAddr("icglr");
        bytes32 scheme = AuditLib.ICGLR_THIRD_PARTY_AUDIT;
        vm.startPrank(admin);
        registry.onboard(icglr, Roles.ACCREDITOR, "org-icglr", H, 0);
        registry.updateLicence(auditor, H, uint64(block.timestamp + 5 * 365 days));
        audits.setScheme(
            scheme,
            AuditLib.Scheme({
                enabled: true,
                reviewRequired: true,
                maxConsecutive: 2,
                accreditorOrg: "org-icglr",
                validity: 365 days,
                coolingOff: 365 days
            })
        );
        vm.stopPrank();
        vm.prank(icglr);
        audits.accredit("org-audit", scheme, uint64(block.timestamp + 5 * 365 days), H);

        vm.prank(refinery); // a buyer's request does not take the company's slot
        audits.requestAudit(scheme, "org-miner", "org-audit", H);
        vm.prank(miner);
        uint256 id = audits.requestAudit(scheme, "org-miner", "org-audit", H);
        vm.prank(auditor);
        audits.acceptAudit(id);

        uint64 until = uint64(block.timestamp) + audits.FIELDWORK_LIMIT();
        vm.prank(miner);
        vm.expectRevert(abi.encodeWithSelector(AuditLib.AuditRegistry__NotLapsed.selector, id, until));
        audits.lapseAudit(id);
        vm.warp(until + 1);
        vm.prank(miner);
        audits.lapseAudit(id);
        assertEq(uint8(audits.getEngagement(id).status), uint8(AuditLib.EngagementStatus.Lapsed));
        vm.prank(miner); // free to engage again
        audits.requestAudit(scheme, "org-miner", "org-audit", H);
    }

    // ================================================================ workforce

    function test_Workforce_WalletChangeNeedsWorkerConfirmation() public {
        bytes32 worker = keccak256("worker");
        address wallet = makeAddr("workerWallet");
        address manager = makeAddr("managersOwnWallet");
        vm.prank(miner);
        workforce.registerWorker(worker, wallet, site);

        vm.prank(miner);
        workforce.setWorkerWallet(worker, manager);
        assertEq(workforce.getWorker(worker).wallet, wallet, "unchanged until the worker confirms");

        vm.prank(manager);
        vm.expectRevert(abi.encodeWithSelector(WorkforceLib.WorkforceManager__Unauthorized.selector, manager));
        workforce.confirmWalletChange(worker, manager);

        vm.prank(wallet);
        workforce.confirmWalletChange(worker, manager);
        assertEq(workforce.getWorker(worker).wallet, manager);
    }

    // ================================================================ helpers

    function _secondInspector() internal returns (address second) {
        second = makeAddr("second");
        vm.prank(admin);
        registry.onboard(second, Roles.INSPECTOR, "org-itsci", H, 0);
        vm.prank(regulator);
        inspections.setInspectorate("org-itsci", InspectionLib.InspectorateKind.TraceabilityOperator);
        _deployInspector(second);
    }

    /// Miner -> refinery single delivery of a 10 kg tin lot at 20 USDC/kg, funded and dispatched.
    function _dispatched(address arbiter) internal returns (uint256 agr, uint256 lot) {
        usdc.mint(refinery, 1_000_000e6);
        vm.prank(refinery);
        usdc.approve(address(b2b), type(uint256).max);
        vm.prank(miner);
        passport.setApprovalForAll(address(b2b), true);

        B2BLib.Terms memory t;
        t.seller = B2BLib.Side.Proposer;
        t.supply = B2BLib.SupplyTerms({
            mineralType: TIN,
            quantityPerDelivery: 10_000_000,
            quantityToleranceBps: 0,
            minGradeBps: 0,
            pricePerKg: 20e6,
            totalDeliveries: 1,
            deliveryInterval: 0,
            firstDeliveryOffset: 7 days
        });
        t.paymentToken = usdc;
        t.arbiter = arbiter;
        t.reviewPeriod = 3 days;
        t.proposalExpiresAt = uint64(block.timestamp + 7 days);
        t.termsHash = H;
        vm.prank(miner);
        agr = b2b.propose(refinery, t);
        vm.prank(refinery);
        b2b.sign(agr, 1);
        vm.prank(refinery);
        b2b.fundDelivery(agr, 0);

        uint256[] memory ids = new uint256[](1);
        lot = _inspected(10_000_000);
        ids[0] = lot;
        vm.prank(miner);
        b2b.dispatchDelivery(agr, 0, ids, 0, H);
    }
}
