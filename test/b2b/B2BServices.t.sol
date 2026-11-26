// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MineNetFixture} from "test/utils/MineNetFixture.sol";
import {B2BLib} from "src/b2b/libraries/B2BLib.sol";
import {ServicesLib} from "src/b2b/libraries/ServicesLib.sol";
import {PassportLib} from "src/traceability/libraries/PassportLib.sol";

contract B2BServicesTest is MineNetFixture {
    address arbiter = makeAddr("arbiter");
    uint256[] none;

    function setUp() public override {
        super.setUp();
        usdc.mint(miner, 10_000_000e6);
        vm.prank(miner);
        usdc.approve(address(services), type(uint256).max);
    }

    // ---------------------------------------------------------------- helpers

    /// The miner (proposer) is the client; the counterparty provides `kind`.
    function _terms(ServicesLib.ServiceKind kind, uint256 rate, uint128 maxUnits)
        internal
        view
        returns (ServicesLib.Terms memory t)
    {
        t.service = ServicesLib.ServiceTerms({
            kind: kind,
            provider: B2BLib.Side.Counterparty,
            ratePerUnit: rate,
            maxUnitsPerJob: maxUnits,
            totalJobs: 4,
            jobInterval: 30 days,
            firstJobOffset: 30 days
        });
        t.paymentToken = usdc;
        t.reviewPeriod = 3 days;
        t.proposalExpiresAt = uint64(block.timestamp + 7 days);
        t.termsHash = keccak256("service-contract");
    }

    function _active(address provider, ServicesLib.Terms memory t) internal returns (uint256 id) {
        vm.prank(miner);
        id = services.propose(provider, t);
        vm.prank(provider);
        services.sign(id, 1);
    }

    function _fund(uint256 id, uint256 index) internal {
        vm.prank(miner);
        services.fundJob(id, index);
    }

    function _one(uint256 x) internal pure returns (uint256[] memory a) {
        a = new uint256[](1);
        a[0] = x;
    }

    function _jStatus(uint256 id, uint256 index) internal view returns (ServicesLib.JobStatus) {
        return services.getJob(id, index).status;
    }

    // ---------------------------------------------------------------- haulage

    function test_Haulage_BillsDeliveredShipmentsOnce() public {
        // 0.05 USDC per kg, budget 2 t per job -> 100 USDC
        uint256 id = _active(transporter, _terms(ServicesLib.ServiceKind.Haulage, 50_000, 2_000_000));
        assertEq(services.budgetOf(id), 100e6);
        _fund(id, 0);

        uint256 lot = _inspected(1_000_000);
        uint256 sid = _deliver(lot, miner, refinery); // carried by the transporter, delivered
        vm.prank(transporter);
        services.claimJob(id, 0, _one(sid), none, 0, keccak256("waybill"));
        ServicesLib.Job memory j = services.getJob(id, 0);
        assertEq(j.units, 1_000_000);
        assertEq(j.amount, 50e6);

        vm.prank(miner);
        services.acceptJob(id, 0);
        assertEq(services.claimable(usdc, transporter), 50e6);
        assertEq(services.claimable(usdc, miner), 50e6);
        assertEq(services.performanceOf("org-transport").jobsCompleted, 1);

        _fund(id, 1); // the same shipment cannot be billed twice
        vm.prank(transporter);
        vm.expectRevert(abi.encodeWithSelector(ServicesLib.B2BServices__InvalidWork.selector, sid));
        services.claimJob(id, 1, _one(sid), none, 0, H);
    }

    function test_Haulage_RejectsShipmentsBeforeActivationOrNotDelivered() public {
        uint256 early = _deliver(_inspected(1_000_000), miner, refinery); // before the agreement
        vm.warp(block.timestamp + 1 hours);
        uint256 id = _active(transporter, _terms(ServicesLib.ServiceKind.Haulage, 50_000, 2_000_000));
        _fund(id, 0);
        vm.prank(transporter);
        vm.expectRevert(abi.encodeWithSelector(ServicesLib.B2BServices__InvalidWork.selector, early));
        services.claimJob(id, 0, _one(early), none, 0, H);

        uint256[] memory ids = _one(_inspected(1_000_000));
        vm.prank(miner);
        uint256 open = delivery.createShipment(ids, transporter, refinery, uint64(block.timestamp + 1 days), SEAL, H);
        vm.prank(transporter);
        vm.expectRevert(abi.encodeWithSelector(ServicesLib.B2BServices__InvalidWork.selector, open));
        services.claimJob(id, 0, _one(open), none, 0, H);
    }

    function test_ProviderMustBeQualifiedForKind() public {
        ServicesLib.Terms memory t = _terms(ServicesLib.ServiceKind.Haulage, 50_000, 2_000_000);
        vm.prank(miner); // a warehouse cannot be hired for haulage
        vm.expectRevert(abi.encodeWithSelector(ServicesLib.B2BServices__ProviderNotQualified.selector, warehouse));
        services.propose(warehouse, t);
    }

    // ---------------------------------------------------------------- storage

    function test_Storage_BillsLotsInCustodyPerPeriod() public {
        // 0.01 USDC per kg per month, budget 5 t
        uint256 id = _active(warehouse, _terms(ServicesLib.ServiceKind.Storage, 10_000, 5_000_000));
        _fund(id, 0);
        uint256 lot = _inspected(2_000_000);
        _moveCustody(lot, miner, warehouse);

        uint64 periodEnd = services.dueAt(id, 0);
        vm.prank(warehouse);
        vm.expectRevert(abi.encodeWithSelector(B2BLib.B2B__TooEarly.selector, 0, periodEnd));
        services.claimJob(id, 0, _one(lot), none, 0, H);

        vm.warp(periodEnd);
        uint256[] memory twice = new uint256[](2);
        twice[0] = lot;
        twice[1] = lot;
        vm.prank(warehouse);
        vm.expectRevert(abi.encodeWithSelector(ServicesLib.B2BServices__InvalidWork.selector, lot));
        services.claimJob(id, 0, twice, none, 0, H);

        vm.prank(warehouse);
        services.claimJob(id, 0, _one(lot), none, 0, keccak256("stock-report"));
        assertEq(services.getJob(id, 0).amount, 20e6);

        // a period can only be billed until the next one ends
        _fund(id, 1);
        vm.warp(services.dueAt(id, 2));
        vm.prank(warehouse);
        vm.expectRevert(abi.encodeWithSelector(ServicesLib.B2BServices__InvalidWork.selector, 1));
        services.claimJob(id, 1, _one(lot), none, 0, H);
    }

    // ---------------------------------------------------------------- toll processing

    function test_TollProcessing_BillsConsumedInputLots() public {
        // 0.2 USDC per kg processed, budget 3 t -> 600 USDC
        uint256 id = _active(processor, _terms(ServicesLib.ServiceKind.TollProcessing, 200_000, 3_000_000));
        _fund(id, 0);
        uint256 lot = _inspected(1_500_000);
        _moveCustody(lot, miner, processor);

        vm.prank(processor);
        vm.expectRevert(abi.encodeWithSelector(ServicesLib.B2BServices__InvalidWork.selector, lot));
        services.claimJob(id, 0, _one(lot), none, 0, H); // not processed yet

        PassportLib.LotOutput[] memory outs = new PassportLib.LotOutput[](1);
        outs[0] = PassportLib.LotOutput(keccak256("concentrate-1"), TIN, 900_000, H);
        vm.prank(miner); // the owner consents to toll processing
        passport.approve(processor, lot);
        vm.prank(processor);
        passport.processLots(_one(lot), outs, keccak256("yield-report"));

        vm.prank(processor);
        services.claimJob(id, 0, _one(lot), none, 0, H);
        assertEq(services.getJob(id, 0).amount, 300e6); // 1,500 kg input x 0.2
    }

    // ---------------------------------------------------------------- inspection

    function test_Inspection_BillsSignedCheckpoints() public {
        uint256 id = _active(inspector, _terms(ServicesLib.ServiceKind.InspectionAssay, 25e6, 10));
        _fund(id, 0);
        uint256 lot = _inspected(1_000_000);
        _grade(lot, 6_500);
        uint256 cp = supplyChain.checkpointCount(lot) - 1;

        vm.prank(inspector);
        vm.expectRevert(abi.encodeWithSelector(ServicesLib.B2BServices__InvalidWork.selector, 0));
        services.claimJob(id, 0, _one(lot), none, 0, H); // checkpoint indexes required

        vm.prank(inspector);
        services.claimJob(id, 0, _one(lot), _one(cp), 0, keccak256("assay-certificate"));
        assertEq(services.getJob(id, 0).amount, 25e6);

        vm.warp(block.timestamp + 3 days + 1);
        services.releaseAfterReview(id, 0);
        assertEq(services.claimable(usdc, inspector), 25e6);
        assertEq(services.claimable(usdc, miner), 225e6);
    }

    // ---------------------------------------------------------------- claimed services & disputes

    function test_ClaimedService_DisputeSettledByOffers() public {
        ServicesLib.Terms memory t = _terms(ServicesLib.ServiceKind.Security, 100e6, 30); // per guard-day
        t.arbiter = arbiter;
        uint256 id = _active(warehouse, t);
        _fund(id, 0);

        uint64 due = services.dueAt(id, 0); // self-declared work is billable from the job's date
        vm.prank(warehouse);
        vm.expectRevert(abi.encodeWithSelector(B2BLib.B2B__TooEarly.selector, 0, due));
        services.claimJob(id, 0, none, none, 10, H);
        vm.warp(due);

        vm.prank(warehouse);
        vm.expectRevert(abi.encodeWithSelector(ServicesLib.B2BServices__InvalidWork.selector, 1));
        services.claimJob(id, 0, _one(1), none, 10, H); // claimed kinds take no references

        vm.prank(warehouse);
        services.claimJob(id, 0, none, none, 40, keccak256("timesheet")); // capped at the 30-day budget
        assertEq(services.getJob(id, 0).units, 30);
        assertEq(services.getJob(id, 0).amount, 3_000e6);

        vm.prank(miner);
        services.disputeJob(id, 0, keccak256("only 25 days covered"));
        vm.prank(warehouse);
        services.offerSettlement(id, 0, 2_600e6);
        vm.prank(miner);
        services.offerSettlement(id, 0, 2_500e6); // below the ask: no settlement yet
        assertEq(uint8(_jStatus(id, 0)), uint8(ServicesLib.JobStatus.Disputed));
        vm.prank(miner);
        services.offerSettlement(id, 0, 2_600e6);

        assertEq(uint8(_jStatus(id, 0)), uint8(ServicesLib.JobStatus.Settled));
        assertEq(services.claimable(usdc, warehouse), 2_600e6);
        assertEq(services.claimable(usdc, miner), 400e6);
        assertEq(services.performanceOf("org-warehouse").disputesLost, 1);
    }

    function test_Arbiter_DecidesAfterNegotiation() public {
        ServicesLib.Terms memory t = _terms(ServicesLib.ServiceKind.Consulting, 100e6, 10);
        t.arbiter = arbiter;
        uint256 id = _active(auditor, t);
        _fund(id, 0);
        uint64 due = services.dueAt(id, 0);
        vm.warp(due);
        vm.prank(auditor);
        services.claimJob(id, 0, none, none, 10, H);
        vm.prank(miner);
        services.disputeJob(id, 0, H);

        uint64 until = due + 14 days;
        vm.prank(arbiter);
        vm.expectRevert(abi.encodeWithSelector(B2BLib.B2B__NegotiationPeriod.selector, until));
        services.arbitrate(id, 0, 500e6, H);
        vm.warp(until + 1);
        vm.prank(arbiter);
        services.arbitrate(id, 0, 500e6, keccak256("award"));
        assertEq(services.claimable(usdc, auditor), 500e6);
        assertEq(services.claimable(usdc, miner), 500e6);
    }

    // ---------------------------------------------------------------- missed, default, termination

    function test_Missed_Default_AndTerminationForCause() public {
        ServicesLib.Terms memory t = _terms(ServicesLib.ServiceKind.Maintenance, 100e6, 10);
        t.maxMissed = 2;
        uint256 id = _active(transporter, t);
        _fund(id, 0);

        uint64 due = services.dueAt(id, 0);
        vm.prank(miner);
        vm.expectRevert(abi.encodeWithSelector(B2BLib.B2B__TooEarly.selector, 0, due + 30 days));
        services.closeMissed(id, 0);
        vm.warp(due + 30 days + 1);
        vm.prank(miner);
        services.closeMissed(id, 0);
        assertEq(services.claimable(usdc, miner), 1_000e6);

        vm.prank(transporter); // the provider gives up job 1 early
        services.closeMissed(id, 1);
        assertEq(services.performanceOf("org-transport").jobsMissed, 2);

        vm.prank(miner);
        services.terminateForCause(id, keccak256("notice"));
        assertEq(uint8(services.getAgreement(id).status), uint8(B2BLib.AgreementStatus.Terminated));
        assertEq(uint8(_jStatus(id, 3)), uint8(ServicesLib.JobStatus.Cancelled));
    }

    function test_Default_ClientDidNotFund() public {
        uint256 id = _active(transporter, _terms(ServicesLib.ServiceKind.Haulage, 50_000, 2_000_000));
        vm.warp(services.dueAt(id, 0) + 1);
        vm.prank(transporter);
        services.markDefaulted(id, 0);
        assertEq(services.performanceOf("org-miner").fundingDefaults, 1);
    }

    function test_MutualTermination_RefundsFundedJobs() public {
        uint256 id = _active(transporter, _terms(ServicesLib.ServiceKind.Haulage, 50_000, 2_000_000));
        _fund(id, 0);
        _fund(id, 1);
        vm.prank(transporter);
        services.requestTermination(id, H);
        vm.prank(miner);
        services.confirmTermination(id);
        assertEq(services.claimable(usdc, miner), 200e6);
        assertEq(services.getAgreement(id).progress.cancelled, 4);
    }

    function test_OffChainPayment_RecordsWithoutEscrow() public {
        ServicesLib.Terms memory t = _terms(ServicesLib.ServiceKind.Labour, 15_000, 100); // RWF per shift
        t.paymentToken = IERC20(address(0));
        uint256 id = _active(processor, t);
        vm.warp(services.dueAt(id, 0));
        vm.prank(processor);
        services.claimJob(id, 0, none, none, 80, keccak256("attendance"));
        vm.prank(miner);
        services.acceptJob(id, 0);
        assertEq(uint8(_jStatus(id, 0)), uint8(ServicesLib.JobStatus.Accepted));
        assertEq(services.getJob(id, 0).amount, 1_200_000);
    }
}
