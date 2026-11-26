// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MineNetFixture} from "test/utils/MineNetFixture.sol";
import {B2BServices} from "src/b2b/B2BServices.sol";
import {B2BLib} from "src/b2b/libraries/B2BLib.sol";
import {ServicesLib} from "src/b2b/libraries/ServicesLib.sol";

/**
 * @title ServicesHandler
 * @notice Drives random sequences of client, provider and arbiter actions against one escrowed service agreement.
 * @dev State-aware: each action targets a job in the state it needs, picked at random among those, so the fuzzer
 * reaches every part of the lifecycle. Expected reverts are swallowed.
 */
contract ServicesHandler is Test {
    B2BServices internal immutable services;
    IERC20 internal immutable token;
    address internal immutable client;
    address internal immutable provider;
    address internal immutable arbiter;
    uint256 public immutable agreementId;
    uint32 internal immutable totalJobs;
    /// Handler calls so far in this campaign.
    uint256 public calls;
    /// Successful calls per action, to confirm the fuzzer reaches every state.
    mapping(bytes32 action => uint256) public hits;

    modifier counted() {
        ++calls;
        _;
    }

    constructor(
        B2BServices services_,
        IERC20 token_,
        address client_,
        address provider_,
        address arbiter_,
        uint256 agreementId_
    ) {
        services = services_;
        token = token_;
        client = client_;
        provider = provider_;
        arbiter = arbiter_;
        agreementId = agreementId_;
        totalJobs = services_.getAgreement(agreementId_).service.totalJobs;
    }

    function fund(uint256 seed) external counted {
        (bool ok, uint256 index) = _find(ServicesLib.JobStatus.Scheduled, seed);
        if (!ok) return;
        vm.prank(client);
        try services.fundJob(agreementId, index) {
            hits["fund"]++;
        } catch {}
    }

    function claim(uint256 seed, uint128 units) external counted {
        (bool ok, uint256 index) = _find(ServicesLib.JobStatus.Funded, seed);
        if (!ok) return;
        uint256[] memory none;
        vm.prank(provider);
        try services.claimJob(agreementId, index, none, none, units, keccak256("work")) {
            hits["claim"]++;
        } catch {}
    }

    function accept(uint256 seed) external counted {
        (bool ok, uint256 index) = _find(ServicesLib.JobStatus.Claimed, seed);
        if (!ok) return;
        vm.prank(client);
        try services.acceptJob(agreementId, index) {
            hits["accept"]++;
        } catch {}
    }

    function release(uint256 seed) external counted {
        (bool ok, uint256 index) = _find(ServicesLib.JobStatus.Claimed, seed);
        if (!ok) return;
        vm.warp(block.timestamp + 3 days + 1);
        try services.releaseAfterReview(agreementId, index) {
            hits["release"]++;
        } catch {}
    }

    function dispute(uint256 seed) external counted {
        (bool ok, uint256 index) = _find(ServicesLib.JobStatus.Claimed, seed);
        if (!ok) return;
        vm.prank(client);
        try services.disputeJob(agreementId, index, keccak256("reason")) {
            hits["dispute"]++;
        } catch {}
    }

    /// Both sides make offers; they settle when the client offers at least the provider's ask.
    function offer(uint256 seed, uint256 ask, uint256 bid) external counted {
        (bool ok, uint256 index) = _find(ServicesLib.JobStatus.Disputed, seed);
        if (!ok) return;
        uint256 max = services.getJob(agreementId, index).amount;
        vm.prank(provider);
        try services.offerSettlement(agreementId, index, bound(ask, 0, max)) {} catch {}
        vm.prank(client);
        try services.offerSettlement(agreementId, index, bound(bid, 0, max)) {
            hits["offer"]++;
        } catch {}
    }

    function arbitrate(uint256 seed, uint256 amount) external counted {
        (bool ok, uint256 index) = _find(ServicesLib.JobStatus.Disputed, seed);
        if (!ok) return;
        vm.warp(block.timestamp + 14 days + 1);
        amount = bound(amount, 0, services.getJob(agreementId, index).amount);
        vm.prank(arbiter);
        try services.arbitrate(agreementId, index, amount, keccak256("award")) {
            hits["arbitrate"]++;
        } catch {}
    }

    function closeMissed(uint256 seed, bool byProvider) external counted {
        (bool ok, uint256 index) = _find(ServicesLib.JobStatus.Funded, seed);
        if (!ok) return;
        if (!byProvider) vm.warp(uint256(services.dueAt(agreementId, index)) + 30 days + 1);
        vm.prank(byProvider ? provider : client);
        try services.closeMissed(agreementId, index) {
            hits["closeMissed"]++;
        } catch {}
    }

    function markDefaulted(uint256 seed) external counted {
        (bool ok, uint256 index) = _find(ServicesLib.JobStatus.Scheduled, seed);
        if (!ok) return;
        vm.prank(provider);
        try services.markDefaulted(agreementId, index) {
            hits["markDefaulted"]++;
        } catch {}
    }

    /// Mutual termination, only late in a campaign so most of it exercises the full job lifecycle.
    function terminate() external counted {
        if (calls < 40) return;
        vm.prank(provider);
        try services.requestTermination(agreementId, keccak256("end")) {} catch {}
        vm.prank(client);
        try services.confirmTermination(agreementId) {
            hits["terminate"]++;
        } catch {}
    }

    function withdraw(uint8 who) external counted {
        address account = who % 3 == 0 ? client : who % 3 == 1 ? provider : arbiter;
        vm.prank(account);
        try services.withdraw(token) {
            hits["withdraw"]++;
        } catch {}
    }

    function warp(uint256 secondsAhead) external counted {
        vm.warp(block.timestamp + bound(secondsAhead, 1 hours, 10 days));
    }

    /// A random job currently in `status`, if any.
    function _find(ServicesLib.JobStatus status, uint256 seed) internal view returns (bool found, uint256 index) {
        uint256 start = seed % totalJobs;
        for (uint256 k; k < totalJobs; ++k) {
            index = (start + k) % totalJobs;
            if (services.getJob(agreementId, index).status == status) return (true, index);
        }
    }
}

