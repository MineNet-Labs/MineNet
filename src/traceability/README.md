# Traceability

The digital passport of every mineral lot and everything that happens to it, from the mine to the refined product.

## Contracts

| Contract | Purpose |
|---|---|
| [`LotPassport`](LotPassport.sol) | One ERC-721 token per lot, with an append-only event history. Tracks ownership (ERC-721 owner) and physical custody separately; handles registration, inspection, two-party custody handovers, processing into derived lots, flags, regulatory freezes and corrections. |
| [`SupplyChain`](SupplyChain.sol) | Signed stage checkpoints and the **mass-balance ledger**: every weighing is compared with the last trusted weight and the baseline. Out-of-tolerance weights, damage or broken seals raise a flag that freezes the lot. Also tracks grades and customs progress. |
| [`DeliveryManager`](DeliveryManager.sol) | Shipments: custody in motion. Pickup and delivery each need both sides; weights and seals are checked at every handover, and mismatches put the shipment on hold for the parties to resolve. |
| [`LotTagRegistry`](LotTagRegistry.sol) | Physical QR tags bound to lots, and the scans made along the chain with OCR comparison. Voided or mismatched tags flag the lot. |
| [`CargoTracker`](CargoTracker.sol) | GPS trackers that sign their own position reports. Tamper alerts and oracle-reported route deviations flag the shipment's lots. |
| [`SupplyChainExplorer`](SupplyChainExplorer.sol) | Read-only: merges passport events and checkpoints into one timeline and walks a product's provenance back to its original mine lots (`fullJourney`). |

## The lot lifecycle

```
registerLot (Active site) ─▶ Registered ─▶ inspection ─▶ Inspected ─▶ sell / ship / process
                                               │                            │
                                               └─▶ Rejected                 └─▶ processLots ─▶ Consumed
                                                                                (derived lots, parent links)
```

- **Ownership vs custody.** Ownership moves by ERC-721 transfer (inspected, unfrozen lots, to accounts allowed to
  own lots). Custody moves only when the sender initiates and the receiver confirms, directly on the passport or
  through a `DeliveryManager` shipment.
- **Production cap.** `registerLot` draws the lot's quantity from the site's recorded extraction
  (`MineSiteRegistry.recordExtraction`), so a site can never lot more than it reported producing.
- **Declared vs attested grade.** The owner can declare a new lot's grade once, before inspection
  (`SupplyChain.declareGrade`); an attested grade more than `gradeDiscrepancyBps` (default 3 points) away emits
  `GradeDiscrepancy`.
- **Splitting a batch.** `SupplyChain.splitLot` cuts an inspected lot by trusted weight into smaller lots that
  stay inspected, keep the owner, custodian, site, grade and customs status, get proportional baselines, and are
  covered by the parent's certificates (`CertificateRegistry.splitParentOf`). The parent is consumed and linked
  as the children's parent. The Marketplace splits automatically when a lot is bigger than what is left of a
  buy request.
- **Site dispatch.** `DeliveryManager.dispatch` books a shipment with the vehicle plate, the driver (hashed id),
  the receiving worker at the verified consignee (hashed id, which the consignee can change with `setReceiver`) and the
  weight handed over per lot. The custodian or the company's site manager (`DISPATCH_LOTS` at the lots' site)
  signs it; the carrier then weighs the lots at pickup.
- **Liens.** `LotFinance` records `Lien`, `LienReleased` and `Insured` events through `recordFinancing`. A pledged
  lot cannot be transferred or processed, and only the escrow may lock it (a sale that repays the financier).
- **Flags freeze lots.** Any open flag or regulatory hold freezes the lot: it cannot be sold, moved or processed
  until a regulator resolves the flag.
- **History is append-only.** A correction is a new event pointing to the one it corrects; nothing is overwritten.

## Modules

`SupplyChain`, `DeliveryManager`, `LotTagRegistry` and `CargoTracker` are passport **modules**
(`LotPassport.setModule`). They can hand over custody after their own two-party checks and raise flags. The admin
enables them at deployment, and disabling a module revokes these powers at once.

## Mass balance

- **Per-hop tolerance** (per mineral, default 2%): weight against the last trusted weight.
- **Cumulative tolerance** (default 5%): weight against the registered quantity or regulator re-baseline. Catches
  slow skimming across many hops.
- Only readings within tolerance become the new trusted weight, so a faulty scale or a swap cannot poison the
  reference. A regulator can accept a new weight after investigating (`rebaseline`).

## Folder contents

| Path | Contents |
|---|---|
| `*.sol` | The contracts above. |
| `interfaces/ILotPassport.sol` | Lots, custody, freezes, escrow locks, history, module hooks (extends OpenZeppelin `IERC721`). |
| `interfaces/ISupplyChain.sol` | Trusted weights, grades, checkpoints, customs status, module recording. |
| `interfaces/IDeliveryManager.sol` | Shipments and the lots they carry. |
| `interfaces/ILotTagRegistry.sol` | A lot's current tag. |
| `libraries/PassportLib.sol`, `SupplyChainLib.sol`, `DeliveryLib.sol`, `TraceLib.sol`, `ExplorerLib.sol` | Types, events, custom errors and the deviation maths. |

## Security notes

- Independent checks (weighbridges, oracle reports, inspections) are compared **by organisation**: a second wallet of
  the same company is not independent.
- Pickup and arrival checkpoints can only be recorded through `DeliveryManager`, as part of a two-party handover.
- Only hashes go on-chain: documents, photos and reports stay encrypted off-chain.
- **Trade locks.** `lockedBy` records which trade contract (escrow or an approved locker such as `B2B`) holds a
  lot; only that contract can transfer or unlock it. While locked, the passport records the first time custody
  reaches each organisation (`custodyReachedAt`), which is how escrow and B2B prove delivery.
- **Inspections.** Results come only from the inspector holding the lot's open assignment, which closes on
  submission; a later failure of an inspected lot raises a flag instead of rejecting it.
- **Processing needs consent.** `processLots` requires the processor to be in the owner's organisation or
  approved by the owner for each input.
- **Customs release** is recorded only by a regulator or an oracle of the customs authority
  (`setCustomsAuthority`, e.g. the RRA system link).
- **Frivolous flags.** Auditors flagging a lot must be independent of its owner and custodian, and every flag a
  regulator dismisses is counted against its reporter (`dismissedFlagsOf`).
