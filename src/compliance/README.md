# Compliance

The regulatory backbone of MineNet: licences and their expiry, mining concessions and the sites inside them, the
certificates a lot needs before it can be sold or exported, and the people who check all of it: inspectors deployed by
the inspectorate, and auditors accredited by standards bodies.

## Contracts

| Contract | Purpose |
|---|---|
| [`LicenceRegistry`](LicenceRegistry.sol) | Licences and permits held by each organisation (mining, transport, customs, insurance, finance...), with validity periods, suspension, revocation and automatic expiry reminders. |
| [`MineSiteRegistry`](MineSiteRegistry.sol) | Mining concessions granted by regulators, the mine sites inside them (with GPS location and administrative divisions), site status (Active, Dormant, Closed), dormant-site safety, and declared mineral reserves. |
| [`CertificateRegistry`](CertificateRegistry.sol) | Compliance certificates per lot: export permit, ICGLR regional certificate, conflict-free / OECD due-diligence attestation, assay certificate. Each type is issued by one configured role. |
| [`InspectionRegistry`](InspectionRegistry.sol) | The inspector roster and the platform's assignment of inspectors to lots. Inspectors are vetted and deployed to districts by the inspectorate (RMB) or a traceability operator, and drawn at random for each inspection. **Operators never choose who inspects them.** |
| [`AuditRegistry`](AuditRegistry.sol) | Accredited audit firms and the audits of mineral companies: accreditation by a standards body, selection from the accredited roster, independence, rotation, and review by the accreditation body before a certification counts. |

## How it fits together

```
LicenceRegistry ──(valid MINING_LICENCE)──▶ MineSiteRegistry ──(Active site)──▶ LotPassport.registerLot
                                                                                    │
CertificateRegistry ──(required certificates)──▶ EscrowManager (sale) / SupplyChain (customs)
```

- **No lot without a licensed, active site.** A lot can only be registered from an Active site of the miner's own
  organisation, inside a concession whose mining licence is valid (`ISiteRegistry.canProduce`). Suspending the
  licence or revoking the concession stops production at once.
- **No sale or export without certificates.** The escrow and customs checkpoints call `hasValidCertificates`.

## Key flows

**Licences.** Regulators (`REGULATE`) issue, renew, suspend, reinstate and revoke licences. The issuing authority is
recorded as the regulator's own organisation, so it can't be misstated. Reminders go out at configurable thresholds
(90, 30 and 7 days by default) and on expiry. Anyone can trigger a due notice with `sendNotice`, and the contract is
**Chainlink Automation** compatible (`checkUpkeep` / `performUpkeep`).

