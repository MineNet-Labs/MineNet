// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {MineNetFixture} from "test/utils/MineNetFixture.sol";
import {WorkforceLib} from "src/workforce/libraries/WorkforceLib.sol";
import {StaffLib} from "src/workforce/libraries/StaffLib.sol";
import {SiteLib} from "src/compliance/libraries/SiteLib.sol";

contract StaffRolesTest is MineNetFixture {
    bytes32 constant MANAGER = keccak256("manager");
    bytes32 constant SUPER = keccak256("supervisor");
    bytes32 constant PAYROLL = keccak256("payroll");
    bytes32 constant SAFETY = keccak256("safety");
    bytes32 constant GEO = keccak256("geologist");
    bytes32 constant LAB = keccak256("labourer");
    bytes32 constant LAB2 = keccak256("labourer-site2");

    address managerW = makeAddr("managerWallet");
    address superW = makeAddr("supervisorWallet");
    address payrollW = makeAddr("payrollWallet");
    address safetyW = makeAddr("safetyWallet");
    address geoW = makeAddr("geologistWallet");
    address labW = makeAddr("labourerWallet");

    uint256 site2;

    function setUp() public override {
        super.setUp();
        vm.startPrank(miner); // the company account
        site2 = sites.registerSite(concession, "site-2", _siteLocation(), H);
        workforce.registerWorker(MANAGER, managerW, site);
        workforce.registerWorker(SUPER, superW, site);
        workforce.registerWorker(PAYROLL, payrollW, site);
        workforce.registerWorker(SAFETY, safetyW, site);
        workforce.registerWorker(GEO, geoW, site);
        workforce.registerWorker(LAB, labW, site);
        workforce.registerWorker(LAB2, address(0), site2);

        workforce.assignRole(MANAGER, StaffLib.SITE_MANAGER, false);
        workforce.assignRole(SUPER, StaffLib.SUPERVISOR, false);
        workforce.assignRole(PAYROLL, StaffLib.PAYROLL_OFFICER, true); // company-wide
        workforce.assignRole(SAFETY, StaffLib.SAFETY_OFFICER, false);
        workforce.assignRole(GEO, StaffLib.GEOLOGIST, false);
        workforce.assignRole(LAB, StaffLib.LABOURER, false);
        vm.stopPrank();

        usdc.mint(payrollW, 10_000e6);
        vm.prank(payrollW);
        usdc.approve(address(workforce), type(uint256).max);
    }

    function _ids(bytes32 a) internal pure returns (bytes32[] memory r) {
        r = new bytes32[](1);
        r[0] = a;
    }

    function _salary(bytes32 payee, uint256 amount) internal pure returns (WorkforceLib.PaymentInput memory) {
        return WorkforceLib.PaymentInput({
            payeeId: payee,
            payeeWallet: address(0),
            category: WorkforceLib.PaymentCategory.Salary,
            method: WorkforceLib.PaymentMethod.MobileMoney,
            currency: USD,
            amount: amount,
            paymentRef: keccak256("2026-11"),
            receiptHash: H
        });
    }

    // ---------------------------------------------------------------- roles

    function test_BuiltInRolePermissions() public view {
        assertEq(
            workforce.rolePermissions("org-miner", StaffLib.SUPERVISOR),
            StaffLib.RECORD_ATTENDANCE | StaffLib.SUBMIT_REPORTS | StaffLib.AUTHORIZE_OVERTIME
        );
        assertEq(workforce.rolePermissions("org-miner", StaffLib.LABOURER), 0);
        assertEq(workforce.staffRole(PAYROLL).roleId, StaffLib.PAYROLL_OFFICER);
        assertTrue(workforce.staffRole(PAYROLL).allSites);
        assertEq(workforce.workerOfWallet(superW), SUPER);
    }

    function test_OnlyCompanyAssignsAndDefinesRoles() public {
        vm.prank(managerW); // even a site manager cannot hand out roles
        vm.expectRevert(abi.encodeWithSelector(WorkforceLib.WorkforceManager__Unauthorized.selector, managerW));
        workforce.assignRole(LAB, StaffLib.SITE_MANAGER, true);

        vm.prank(managerW);
        vm.expectRevert(abi.encodeWithSelector(WorkforceLib.WorkforceManager__Unauthorized.selector, managerW));
        workforce.defineRole("SHIFT_LEAD", StaffLib.ALL);
    }

    function test_CustomRoleAndRedefinedBuiltIn() public {
        vm.startPrank(miner);
        vm.expectRevert(abi.encodeWithSelector(StaffLib.WorkforceManager__InvalidRole.selector, bytes32("SHIFT_LEAD")));
        workforce.assignRole(LAB, "SHIFT_LEAD", false); // not defined yet
        workforce.defineRole("SHIFT_LEAD", StaffLib.RECORD_ATTENDANCE | StaffLib.SITE_SAFETY);
        workforce.assignRole(LAB, "SHIFT_LEAD", false);
        vm.expectRevert(abi.encodeWithSelector(StaffLib.WorkforceManager__InvalidPermissions.selector, uint32(1 << 13)));
        workforce.defineRole("BAD", 1 << 13);
        vm.stopPrank();

        vm.prank(labW);
        workforce.recordAttendance(site, uint64(block.timestamp / 1 days), _ids(LAB));

        // the company takes attendance away from every supervisor at once
        vm.prank(miner);
        workforce.defineRole(StaffLib.SUPERVISOR, 0);
        vm.prank(superW);
        vm.expectRevert(abi.encodeWithSelector(StaffLib.WorkforceManager__OutOfScope.selector, superW, site));
        workforce.recordAttendance(site, uint64(block.timestamp / 1 days), _ids(LAB));
        assertEq(workforce.definedRoles("org-miner").length, 2);
    }

    // ---------------------------------------------------------------- scope

    function test_SupervisorRecordsAttendanceOnlyAtOwnSite() public {
        uint64 today = uint64(block.timestamp / 1 days);
        vm.prank(superW);
        workforce.recordAttendance(site, today, _ids(LAB));
        assertTrue(workforce.attendedOn(LAB, today));

        vm.prank(superW);
        vm.expectRevert(abi.encodeWithSelector(StaffLib.WorkforceManager__OutOfScope.selector, superW, site2));
        workforce.recordAttendance(site2, today, _ids(LAB2));

        // an all-sites supervisor can
        vm.prank(miner);
        workforce.assignRole(SUPER, StaffLib.SUPERVISOR, true);
        vm.prank(superW);
        workforce.recordAttendance(site2, today, _ids(LAB2));
    }

    function test_LabourerHasNoPermissions() public {
        vm.prank(labW);
        vm.expectRevert(abi.encodeWithSelector(StaffLib.WorkforceManager__OutOfScope.selector, labW, site));
        workforce.recordAttendance(site, uint64(block.timestamp / 1 days), _ids(LAB));
    }

    function test_DeactivatedOrUnassignedStaffLoseRights() public {
        uint64 today = uint64(block.timestamp / 1 days);
        vm.prank(miner);
        workforce.setWorkerActive(SUPER, false);
        vm.prank(superW);
        vm.expectRevert(abi.encodeWithSelector(StaffLib.WorkforceManager__OutOfScope.selector, superW, site));
        workforce.recordAttendance(site, today, _ids(LAB));

        vm.startPrank(miner);
        workforce.setWorkerActive(SUPER, true);
        workforce.assignRole(SUPER, bytes32(0), false); // role removed
        vm.stopPrank();
        assertEq(workforce.staffOrg(superW, site, StaffLib.RECORD_ATTENDANCE), bytes32(0));
    }

    // ---------------------------------------------------------------- site manager

    /// By default workers join through approved hires ({SiteOperations}); a company can still let its managers
    /// add workers directly by redefining the role.
    function _letManagersAddWorkers() internal {
        vm.prank(managerW);
        vm.expectRevert(abi.encodeWithSelector(StaffLib.WorkforceManager__OutOfScope.selector, managerW, site));
        workforce.registerWorker(keccak256("not-yet"), address(0), site);
        vm.prank(miner);
        workforce.defineRole(StaffLib.SITE_MANAGER, StaffLib.builtIn(StaffLib.SITE_MANAGER) | StaffLib.MANAGE_WORKERS);
    }

    function test_SiteManagerManagesWorkersAtOwnSite() public {
        _letManagersAddWorkers();
        bytes32 hire = keccak256("new-hire");
        vm.startPrank(managerW);
        workforce.registerWorker(hire, address(0), site);
        vm.expectRevert(abi.encodeWithSelector(StaffLib.WorkforceManager__OutOfScope.selector, managerW, site2));
        workforce.registerWorker(keccak256("new-hire-2"), address(0), site2);
        vm.expectRevert(abi.encodeWithSelector(StaffLib.WorkforceManager__OutOfScope.selector, managerW, site2));
        workforce.assignSite(hire, site2); // target site out of scope
        workforce.setWorkerActive(keccak256("new-hire"), false); // a worker without a role at their site
        vm.stopPrank();
    }

    function test_StaffCannotChangeRoleHoldersOrThemselves() public {
        _letManagersAddWorkers();
        vm.startPrank(managerW);
        vm.expectRevert(abi.encodeWithSelector(StaffLib.WorkforceManager__ProtectedWorker.selector, SUPER));
        workforce.setWorkerWallet(SUPER, managerW); // would hijack the supervisor's role
        vm.expectRevert(abi.encodeWithSelector(StaffLib.WorkforceManager__ProtectedWorker.selector, MANAGER));
        workforce.setWorkerActive(MANAGER, true);
        vm.stopPrank();
    }

    function test_WalletBelongsToOneWorker() public {
        vm.prank(miner);
        vm.expectRevert(abi.encodeWithSelector(StaffLib.WorkforceManager__WalletInUse.selector, superW, SUPER));
        workforce.registerWorker(keccak256("dup"), superW, site);
    }

    // ---------------------------------------------------------------- payroll officer

    function test_PayrollOfficerRecordsAndPaysWages() public {
        vm.prank(payrollW);
        uint256 id = workforce.recordPayment(_salary(LAB, 150e6));
        assertEq(workforce.getPayment(id).recordedBy, payrollW);
        assertEq(workforce.getPayment(id).orgId, bytes32("org-miner"));

        vm.prank(payrollW);
        workforce.payStablecoin(LAB, address(0), WorkforceLib.PaymentCategory.Salary, usdc, 200e6, H);
        assertEq(usdc.balanceOf(labW), 200e6);
    }

    function test_PayrollOfficerCannotPayThemselves() public {
        vm.prank(payrollW);
        vm.expectRevert(abi.encodeWithSelector(StaffLib.WorkforceManager__SelfPayment.selector, PAYROLL));
        workforce.recordPayment(_salary(PAYROLL, 1_000e6));

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1_000e6;
        vm.prank(payrollW);
        vm.expectRevert(abi.encodeWithSelector(StaffLib.WorkforceManager__SelfPayment.selector, PAYROLL));
        workforce.payPayroll(usdc, _ids(PAYROLL), amounts, H);
    }

    function test_SupplierPaymentsNeedCompanyWideScope() public {
        WorkforceLib.PaymentInput memory p = _salary("supplier-1", 10e6);
        p.category = WorkforceLib.PaymentCategory.Supplier;
        vm.prank(managerW); // site-scoped
        vm.expectRevert(abi.encodeWithSelector(StaffLib.WorkforceManager__OutOfScope.selector, managerW, 0));
        workforce.recordPayment(p);
        vm.prank(payrollW); // all sites
        workforce.recordPayment(p);
    }

    // ---------------------------------------------------------------- staff at the site registry

    function test_StaffActOnTheirSite() public {
        vm.prank(managerW);
        sites.declareDormant(site, keccak256("plan"));
        vm.prank(safetyW);
        sites.recordSafetyMeasure(site, SiteLib.SafetyMeasure.Fencing, H);
        vm.prank(geoW);
        sites.declareReserve(site, TIN, 1_000e6, H);
        assertEq(sites.getSite(site).safetyMeasures, 1);
        assertEq(sites.getReserve(site, TIN).declaredBy, geoW);

        // wrong permission, or another site
        vm.prank(geoW);
        vm.expectRevert(
            abi.encodeWithSelector(SiteLib.MineSiteRegistry__NotOrgMember.selector, geoW, bytes32("org-miner"))
        );
        sites.recordSafetyMeasure(site, SiteLib.SafetyMeasure.Fencing, H);
        vm.prank(managerW);
        vm.expectRevert(
            abi.encodeWithSelector(SiteLib.MineSiteRegistry__NotOrgMember.selector, managerW, bytes32("org-miner"))
        );
        sites.declareDormant(site2, H);

        vm.prank(managerW);
        sites.reactivateSite(site, H);
        assertTrue(sites.canProduce(site, miner));
    }
}
