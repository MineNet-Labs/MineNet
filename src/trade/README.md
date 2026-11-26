# Trade

The marketplace for verified mineral lots, the escrow that holds payment until delivery, and the decentralised
dispute judge.

## Contracts

| Contract | Purpose |
|---|---|
| [`Marketplace`](Marketplace.sol) | Sellers list inspected lots at a fixed total or per kilogram of trusted weight, priced in USD or a local currency (e.g. RWF) and paid in USDC or a local stablecoin. Buyers buy at the live quote (with a `maxTotal` guard), or post **buy requests** (reverse market) that sellers fill with matching lots. |
| [`EscrowManager`](EscrowManager.sol) | Holds the payment of every sale against the locked lot. Settles when the buyer holds custody, refunds non-delivery, and runs disputes. Payouts use the pull pattern. |

## The sale flow

```
createListing ─▶ buyListing ─▶ EscrowManager.openOrder (lot locked, payment escrowed)
                                    │
           delivery (custody to buyer) ─▶ releaseFunds / settle after the dispute window
                                    │
         no delivery by the deadline ─▶ cancelForNonDelivery (full refund)
                                    │
                     buyer disputes ─▶ evidence period ─▶ resolveDispute (DisputeLib verdict)
```

- **A sold lot is locked.** The lot stays in the seller's wallet while listed. A sale locks it to the order, using
  the seller's passport approval to the escrow as consent, so only the escrow can transfer it.
- **Certificates are required.** Lots must hold the configured certificates (e.g. EXPORT_PERMIT, CONFLICT_FREE)
  both to be sold and to settle.
- **Snapshots at opening.** The fee (max 5%), dispute window and grade at sale are fixed when the order opens.

## Decentralised disputes

No regulator, admin or arbiter decides. Both parties submit **on-chain evidence**: references to `SupplyChain`
checkpoints of the lot recorded after the sale. `DisputeLib.judge`, a pure function, applies these rules in order:

| # | Verdict | When | Outcome |
|---|---|---|---|
| 1 | `NoResponse` | Seller never responded | Full refund |
| 2 | `ComplianceFailure` | A required certificate is no longer valid | Full refund |
| 3 | `IntegrityFailure` | Proven broken seal, damage, failed audit or oracle report | Full refund |
| 4 | `NotDelivered` | No custody and the deadline passed | Full refund |
| 5 | `QualityShortfall` | Proven missing weight and/or lower grade | Proportional refund, buyer keeps the lot |
| 6 | `SellerWins` | Nothing proven | Seller paid |

Independent signers (outside both organisations) are decisive. A party-signed fact counts unless the other side
rebuts it with a *later* independent fact.

## Folder contents

| Path | Contents |
|---|---|
| `Marketplace.sol`, `EscrowManager.sol` | The contracts. |
| `interfaces/IEscrowManager.sol` | What the marketplace uses: `openOrder`, `getOrder`, delivery-window limits. |
| `libraries/MarketplaceLib.sol` | Listing and buy-request types, pricing maths, events, errors. |
| `libraries/EscrowLib.sol` | Order, dispute and evidence types, events, errors. |
| `libraries/DisputeLib.sol` | The judge. |

## Security notes

- Only settlement tokens approved in `CurrencyManager` are accepted. Fee-on-transfer and rebasing tokens are not
  supported.
- Withdrawals, refunds and dispute resolution keep working while the contracts are paused.
- If a verdict gives the lot to the buyer while it is frozen, the money is paid out and the title transfer waits
  until the freeze is lifted (`finalizeTitle`).
