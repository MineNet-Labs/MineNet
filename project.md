Decentralized Mineral Supply Chain and AI-Powered Marketplace
Whitepaper aligned to the theme: Powering the Future: Mechanisation, Scale and Sustainable Growth in Mining
1. Executive Summary
The global mineral supply chain struggles with traceability, transparency and trust. Paper certificates are easy to forge, data sits in silos, verification takes weeks, and buyers cannot see where a mineral really came from. Small and artisanal miners are shut out of premium markets because they cannot prove their origin, while large buyers carry growing compliance risk.
This platform is a decentralized supply chain and marketplace for minerals, built on Base Layer 2 and assisted by AI. Every mineral lot receives a digital passport (an ERC-721 token). Each participant in the chain adds a signed event to that passport, from licence verification at the mine to delivery at the buyer. The result is a single, tamper-resistant history that any authorized party can verify.
The platform plugs into the institutions that already govern mining in Rwanda. Regulators from the Rwanda Mines, Petroleum and Gas Board (RMB), the Rwanda Utilities Regulatory Authority (RURA), the Rwanda Revenue Authority (RRA) and the National Bank of Rwanda (BNR) validate the legal documents of the companies they license before those companies can act on the platform. Insurers cover lots in storage and transit, financiers lend against verified lots, customs operators clear exports and imports, and a network of autonomous oracle nodes continuously compares on-chain records with off-chain data to detect fraud.
An AI layer makes the platform easy to use. Buyers search in plain language, miners upload documents instead of filling forms, and auditors see a prioritized list of risky lots instead of combing through everything. The AI recommends and flags; people and verified devices attest. The AI is never the source of truth.
What the platform delivers
•Verifiable provenance: every lot's journey is recorded on-chain and linked to signed off-chain evidence.
•Licence-gated entry: only lots from regulator-verified miners can be listed.
•Automated settlement: escrow releases payment when delivery is accepted.
•Mass-balance control: quantities are checked at every stage that holds or transforms a lot.
•AI-simplified use: natural-language search, document extraction, anomaly detection and a compliance assistant.
•Regulator-validated participants: every company is validated by the Rwandan authority that licenses it.
•Trade finance and insurance: verified lots can be insured and pledged as loan collateral.
•Oracle-based fraud detection: independent nodes compare on-chain records with off-chain sources and flag mismatches.
2. Alignment with the Theme
Theme pillar	How the platform responds
Mechanisation	Digitizes the physical flow. Weighbridges, scales, GPS seals and scanned assay certificates feed data into the platform with minimal manual entry. AI extracts data from documents so paperwork no longer slows operations, and oracle nodes reconcile device and government-system data with the ledger without manual checks.
Scale	The marketplace gives small and artisanal miners access to refineries and buyers they could not reach alone. Warehouses allow lots to be pooled into larger batches. Financiers and insurers can lend against and cover verified lots, giving small miners working capital. One platform replaces many disconnected systems.
Sustainable growth	Provenance, conflict-free status, licence validity and environmental data travel with each lot. Buyers can meet due diligence requirements without costly manual audits, which rewards responsible producers with premium access.
3. The Problem
Minerals pass through many hands between extraction and sale. Each handover is a point of failure.
•Document fraud: paper certificates can be forged or altered.
•Information silos: each party keeps its own records, with no shared source of truth.
•Storage and transit risk: lots can be swapped, diluted or lost while stored or moved.
•Slow verification: manual checks delay trade and raise cost.
•Limited buyer visibility: buyers cannot easily see the full history of what they purchase.
•Compliance pressure: regimes such as Dodd-Frank Section 1502, the EU Conflict Minerals Regulation and OECD Due Diligence Guidance require documented sourcing.
•Complex discovery: finding the right supplier, grade, certification and delivery window is slow and relationship-driven.
•Limited access to finance and insurance: lenders and insurers cannot verify what they are financing or covering, so small miners pay more or are refused.
•Slow, paper-based customs clearance: export documents are checked by hand, which delays shipments and leaves room for false declarations.
4. The Solution
4.1 The Lot Passport
Each mineral lot is represented by a unique ERC-721 token. The token carries a reference to its passport: a chronological list of signed events. Large documents (assay certificates, permits, photos, inspection reports) are stored off-chain and encrypted, and only their cryptographic hashes are recorded on-chain.
The passport separates two concepts that are often confused:
•Ownership: who legally owns the lot. This changes when a sale completes, even if the lot does not move.
•Custody: who physically holds the lot. This changes at each handover between miner, transporter, warehouse, processor and refinery.
A trader can therefore resell a lot while it sits in a warehouse. Ownership changes; custody does not.
4.2 Core Capabilities
•Licence-gated registration: a lot can be registered only if the miner holds a valid mining licence issued by the Rwanda Mines, Petroleum and Gas Board (RMB) and validated on the platform by an RMB regulator.
•Regulator validation of participants: mining, transport, processing, customs, insurance and finance companies are validated by the authority that licenses them before they can sign events.
•Role-based access control: wallet-based authentication, with permissions defined by role.
•Independent verification: inspectors attest to grade, purity and safety before a lot is listed.
•Chain of custody: every handover requires confirmation from both the giving and receiving party.
•Mass-balance checks: quantities are compared at warehouses, processors and refineries.
•Marketplace with escrow: buyers purchase verified lots, and funds are locked until delivery is accepted.
•Lot-backed finance and insurance: financiers record a lien on a verified lot and are repaid from escrow when it sells; insurers link cover to the lot and decide claims from its passport.
•Customs clearance: customs operators file declarations built from the lot passport, and release is confirmed against the customs record.
•Oracle verification: autonomous oracle nodes compare each on-chain event with off-chain data and raise fraud flags on mismatches.
•Audit trail: auditors have read-only access to the full history and can raise flags.
•Dispute handling: disputes are opened on-chain and resolved automatically by the smart contract from the evidence on the lot passport.
5. AI Layer
The AI service sits beside the blockchain, not on it. It reads from the platform database and the ledger, and it can suggest or draft actions. It cannot sign events. This rule keeps the trust model clean: AI recommends, humans and verified sources attest.
5.1 AI Features
1.Natural-language search and matching. A buyer types a request such as "500 kg tantalum ore, conflict-free certified, delivered within three weeks." The AI converts it into structured filters (mineral, grade, quantity, certification, location, deadline, warehouse availability) and ranks matching lots and suppliers.
2.Document extraction. Miners, inspectors, regulators, customs operators, insurers and financiers upload certificates, permits, declarations, policies and loan documents. The AI extracts mineral type, grade, quantity, dates and permit numbers, and pre-fills the forms. The person reviews and signs.
3.Anomaly and fraud detection. Rule-based checks combined with a statistical model flag:
omass-balance mismatches at processors, refineries and warehouses
otransport route deviations or unusual delays
ogrades that do not fit a mine's history
oexpiring or suspicious licences
ounusual pricing or repeated rapid resales
•mismatches reported by oracle nodes, such as a customs declaration weight that differs from the last warehouse weight
•the same lot pledged to more than one financier
4.Compliance assistant. A chat helper tells each role what is required next, for example "this lot needs a transport permit before dispatch."
5.Price guidance. Shows a fair price range based on mineral, grade, quantity and market trends.
6.Lot journey summary. Produces a plain-language summary of a lot's full history for buyers.
7.Risk prioritization for auditors. Ranks lots by risk score so auditors review the most suspicious first.
5.2 AI Guardrails
•AI outputs are advisory. Every on-chain event is signed by a verified person or device, or by a quorum of oracle nodes.
•Extracted document data is shown for confirmation before signing.
•Flags are explainable, showing which rule or data point triggered them.
•Sensitive commercial data is accessible to the AI only within the requesting user's role permissions.
•The AI and the oracle nodes are separate. Oracle nodes check facts against defined sources and rules; the AI interprets patterns. Neither can grant or withdraw a regulator validation.
6. User Roles and Workflows
The platform has fourteen roles covering the full chain from licence to sale: thirteen held by verified organizations and one autonomous role, the oracle node network.
6.1 Role Overview
Role	What they do	What they sign on the lot passport	AI help
Regulator	Authorized officer of the Rwandan authority that licenses a participant (RMB, RURA, RRA or BNR). Validates the company's legal documents and records licence status	Company validation, licence validity and expiry, export permits, suspension and revocation	Extracts licence details; flags expiring licences, mismatched company names and unusual licence patterns
Miner	Extracts minerals and registers lots	Lot creation (site, mineral, quantity, date)	Extracts details from documents; shows what is missing before a lot can be listed
Inspector	Verifies grade, sampling and safety compliance	Grade and purity attestation, compliance check	Pre-fills reports; flags results that do not fit the mine's history
Transporter	Moves lots between parties (custody in motion)	Custody transfer, seal ID, route and delivery confirmation	Route deviation alerts, delay prediction
Warehouse	Stores lots between stages (custody at rest)	Receipt (quantity, seal status), storage conditions, release	Flags weight differences between check-in and check-out; dwell-time and storage alerts
Processor	Primary processing near the mine (crushing, milling, concentrating)	Input and output quantities, recovery rate	Mass-balance check against typical recovery rates
Refinery	Final purification to market-grade product	Input and output quantities, final purity	Mass-balance mismatch detection, quality prediction
Customs operator	Licensed clearing agent that prepares and files export and import declarations	Declaration filed (HS code, weight, value, permit and certificate references), border exit	Pre-fills declarations from the lot passport; flags weight or value differences
Buyer / Trader	Searches, buys and resells lots	Purchase, payment release, delivery acceptance, resale	Natural-language search, supplier ranking, price guidance, journey summaries
Insurer	Licensed insurer that covers lots in storage and transit	Policy issued (cover, period, insured value), claim decision	Suggests premiums from route and custody history; assembles claim evidence
Financier	Bank, microfinance institution or SACCO that lends against verified lots	Loan and lien registration, lien release on repayment	Estimates collateral value from grade and price guidance; flags lots pledged twice
Auditor	Reviews the full trail after the fact	Audit findings, flags, clearance	Prioritized risk list
Oracle node	Independent automated node that compares on-chain records with off-chain sources	Integrity reports (match or mismatch), signed by a quorum of nodes	Mismatches feed the anomaly model and the auditor risk list
Platform admin	Onboards and verifies users, manages platform rules and the user directory	User verification	Dashboard of anomalies, usage and open disputes
6.2 Regulators and the Responsible Rwandan Institutions
On the platform, a regulator is not a single body. Each regulator account belongs to an authorized officer of the Rwandan institution that licenses a type of participant, and it can validate only that type. An RMB regulator cannot validate a transport company, and a RURA regulator cannot validate a mining licence. Every organization except the platform admin and the buyer must be validated before it can sign events.
Participant validated	Platform regulator (institution)	What the regulator validates
Miners (mining companies and cooperatives)	Rwanda Mines, Petroleum and Gas Board (RMB)	Mining or quarry licence under Law No 072/2024, licence area and expiry, company registration, environmental impact assessment approval
Processors and refineries	RMB	Processing or refining authorization, licence status, declared capacity
Mineral exports	RMB	Export permit and, for tin, tantalum, tungsten and gold, the ICGLR regional certificate
Inspectors and auditors	RMB	Recognition as an inspection body, assay laboratory or third-party auditor for mineral traceability
Transport companies	Rwanda Utilities Regulatory Authority (RURA)	Licence or authorization for transport of goods, vehicles listed under it, licence expiry
Customs operators	Rwanda Revenue Authority (RRA), Customs Services	Clearing agency licence, customs guarantee, licence period, staff accreditation
Warehouses	RRA for customs (bonded) warehouses; RMB for mineral storage	Warehouse licence, location, storage capacity
Insurers	National Bank of Rwanda (BNR)	Insurance licence and the classes of business it covers
Financiers	BNR	Banking, microfinance or SACCO licence
Oracle node operators	Platform admin, with RMB sign-off	Operator identity, independence from the lots it checks, posted stake
Supporting institutions. Some documents come from bodies that are not separate platform roles. The Rwanda Development Board (RDB) registers companies through the Office of the Registrar General and approves environmental impact assessments, and the Rwanda Environment Management Authority (REMA) issues rehabilitation certificates when a mine closes. These documents are uploaded by the participant and checked by the RMB regulator. Transport policy is set by the Ministry of Infrastructure (MININFRA), and customs procedures follow the East African Community Customs Management Act.
Validation is time-bound. Each validation carries the licence expiry date. At expiry, or when the institution suspends or revokes the licence, the participant is suspended automatically: it cannot sign new events, and its lots in progress are frozen until another validated party takes custody or the regulator restores the licence.
Institutional note. In October 2026 Rwanda's Cabinet approved a structure under which RMB operates as an independent institution, after a period under RDB supervision from July 2025. The platform maps roles to the institution that issues each licence, so it does not depend on which ministry supervises that institution. The mapping should be confirmed with each institution before launch.
6.3 Role Boundaries
•Regulators come first. Without a valid licence on record, a miner cannot register a lot. This is the platform's answer to illegitimate minerals entering the chain.
•Auditors are read-only plus flagging. They cannot alter data, which keeps them independent.
•The platform admin cannot edit the trail. The admin manages users only, and can view a directory of all registered users with their roles, organizations and verification status. Lot history is append-only.
•Transporter and warehouse are separate. The transporter signs custody in motion; the warehouse signs custody at rest. Each handover needs confirmation from both sides.
•Processor and refinery are separate. The processor performs primary processing near the mine; the refinery produces the final market-grade product. This creates a multi-stage chain with a mass-balance check at each stage.
•Regulators validate; they do not trade. Each regulator acts only on the participant types its institution licenses and cannot create, buy or move lots.
•Customs operators file; the customs record confirms. The customs operator files the declaration, but release is confirmed by oracle nodes against the RRA customs record, or by an RRA regulator where no system link exists.
•Financiers hold a lien, not ownership. A lot with an active lien cannot change ownership until the loan is repaid, either directly or from the sale escrow.
•Insurers never take custody. They link cover to a lot and decide claims from the evidence on its passport.
•No single oracle node is trusted. Results count only when a quorum of independent nodes agrees, and no node may check a lot in which its operator is a party.
6.4 Lot Lifecycle
1.Participants validated. Regulators from RMB, RURA, RRA and BNR validate the companies that will handle the lot.
2.Licence verified. The RMB licence record for the miner is confirmed.
3.Lot registered. The miner creates the lot and its token.
4.Inspected. The inspector attests to grade, purity and compliance.
5.Warehoused. The lot is stored and its weight recorded at check-in.
6.Financed (optional). A financier lends against the inspected, warehoused lot and records a lien on its token.
7.Listed. The lot appears on the marketplace with its verification and lien status.
8.Bought. The buyer purchases; payment is locked in escrow and ownership is marked as pending.
9.Insured. The insurer issues cover for storage and transit and links the policy to the lot.
10.Transported. The transporter takes custody with a seal ID and route tracking.
11.Processed. The processor records input, output and recovery rate.
12.Warehoused (optional). Interim storage with check-in and check-out weights.
13.Transported. Custody moves to the refinery.
14.Refined. The refinery records input, output and final purity. A refined product token is created and linked to its source lot.
15.Customs cleared (when crossing a border). The customs operator files the declaration, oracle nodes confirm release against the RRA record, and border exit is recorded.
16.Delivered and accepted. The buyer confirms delivery. Escrow first repays any lien, then pays the seller.
17.Audited. The auditor reviews the full trail and records findings.
Steps 10 to 15 may repeat or be reordered depending on the route; for example, concentrate exported to a foreign smelter is cleared by customs before refining. Oracle nodes check every event as it is recorded (see 7.5).
6.5 Workflow Summaries
Participant validation flow: company submits licence and registration documents, AI extracts the details, the regulator from the licensing institution checks them against its own register, validation is signed with the licence expiry date, and the company is suspended automatically at expiry or on revocation.
Registration flow: license check, lot registration, token creation, document upload, inspection request.
Validation flow: request received, physical inspection, results recorded and signed, approval or rejection, lot status updated.
Transfer flow: transfer initiated, transporter assigned, handover confirmed by both parties, delivery confirmed, ownership and custody updated.
Transformation flow: lot received, input quantity recorded, processing or refining, output recorded, mass-balance check, new token linked to source lot.
Finance flow: loan request, collateral valuation, lien recorded on the lot token, disbursement, repayment from escrow at sale, lien released.
Insurance flow: cover requested, policy issued and linked to the lot, incident flagged by oracle nodes or a custody party, claim assessed from passport evidence, payout or rejection recorded.
Customs flow: declaration prepared from the lot passport, export permit and certificate attached, declaration filed with RRA, release confirmed by oracle nodes, border exit recorded.
Oracle check flow: event recorded, nodes selected, each node fetches the matching off-chain data and signs its comparison, quorum result posted, mismatch raises a fraud flag and can freeze the lot.
7. Technology Foundation
7.1 Blockchain Layer
The platform is built on Base, an Ethereum Layer 2 network. It inherits Ethereum's security model while offering low fees, fast finality and full EVM compatibility, which keeps transactions affordable for small miners and high-volume traders.
7.2 Smart Contracts
The contracts handle:
•organization registration and role assignment
•participant validation by regulator type (RMB, RURA, RRA, BNR) and licence records
•lot tokenization (ERC-721) and passport events
•custody and ownership transfers
•validation and attestation workflows
•escrow for marketplace purchases
•liens and loan records for financiers
•insurance policy and claim records
•customs declaration and release records
•oracle node registry, staking and quorum reporting
•dispute initiation and outcome recording
•protocol fee collection
Contracts use audited libraries such as OpenZeppelin, an emergency pause, and multi-signature control for sensitive administration.
7.3 Data Architecture
Layer	Contents
On-chain	Ownership, custody, status, event signatures, document hashes, escrow state, liens, policy references, customs release status, oracle integrity reports
Off-chain (encrypted)	Certificates, permits, photos, inspection reports, customs declarations, insurance policies, loan agreements, commercial terms
AI service	Search index, extraction pipeline, anomaly models, compliance assistant
Oracle network	Independent nodes that fetch off-chain data, compare it with on-chain records and post signed integrity reports
Data sources	Inspectors, regulators, weighbridges, scales, GPS seals and other trusted devices, RRA customs records, RMB and RURA licence registers, insurers and financiers
7.4 The Data Integrity Problem
A blockchain proves that data was not changed after it was recorded. It cannot prove that the data was true when entered. The platform addresses this at the source:
•Trusted attesters: grade, license and audit claims come from roles that are verified and accountable, not from the lot owner alone.
•Device-signed readings: weights, locations and seal status come from devices that sign their own data where possible.
•Cross-checks: mass-balance comparisons across stages expose inconsistent claims.
•Reputation and accountability: every signature is tied to a verified organization, and false attestations can lead to suspension.
•AI anomaly detection: unusual patterns are flagged for audit.
•Oracle cross-checks: autonomous nodes compare on-chain events with off-chain sources (see 7.5).
No system can eliminate fraud entirely. The platform makes it harder, more visible and easier to trace to a responsible party.
7.5 Autonomous Oracle Network
Oracle nodes are automated services that bring off-chain facts on-chain and check that the two agree. They do not create lot events; they test them. The network can be built as a custom node set or on an established oracle framework, as long as the rules below hold.
What the nodes compare
Check	On-chain record	Off-chain source
Licence status	Regulator validation and expiry	RMB and RURA licence registers
Weight continuity	Weight at check-out and at next check-in	Signed weighbridge and scale readings
Route	Custody transfer points	GPS seal track
Seal integrity	Seal ID at dispatch	Seal status at arrival
Customs	Declared weight, value and HS code	RRA customs declaration and release record
Grade	Inspector's attested grade	Laboratory report and assay values
Finance	Active lien on the lot	Financier's loan record (prevents double pledging)
Insurance	Policy linked to the lot	Insurer's policy record and claim history
Price	Sale price	Market reference price
How a check works
1.An event recorded on a lot triggers a check, and a set of nodes is selected at random.
2.Each node fetches the off-chain data, compares it with the on-chain record and signs its result.
3.When a quorum (for example two-thirds of the selected nodes) agrees, the result is posted on-chain as an integrity report.
4.A match lets the lot proceed. A mismatch raises a fraud flag, notifies the auditor and the relevant regulator, and can freeze listing, escrow release or lien release until it is resolved.
Keeping the oracles honest
•Independence: node operators are validated like other participants and may not check lots in which they are a party.
•Stake and slashing: each node posts a stake that is reduced if its reports are proven wrong or it fails to respond.
•Source diversity: where possible, a fact is checked against two independent sources.
•Transparency: every report shows which sources were used and which rule failed.
Oracles have limits. They can only compare data that exists: where a government system offers no machine-readable access, a regulator attests the fact and the oracle checks the signature and timing of that attestation. Oracles also detect inconsistency, not truth. If two sources are falsified in the same way, the oracle sees a match. That is why oracle checks sit beside trusted attesters, device signatures, mass-balance checks and audits, not in place of them.
8. Security and Compliance
8.1 Security
•Access control: role-based permissions with wallet-based authentication and multi-signature support for sensitive actions.
•Cryptographic protection: all transactions are signed; off-chain files are encrypted and verified against on-chain hashes.
•Immutable audit log: every action is recorded and cannot be removed.
•Incident response: emergency pause and defined response procedures.
•Separation of duties: no single role can create, attest and approve the same lot.
8.2 Privacy
Transparency is balanced with confidentiality. Buyers see provenance and verification status. Commercial terms, pricing and sensitive documents are visible only to the parties involved and to authorized auditors and regulators. Financiers and insurers see only the lots they finance or cover, and oracle nodes receive only the fields each check needs. Data handling is designed with GDPR principles in mind.
8.3 Regulatory Alignment
•Rwanda Law No 072/2024 on mining and quarry operations: mining licences and export permits administered by RMB.
•ICGLR Regional Certification Mechanism: regional certificates for exports of tin, tantalum, tungsten and gold.
•EAC Customs Management Act: customs clearance and licensing of clearing agents through RRA.
•BNR regulations: licensing and supervision of banks, microfinance institutions, SACCOs and insurers.
•Dodd-Frank Act Section 1502 (US): reporting on conflict minerals (tin, tantalum, tungsten and gold).
•EU Conflict Minerals Regulation (2017/821): due diligence obligations for EU importers of 3TG.
•OECD Due Diligence Guidance: the five-step framework for responsible sourcing.
•Industry standards: requirements from bodies such as RMI and LBMA.
The platform provides the records and reports that support compliance. Legal responsibility for compliance remains with each participant.
8.4 Dispute Resolution
Either party to a transaction can open a dispute on-chain. No human reviews it. The contract applies fixed rules to the evidence on the lot passport and enforces the outcome (for example refund, partial release or full release). Escrow stays locked while a dispute is open. The rules cover cases such as a missing or mismatched delivery confirmation, a failed mass-balance check, a broken seal, or a grade that differs from the inspector's attestation. If a party does not respond by the deadline, a default outcome applies. Oracle integrity reports are part of the evidence the contract reads, and insurance claims and lien disputes follow the same rule-based process. The AI can explain the evidence to both parties but cannot decide. The admin has no role in disputes and cannot modify lot history.
9. Economic Model
9.1 Fee Structure
•Organization registration fee: a one-time fee covering onboarding and verification.
•Protocol operational fee: a small fixed fee on state-changing transactions such as lot registration, transfers and attestations. The amount is publicly visible and kept low through Base Layer 2.
•Marketplace fee: a small percentage on completed sales (to be defined).
•Premium services: advanced analytics, API access and extended AI features.
•Finance and insurance fee: a small fee on loans and policies originated through the platform.
•Exemptions: platform administration functions are exempt from protocol fees.
9.2 Incentives
Participant	Incentive
Miners	Access to verified buyers, premium pricing, reputation, faster payment
Inspectors and auditors	Fees for verification services, reputation
Transporters and warehouses	Automated documentation, clear custody records, faster payment
Processors and refineries	Trusted inputs, simpler compliance, access to verified supply
Buyers and traders	Confidence in provenance, automated compliance, price guidance
Customs operators	Declarations pre-filled from verified data, faster release
Insurers	Lower risk from verified custody and oracle checks, evidence-based claims
Financiers	Verified collateral, liens that prevent double pledging, repayment from escrow
Oracle node operators	Fees per check paid from protocol fees, reputation backed by stake
Regulators	Real-time oversight of every participant they license, with less manual paperwork
9.3 Sustainability of the Model
Revenue comes from registration, protocol and marketplace fees and premium features. Costs stay low through the Layer 2 network, efficient contracts and automation.
10. Use Cases
Conflict-free 3TG sourcing. A tantalum miner with a valid license registers a lot, an inspector attests to grade and origin, and a buyer finds it through AI search. Escrow locks, the lot moves through transport, processing and refining, and the auditor sees the complete trail.
Battery minerals. Cobalt and lithium buyers need provenance, labor practice evidence and environmental data for their own reporting. The passport carries these records from mine to refinery.
Gold and precious metals. Verified origin and mass-balance control reduce mixing and laundering risk and support premium pricing.
Artisanal and small-scale mining. Small miners deposit lots in a shared warehouse, have them inspected, and sell as a pooled batch through the marketplace, with AI helping them complete paperwork.
Export compliance. RMB regulators record export permits and regional certificates, customs operators file declarations built from the lot passport, and oracle nodes confirm release against the RRA record.
Working capital for small miners. A cooperative pledges an inspected, warehoused lot to a SACCO. The lien is recorded on the lot, and the loan is repaid from escrow when the lot sells.
Insured transit. Oracle nodes flag a broken seal on arrival. The insurer assesses the claim from the passport evidence and records the payout.
ESG reporting. Environmental and social data attached to lots feeds automated reports for buyers and investors.
11. Roadmap
Phase 1: Core platform. Smart contracts for roles, licenses, lot tokens and passport events. Role-based portals for all organizational roles, with regulator validation scoped to RMB, RURA, RRA and BNR. Escrow marketplace. Natural-language search and document extraction. Demonstration on a testnet with one mineral and a full end-to-end flow.
Phase 2: Intelligence and operations. Anomaly detection and auditor risk ranking. Compliance assistant. Price guidance. Customs operator, insurer and financier workflows. First oracle nodes for licence, weight and seal checks. Analytics dashboards and mobile access. Bulk operations and API documentation. Mainnet deployment.
Phase 3: Integration and scale. IoT device integration for weighbridges, scales and GPS seals. Oracle integration with RRA customs records and the RMB and RURA licence registers. Decentralized oracle network with staking. Multi-chain support. Advanced dispute resolution. Pooled and fractional lots for small miners.
Phase 4: Ecosystem. Developer platform and third-party integrations. Marketplace for verification services. ERP integration. Additional roles such as brokers and aggregators, certification bodies, equipment lessors and recyclers.
Long-Term Vision
A global standard for mineral traceability: every mineral in trade carries a verifiable history, small miners can reach premium markets, and responsible production is visible and rewarded.
12. Governance
During development and early adoption, The platform operates under a centralized governance model. The platform owner controls core parameters, the fee structure, security controls and protocol upgrades. As the platform matures, governance will move toward community participation through an advisory board, user voting on features and a transparent proposal process. Sensitive administration is protected by multi-signature control, and the platform admin role cannot alter recorded lot history.
13. Conclusion
This platform combines blockchain traceability with practical AI to make the mineral supply chain more mechanised, scalable and sustainable. Fourteen clearly defined roles, regulator validation tied to Rwanda's licensing institutions, a lot passport that separates custody from ownership, licence-gated entry, mass-balance checks at every stage, oracle cross-checks, lot-backed finance and insurance, and escrow-based settlement give every participant a verifiable place in the chain.
The design is deliberate about trust. The blockchain keeps records tamper-resistant, verified roles and devices supply the data, and AI makes the system simple to use and quick to spot problems, without ever replacing human attestation.
Next steps
•Miners and processors: register your organization and prove the legitimacy of your minerals.
•Buyers and traders: source verified lots with plain-language search.
•Transporters, warehouses and refineries: maintain clear custody records and automated documentation.
•Inspectors and auditors: streamline verification and build your reputation.
•Customs operators: file declarations from verified data and clear lots faster.
•Insurers and financiers: cover and lend against lots you can verify.
•Regulators (RMB, RURA, RRA, BNR): validate the companies you license and gain real-time oversight of licences and permits.
Appendix A: Glossary
•3TG: tin, tantalum, tungsten and gold, the conflict minerals regulated by Dodd-Frank and EU rules.
•Base Layer 2: an Ethereum Layer 2 scaling network with low fees and fast transactions.
•BNR: National Bank of Rwanda, which licenses banks, microfinance institutions, SACCOs and insurers.
•Chain of custody: the chronological record of who held and handled a material.
•Custody vs ownership: custody is who physically holds a lot; ownership is who legally owns it.
•Conflict minerals: minerals extracted in conflict zones and sold to fund fighting.
•ERC-721: the token standard for non-fungible tokens on Ethereum.
•ESG: environmental, social and governance criteria.
•ICGLR Regional Certification Mechanism: the International Conference on the Great Lakes Region scheme that certifies 3TG exports as conflict-free.
•Escrow: funds locked in a smart contract until agreed conditions are met.
•Lien: a financier's claim on a lot used as loan collateral, recorded on its token until the loan is repaid.
•Lot passport: the signed, chronological record of a lot's events.
•Mass balance: a comparison of input and output quantities to detect loss or substitution.
•Oracle node: an automated service that compares on-chain records with off-chain data and signs the result.
•Quorum: the minimum share of oracle nodes that must agree before a result is accepted.
•RMB: Rwanda Mines, Petroleum and Gas Board, which issues mining licences and export permits.
•RRA: Rwanda Revenue Authority, whose Customs Services licenses clearing agents and releases goods.
•RURA: Rwanda Utilities Regulatory Authority, which licenses goods transport operators.
•Slashing: reducing an oracle node's stake when it reports wrongly or fails to respond.
•Smart contract: self-executing code that enforces agreed rules.
•Traceability: the ability to follow a product through all stages from origin to sale.
Appendix B: References
•Regulatory: US Dodd-Frank Act Section 1502; EU Regulation 2017/821; OECD Due Diligence Guidance for Responsible Supply Chains of Minerals from Conflict-Affected and High-Risk Areas.
•Rwanda: Law No 072/2024 of 26 June 2024 on mining and quarry operations; ICGLR Regional Certification Mechanism; East African Community Customs Management Act; RRA requirements for licensing of clearing agencies; RURA licensing of goods transport.
•Institutions: Rwanda Mines, Petroleum and Gas Board (RMB); Rwanda Utilities Regulatory Authority (RURA); Rwanda Revenue Authority (RRA); National Bank of Rwanda (BNR); Rwanda Development Board (RDB); Rwanda Environment Management Authority (REMA); Ministry of Infrastructure (MININFRA).
•Technical: ERC-721 token standard; OpenZeppelin contract libraries; Base technical documentation.
•Industry: Responsible Minerals Initiative (RMI); London Bullion Market Association (LBMA); World Gold Council.
Appendix C: Disclaimers
This whitepaper contains forward-looking statements about development plans, adoption and capabilities. Actual results may differ materially. Risks include technology, regulatory, adoption, competition and operational risk. This document is for information only and is not investment, legal or compliance advice. Users are responsible for complying with applicable laws. The platform is provided as is, without warranty, and liability is limited to the fullest extent permitted by law.