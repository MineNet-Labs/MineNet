// Site managers run their own site. Anything that needs the owner's say
// (hiring, new shafts, site papers, mineral handovers) becomes a request the
// owner approves; only then is it added.
import { today, type AppData } from "./data";
import { makeNotice } from "./domain";
import { getState, nextId, siteName, update } from "./store";
import type { Approval } from "./roles";
export type { Approval } from "./roles";

const me = (s: AppData) => s.members.find((m) => m.id === s.sessionMemberId);
export const needsApproval = (s: AppData = getState()) => me(s)?.role === "Site manager";

/** Adds the items now (owner, HR) or files a request for the owner (site manager). Returns true when added. */
export function addOrRequest(kind: string, summary: string, siteId: string | undefined, adds: Approval["adds"]): boolean {
  const s = getState();
  if (!needsApproval(s)) {
    update((x) => apply(x, adds));
    return true;
  }
  const m = me(s)!;
  const id = nextId(s.approvals.map((a) => a.id), "APR-", 4);
  update((x) => ({
    approvals: [{ id, kind, summary, siteId, requestedBy: m.name, memberId: m.id, requested: today(), status: "Pending" as const, adds }, ...x.approvals],
    notices: [makeNotice(x, "alert", `${m.name} asks for approval: ${summary}${siteId ? ` (${siteName(x, siteId)})` : ""}`, "/miner/approvals"), ...x.notices],
  }));
  return false;
}

function apply(s: AppData, adds: Approval["adds"]): Partial<AppData> {
  const out: Record<string, unknown[]> = {};
  for (const a of adds) out[a.to] = [a.item, ...((out[a.to] ?? s[a.to]) as unknown[])];
  return out as Partial<AppData>;
}

export function decide(a: Approval, approve: boolean, note?: string) {
  update((s) => ({
    ...(approve ? apply(s, a.adds) : {}),
    approvals: s.approvals.map((x) => (x.id === a.id ? { ...x, status: approve ? ("Approved" as const) : ("Rejected" as const), decided: today(), note } : x)),
    notices: [makeNotice(s, "alert", `Your request ${a.id} was ${approve ? "approved" : "rejected"}: ${a.summary}`, "/miner/approvals"), ...s.notices],
  }));
}

