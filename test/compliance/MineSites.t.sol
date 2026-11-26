// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {MineNetFixture} from "test/utils/MineNetFixture.sol";
import {LotPassport} from "src/traceability/LotPassport.sol";
import {SiteLib} from "src/compliance/libraries/SiteLib.sol";
import {PassportLib} from "src/traceability/libraries/PassportLib.sol";
import {Roles} from "src/access/libraries/Roles.sol";

contract MineSitesTest is MineNetFixture {
    address miner2 = makeAddr("miner2");

    function setUp() public override {
        super.setUp();
        vm.prank(admin);
        registry.onboard(miner2, Roles.MINER, "org-miner2", H, uint64(block.timestamp + 365 days));
    }

    function _dormant() internal {
        vm.prank(miner);
        sites.declareDormant(site, keccak256("safety-plan"));
    }

    // ---------------------------------------------------------------- lot registration gating

    function test_RegisterLot_RecordsSite() public {
        uint256 id = _register(1_000);
        assertEq(passport.siteOf(id), site);
        assertTrue(sites.canProduce(site, miner));
    }

    function test_RegisterLot_OnlyFromOwnOrgSite() public {
        assertFalse(sites.canProduce(site, miner2));
        vm.prank(miner2);
        vm.expectRevert(abi.encodeWithSelector(PassportLib.LotPassport__SiteNotProducing.selector, site, miner2));
        passport.registerLot(keccak256("x"), TIN, 1_000, site, H);
    }

    function test_RegisterLot_UnknownSite() public {
        vm.prank(miner);
        vm.expectRevert(abi.encodeWithSelector(PassportLib.LotPassport__SiteNotProducing.selector, 99, miner));
        passport.registerLot(keccak256("x"), TIN, 1_000, 99, H);
    }

    function test_RegisterLot_BlockedWhenLicenceSuspendedOrConcessionRevoked() public {
        vm.prank(regulator);
        licences.suspendLicence(miningLicence, H);
        vm.prank(miner);
        vm.expectRevert(abi.encodeWithSelector(PassportLib.LotPassport__SiteNotProducing.selector, site, miner));
        passport.registerLot(keccak256("x"), TIN, 1_000, site, H);

        vm.startPrank(regulator);
        licences.reinstateLicence(miningLicence, H);
        sites.revokeConcession(concession, H);
        vm.stopPrank();
        assertFalse(sites.canProduce(site, miner));
    }

    function test_RegisterLot_BlockedWhenDormant() public {
        _dormant();
        vm.prank(miner);
        vm.expectRevert(abi.encodeWithSelector(PassportLib.LotPassport__SiteNotProducing.selector, site, miner));
        passport.registerLot(keccak256("x"), TIN, 1_000, site, H);
    }

    function test_RegisterLot_NeedsSiteRegistry() public {
        LotPassport bare = new LotPassport(registry);
        vm.prank(miner);
        vm.expectRevert(PassportLib.LotPassport__SitesNotConfigured.selector);
        bare.registerLot(keccak256("x"), TIN, 1_000, site, H);
    }

    // ---------------------------------------------------------------- concessions and sites

    function test_GrantConcession_NeedsMiningLicenceOfThatOrg() public {
        vm.startPrank(regulator);
        uint256 other = licences.issueLicence(
            "org-miner2", keccak256("TRANSPORT_LICENCE"), H, 0, uint64(block.timestamp + 365 days), H
        );
        vm.expectRevert(abi.encodeWithSelector(SiteLib.MineSiteRegistry__InvalidLicence.selector, other));
        sites.grantConcession("org-miner2", other, H, H); // wrong licence type
        vm.expectRevert(abi.encodeWithSelector(SiteLib.MineSiteRegistry__InvalidLicence.selector, miningLicence));
        sites.grantConcession("org-miner2", miningLicence, H, H); // someone else's licence
        vm.stopPrank();

        vm.prank(miner);
        vm.expectRevert(abi.encodeWithSelector(SiteLib.MineSiteRegistry__NotRegulator.selector, miner));
        sites.grantConcession("org-miner", miningLicence, H, H);
    }

    function test_RegisterSite_OnlyHolderAndUniqueRef() public {
        vm.prank(miner2);
        vm.expectRevert(
            abi.encodeWithSelector(SiteLib.MineSiteRegistry__NotOrgMember.selector, miner2, bytes32("org-miner"))
        );
        sites.registerSite(concession, "site-2", _siteLocation(), H);

        vm.startPrank(miner);
        vm.expectRevert(abi.encodeWithSelector(SiteLib.MineSiteRegistry__DuplicateSiteRef.selector, bytes32("site-1")));
        sites.registerSite(concession, "site-1", _siteLocation(), H);
        uint256 s2 = sites.registerSite(concession, "site-2", _siteLocation(), H);
        vm.stopPrank();

        assertEq(sites.sitesOf("org-miner").length, 2);
        assertEq(sites.sitesOfConcession(concession).length, 2);
        assertEq(sites.siteOfRef("site-2"), s2);
        assertEq(sites.orgOfSite(s2), bytes32("org-miner"));
    }

    // ---------------------------------------------------------------- site location

    function test_RegisterSite_StoresLocation() public view {
        SiteLib.SiteLocation memory loc = sites.getSiteLocation(site);
        assertEq(loc.latitude, -1_939_100);
        assertEq(loc.longitude, 29_366_200);
        assertEq(loc.elevation, 2_150);
        assertEq(loc.province, "Western Province");
        assertEq(loc.district, "Rutsiro");
        assertEq(loc.sector, "Nyabirasi");
        assertEq(loc.cell, "Mubuga");
        assertEq(loc.village, "Rugarama");
        assertEq(sites.getSite(site).surveyHash, keccak256("site-1-survey"));
    }

    function test_RegisterSite_EmitsLocation() public {
        SiteLib.SiteLocation memory loc = _siteLocation();
        vm.expectEmit(address(sites));
        emit SiteLib.SiteRegistered(2, concession, "org-miner", "site-2", loc, H);
        vm.prank(miner);
        sites.registerSite(concession, "site-2", loc, H);
    }

    function test_RegisterSite_OptionalCellAndVillage() public {
        SiteLib.SiteLocation memory loc = _siteLocation();
        loc.cell = "";
        loc.village = "";
        vm.prank(miner);
        uint256 s2 = sites.registerSite(concession, "site-2", loc, H);
        assertEq(bytes(sites.getSiteLocation(s2).cell).length, 0);
    }

    function test_RegisterSite_RejectsInvalidCoordinates() public {
        int32[2][5] memory bad = [
            [int32(90_000_001), int32(30_000_000)],
            [int32(-90_000_001), int32(30_000_000)],
            [int32(-1_900_000), int32(180_000_001)],
            [int32(-1_900_000), int32(-180_000_001)],
            [int32(0), int32(0)] // unset
        ];
        vm.startPrank(miner);
        for (uint256 i; i < bad.length; ++i) {
            SiteLib.SiteLocation memory loc = _siteLocation();
            loc.latitude = bad[i][0];
            loc.longitude = bad[i][1];
            vm.expectRevert(
                abi.encodeWithSelector(SiteLib.MineSiteRegistry__InvalidCoordinates.selector, bad[i][0], bad[i][1])
            );
            sites.registerSite(concession, "site-2", loc, H);
        }
        vm.stopPrank();
    }

    function test_RegisterSite_AcceptsBoundaryCoordinates() public {
        SiteLib.SiteLocation memory loc = _siteLocation();
        loc.latitude = -90_000_000;
        loc.longitude = 180_000_000;
        vm.prank(miner);
        sites.registerSite(concession, "site-2", loc, H);
    }

    function test_RegisterSite_RequiresProvinceDistrictSector() public {
        vm.startPrank(miner);
        for (uint256 i; i < 3; ++i) {
            SiteLib.SiteLocation memory loc = _siteLocation();
            if (i == 0) loc.province = "";
            else if (i == 1) loc.district = "";
            else loc.sector = "";
            vm.expectRevert(SiteLib.MineSiteRegistry__InvalidAdministrativeArea.selector);
            sites.registerSite(concession, "site-2", loc, H);
        }
        vm.stopPrank();
    }

    function test_RegisterSite_RejectsOverlongPlaceName() public {
        SiteLib.SiteLocation memory loc = _siteLocation();
        loc.village = string(new bytes(SiteLib.MAX_PLACE_NAME_LENGTH + 1));
        vm.prank(miner);
        vm.expectRevert(SiteLib.MineSiteRegistry__InvalidAdministrativeArea.selector);
        sites.registerSite(concession, "site-2", loc, H);

        loc.village = string(new bytes(SiteLib.MAX_PLACE_NAME_LENGTH)); // exactly at the limit
        vm.prank(miner);
        sites.registerSite(concession, "site-2", loc, H);
    }

    function testFuzz_RegisterSite_CoordinateBounds(int32 lat, int32 lon) public {
        SiteLib.SiteLocation memory loc = _siteLocation();
        loc.latitude = lat;
        loc.longitude = lon;
        bool valid = lat >= -90e6 && lat <= 90e6 && lon >= -180e6 && lon <= 180e6 && !(lat == 0 && lon == 0);
        if (!valid) {
            vm.expectRevert(abi.encodeWithSelector(SiteLib.MineSiteRegistry__InvalidCoordinates.selector, lat, lon));
        }
        vm.prank(miner);
        sites.registerSite(concession, "site-2", loc, H);
    }

    function test_CorrectSiteLocation_OnlyRegulator() public {
        SiteLib.SiteLocation memory loc = _siteLocation();
        loc.latitude = -1_940_000;
        loc.sector = "Ruhango";

        vm.prank(miner);
        vm.expectRevert(abi.encodeWithSelector(SiteLib.MineSiteRegistry__NotRegulator.selector, miner));
        sites.correctSiteLocation(site, loc, keccak256("resurvey"));

        vm.expectEmit(address(sites));
        emit SiteLib.SiteLocationCorrected(site, loc, keccak256("resurvey"), regulator);
        vm.prank(regulator);
        sites.correctSiteLocation(site, loc, keccak256("resurvey"));

        assertEq(sites.getSiteLocation(site).latitude, -1_940_000);
        assertEq(sites.getSiteLocation(site).sector, "Ruhango");
        assertEq(sites.getSite(site).surveyHash, keccak256("resurvey"));
    }

    function test_CorrectSiteLocation_ValidatesAndNeedsKnownSite() public {
        SiteLib.SiteLocation memory loc = _siteLocation();
        vm.startPrank(regulator);
        vm.expectRevert(abi.encodeWithSelector(SiteLib.MineSiteRegistry__UnknownSite.selector, 99));
        sites.correctSiteLocation(99, loc, H);

        loc.district = "";
        vm.expectRevert(SiteLib.MineSiteRegistry__InvalidAdministrativeArea.selector);
        sites.correctSiteLocation(site, loc, H);
        vm.stopPrank();
    }

    // ---------------------------------------------------------------- dormant sites and safety

    function test_Dormant_SafetyLifecycleAndClosure() public {
        _dormant();
        SiteLib.Site memory s = sites.getSite(site);
        assertEq(uint8(s.status), uint8(SiteLib.SiteStatus.Dormant));
        assertEq(s.safetyPlanHash, keccak256("safety-plan"));

        vm.startPrank(miner);
        sites.recordSafetyMeasure(site, SiteLib.SafetyMeasure.Fencing, keccak256("fence-photos"));
        sites.recordSafetyMeasure(site, SiteLib.SafetyMeasure.Backfilling, keccak256("backfill"));
        vm.stopPrank();
        assertEq(sites.getSite(site).safetyMeasures, 2);

        // closing needs a passing safety inspection
        vm.prank(regulator);
        vm.expectRevert(abi.encodeWithSelector(SiteLib.MineSiteRegistry__SafetyNotVerified.selector, site));
        sites.closeSite(site, keccak256("rema-cert"));

        vm.prank(inspector);
        sites.inspectSafety(site, true, keccak256("report"));
        vm.prank(regulator);
        sites.closeSite(site, keccak256("rema-cert"));
        assertEq(uint8(sites.getSite(site).status), uint8(SiteLib.SiteStatus.Closed));
        assertFalse(sites.isSafetyOverdue(site));
    }

    function test_Dormant_SafetyOverdue() public {
        _dormant();
        assertFalse(sites.isSafetyOverdue(site));
        vm.warp(block.timestamp + 30 days + 1); // grace period over, never inspected
        assertTrue(sites.isSafetyOverdue(site));
        assertEq(sites.overdueSafetySites("org-miner").length, 1);

        vm.prank(inspector);
        sites.inspectSafety(site, false, keccak256("open pit unfenced"));
        assertTrue(sites.isSafetyOverdue(site)); // a failed inspection stays overdue

        vm.prank(inspector);
        sites.inspectSafety(site, true, keccak256("fixed"));
        assertFalse(sites.isSafetyOverdue(site));

        vm.warp(block.timestamp + 180 days + 1); // re-inspection due
        assertTrue(sites.isSafetyOverdue(site));
    }

    function test_Dormant_InspectionMustBeIndependent() public {
        _dormant();
        vm.prank(miner);
        vm.expectRevert(abi.encodeWithSelector(SiteLib.MineSiteRegistry__NotInspectorOrRegulator.selector, miner));
        sites.inspectSafety(site, true, H);

        // an inspector working for the site's own organisation is not independent
        address inHouse = makeAddr("inHouseInspector");
        vm.prank(admin);
        registry.onboard(inHouse, Roles.INSPECTOR, "org-miner", H, uint64(block.timestamp + 365 days));
        vm.prank(inHouse);
        vm.expectRevert(abi.encodeWithSelector(SiteLib.MineSiteRegistry__NotIndependent.selector, inHouse));
        sites.inspectSafety(site, true, H);
    }

    function test_Dormant_RegulatorCanStopASiteAndHolderReactivates() public {
        vm.prank(regulator);
        sites.declareDormant(site, keccak256("stop order"));
        assertFalse(sites.canProduce(site, miner));

        vm.prank(miner);
        sites.reactivateSite(site, H);
        assertTrue(sites.canProduce(site, miner));
        _register(1_000);
    }

    function test_Dormant_MeasuresOnlyWhileDormant() public {
        vm.prank(miner);
        vm.expectRevert(
            abi.encodeWithSelector(SiteLib.MineSiteRegistry__InvalidStatus.selector, site, SiteLib.SiteStatus.Active)
        );
        sites.recordSafetyMeasure(site, SiteLib.SafetyMeasure.Fencing, H);
    }

    // ---------------------------------------------------------------- reserves

    function test_Reserves_DeclareVerifyUpdate() public {
        bytes32 COLTAN = keccak256("COLTAN");
        vm.startPrank(miner);
        sites.declareReserve(site, TIN, 500_000e6, keccak256("resource-report"));
        sites.declareReserve(site, COLTAN, 80_000e6, keccak256("resource-report"));
        vm.stopPrank();
        assertEq(sites.reserveMinerals(site).length, 2);

        vm.prank(inspector);
        sites.verifyReserve(site, TIN, keccak256("audit"));
        SiteLib.Reserve memory r = sites.getReserve(site, TIN);
        assertEq(r.estimatedQty, 500_000e6);
        assertEq(r.verifiedBy, inspector);

        // a new declaration clears the verification
        vm.prank(miner);
        sites.declareReserve(site, TIN, 900_000e6, keccak256("new-report"));
        assertEq(sites.getReserve(site, TIN).verifiedBy, address(0));
        assertEq(sites.reserveMinerals(site).length, 2);

        vm.prank(inspector);
        vm.expectRevert(
            abi.encodeWithSelector(SiteLib.MineSiteRegistry__UnknownReserve.selector, site, keccak256("GOLD"))
        );
        sites.verifyReserve(site, keccak256("GOLD"), H);
    }
}
