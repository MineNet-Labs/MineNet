// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {MineNetFixture} from "test/utils/MineNetFixture.sol";
import {WorkforceLib} from "src/workforce/libraries/WorkforceLib.sol";
import {Roles} from "src/access/libraries/Roles.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract OtherToken is ERC20("Other", "OTH") {}

contract WorkforceTest is MineNetFixture {
    bytes32 constant W1 = keccak256("worker-1-salt");
    bytes32 constant W2 = keccak256("worker-2-salt");
    bytes32 constant W3 = keccak256("worker-3-salt"); // no wallet
    address w1 = makeAddr("w1");
    address w2 = makeAddr("w2");
    address miner2 = makeAddr("miner2");
    uint256 site2; // a second site of the same company

    function setUp() public override {
        super.setUp();
        vm.prank(admin);
        registry.onboard(miner2, Roles.MINER, "org-miner2", H, uint64(block.timestamp + 365 days));

        vm.startPrank(miner);
        site2 = sites.registerSite(concession, "site-2", _siteLocation(), H);
        workforce.registerWorker(W1, w1, site);
        workforce.registerWorker(W2, w2, site);
        workforce.registerWorker(W3, address(0), site2);
        vm.stopPrank();

        usdc.mint(miner, 100_000e6);
        vm.prank(miner);
        usdc.approve(address(workforce), type(uint256).max);
    }

    function _today() internal view returns (uint64) {
        return uint64(block.timestamp / 1 days);
    }

    function _ids(bytes32 a) internal pure returns (bytes32[] memory r) {
        r = new bytes32[](1);
        r[0] = a;
    }

    function _ids(bytes32 a, bytes32 b) internal pure returns (bytes32[] memory r) {
        r = new bytes32[](2);
        r[0] = a;
        r[1] = b;
    }

    function _payment(WorkforceLib.PaymentMethod method, bytes32 payee, bytes32 currency, uint256 amount)
        internal
        pure
        returns (WorkforceLib.PaymentInput memory)
    {
        return WorkforceLib.PaymentInput({
            payeeId: payee,
            payeeWallet: address(0),
            category: WorkforceLib.PaymentCategory.Salary,
            method: method,
            currency: currency,
            amount: amount,
            paymentRef: keccak256("2026-11"),
            receiptHash: keccak256("receipt")
        });
    }

    // ---------------------------------------------------------------- workers

    function test_RegisterWorker() public view {
        WorkforceLib.Worker memory w = workforce.getWorker(W1);
        assertEq(w.orgId, bytes32("org-miner"));
        assertEq(w.wallet, w1);
        assertEq(w.siteId, site);
        assertTrue(w.active);
        assertEq(workforce.workersOf("org-miner").length, 3);
    }

    function test_RegisterWorker_Rules() public {
        vm.startPrank(miner);
        vm.expectRevert(abi.encodeWithSelector(WorkforceLib.WorkforceManager__WorkerExists.selector, W1));
        workforce.registerWorker(W1, w1, site);
        vm.expectRevert(WorkforceLib.WorkforceManager__InvalidWorkerId.selector);
        workforce.registerWorker(bytes32(0), w1, site);
        vm.stopPrank();

        // another company cannot put workers on our site, nor manage our workers
        vm.startPrank(miner2);
        vm.expectRevert(abi.encodeWithSelector(WorkforceLib.WorkforceManager__SiteNotOfOrg.selector, site));
        workforce.registerWorker(keccak256("x"), w1, site);
        vm.expectRevert(abi.encodeWithSelector(WorkforceLib.WorkforceManager__NotYourWorker.selector, W1));
        workforce.assignSite(W1, 0);
        vm.stopPrank();

        vm.prank(buyer);
        vm.expectRevert(abi.encodeWithSelector(WorkforceLib.WorkforceManager__Unauthorized.selector, buyer));
        workforce.registerWorker(keccak256("y"), w1, 0);
    }

    function test_AssignSiteAndDeactivate() public {
        vm.startPrank(miner);
        workforce.assignSite(W1, site2);
        workforce.setWorkerActive(W2, false);
        vm.stopPrank();
        assertEq(workforce.getWorker(W1).siteId, site2);
        assertFalse(workforce.getWorker(W2).active);
    }

    // ---------------------------------------------------------------- attendance

    function test_Attendance_CountsOncePerDay() public {
        uint64 today = _today();
        vm.startPrank(miner);
        workforce.recordAttendance(site, today, _ids(W1, W2));
        workforce.recordAttendance(site, today, _ids(W1)); // retry: skipped
        vm.stopPrank();
        assertEq(workforce.getWorker(W1).daysWorked, 1);
        assertTrue(workforce.attendedOn(W1, today));

        vm.warp(block.timestamp + 1 days);
        vm.prank(oracle); // biometric attendance device, independent of the employer
        workforce.recordAttendance(site, today + 1, _ids(W1));
        assertEq(workforce.getWorker(W1).daysWorked, 2);
        assertEq(workforce.getWorker(W2).daysWorked, 1);
    }

    function test_Attendance_Backdating() public {
        vm.warp(block.timestamp + 30 days);
        uint64 today = _today();
        vm.startPrank(miner);
        workforce.recordAttendance(site, today - 7, _ids(W1)); // offline site syncing a week later
        vm.expectRevert(abi.encodeWithSelector(WorkforceLib.WorkforceManager__InvalidDay.selector, today - 8));
        workforce.recordAttendance(site, today - 8, _ids(W1));
        vm.expectRevert(abi.encodeWithSelector(WorkforceLib.WorkforceManager__InvalidDay.selector, today + 1));
        workforce.recordAttendance(site, today + 1, _ids(W1));
        vm.stopPrank();
    }

    function test_Attendance_Rules() public {
        uint64 today = _today();
        vm.prank(miner);
        vm.expectRevert(abi.encodeWithSelector(WorkforceLib.WorkforceManager__NotAtSite.selector, W3, site));
        workforce.recordAttendance(site, today, _ids(W3)); // W3 works at site2

        vm.prank(miner2);
        vm.expectRevert(abi.encodeWithSelector(WorkforceLib.WorkforceManager__Unauthorized.selector, miner2));
        workforce.recordAttendance(site, today, _ids(W1));

        vm.prank(miner);
        workforce.setWorkerActive(W2, false);
        vm.prank(miner);
        vm.expectRevert(abi.encodeWithSelector(WorkforceLib.WorkforceManager__WorkerInactive.selector, W2));
        workforce.recordAttendance(site, today, _ids(W2));
    }

    // ---------------------------------------------------------------- off-chain payments

    function test_MobileMoney_ConfirmedWithUsdValue() public {
        vm.prank(miner);
        uint256 id = workforce.recordPayment(_payment(WorkforceLib.PaymentMethod.MobileMoney, W1, RWF, 125_000));
        WorkforceLib.Payment memory p = workforce.getPayment(id);
        assertEq(uint8(p.status), uint8(WorkforceLib.PaymentStatus.Confirmed));
        assertEq(p.usdValue, 100e6); // 125,000 RWF at 1,250 RWF per USD
        assertEq(p.payeeWallet, w1);

        WorkforceLib.OrgReport memory r = workforce.orgReport("org-miner");
        assertEq(r.payments, 1);
        assertEq(r.totalUsd, 100e6);
        assertEq(r.usdByMethod[uint8(WorkforceLib.PaymentMethod.MobileMoney)], 100e6);
    }

    function test_Payment_StaleRateStillRecorded() public {
        vm.warp(block.timestamp + 2 days); // RWF rate is now stale
        vm.prank(miner);
        uint256 id = workforce.recordPayment(_payment(WorkforceLib.PaymentMethod.BankTransfer, W1, RWF, 125_000));
        assertEq(workforce.getPayment(id).usdValue, 0);
    }

    function test_Cash_AcknowledgedByWorker() public {
        vm.prank(miner);
        uint256 id = workforce.recordPayment(_payment(WorkforceLib.PaymentMethod.Cash, W1, USD, 200e6));
        assertEq(uint8(workforce.getPayment(id).status), uint8(WorkforceLib.PaymentStatus.PendingAck));
        assertEq(workforce.orgReport("org-miner").cashPendingAck, 1);

        vm.prank(w2);
        vm.expectRevert(abi.encodeWithSelector(WorkforceLib.WorkforceManager__NotPayee.selector, id, w2));
        workforce.acknowledgePayment(id, H);

        vm.prank(w1);
        workforce.acknowledgePayment(id, H);
        assertEq(uint8(workforce.getPayment(id).status), uint8(WorkforceLib.PaymentStatus.Acknowledged));
        assertEq(workforce.orgReport("org-miner").cashPendingAck, 0);
    }

    function test_Cash_WorkerWithoutWalletAcknowledgesThroughDevice() public {
        vm.prank(miner);
        uint256 id = workforce.recordPayment(_payment(WorkforceLib.PaymentMethod.Cash, W3, USD, 50e6));
        vm.prank(oracle); // fingerprint terminal
        workforce.acknowledgePayment(id, keccak256("fingerprint-match"));
        assertEq(uint8(workforce.getPayment(id).status), uint8(WorkforceLib.PaymentStatus.Acknowledged));
    }

    function test_Cash_RiskFlagsAndOverdue() public {
        vm.prank(miner);
        uint256 big = workforce.recordPayment(_payment(WorkforceLib.PaymentMethod.Cash, W1, USD, 2_000e6));
        assertTrue(workforce.getPayment(big).cashRisk);
        assertEq(workforce.orgReport("org-miner").cashRiskPayments, 1);

        assertFalse(workforce.isAckOverdue(big));
        vm.warp(block.timestamp + 7 days + 1);
        assertTrue(workforce.isAckOverdue(big));
    }

    function test_CashShare() public {
        vm.startPrank(miner);
        workforce.recordPayment(_payment(WorkforceLib.PaymentMethod.Cash, W1, USD, 100e6));
        workforce.recordPayment(_payment(WorkforceLib.PaymentMethod.MobileMoney, W2, USD, 300e6));
        vm.stopPrank();
        assertEq(workforce.cashShareBps("org-miner"), 2_500);
    }

    function test_Dispute() public {
        vm.prank(miner);
        uint256 id = workforce.recordPayment(_payment(WorkforceLib.PaymentMethod.Cash, W1, USD, 100e6));
        vm.prank(w1);
        workforce.disputePayment(id, keccak256("never received"));
        WorkforceLib.OrgReport memory r = workforce.orgReport("org-miner");
        assertEq(r.disputed, 1);
        assertEq(r.cashPendingAck, 0);
        vm.prank(w1);
        vm.expectRevert(
            abi.encodeWithSelector(
                WorkforceLib.WorkforceManager__InvalidPaymentStatus.selector, id, WorkforceLib.PaymentStatus.Disputed
            )
        );
        workforce.acknowledgePayment(id, H);
    }

    function test_RecordPayment_Rules() public {
        vm.startPrank(miner);
        vm.expectRevert(WorkforceLib.WorkforceManager__InvalidMethod.selector);
        workforce.recordPayment(_payment(WorkforceLib.PaymentMethod.Stablecoin, W1, USD, 1));
        vm.expectRevert(abi.encodeWithSelector(WorkforceLib.WorkforceManager__UnknownCurrency.selector, bytes32("KES")));
        workforce.recordPayment(_payment(WorkforceLib.PaymentMethod.Cash, W1, "KES", 1));
        vm.expectRevert(
            abi.encodeWithSelector(WorkforceLib.WorkforceManager__UnknownWorker.selector, keccak256("ghost"))
        );
        workforce.recordPayment(_payment(WorkforceLib.PaymentMethod.Cash, keccak256("ghost"), USD, 1));
        vm.stopPrank();

        // a supplier payment does not need a registered worker
        WorkforceLib.PaymentInput memory p = _payment(WorkforceLib.PaymentMethod.BankTransfer, "supplier-7", USD, 5e6);
        p.category = WorkforceLib.PaymentCategory.Supplier;
        vm.prank(miner);
        workforce.recordPayment(p);
    }

    // ---------------------------------------------------------------- on-chain stablecoin payroll

    function test_Payroll_PaysWorkersInStablecoin() public {
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 300e6;
        amounts[1] = 250e6;
        vm.prank(miner);
        uint256 first = workforce.payPayroll(usdc, _ids(W1, W2), amounts, keccak256("2026-11"));

        assertEq(usdc.balanceOf(w1), 300e6);
        assertEq(usdc.balanceOf(w2), 250e6);
        WorkforceLib.Payment memory p = workforce.getPayment(first);
        assertEq(uint8(p.method), uint8(WorkforceLib.PaymentMethod.Stablecoin));
        assertEq(p.currency, USD);
        assertEq(p.usdValue, 300e6);
        assertEq(workforce.orgReport("org-miner").usdByMethod[uint8(WorkforceLib.PaymentMethod.Stablecoin)], 550e6);
    }

    function test_Payroll_NeedsWalletAndSettlementToken() public {
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1e6;
        OtherToken other = new OtherToken();
        vm.startPrank(miner);
        vm.expectRevert(abi.encodeWithSelector(WorkforceLib.WorkforceManager__NoWallet.selector, W3));
        workforce.payPayroll(usdc, _ids(W3), amounts, H);
        vm.expectRevert(); // not a settlement token
        workforce.payPayroll(other, _ids(W1), amounts, H);
        vm.stopPrank();
    }

    function test_PayStablecoin_Supplier() public {
        address supplier = makeAddr("supplier");
        vm.prank(miner);
        workforce.payStablecoin("supplier-7", supplier, WorkforceLib.PaymentCategory.Supplier, usdc, 1_000e6, H);
        assertEq(usdc.balanceOf(supplier), 1_000e6);
    }
}
