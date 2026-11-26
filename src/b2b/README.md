# B2B

Long-term business-to-business agreements between MineNet companies: recurring mineral **supply** contracts, and
recurring **service** contracts (haulage, storage, tolling, inspection, audit, customs clearing and general services).

Both contracts share one model: an on-chain negotiation, a recurring schedule, per-delivery (or per-job) escrow,
disputes the parties settle themselves (or a neutral arbiter they agreed on), and a public track record for every
company.

## Contracts

| Contract | Purpose |
|---|---|
| [`B2B`](B2B.sol) | Recurring **mineral supply**: e.g. a miner supplying a refinery. Every delivery is filled with lot passports, weighed by the supply-chain ledger, paid for the kilograms actually delivered, and title passes to the buyer on payment. Optional named transporter (paid per delivery) and an independent destination inspection by a platform-assigned inspector. |
| [`B2BServices`](B2BServices.sol) | Recurring **services**, each billed on work verified on-chain wherever possible (see below). |

## Negotiation (both contracts)

1. A company with `ENTER_AGREEMENT` proposes terms to another company. Proposing signs version 1.
2. Either side can **amend** the terms, which creates a new version: a counter-offer.
3. The agreement becomes **Active** once both sides have signed the same version before the deadline. In `B2B`, a
   named transporter must also accept that version. Nobody is ever bound to terms they did not see.
4. Before activation, the counterparty can reject or the proposer can withdraw.

Regulators and oracle nodes cannot contract: they stay neutral.

## Supply agreements (`B2B`)

**Schedule.** `totalDeliveries` deliveries of `quantityPerDelivery` grams at `pricePerKg`, the first one
`firstDeliveryOffset` after activation and then every `deliveryInterval`. Before a delivery is funded, either side
can request a one-off change to its quantity, price or due date, which the other confirms.

**One delivery:**
1. **Fund**: the buyer escrows the price at the upper quantity tolerance, plus the transport fee.
2. **Dispatch**: the seller commits lot passports. Each lot must be the agreed mineral, inspected, unfrozen and at
   or above the minimum grade. Their total trusted weight must be within the quantity tolerance. With a transporter,
   the lots must travel in its `DeliveryManager` shipment.
3. **Arrival**: the buyer's organisation holds custody of every lot, and the review period starts.
4. **Payment**: the buyer accepts, or anyone releases the delivery after the review period. When the agreement
   requires inspection, automatic release waits for an inspection by the inspector the platform assigns
   (`InspectionRegistry`). Neither party chooses the inspector. The seller is paid for the delivered weight, the unused escrow is
   refunded, the transporter is paid, and **ownership of the lots passes to the buyer**.

**Problems:**
- A lot flagged before arrival can be refused at once.
- An arrived delivery can be rejected, which opens a dispute.
- Deliveries not made are refunded as *missed*.
- Deliveries the buyer never funded can be marked in *default*.

## Service agreements (`B2BServices`)

| Kind | Provider must hold | Billed on (verified on-chain) | Unit |
|---|---|---|---|
| Haulage | `CARRY` | Delivered shipments of the client's lots carried by the provider | kg |
| Storage | `OPERATE_WAREHOUSE` | Client lots in the provider's custody, billed per period within its window | kg per period |
| Toll processing / refining | `PROCESS_LOTS` | Client lots consumed by the provider's `processLots` after activation | kg of input |
| Inspection & assay / Audit | `INSPECT_LOT` / `AUDIT` | `Inspection` / `Audit` checkpoints signed by the provider's organisation | checkpoint |
| Customs clearing | `FILE_CUSTOMS` | `CustomsDeclared` checkpoints by the provider on lots since released | lot |
| Equipment rental, maintenance, security, consulting, labour, other | any business | Units claimed with an evidence hash, accepted or disputed by the client | agreed unit |

- Each piece of work is billed once (`workBilled`).
- Billing is capped at the job's budget (`maxUnitsPerJob × ratePerUnit`). The client escrows that budget, and the
  unused part is refunded.

## Ending an agreement (both contracts)

- **Completion**: automatic once every delivery or job is resolved.
- **Mutual termination**: request, confirm or withdraw. Funded deliveries or jobs that haven't started are refunded.
- **Termination for cause**: either side can terminate once the other has missed (or failed to fund) `maxMissed`
  deliveries.
- **Track record**: every company builds one (`performanceOf`): deliveries or jobs completed, on time, missed,
  rejected, funding defaults and disputes lost.

## Folder contents

| Path | Contents |
|---|---|
| `B2B.sol`, `B2BServices.sol` | The contracts. |
| `interfaces/IB2B.sol`, `interfaces/IB2BServices.sol` | Full external APIs for frontends, indexers and integrators. |
| `libraries/B2BLib.sol` | Supply types, events, custom errors, pricing maths (shared types also used by services). |
| `libraries/ServicesLib.sol` | Service types, events, custom errors. |
| `libraries/B2BLogic.sol`, `libraries/ServicesLogic.sol` | **External libraries** holding the validation and verification logic, called via `DELEGATECALL`. They keep both contracts under the EIP-170 24 KB size limit, and Foundry links them automatically in tests and `forge script`. |

## Security notes

- The admin can only pause **new business**. Payments, refunds, disputes, termination and withdrawals always work,
  and the admin has no power over any agreement or its funds.
- Payouts use the pull pattern (`withdraw`). Only settlement tokens approved in `CurrencyManager` are accepted.
- Arbiters and transporters must be neutral: outside both parties' organisations. Inspectors are never chosen by
  the parties: the platform assigns them.
