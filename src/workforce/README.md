# Workforce

Workers of mining and processing companies: where they work, their attendance, how they (and the company's other
payees) are paid, and what company staff may do at their sites.

## Contracts

| Contract | Purpose |
|---|---|
| [`WorkforceManager`](WorkforceManager.sol) | Worker registry, site assignments, attendance, payment records (mobile money, e-banking, cash, stablecoin), cash-risk monitoring, management reports, company staff roles and site seats (manager, HR). Also serves as the protocol's `IStaffDirectory`. |
| [`SiteOperations`](SiteOperations.sol) | Shift and period reports behind an internal inspection gate (verified output feeds the extraction cap), tunnels, staffing requests, job adverts, hires and the site budget. |
| [`PayrollEngine`](PayrollEngine.sol) | Day types (rest days, holidays, paid and excused leave, no-shows), the check-in gate and 1-in-7 fatigue lock, overtime, daily-rate and salaried pay, automatic settlement with a primary / secondary payment method. |

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
| `SITE_MANAGER` | Attendance, payment records, site status, safety, reserves, site reports, report inspection, lot dispatch, overtime |
| `SUPERVISOR` | Attendance, shift reports, overtime |
| `PAYROLL_OFFICER` | Payment records and stablecoin wages |
| `SAFETY_OFFICER` | Safety measures at dormant sites |
| `GEOLOGIST` | Reserve declarations |
| `LABOURER` | None (a labelled worker) |
| `SITE_HR` | Attendance, payment records, stablecoin wages, hiring (no direct worker registration) |
| `SITE_INSPECTOR` | Inspecting site reports |

Companies can redefine these roles or create their own. A staff member acts from their own wallet within the role's
scope. Other contracts (e.g. `MineSiteRegistry`) check staff permissions through `IStaffDirectory.staffOrg`.

## Site manager, site HR and report inspector

The company account appoints **one site manager, one site HR and one report inspector per site**
(`appointSiteSeat`). Each must be an active worker of the company with a wallet, and one person cannot hold two
seats of a site. The company can remove a holder (zero worker id) or replace them at any time, with immediate
effect. A holder has the company's `SITE_MANAGER` / `SITE_HR` / `SITE_INSPECTOR` permissions at that site only.
Shift supervisors get the `SUPERVISOR` role. Workers join only through approved hires (a company may opt back in
by redefining a role with `MANAGE_WORKERS`).

### Reports: an internal quality gate before official output

| Status | Meaning |
|---|---|
| `Submitted` (Pending_Inspection) | Filed; informational only, shown as "Estimated". Nothing counts yet |
| `Accepted` (Approved_Official) | Verified by the internal inspector; no further company review |
| `Rejected` | Found inaccurate; a corrected report is filed |

- **Shift reports**: a shift supervisor files the end-of-shift extraction log (unique `shiftRef`). The inspector
  (the site's traceability officer, or the site manager for reports they did not file) weighs the output and calls
  `inspectReport` with the verified weights. These are recorded at once as the site's extraction in
  `MineSiteRegistry`: they count toward the regulator-set licence ceiling and become official inventory that lots
  are registered and tagged (ITSCI / RMTS) from.
- **Period reports**: the manager's site report (tunnels opened / inactive / closed, headcount, incidents,
  output summary). Once verified, the tunnel states go on record. Report periods never overlap.
- **Accountability**: each sign-off stores the inspector's wallet, employee (worker) id and time as the
  internal quality sign-off (`Verified_Internal`). It is kept separate from external regulatory audits and from
  ITSCI / RMTS tag checks.

### Hiring

HR deals with the company directly. A staffing request (`requestPosition`) states the job title, the workers
available, the people needed, the daily rate or monthly salary, the pay frequency and the onboarding cost. HR cannot
advertise or hire until the company approves it. Approved hires are onboarded at the site. The site budget
(`budgetOf`) shows estimated monthly pay over a standard 26-day month, committed and planned, plus onboarding costs.

