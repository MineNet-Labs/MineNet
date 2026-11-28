// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MineNetFixture} from "test/utils/MineNetFixture.sol";
import {StaffLib} from "src/workforce/libraries/StaffLib.sol";
import {SiteOpsLib} from "src/workforce/libraries/SiteOpsLib.sol";
import {PayrollLib} from "src/workforce/libraries/PayrollLib.sol";

/**
 * @notice A site team on top of {MineNetFixture}: manager, HR, inspector and a shift supervisor at `site`, and
 * helpers to hire workers and run their attendance and pay. Day 60 (the start) is a Monday.
 */
abstract contract SiteTeamFixture is MineNetFixture {
    bytes32 constant MGR = keccak256("grace");
    bytes32 constant HR = keccak256("alice");
    bytes32 constant INSP = keccak256("patrick");
    bytes32 constant SUP = keccak256("samuel");
    bytes32 constant MGR2 = keccak256("eric");
    bytes32 constant NEW1 = keccak256("jean-paul");
    bytes32 constant NEW2 = keccak256("claudine");
    bytes32 constant DRILLER = "DRILLER";
    uint128 constant RATE = 10e6; // 10 USD per shift
    uint128 constant SALARY = 2_600e6; // 2,600 USD a month = 100 USD a day over 26 days
    uint128 constant ONBOARD = 50e6;
    uint16 constant PENALTY_BPS = 5_000;
    uint16 constant REST_OT_BPS = 15_000;
    uint16 constant HOLIDAY_OT_BPS = 20_000;
    uint8 constant MON_SAT = 0x3F;

    address mgrW = makeAddr("managerWallet");
    address hrW = makeAddr("hrWallet");
    address inspW = makeAddr("inspectorWallet");
    address supW = makeAddr("supervisorWallet");
    address mgr2W = makeAddr("manager2Wallet");
    address new1W = makeAddr("newHire1");
    address new2W = makeAddr("newHire2");

    uint256 site2;

    function setUp() public virtual override {
        super.setUp();
        vm.warp(60 days + 8 hours); // Monday 2 March 1970, 08:00
        vm.prank(oracle);
        rwfFeed.postRate(RWF_RATE);
        vm.startPrank(miner);
        site2 = sites.registerSite(concession, "site-2", _siteLocation(), H);
        workforce.registerWorker(MGR, mgrW, site);
        workforce.registerWorker(HR, hrW, site);
        workforce.registerWorker(INSP, inspW, site);
        workforce.registerWorker(SUP, supW, site);
        workforce.registerWorker(MGR2, mgr2W, site);
        workforce.appointSiteSeat(site, StaffLib.SiteSeat.Manager, MGR);
        workforce.appointSiteSeat(site, StaffLib.SiteSeat.Hr, HR);
        workforce.appointSiteSeat(site, StaffLib.SiteSeat.Inspector, INSP);
        workforce.assignRole(SUP, StaffLib.SUPERVISOR, false);
        usdc.approve(address(payroll), type(uint256).max);
        rwfCoin.approve(address(payroll), type(uint256).max);
        vm.stopPrank();
        usdc.mint(miner, 1_000_000e6);
        rwfCoin.mint(miner, 1_000_000_000);
    }

    function _position(uint32 headcount, SiteOpsLib.PayFrequency f, SiteOpsLib.PayBasis basis, uint128 rate)
        internal
        pure
        returns (SiteOpsLib.PositionInput memory)
    {
        return SiteOpsLib.PositionInput({
            title: DRILLER,
            available: 4,
            headcount: headcount,
            currency: USD,
            basis: basis,
            rate: rate,
            onboardingCost: ONBOARD,
            frequency: f,
            requirementsHash: keccak256("driller-jd")
        });
    }

    function _openPosition(SiteOpsLib.PositionInput memory p) internal returns (uint256 positionId) {
        vm.prank(hrW);
        positionId = siteOps.requestPosition(site, p);
        vm.prank(miner);
        siteOps.decidePosition(positionId, p.headcount, H);
        vm.prank(hrW);
        siteOps.openVacancy(positionId, 0, keccak256("advert"));
    }

    function _hire(uint256 positionId, bytes32 workerId, address wallet) internal returns (uint256 hireId) {
        vm.prank(hrW);
        hireId = siteOps.submitHire(positionId, workerId, wallet, keccak256(abi.encode("contract", workerId)));
        vm.prank(miner);
        siteOps.decideHire(hireId, true, H);
    }

    /// Hires NEW1 on a one-person position.
    function _hireDriller(SiteOpsLib.PayFrequency f, SiteOpsLib.PayBasis basis, uint128 rate)
        internal
        returns (uint256)
    {
        return _hire(_openPosition(_position(1, f, basis, rate)), NEW1, new1W);
    }

    function _policy(IERC20 primary, IERC20 secondary, uint8 grace, uint8 alertAfter) internal {
        vm.prank(miner);
        payroll.setPayPolicy(
            site,
            PayrollLib.PayPolicy({
                payer: miner,
                workdays: MON_SAT,
                graceDays: grace,
                noShowAlert: alertAfter,
                absencePenaltyBps: PENALTY_BPS,
                restDayOvertimeBps: REST_OT_BPS,
                holidayOvertimeBps: HOLIDAY_OT_BPS,
                primary: primary,
                secondary: secondary
            })
        );
    }

    function _today() internal view returns (uint64) {
        return uint64(block.timestamp / 1 days);
    }

    /// The supervisor checks `worker` in today.
    function _checkIn(bytes32 worker) internal {
        bytes32[] memory ids = new bytes32[](1);
        ids[0] = worker;
        vm.prank(supW);
        workforce.recordAttendance(site, _today(), ids);
    }

    /// Lives `n` days from today: `worker` checks in on each day whose bit is set in `mask`, then the day passes.
    function _live(bytes32 worker, uint256 n, uint256 mask) internal {
        for (uint256 i; i < n; ++i) {
            if ((mask >> i) & 1 == 1) _checkIn(worker);
            vm.warp(block.timestamp + 1 days);
        }
    }

    function _days(uint64 a) internal pure returns (uint64[] memory d) {
        d = new uint64[](1);
        d[0] = a;
    }

    function _one(uint256 id) internal pure returns (uint256[] memory a) {
        a = new uint256[](1);
        a[0] = id;
    }
}
