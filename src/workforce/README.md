# Workforce

Workers of mining and processing companies: where they work, their attendance, how they (and the company's other
payees) are paid, and what company staff may do at their sites.

## Contracts

| Contract | Purpose |
|---|---|
| [`WorkforceManager`](WorkforceManager.sol) | Worker registry, site assignments, attendance, payment records (mobile money, e-banking, cash, stablecoin), cash-risk monitoring, management reports, and company staff roles. Also serves as the protocol's `IStaffDirectory`. |

## Workers and attendance

- **No personal data on-chain.** A company account (`MANAGE_WORKFORCE`) registers each worker under an opaque,
  salted id, never a name or national id. A wallet is optional.
- **Site assignment.** Workers are assigned to one of the company's mine sites.
- **Attendance.** Recorded per site and day by the company, staff with `RECORD_ATTENDANCE`, or an attendance device
  (`REPORT_READING`, e.g. a biometric clock).
  - Each worker counts once per day, so retried submissions are harmless.
  - Up to 7 days can be backdated, for sites without connectivity.

## Payments

Every payment the company makes (salaries, suppliers, contractors) is recorded with its method:

| Method | How it is recorded |
|---|---|
| Mobile money, bank transfer, other | Recorded with the provider's receipt hash |
| Stablecoin | Paid on-chain by this contract (`payStablecoin`, batch `payPayroll`) |
| Cash | Waits for the payee's acknowledgement (wallet or attendance device). Cash above `cashLimitUsd` (default 500 USD) is flagged; cash unacknowledged after `ackWindow` (default 7 days) is overdue |

- **Disputes.** Payees with a wallet can dispute a payment they did not receive.
- **Reports.** `orgReport` gives each company its totals in USD by method, its cash share, and its open cash and
  dispute counts.

## Staff roles

The company account defines roles as sets of permissions and assigns them to workers, either for the worker's own
site or for all of the company's sites. Built-in roles:

| Role | Permissions |
|---|---|
| `SITE_MANAGER` | Workers, attendance, payment records, site status, safety, reserves |
| `SUPERVISOR` | Attendance |
| `PAYROLL_OFFICER` | Payment records and stablecoin wages |
| `SAFETY_OFFICER` | Safety measures at dormant sites |
| `GEOLOGIST` | Reserve declarations |
| `LABOURER` | None (a labelled worker) |

Companies can redefine these roles or create their own. A staff member acts from their own wallet within the role's
scope. Other contracts (e.g. `MineSiteRegistry`) check staff permissions through `IStaffDirectory.staffOrg`.

## Folder contents

| Path | Contents |
|---|---|
| `WorkforceManager.sol` | The contract. |
| `interfaces/IStaffDirectory.sol` | `staffOrg`: the company an account acts for, as staff holding a permission at a site. |
| `libraries/WorkforceLib.sol` | Worker, payment and report types, events, errors. |
| `libraries/StaffLib.sol` | Permission bit flags, built-in roles, staff types and errors. |

## Security notes

- Staff can never assign roles, change a role holder or themselves, or pay or record payments to themselves.
- An inactive worker's staff role has no effect.
- Stablecoin payments are pulled from the paying wallet, which must have approved this contract.
