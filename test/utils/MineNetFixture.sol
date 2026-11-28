// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {MineNetRegistry} from "src/access/MineNetRegistry.sol";
import {LotPassport} from "src/traceability/LotPassport.sol";
import {PassportLib} from "src/traceability/libraries/PassportLib.sol";
import {CertificateRegistry} from "src/compliance/CertificateRegistry.sol";
import {EscrowManager} from "src/trade/EscrowManager.sol";
import {DeliveryManager} from "src/traceability/DeliveryManager.sol";
import {SupplyChain} from "src/traceability/SupplyChain.sol";
import {Marketplace} from "src/trade/Marketplace.sol";
import {MarketplaceLib} from "src/trade/libraries/MarketplaceLib.sol";
import {SupplyChainLib} from "src/traceability/libraries/SupplyChainLib.sol";
import {Roles} from "src/access/libraries/Roles.sol";
import {CurrencyManager} from "src/finance/CurrencyManager.sol";
import {OracleRateFeed} from "src/finance/OracleRateFeed.sol";
import {CurrencyLib} from "src/finance/libraries/CurrencyLib.sol";
import {LicenceRegistry} from "src/compliance/LicenceRegistry.sol";
import {MineSiteRegistry} from "src/compliance/MineSiteRegistry.sol";
import {WorkforceManager} from "src/workforce/WorkforceManager.sol";
import {SiteOperations} from "src/workforce/SiteOperations.sol";
import {PayrollEngine} from "src/workforce/PayrollEngine.sol";
import {LotTagRegistry} from "src/traceability/LotTagRegistry.sol";
import {CargoTracker} from "src/traceability/CargoTracker.sol";
import {MineralPriceOracle} from "src/finance/MineralPriceOracle.sol";
import {SiteLib} from "src/compliance/libraries/SiteLib.sol";
import {SupplyChainExplorer} from "src/traceability/SupplyChainExplorer.sol";
import {B2B} from "src/b2b/B2B.sol";
import {B2BServices} from "src/b2b/B2BServices.sol";
import {InspectionRegistry} from "src/compliance/InspectionRegistry.sol";
import {AuditRegistry} from "src/compliance/AuditRegistry.sol";
import {InspectionLib} from "src/compliance/libraries/InspectionLib.sol";
import {LotFinance} from "src/finance/LotFinance.sol";

