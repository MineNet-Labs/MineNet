# Access

Who may act in MineNet, what each participant may do, and who licenses them.

Every other contract in the protocol asks this domain one question before acting: *may this account perform this
action right now?* Permissions, suspensions, licence expiry and licensing authority are therefore enforced in one
place, and changing who may do what never requires redeploying a contract.

## Contracts

| Contract | Purpose |
|---|---|
| [`MineNetRegistry`](MineNetRegistry.sol) | The participant registry. Onboards accounts into roles under an organisation and licence, maps permission *actions* to roles, handles suspension, and runs the licensing workflow: regulators register new companies and approve role requests. |

## Core concepts

**Organisations and accounts.** Every account belongs to exactly one organisation (`orgId`, an opaque id).
Several accounts can act for the same organisation, and the protocol reasons about organisations, not wallets.
For example, an inspector from the seller's own company is never "independent".

**Roles vs actions.** A *role* is what a participant **is** (MINER, REFINERY, TRANSPORTER, BUYER, WAREHOUSE,
INSPECTOR, AUDITOR, REGULATOR, ORACLE, PROCESSOR, CUSTOMS, ACCREDITOR, FINANCIER, INSURER). An *action* is what it may **do** (`REGISTER_LOT`,
`SELL_LOT`, `CARRY`, `REGULATE`, `ENTER_AGREEMENT`, `ACCREDIT`...). Contracts only ever check actions:

```solidity
if (!registry.isAuthorized(msg.sender, Actions.SELL_LOT)) revert ...;
```

The admin maps each action to a set of roles (`setActionRoles`), so permissions change without redeployment.

**Good standing.** `isAuthorized` is true only if the account holds an enabled role mapped to the action, is not
suspended, and its licence has not expired. A suspension or an expired licence blocks the account everywhere at once.

## Licensing workflow

The admin assigns the regulator institution that licenses each role (`setRoleAuthority`), for example
MINER → RMB and CUSTOMS → RRA. Regulators of that institution then:

| Flow | Who | Function |
|---|---|---|
| Register a **new** company (new organisation + first account + licence) | Licensing regulator | `registerCompany` |
| Request an **additional** role (existing participant in good standing, with evidence) | The participant | `requestRole` / `cancelRoleRequest` |
| Approve or reject a role request | Licensing regulator | `approveRoleRequest` / `rejectRoleRequest` |
| Withdraw a role it licensed (e.g. licence revoked) | Licensing regulator | `revokeRoleByAuthority` |
| Suspend / reinstate any account | Any regulator | `suspend` / `reinstate` |

Pending requests are queued per institution (`pendingRoleRequests`) using OpenZeppelin `EnumerableSet`.

The same licensing authority also governs the inspection side: regulators of the institution that licenses the
INSPECTOR role (RMB) approve inspectorate bodies and deploy inspectors in `InspectionRegistry`. ACCREDITOR accounts
(the ICGLR Audit Committee, RMI, ICPAR) accredit auditors in `AuditRegistry`.

**Safeguards:**
- A regulator never decides on its own organisation (`MineNetRegistry__ConflictOfInterest`).
- The REGULATOR role cannot be delegated, so only the admin creates regulators.
- A new company must use a new organisation id and an unexpired licence.

## Folder contents

| Path | Contents |
|---|---|
| `MineNetRegistry.sol` | The registry (extends OpenZeppelin `AccessControlDefaultAdminRules`). |
| `interfaces/IMineNetRegistry.sol` | What other contracts use: `isAuthorized`, `isActive`, `isAdmin`, `participant`, `sameOrg`, `isParticipantRole` (extends OpenZeppelin `IAccessControl`). |
| `libraries/Roles.sol` | Role identifiers. |
| `libraries/Actions.sol` | Action identifiers and the default action → roles table installed at deployment. |
| `libraries/RegistryLib.sol` | Participant and role-request types, events and custom errors. |

## Security notes

- Admin transfers are two-step and delayed (`AccessControlDefaultAdminRules`). The admin must be a multisig from the first deployment.
- The admin onboards, maps permissions and pauses. It never acts in the supply chain, edits lot history or decides disputes.
- Only hashes and opaque ids are stored: no documents, no personal data.
- **Company-wide suspension.** `suspendOrg` blocks every account of an organisation at once (suspending one
  account no longer leaves the company's other accounts trading). Accounts suspended individually stay suspended
  when the organisation is reinstated.
- **Company payout account.** The admin can set `orgPayout` from a company's verified treasury details; escrow,
  B2B and service proceeds and refunds owed to any of the company's accounts are credited there (`payoutOf`), so
  no single employee receives the company's money.
