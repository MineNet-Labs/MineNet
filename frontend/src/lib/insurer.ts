// Insurer-side actions and helpers. Each one updates the shared store and
// notifies the other side (miner or insurer).

import { addDays, makeNotice } from "./domain";
import { fmtNum, today, type AppData, type Notice } from "./data";
import { nextId, update } from "./store";

export const insurerAudience = (partyId: string) => `insurer:${partyId}`;
export const isMinerNotice = (n: Notice) => !n.audience || n.audience === "miner";

/** Notification for an insurer's inbox. */
export function insurerNotice(s: AppData, partyId: string, kind: Notice["kind"], text: string, href: string): Notice {
  return { ...makeNotice(s, kind, text, href), audience: insurerAudience(partyId) };
}

export function sendQuote(policyId: string, premium: number, months: number) {
  update((s) => {
    const p = s.policies.find((x) => x.id === policyId)!;
    const ins = s.parties.find((x) => x.id === p.insurerId);
    return {
      policies: s.policies.map((x) => (x.id === p.id ? { ...x, status: "Quoted" as const, premium, from: today(), to: addDays(today(), months * 30) } : x)),
      notices: [makeNotice(s, "finance", `${ins?.name} sent a quote for ${p.lotId}: ${p.currency} ${fmtNum(premium)}`, "/miner/insurance"), ...s.notices],
    };
  });
}

export function declineRequest(policyId: string, reason: string) {
  update((s) => {
    const p = s.policies.find((x) => x.id === policyId)!;
    const ins = s.parties.find((x) => x.id === p.insurerId);
    return {
      policies: s.policies.map((x) => (x.id === p.id ? { ...x, status: "Declined" as const } : x)),
      notices: [makeNotice(s, "finance", `${ins?.name} declined cover request ${p.id}: ${reason}`, "/miner/insurance"), ...s.notices],
    };
  });
}

export function decideClaim(claimId: string, approve: boolean, note: string, payout?: number) {
  update((s) => {
    const c = s.claims.find((x) => x.id === claimId)!;
    const p = s.policies.find((x) => x.id === c.policyId);
    const ins = s.parties.find((x) => x.id === p?.insurerId);
    const amount = payout ?? c.amount;
    return {
      claims: s.claims.map((x) => (x.id === c.id ? { ...x, status: approve ? ("Approved" as const) : ("Rejected" as const), decided: today(), note, amount: approve ? amount : x.amount } : x)),
      txns: approve
        ? [{ id: nextId(s.txns.filter((t) => t.direction === "in").map((t) => t.id), "TXN-IN-2511-", 3), direction: "in" as const, party: ins?.name ?? "Insurer", ref: `Claim ${c.id} · ${c.lotId}`, amount, currency: c.currency, method: "Bank Transfer", date: today(), status: "Received" as const }, ...s.txns]
        : s.txns,
      notices: [makeNotice(s, "finance", `${ins?.name} ${approve ? `approved claim ${c.id} and paid ${c.currency} ${fmtNum(amount)}` : `rejected claim ${c.id}`}`, "/miner/insurance"), ...s.notices],
    };
  });
}

/** Marks quotes the miner never answered and policies past their end date. */
export function policyState(p: AppData["policies"][number]) {
  if (p.status === "Active" && Date.parse(p.to) < Date.now()) return "Expired" as const;
  return p.status;
}
