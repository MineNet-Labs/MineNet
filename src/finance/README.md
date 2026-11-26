# Finance

Pricing currencies, exchange-rate feeds and mineral reference prices: the money layer used by the marketplace,
escrow, B2B agreements and payroll.

## Contracts

| Contract | Purpose |
|---|---|
| [`CurrencyManager`](CurrencyManager.sol) | The registry of **pricing currencies** (USD built in, plus local currencies such as RWF, KES, UGX, each with a USD rate feed and a staleness limit) and **settlement tokens** (stablecoins such as USDC or a RWF stablecoin, each pegged to a currency). Converts between them at live rates. |
| [`OracleRateFeed`](OracleRateFeed.sol) | A USD exchange-rate feed for currencies with no Chainlink feed on Base. MineNet oracle nodes post rates from an approved source (e.g. the National Bank of Rwanda reference rate). Implements Chainlink's `AggregatorV3Interface`, so it can later be swapped for a Chainlink feed. |
| [`MineralPriceOracle`](MineralPriceOracle.sol) | International reference prices of minerals in USD: Chainlink feeds where they exist (e.g. gold), and `OracleRateFeed` instances for minerals Chainlink does not cover (tin, tantalum, tungsten...). |

## How conversions work

Every currency has a rate: how many US dollars one whole unit is worth, scaled to 1e18. Any conversion goes through
USD:

```
out = amount × rate(from) × 10^decimals(to) / (rate(to) × 10^decimals(from))
```

So a seller can price a lot in RWF and be paid in USDC, converted at the live rate when the buyer pays. Any amount
can also be shown in USD for reporting (`toUsd`, `tokenToUsd`).

## Safeguards

- **Stale or invalid rates revert.** A rate older than its currency's `maxStaleness`, or a non-positive answer, is
  rejected.
- **Deviation guard.** With `maxDeviationBps` set, one `OracleRateFeed` update cannot move the rate by more than
  that. This limits the damage a faulty or rogue node can do.
- **Only oracle nodes post rates** (`REPORT_READING`), and only the admin configures currencies, tokens and feeds.

## Folder contents

| Path | Contents |
|---|---|
| `CurrencyManager.sol`, `OracleRateFeed.sol`, `MineralPriceOracle.sol` | The contracts. |
| `interfaces/ICurrencyManager.sol` | What other contracts use: settlement tokens, currencies and conversions. |
| `libraries/CurrencyLib.sol` | Currency and token types, conversion maths, events, errors. |

## Security notes

- Settlement tokens must be plain ERC-20s: fee-on-transfer and rebasing tokens break escrow accounting.
- Reference prices are **advisory** (AI market assistant, listing display, oracle price checks). No payment is
  computed from them.
- Phase 1 accepts a single oracle node's rate. Quorum aggregation across nodes is a planned extension.
