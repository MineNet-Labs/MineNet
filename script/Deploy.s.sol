// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MineNetRegistry} from "src/access/MineNetRegistry.sol";
import {LotPassport} from "src/traceability/LotPassport.sol";
import {CertificateRegistry} from "src/compliance/CertificateRegistry.sol";
import {EscrowManager} from "src/trade/EscrowManager.sol";
import {SupplyChain} from "src/traceability/SupplyChain.sol";
import {DeliveryManager} from "src/traceability/DeliveryManager.sol";
import {Marketplace} from "src/trade/Marketplace.sol";
import {CurrencyManager} from "src/finance/CurrencyManager.sol";
import {OracleRateFeed} from "src/finance/OracleRateFeed.sol";
import {CurrencyLib} from "src/finance/libraries/CurrencyLib.sol";
import {LicenceRegistry} from "src/compliance/LicenceRegistry.sol";
import {MineSiteRegistry} from "src/compliance/MineSiteRegistry.sol";
import {WorkforceManager} from "src/workforce/WorkforceManager.sol";
import {LotTagRegistry} from "src/traceability/LotTagRegistry.sol";
import {CargoTracker} from "src/traceability/CargoTracker.sol";
import {MineralPriceOracle} from "src/finance/MineralPriceOracle.sol";
import {SupplyChainExplorer} from "src/traceability/SupplyChainExplorer.sol";
import {B2B} from "src/b2b/B2B.sol";
import {B2BServices} from "src/b2b/B2BServices.sol";
import {InspectionRegistry} from "src/compliance/InspectionRegistry.sol";
import {AuditRegistry} from "src/compliance/AuditRegistry.sol";

/**
 * @notice Deploys the full MINENET suite.
 *   ADMIN_ADDRESS     platform admin (use a multisig on mainnet)
 *   TREASURY_ADDRESS  receives escrow fees
 *   ADMIN_DELAY       seconds before an admin transfer can complete (default 2 days)
 *   FEE_BPS           escrow platform fee in basis points (default 100 = 1%)
 *   PAYMENT_TOKEN     optional USD stablecoin to allow (e.g. USDC on Base)
 *   LOCAL_CURRENCY    optional local pricing currency code (default "RWF"); an OracleRateFeed is
 *                     deployed for it (8 decimals, max 5% move per update) and registered with a
 *                     1-day staleness limit once oracle nodes post a first rate
 *
 * The wiring steps need the admin. If the broadcaster is the admin (e.g. on testnet), they run
 * here; otherwise they are printed so the multisig can run them.
 *
 *   forge script script/Deploy.s.sol --rpc-url base_sepolia --account <keystore> --broadcast --verify
 */