/**
 * @title B2BServicesInvariantTest
 * @notice Stateful invariants of {B2BServices}: exact escrow solvency and consistent job accounting.
 */
contract B2BServicesInvariantTest is MineNetFixture {
    ServicesHandler internal handler;
    address internal arbiter = makeAddr("arbiter");
    uint256 internal id;

    function setUp() public override {
        super.setUp();
        usdc.mint(miner, 1_000_000_000e6);
        vm.prank(miner);
        usdc.approve(address(services), type(uint256).max);

        ServicesLib.Terms memory t;
        t.service = ServicesLib.ServiceTerms({
            kind: ServicesLib.ServiceKind.Security,
            provider: B2BLib.Side.Counterparty,
            ratePerUnit: 100e6,
            maxUnitsPerJob: 30,
            totalJobs: 6,
            jobInterval: 7 days,
            firstJobOffset: 7 days
        });
        t.paymentToken = usdc;
        t.arbiter = arbiter;
        t.reviewPeriod = 3 days;
        t.proposalExpiresAt = uint64(block.timestamp + 7 days);
        t.termsHash = keccak256("security-contract");
        vm.prank(miner);
        id = services.propose(warehouse, t);
        vm.prank(warehouse);
        services.sign(id, 1);

        handler = new ServicesHandler(services, usdc, miner, warehouse, arbiter, id);
        targetContract(address(handler));
    }

    /**
     * @notice The contract holds exactly the escrow of open jobs plus every credited balance: nothing is created,
     * lost or double-paid.
     */
    function invariant_EscrowSolvencyIsExact() public view {
        uint256 escrowed;
        uint32 total = services.getAgreement(id).service.totalJobs;
        for (uint256 i; i < total; ++i) {
            ServicesLib.Job memory j = services.getJob(id, i);
            if (
                j.status == ServicesLib.JobStatus.Funded || j.status == ServicesLib.JobStatus.Claimed
                    || j.status == ServicesLib.JobStatus.Disputed
            ) escrowed += j.funded;
        }
        uint256 credited =
            services.claimable(usdc, miner) + services.claimable(usdc, warehouse) + services.claimable(usdc, arbiter);
        assertEq(usdc.balanceOf(address(services)), escrowed + credited);
    }

    /**
     * @notice The agreement's counters always match the jobs' actual statuses, and a job never bills more than its
     * budget.
     */
    function invariant_ProgressMatchesJobs() public view {
        ServicesLib.Agreement memory a = services.getAgreement(id);
        uint32 funded;
        uint32 inFlight;
        uint32 finals;
        for (uint256 i; i < a.service.totalJobs; ++i) {
            ServicesLib.Job memory j = services.getJob(id, i);
            if (j.status == ServicesLib.JobStatus.Funded) ++funded;
            else if (j.status == ServicesLib.JobStatus.Claimed || j.status == ServicesLib.JobStatus.Disputed) ++inFlight;
            else if (j.status != ServicesLib.JobStatus.Scheduled) ++finals;
            if (j.funded != 0) assertLe(j.amount, j.funded);
        }
        assertEq(a.progress.funded, funded);
        assertEq(a.progress.inFlight, inFlight);
        assertLe(finals, a.service.totalJobs);
        if (a.status == B2BLib.AgreementStatus.Completed) assertEq(finals, a.service.totalJobs);
    }

    /**
     * @notice The arbiter is never paid: only the parties ever hold a balance.
     */
    function invariant_OnlyPartiesArePaid() public view {
        assertEq(services.claimable(usdc, arbiter), 0);
        assertEq(usdc.balanceOf(arbiter), 0);
    }

    /**
     * @notice Logs how often each action succeeded in the last campaign (coverage check, always passes).
     */
    function invariant_callSummary() public view {
        string[12] memory names = [
            "fund",
            "claim",
            "accept",
            "release",
            "dispute",
            "offer",
            "arbitrate",
            "closeMissed",
            "markDefaulted",
            "terminate",
            "withdraw",
            "none"
        ];
        for (uint256 i; i < names.length - 1; ++i) {
            console.log(names[i], handler.hits(bytes32(bytes(names[i]))));
        }
    }
}
