# Finance

Pricing currencies, exchange-rate feeds and mineral reference prices: the money layer used by the marketplace,
escrow, B2B agreements and payroll.

## Contracts

| Contract | Purpose |
|---|---|
| [`CurrencyManager`](CurrencyManager.sol) | The registry of **pricing currencies** (USD built in, plus local currencies such as RWF, KES, UGX, each with a USD rate feed and a staleness limit) and **settlement tokens** (stablecoins such as USDC or a RWF stablecoin, each pegged to a currency). Converts between them at live rates. |
| [`OracleRateFeed`](OracleRateFeed.sol) | A USD exchange-rate feed for currencies with no Chainlink feed on Base. MineNet oracle nodes post rates from an approved source (e.g. the National Bank of Rwanda reference rate). Implements Chainlink's `AggregatorV3Interface`, so it can later be swapped for a Chainlink feed. |
| [`LotFinance`](LotFinance.sol) | **Lot-backed loans and insurance cover.** A lot's owner borrows from a licensed financier against an inspected lot; funding records a lien on the passport and the lot cannot be transferred, processed or committed to a B2B delivery until the lien ends. Insurers bind storage or transit cover, recorded as an `Insured` passport event. |
| [`MineralPriceOracle`](MineralPriceOracle.sol) | International reference prices of minerals in USD: Chainlink feeds where they exist (e.g. gold), and `OracleRateFeed` instances for minerals Chainlink does not cover (tin, tantalum, tungsten...). |

## How conversions work

Every currency has a rate: how many US dollars one whole unit is worth, scaled to 1e18. Any conversion goes through
USD:

```
out = amount × rate(from) × 10^decimals(to) / (rate(to) × 10^decimals(from))
```

So a seller can price a lot in RWF and be paid in USDC, converted at the live rate when the buyer pays. Any amount
can also be shown in USD for reporting (`toUsd`, `tokenToUsd`).

## Loans secured on lots (`LotFinance`)

| Step | Who | Function |
|---|---|---|
| Request a loan on an inspected lot | Lot owner (`SELL_LOT`) | `requestLoan` |
| Fund it: lien recorded on the passport; principal paid on-chain or off-chain | Financier (`FINANCE_LOT`, other organisation) | `fundLoan` |
| Decline / withdraw the request | Financier / owner | `declineLoan` / `cancelLoanRequest` |
| Repay on-chain (anyone); full repayment releases the lien | Anyone | `repay` |
| Release the lien (repaid off-chain, restructured, forgiven) | Financier | `releaseLien` |
| Sell the collateral: the financier is paid first from the sale | `EscrowManager` | `checkSale` at order opening, `repayFromSale` at settlement |

- The debt is a fixed `amountDue` (principal plus agreed interest) set at request time: no interest maths on-chain.
- A sale of a pledged lot must be paid in the loan's token, and the seller's proceeds after fees must cover the
  debt. A refunded sale keeps the lien.
- A loan past its due date stays a lien (`isOverdue`); enforcement is off-chain.
- Insurance cover: the owner or custodian requests (`requestCover`), the insurer binds (`bindCover`). Premiums
  and claims are paid off-chain.
- Pausing stops new loans and cover only; repayments, releases and sale settlements always work.
- The passport accepts its lot-finance contract once (`LotPassport.setFinancing`), so liens can never be stranded.

## Safeguards

- **Stale or invalid rates revert.** A rate older than its currency's `maxStaleness`, or a non-positive answer, is
  rejected.
- **Deviation guard.** With `maxDeviationBps` set, one `OracleRateFeed` update cannot move the rate by more than
  that. This limits the damage a faulty or rogue node can do.
- **Only oracle nodes post rates** (`REPORT_READING`), and only the admin configures currencies, tokens and feeds.

## Folder contents

| Path | Contents |
|---|---|
| `CurrencyManager.sol`, `OracleRateFeed.sol`, `MineralPriceOracle.sol`, `LotFinance.sol` | The contracts. |
| `interfaces/ICurrencyManager.sol` | What other contracts use: settlement tokens, currencies and conversions. |
| `interfaces/ILotFinance.sol` | What the escrow uses to sell a pledged lot: `checkSale`, `repayFromSale`, `activeLoanOf`. |
| `libraries/CurrencyLib.sol` | Currency and token types, conversion maths, events, errors. |
| `libraries/LotFinanceLib.sol` | Loan and cover types, events, errors. |

## Security notes

- Settlement tokens must be plain ERC-20s: fee-on-transfer and rebasing tokens break escrow accounting.
- Reference prices are **advisory** (AI market assistant, listing display, oracle price checks). No payment is
  computed from them.
- Phase 1 accepts a single oracle node's rate. Quorum aggregation across nodes is a planned extension.