contract Deploy is Script {
    function run() external {
        address admin = vm.envAddress("ADMIN_ADDRESS");
        address treasury = vm.envAddress("TREASURY_ADDRESS");
        uint48 delay = uint48(vm.envOr("ADMIN_DELAY", uint256(2 days)));
        uint16 feeBps = uint16(vm.envOr("FEE_BPS", uint256(100)));
        address paymentToken = vm.envOr("PAYMENT_TOKEN", address(0));

        vm.startBroadcast();
        MineNetRegistry registry = new MineNetRegistry(delay, admin);
        LotPassport passport = new LotPassport(registry);
        CertificateRegistry certs = new CertificateRegistry(registry, passport);
        SupplyChain supplyChain = new SupplyChain(registry, passport, certs);
        CurrencyManager currencies = new CurrencyManager(registry);
        EscrowManager escrow = new EscrowManager(registry, passport, certs, supplyChain, currencies, treasury, feeBps);
        DeliveryManager delivery = new DeliveryManager(registry, passport, supplyChain);
        Marketplace market = new Marketplace(registry, passport, supplyChain, escrow, currencies);
        string memory localCode = vm.envOr("LOCAL_CURRENCY", string("RWF"));
        OracleRateFeed localFeed = new OracleRateFeed(registry, 8, string.concat(localCode, " / USD"), 500);
        LicenceRegistry licences = new LicenceRegistry(registry);
        MineSiteRegistry sites = new MineSiteRegistry(registry, licences);
        WorkforceManager workforce = new WorkforceManager(registry, sites, currencies);
        LotTagRegistry tags = new LotTagRegistry(registry, passport);
        CargoTracker tracker = new CargoTracker(registry, passport, delivery);
        MineralPriceOracle prices = new MineralPriceOracle(registry);
        SupplyChainExplorer explorer = new SupplyChainExplorer(passport, supplyChain, sites, tags);
        B2B b2b = new B2B(registry, currencies, passport, supplyChain, delivery);
        B2BServices services = new B2BServices(registry, currencies, passport, supplyChain, delivery);
        InspectionRegistry inspections = new InspectionRegistry(registry, passport, sites, supplyChain);
        AuditRegistry audits = new AuditRegistry(registry);

        (, address broadcaster,) = vm.readCallers();
        bool wired = broadcaster == admin;
        if (wired) {
            passport.setEscrow(address(escrow));
            passport.setLocker(address(b2b), true); // B2B locks dispatched lots until the delivery ends
            passport.setModule(address(supplyChain), true);
            passport.setModule(address(delivery), true);
            supplyChain.setModule(address(delivery), true);
            passport.setModule(address(tags), true);
            passport.setModule(address(tracker), true);
            passport.setSiteRegistry(sites);
            sites.setStaffDirectory(workforce);
            // inspectors are assigned by the platform, never chosen by operators
            supplyChain.setInspectionAssigner(address(inspections));
            passport.setInspectionRegistry(inspections);
            sites.setInspectionRegistry(inspections);
            escrow.setMarketplace(address(market));
            currencies.setCurrency(bytes32(bytes(localCode)), 0, localFeed, 1 days, true);
            if (paymentToken != address(0)) {
                currencies.setSettlementToken(IERC20(paymentToken), CurrencyLib.USD, true);
            }
        }
        vm.stopBroadcast();

        console.log("MineNetRegistry:    ", address(registry));
        console.log("LotPassport:        ", address(passport));
        console.log("CertificateRegistry:", address(certs));
        console.log("EscrowManager:      ", address(escrow));
        console.log("SupplyChain:        ", address(supplyChain));
        console.log("DeliveryManager:    ", address(delivery));
        console.log("Marketplace:        ", address(market));
        console.log("CurrencyManager:    ", address(currencies));
        console.log("OracleRateFeed:     ", address(localFeed));
        console.log("LicenceRegistry:    ", address(licences));
        console.log("MineSiteRegistry:   ", address(sites));
        console.log("WorkforceManager:   ", address(workforce));
        console.log("LotTagRegistry:     ", address(tags));
        console.log("CargoTracker:       ", address(tracker));
        console.log("MineralPriceOracle: ", address(prices));
        console.log("SupplyChainExplorer:", address(explorer));
        console.log("B2B:                ", address(b2b));
        console.log("B2BServices:        ", address(services));
        console.log("InspectionRegistry: ", address(inspections));
        console.log("AuditRegistry:      ", address(audits));

        if (!wired) {
            console.log("\nAdmin must run:");
            console.log("  passport.setEscrow(escrow); passport.setLocker(b2b, true)");
            console.log("  passport.setModule(supplyChain, true); passport.setModule(delivery, true)");
            console.log("  supplyChain.setModule(delivery, true)");
            console.log("  passport.setModule(tags, true); passport.setModule(tracker, true)");
            console.log("  passport.setSiteRegistry(sites); sites.setStaffDirectory(workforce)");
            console.log("  supplyChain.setInspectionAssigner(inspections); passport.setInspectionRegistry(inspections)");
            console.log("  sites.setInspectionRegistry(inspections)");
            console.log("  escrow.setMarketplace(market)");
            console.log("  currencies.setCurrency(<LOCAL>, 0, localFeed, 1 days, true)");
            console.log("  currencies.setSettlementToken(<USDC>, 'USD', true)");
            console.log("  certs.configureCertType(<type>, <issuer role>)  // e.g. EXPORT_PERMIT -> REGULATOR");
            console.log("  registry.setRoleAuthority(<role>, <regulator org>)  // e.g. MINER -> RMB, CUSTOMS -> RRA");
        }
        console.log("\nProduction hardening:");
        console.log(
            "  supplyChain.setCustomsAuthority(<RRA org>)  // only RRA's system oracle may release from customs"
        );
        console.log("  inspections.setVrfConfig({coordinator, keyHash, subId, ...})  // Chainlink VRF v2.5 on Base;");
        console.log("    then add the InspectionRegistry as a consumer of the VRF subscription");
        console.log("  registry.setOrgPayout(<org>, <company treasury>)  // per company, from verified details");
        console.log("\nLicensing and oversight (needed before lots can be inspected or companies audited):");
        console.log("  registry.setRoleAuthority(INSPECTOR, <RMB org>); RMB regulators then call");
        console.log(
            "  inspections.setInspectorate(<org>, <kind>) and inspections.deployInspector(<inspector>, <districts>)"
        );
        console.log(
            "  registry.onboard(<ICGLR / RMI / ICPAR account>, ACCREDITOR, ...); audits.setScheme(<scheme>, ...)"
        );
        console.log("\nOptional: register LicenceRegistry as a Chainlink Automation upkeep for expiry reminders,");
        console.log("and prices.setFeed(<mineral>, <Chainlink feed>, <staleness>, <unit>) for reference prices.");
    }
}