/// A Rwandan-franc stablecoin (whole francs: 0 decimals), to test local-currency settlement.
contract MockRWF is ERC20("Rwandan Franc Coin", "RWFC") {
    function decimals() public pure override returns (uint8) {
        return 0;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract MockUSDC is ERC20("USD Coin", "USDC") {
    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/// @dev Deploys and wires the full MINENET suite with one participant per role.
abstract contract MineNetFixture is Test {
    MineNetRegistry registry;
    LotPassport passport;
    CertificateRegistry certs;
    EscrowManager escrow;
    DeliveryManager delivery;
    SupplyChain supplyChain;
    Marketplace market;
    CurrencyManager currencies;
    OracleRateFeed rwfFeed;
    MockUSDC usdc;
    MockRWF rwfCoin;
    LicenceRegistry licences;
    MineSiteRegistry sites;
    WorkforceManager workforce;
    SiteOperations siteOps;
    PayrollEngine payroll;
    LotTagRegistry tags;
    CargoTracker tracker;
    MineralPriceOracle prices;
    SupplyChainExplorer explorer;
    B2B b2b;
    B2BServices services;
    InspectionRegistry inspections;
    AuditRegistry audits;
    LotFinance finance;

    /// The miner's mining licence, concession and active site; every fixture lot comes from `site`.
    uint256 miningLicence;
    uint256 concession;
    uint256 site;

    address admin = makeAddr("admin");
    address treasury = makeAddr("treasury");
    address miner = makeAddr("miner");
    address refinery = makeAddr("refinery");
    address transporter = makeAddr("transporter");
    address buyer = makeAddr("buyer");
    address buyer2 = makeAddr("buyer2");
    address warehouse = makeAddr("warehouse");
    address processor = makeAddr("processor");
    address customs = makeAddr("customs");
    address inspector = makeAddr("inspector");
    address auditor = makeAddr("auditor");
    address regulator = makeAddr("regulator");
    address oracle = makeAddr("oracle");
    address outsider = makeAddr("outsider");
    address financier = makeAddr("financier");
    address insurer = makeAddr("insurer");

    bytes32 constant TIN = keccak256("CASSITERITE");
    bytes32 constant H = keccak256("evidence");
    bytes32 constant SEAL = keccak256("seal-0001");
    bytes32 constant EXPORT_PERMIT = keccak256("EXPORT_PERMIT");
    bytes32 constant CONFLICT_FREE = keccak256("CONFLICT_FREE");
    uint16 constant FEE_BPS = 100; // 1%
    uint256 constant PRICE = 50_000e6;
    bytes32 constant USD = "USD";
    bytes32 constant RWF = "RWF";
    /// 1 RWF = 0.0008 USD (1 USD = 1,250 RWF), with 8 feed decimals.
    int256 constant RWF_RATE = 80_000;

    /// Extraction the fixture records per mineral at `site`, in grams.
    uint128 constant EXTRACTED = 1e30;

    uint256 private _lotNonce;

    function setUp() public virtual {
        registry = new MineNetRegistry(1 days, admin);
        passport = new LotPassport(registry);
        certs = new CertificateRegistry(registry, passport);
        supplyChain = new SupplyChain(registry, passport, certs);
        currencies = new CurrencyManager(registry);
        escrow = new EscrowManager(registry, passport, certs, supplyChain, currencies, treasury, FEE_BPS);
        delivery = new DeliveryManager(registry, passport, supplyChain);
        market = new Marketplace(registry, passport, supplyChain, escrow, currencies);
        rwfFeed = new OracleRateFeed(registry, 8, "RWF / USD", 500);
        usdc = new MockUSDC();
        rwfCoin = new MockRWF();
        licences = new LicenceRegistry(registry);
        sites = new MineSiteRegistry(registry, licences);
        workforce = new WorkforceManager(registry, sites, currencies);
        siteOps = new SiteOperations(registry, sites, workforce, currencies);
        payroll = new PayrollEngine(registry, sites, workforce, currencies, siteOps);
        tags = new LotTagRegistry(registry, passport);
        tracker = new CargoTracker(registry, passport, delivery);
        prices = new MineralPriceOracle(registry);
        explorer = new SupplyChainExplorer(passport, supplyChain, sites, tags);
        b2b = new B2B(registry, currencies, passport, supplyChain, delivery);
        services = new B2BServices(registry, currencies, passport, supplyChain, delivery);
        inspections = new InspectionRegistry(registry, passport, sites, supplyChain);
        audits = new AuditRegistry(registry);
        finance = new LotFinance(registry, passport, currencies);

        vm.startPrank(admin);
        uint64 exp = uint64(block.timestamp + 365 days);
        registry.onboard(miner, Roles.MINER, "org-miner", H, exp);
        registry.onboard(refinery, Roles.REFINERY, "org-refinery", H, exp);
        registry.onboard(transporter, Roles.TRANSPORTER, "org-transport", H, exp);
        registry.onboard(buyer, Roles.BUYER, "org-buyer", H, exp);
        registry.onboard(buyer2, Roles.BUYER, "org-buyer2", H, exp);
        registry.onboard(warehouse, Roles.WAREHOUSE, "org-warehouse", H, exp);
        registry.onboard(inspector, Roles.INSPECTOR, "org-inspect", H, exp);
        registry.onboard(auditor, Roles.AUDITOR, "org-audit", H, exp);
        registry.onboard(regulator, Roles.REGULATOR, "org-rmb", H, 0);
        registry.onboard(oracle, Roles.ORACLE, "org-oracle", H, 0);
        registry.onboard(processor, Roles.PROCESSOR, "org-processor", H, exp);
        registry.onboard(customs, Roles.CUSTOMS, "org-customs", H, exp);
        registry.onboard(financier, Roles.FINANCIER, "org-bank", H, exp);
        registry.onboard(insurer, Roles.INSURER, "org-insurer", H, exp);

        passport.setEscrow(address(escrow));
        passport.setLocker(address(b2b), true);
        passport.setModule(address(supplyChain), true);
        passport.setModule(address(delivery), true);
        supplyChain.setModule(address(delivery), true);
        passport.setModule(address(tags), true);
        passport.setModule(address(tracker), true);
        passport.setSiteRegistry(sites);
        sites.setPassport(address(passport));
        passport.setFinancing(address(finance));
        sites.setStaffDirectory(workforce);
        workforce.setSiteOperations(address(siteOps));
        workforce.setPayrollEngine(address(payroll)); // check-in gate and attendance-based pay
        sites.setSiteOperations(address(siteOps)); // inspected shift output counts toward extraction
        delivery.setStaffDirectory(workforce); // site managers dispatch their company's lots
        supplyChain.setSplitter(address(market), true); // auto-split a batch to fill an order
        supplyChain.setDeliveryManager(delivery); // never split a lot booked on a shipment
        certs.setSplitter(address(supplyChain)); // split lots keep their parent's certificates
        currencies.setSettlementToken(usdc, USD, true);
        escrow.setMarketplace(address(market));
        certs.configureCertType(EXPORT_PERMIT, Roles.REGULATOR);
        certs.configureCertType(CONFLICT_FREE, Roles.AUDITOR);
        vm.stopPrank();

        // an oracle node posts the RWF rate (NBR reference), then RWF and its stablecoin are enabled
        vm.prank(oracle);
        rwfFeed.postRate(RWF_RATE);
        vm.startPrank(admin);
        currencies.setCurrency(RWF, 0, rwfFeed, 1 days, true);
        currencies.setSettlementToken(rwfCoin, RWF, true);
        vm.stopPrank();

        // RMB records the miner's mining licence and concession; the miner opens a site
        vm.startPrank(regulator);
        miningLicence = licences.issueLicence(
            "org-miner", SiteLib.MINING_LICENCE, keccak256("ML-2026-001"), 0, uint64(block.timestamp + 3650 days), H
        );
        concession = sites.grantConcession("org-miner", miningLicence, keccak256("area"), H);
        vm.stopPrank();
        vm.prank(miner);
        site = sites.registerSite(concession, "site-1", _siteLocation(), keccak256("site-1-survey"));
        // the miner reports ample production, so fixture lots never hit the extraction cap
        _extract(site, TIN, EXTRACTED);
        _extract(site, keccak256("COLTAN"), EXTRACTED);

        // RMB licenses inspectors and deploys them: operators never choose who inspects their lots or sites
        vm.startPrank(admin);
        registry.setRoleAuthority(Roles.INSPECTOR, "org-rmb");
        supplyChain.setInspectionAssigner(address(inspections));
        supplyChain.setCustomsAuthority("org-oracle");
        passport.setInspectionRegistry(inspections);
        sites.setInspectionRegistry(inspections);
        vm.stopPrank();
        vm.prank(regulator);
        inspections.setInspectorate("org-inspect", InspectionLib.InspectorateKind.StateInspectorate);
        _deployInspector(inspector);

        usdc.mint(buyer, 1_000_000e6);
        usdc.mint(buyer2, 1_000_000e6);
        vm.prank(buyer);
        usdc.approve(address(market), type(uint256).max);
        vm.prank(buyer2);
        usdc.approve(address(market), type(uint256).max);
        // sellers approve the escrow on the passport once: a sale can then lock their lots
        vm.prank(miner);
        passport.setApprovalForAll(address(escrow), true);
    }

    // ---------------------------------------------------------------- helpers

    /// A valid site location: an open-pit tin mine in Rutsiro district, Western Province.
    function _siteLocation() internal pure returns (SiteLib.SiteLocation memory) {
        return SiteLib.SiteLocation({
            latitude: -1_939_100,
            longitude: 29_366_200,
            elevation: 2_150,
            province: "Western Province",
            district: "Rutsiro",
            sector: "Nyabirasi",
            cell: "Mubuga",
            village: "Rugarama"
        });
    }

    /// The miner records extraction at a site.
    function _extract(uint256 siteId, bytes32 mineral, uint128 qty) internal {
        vm.prank(miner);
        sites.recordExtraction(siteId, mineral, qty, H);
    }

    function _register(uint128 qty) internal returns (uint256 id) {
        vm.prank(miner);
        id = passport.registerLot(keccak256(abi.encode("lot", ++_lotNonce)), TIN, qty, site, H);
    }

    function _inspected(uint128 qty) internal returns (uint256 id) {
        id = _register(qty);
        _assignTo(id, inspector);
        vm.prank(inspector);
        passport.submitInspection(id, true, H);
    }

    /// RMB deploys an inspector (of an approved inspectorate) to Rutsiro district and the national pool.
    function _deployInspector(address who) internal {
        bytes32[] memory coverage = new bytes32[](2);
        coverage[0] = InspectionLib.districtKey("Rutsiro");
        coverage[1] = InspectionLib.NATIONAL;
        vm.prank(regulator);
        inspections.deployInspector(who, coverage);
    }

    /// Gets `who` assigned to the lot the way the platform does it: the owner requests an inspection, and any other
    /// inspector drawn declines until `who` is assigned (it must be on the roster and eligible).
    function _assignTo(uint256 id, address who) internal {
        address current = inspections.assignedInspector(id);
        if (!inspections.isAssignmentOpen(id, current)) {
            // a new round: the owner requests it (a regulator orders it for a lot that failed inspection)
            bool rejected = passport.getLot(id).status == PassportLib.LotStatus.Rejected;
            vm.prank(rejected ? regulator : passport.ownerOf(id));
            current = inspections.requestInspection(id);
        }
        for (uint256 i; current != who && i < 8; ++i) {
            vm.prank(current);
            current = inspections.declineInspection(id, keccak256("unavailable"));
        }
        require(current == who, "fixture: inspector not assignable");
    }

    /// Inspected lot listed by the miner at a fixed total of PRICE, 14-day delivery, 30-day expiry.
    function _listed(uint128 qty) internal returns (uint256 id, uint256 listingId) {
        id = _inspected(qty);
        vm.prank(miner);
        listingId = market.createListing(_listingParams(id, MarketplaceLib.PriceModel.FixedTotal, PRICE));
    }

    function _fixed() internal pure returns (MarketplaceLib.PriceModel) {
        return MarketplaceLib.PriceModel.FixedTotal;
    }

    function _listingParams(uint256 id, MarketplaceLib.PriceModel model, uint256 price)
        internal
        view
        returns (MarketplaceLib.ListingParams memory)
    {
        return MarketplaceLib.ListingParams({
            tokenId: id,
            paymentToken: usdc,
            priceCurrency: USD,
            priceModel: model,
            price: price,
            deliveryWindow: 14 days,
            expiresAt: uint64(block.timestamp + 30 days),
            termsHash: H
        });
    }

    /// The platform-assigned inspector attests a grade for the lot in SupplyChain.
    function _grade(uint256 id, uint16 gradeBps) internal {
        _assignTo(id, inspector);
        vm.prank(inspector);
        supplyChain.recordCheckpoint(
            SupplyChainLib.CheckpointInput({
                tokenId: id,
                cpType: SupplyChainLib.CheckpointType.Inspection,
                measuredQty: 0,
                condition: SupplyChainLib.Condition.Good,
                gradeBps: gradeBps,
                evidenceHash: keccak256(abi.encode("assay", gradeBps)),
                locationHash: bytes32(0)
            })
        );
    }

    function _moveCustody(uint256 id, address from, address to) internal {
        vm.prank(from);
        passport.initiateCustodyTransfer(id, to, H);
        vm.prank(to);
        passport.confirmCustodyTransfer(id, H);
    }

    function _weights(uint256 n, uint128 w) internal pure returns (uint128[] memory ws) {
        ws = new uint128[](n);
        for (uint256 i; i < n; ++i) {
            ws[i] = w;
        }
    }

    /// Ships one lot `from` -> `to` through DeliveryManager with exact weights and an intact seal.
    function _deliver(uint256 id, address from, address to) internal returns (uint256 sid) {
        uint256[] memory ids = new uint256[](1);
        ids[0] = id;
        uint128 w = supplyChain.lastWeight(id);
        vm.prank(from);
        sid = delivery.createShipment(ids, transporter, to, uint64(block.timestamp + 1 days), SEAL, H);
        vm.prank(transporter);
        delivery.confirmPickup(sid, _weights(1, w), SEAL, H);
        vm.prank(transporter);
        delivery.markArrived(sid, H);
        vm.prank(to);
        delivery.confirmDelivery(sid, _weights(1, w), SEAL, SupplyChainLib.Condition.Good, H);
    }

    function _buy(address who, uint256 listingId) internal returns (uint256 orderId) {
        vm.prank(who);
        orderId = market.buyListing(listingId, type(uint256).max);
    }

    /// Listed lot bought by `buyer` at PRICE: the escrow order is Active and the lot locked.
    function _acceptedOrder() internal returns (uint256 id, uint256 orderId) {
        uint256 listingId;
        (id, listingId) = _listed(10_000);
        orderId = _buy(buyer, listingId);
    }
}