## Attendance, days off and pay (`PayrollEngine`)

| Day type | Set by | Daily-rate miner | Salaried staff | Penalty / alert |
|---|---|---|---|---|
| Shift worked (check-in) | gate / supervisor | 100% day rate | in salary | no |
| Scheduled rest day (site roster, or a personal rotating roster) | company / site manager | 0 | in salary | no |
| Public holiday (company HQ calendar, all sites) | company | 0 | in salary | no |
| Paid statutory leave (annual 1.5 days/month from the accrued balance, sick, maternity) | site HR / company | 100% base | in salary | no |
| Excused leave (unpaid personal leave) | supervisor / site admin / HR | 0 | salary ÷ 26 deducted | no (protected) |
| Unexcused absence (no-show) | — | 0 | salary ÷ 26 deducted | penalty + `NoShowAlert` to HR |

- **Overtime.** A supervisor (`AUTHORIZE_OVERTIME`) authorises work on a rest day, holiday or leave day. It pays
  `restDayOvertimeBps` / `holidayOvertimeBps` of a day's pay.
- **Gate terminal.** `WorkforceManager.recordAttendance` asks `PayrollEngine.checkAttendance` before each check-in.
  A rest day, holiday or leave day is blocked unless overtime was authorised ("Overtime Authorization Required").
- **1-in-7 rest rule.** After 6 consecutive days the next day is locked (`FatigueLock`). Overriding it needs the
  site manager (`MANAGE_SITE`), not only a supervisor.
- **Workers request leave** from their wallet (`requestLeave`) and an approver decides it (`decideLeave`).
  Approvers can also record leave directly (`grantLeave`). Nobody approves their own leave.
- **Automatic pay.** Positions are paid daily, weekly, every two weeks or monthly. Once a period ends (plus the
  policy's `graceDays`, up to 7, for offline sites), anyone can call `settlePay`, with no approval.
- **Payer and fallback.** The company sets the payer account and a primary and secondary settlement token
  (`setPayPolicy`). If the primary payment fails the secondary is used, and if both fail the amount is owed and
  retried at the next settlement. Payments are booked in `WorkforceManager`.
- **Accrued-to-date payroll.** `accruedPayroll(site, currency)` goes down with excused leave and no-shows, and up
  with approved overtime.

## Folder contents

| Path | Contents |
|---|---|
| `WorkforceManager.sol` | The contract. |
| `interfaces/IStaffDirectory.sol` | `staffOrg`: the company an account acts for, as staff holding a permission at a site. |
| `libraries/WorkforceLib.sol` | Worker, payment and report types, events, errors. |
| `SiteOperations.sol` | Reports, inspection, tunnels, hiring and budgets. |
| `PayrollEngine.sol` | Day types, check-in gate, leave, overtime and pay. |
| `interfaces/IAttendanceGate.sol`, `interfaces/ISiteOperations.sol` | The check-in gate; what the engine reads from `SiteOperations`. |
| `libraries/PayrollLib.sol` | Pay policy, leave, period-pay types, events and errors. |
| `interfaces/IWorkforce.sol` | What `SiteOperations` needs from `WorkforceManager` (staff directory, onboarding and payroll hooks). |
| `libraries/StaffLib.sol` | Permission bit flags, built-in roles, site seats, staff types and errors. |
| `libraries/SiteOpsLib.sol` | Report, tunnel, position, hire and budget types, events and errors. |

## Security notes

- Staff can never assign roles, change a role holder or themselves, or pay or record payments to themselves.
- An inactive worker's staff role has no effect.
- Stablecoin payments are pulled from the paying wallet, which must have approved this contract.
- **Wallet changes need the worker.** An employer sets a worker's first wallet directly, but changing an
  existing one only proposes it: the worker (from the current wallet) or a regulator must confirm
  (`confirmWalletChange`), so nobody at the employer can redirect wages.
- **Independent devices only.** Attendance devices and cash-acknowledgement oracles must belong to an
  organisation other than the employer.