**Sites.**
1. A regulator grants a concession under a valid mining licence.
2. The holder registers sites with their `SiteLocation`:
   - WGS-84 coordinates in micro-degrees, plus elevation;
   - province, district, sector, cell and village (Rwanda's administrative divisions).
3. Only a regulator can correct a recorded location, and every correction is kept as an event.
4. A site moves Active → Dormant → Closed:
   - when a site goes dormant, safety measures are recorded and independently inspected;
   - a site whose inspection is overdue shows up in `overdueSafetySites`;
   - closure requires a passing inspection and a rehabilitation certificate.

**Reserves.** Holders declare estimated deposits per mineral; independent inspectors or regulators verify them.

**Certificates.** The admin chooses which role issues each type (`configureCertType`). Certificates expire and can be
revoked by their issuer or a regulator.

## Inspectors: deployed, never chosen

This mirrors how inspection works in Rwanda:
- **State inspectors.** The Rwanda Mines, Petroleum and Gas Board (RMB) recruits mine inspectors (mining engineers,
  geologists, environmental specialists) through civil service recruitment under Law n° 072/2024. It deploys them to
  licensed concessions, processing plants and quarries on scheduled or unannounced visits.
- **Traceability field agents.** Agents of programmes such as ITSCI or RCS Global Better Mining are assigned by the
  traceability operator, not by the mine owner.

How the contract enforces this:

| Step | Who | Function |
|---|---|---|
| Approve an inspectorate body (state inspectorate or traceability operator) | Regulator of the INSPECTOR licensing authority (RMB) | `setInspectorate` |
| Enrol a vetted inspector and deploy it to districts and/or the national pool | Same | `deployInspector` / `removeInspector` |
| Set own availability (leave, workload) | The inspector | `setAvailability` |
| Request an inspection of a lot | Owner, custodian, or a regulator (unannounced) | `requestInspection` |
| Decline an assignment (e.g. conflict of interest): reassigned at once | The assigned inspector | `declineInspection` |

- **The draw.** The platform draws at random among inspectors deployed to the district of the lot's mine site who are
  available, authorised and outside both the owner's and the custodian's organisation. If none is eligible, it falls
  back to the national pool.
- **Deadline.** An assignment lasts `inspectionWindow` (7 days by default). After that, the lot can be reassigned to a
  different inspector.
- **Enforcement points.**
  - `SupplyChain` accepts inspection checkpoints only from the assigned inspector. Owners can assign customs agents,
    but never inspectors, and they cannot remove a platform-assigned inspector.
  - `LotPassport` accepts the pass / fail inspection only from the assigned inspector.
  - `MineSiteRegistry` accepts site safety inspections and reserve verifications only from inspectors deployed to the
    site's district (or regulators).
- **Randomness.** The draw uses `block.prevrandao`. This removes any choice by the requester, but it is not bias-proof
  against the block producer. A verifiable source such as Chainlink VRF can replace it behind the same interface.

## Auditors: accredited roster, exporter's choice, rotation

This mirrors mineral supply-chain audits under the OECD Due Diligence Guidance and the ICGLR Regional Certification
Mechanism:

| Scheme | Accreditation body (role ACCREDITOR) | Report review |
|---|---|---|
| `ICGLR_THIRD_PARTY_AUDIT`: keeps an exporter's ICGLR Certified Exporter status | ICGLR Audit Committee | Yes: the Independent Mineral Chain Auditor (IMCA) reviews it and publishes an executive summary |
| `RMI_RMAP_AUDIT`: smelter and refiner audits | Responsible Minerals Initiative | Configurable |
| `ICPAR_FINANCIAL_AUDIT`: statutory audit of the company's books | ICPAR (licensed external auditors) | Configurable |

1. **Accreditation.** Firms cannot declare themselves auditors. The scheme's accreditation body vets them and puts
   them on the roster with an expiry (`accredit`), and can suspend them at any time.
2. **Selection.** The audited company chooses and pays a firm **strictly from the roster** (`requestAudit`). A buyer
   may request an audit of a supplier, which the supplier must consent to (`consentAudit`). Only one engagement per
   company and scheme can be open at a time, which prevents opinion shopping.
3. **Independence.** A firm cannot audit itself or a company it has declared financial, consulting or ownership ties
   with (`setConflict`). The firm or the company discloses a conflict, and only an accreditation body can clear it.
4. **Rotation.** The same firm cannot audit the same company more than `maxConsecutive` times in a row until the
   scheme's cooling-off period has passed.
5. **Review.** Where the scheme requires it, the accreditation body reviews the report and publishes its summary
   (`reviewReport`) before the certification counts. A passed and approved audit certifies the company for the
   scheme's validity period (`isCertified`). A failed or rejected audit ends any current certification.

## Folder contents

| Path | Contents |
|---|---|
| `LicenceRegistry.sol`, `MineSiteRegistry.sol`, `CertificateRegistry.sol`, `InspectionRegistry.sol`, `AuditRegistry.sol` | The contracts. |
| `interfaces/ILicenceRegistry.sol` | `status`, `isValid`, `isValidFor`. |
| `interfaces/ISiteRegistry.sol` | `canProduce`, `orgOfSite`, `getSite`, `getSiteLocation`. |
| `interfaces/ICertificateRegistry.sol` | `isValid`, `hasValidCertificate`, `hasValidCertificates`. |
| `interfaces/IInspectionRegistry.sol` | `assignedInspector`, `coversSite`. |
| `libraries/LicenceLib.sol`, `SiteLib.sol`, `CertificateLib.sol`, `InspectionLib.sol`, `AuditLib.sol` | Types, events, custom errors; `SiteLib.validateLocation`, `InspectionLib.districtKey`, the audit scheme ids. |

## Security notes

- Independence is enforced by organisation: an inspector from the site's own company cannot pass its safety
  inspection or verify its reserves.
- Site locations are public on purpose (lot origin must be verifiable). Detailed surveys stay off-chain as hashes.
- Company staff (via `IStaffDirectory`) can manage sites, record safety measures and declare reserves only within
  their assigned permissions and sites.
