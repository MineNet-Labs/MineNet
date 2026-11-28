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
- **Partial fills.** A buy request can be filled by several lots, each weighing at least `minQty`. The deposit
  for the rest stays locked; the request closes once less than `minQty` is left.
- **Auto-split.** The company approves an order by claiming it with one of its lots. A lot bigger than what is
  left of the order is split automatically (`SupplyChain.splitLot`): exactly the remaining amount is sold as a
  new inspected lot and the rest stays with the seller. The site manager then dispatches the sold lot
  (`DeliveryManager.dispatch`).
- **Negotiated sales.** Offers and counter-offers happen off-chain. The final terms are signed by one party
  (EIP-712, or EIP-1271 for a contract wallet) and submitted by the other (`acceptOffer`), which pulls the price
  from the buyer and opens the escrow order. Each signer nonce works once and can be cancelled (`cancelOfferNonce`).
- **Pledged lots.** A lot under a lien (`LotFinance`) sells only in the loan's token and for enough to repay the
  financier, who is paid first at settlement.
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

Only facts signed by someone outside both organisations prove an integrity failure or a weight shortfall; a
party-signed fact is kept on record but proves nothing by itself (the party holding the goods could write anything,
and the other side cannot reach the goods to rebut it). A full refund after delivery is paid once the goods are back
with the seller.

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
- **Delivery is the passport's custody record.** An order is delivered once custody reached the buyer's
  organisation during the lock (`custodyReachedAt`); forwarding the goods afterwards does not make them
  undelivered, so `cancelForNonDelivery` cannot be abused. `settle` records the delivery itself.
- **No refund while keeping the goods.** A full refund judged after delivery waits (`AwaitingReturn`) until the
  goods are back with the seller's organisation, or with the custodian the seller names (`setReturnAddress`, e.g.
  its warehouse, since miners do not hold custody themselves) (`completeReturn`); after `RETURN_WINDOW` (30 days) without a return the sale
  completes instead (`claimUnreturned`). A frozen lot is under the regulator's control and is refunded at once.
- **Only independent evidence decides.** A party's own checkpoints (e.g. the buyer reporting a broken seal at
  arrival) prove nothing by themselves; integrity failures and weight shortfalls need an independent signer.
- **Both parties must be licensed.** `openOrder` checks the seller's `SELL_LOT` as well as the buyer's
  `BUY_LOT`, so a suspended seller cannot sell through an old listing.
