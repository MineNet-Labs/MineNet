// Business rules shared by the miner pages: licence checks, the lot
// passport timeline, custody, price guidance, listing readiness and anomaly
// flags. Pure functions over AppData so they can move to the backend later.

import { MONTHS, fmtKg, parseDate, simHash, today, type AppData, type EventKind, type Lot, type LotEvent, type Notice, type Site } from "./data";

/* -------------------------------------------------------------- licences */

export type LicenceState = "Valid" | "Expiring" | "Expired";

export const daysUntil = (date: string) => Math.ceil((parseDate(date) - Date.now()) / 86_400_000);

export function licenceState(expiry: string): LicenceState {
  const d = daysUntil(expiry);
  if (d < 0) return "Expired";
  if (d <= 60) return "Expiring";
  return "Valid";
}

/** The organisation may sign events (register lots, list, dispatch). */
export const orgCanAct = (s: AppData) => s.org.status === "Validated" && licenceState(s.org.validatedUntil) !== "Expired";

/** Lots can be registered at this site: organisation validated and site licence not expired. */
export const siteCanRegister = (s: AppData, site: Site) => orgCanAct(s) && site.status === "Active" && licenceState(site.licenceExpiry) !== "Expired";

/** Date input value (yyyy-mm-dd) → "Mon DD, YYYY". */
export function fmtInputDate(v: string) {
  if (!v) return "";
  const [y, m, d] = v.split("-").map(Number);
  return `${MONTHS[m - 1]} ${String(d).padStart(2, "0")}, ${y}`;
}

/** "Mon DD, YYYY" + n days. */
export function addDays(date: string, n: number) {
  const d = new Date(parseDate(date) || Date.now());
  d.setDate(d.getDate() + n);
  return `${MONTHS[d.getMonth()]} ${String(d.getDate()).padStart(2, "0")}, ${d.getFullYear()}`;
}

/* -------------------------------------------------------------- passport */

export const tokenId = (lotId: string) => Number(lotId.replace(/\D+/g, "").slice(-5)) || 0;
export const PASSPORT_CONTRACT = "0x4dE1…9b2C (Base Sepolia · simulated)";

/** New signed event (hash simulated until the contracts are connected). */
export function makeEvent(s: AppData, lotId: string, kind: EventKind, actor: string, role: string, detail: string): LotEvent {
  const n = s.events.length + 1;
  const id = `EV-${String(n).padStart(4, "0")}`;
  const date = today();
  return { id, lotId, kind, actor, role, date, detail, hash: simHash(`${id}${lotId}${kind}${date}${detail}`) };
}

export function makeNotice(s: AppData, kind: Notice["kind"], text: string, href: string): Notice {
  return { id: `N-${String(s.notices.length + 1).padStart(4, "0")}`, kind, text, href, date: today(), read: false };
}

/** Full passport history: the registration event plus every signed event, oldest first. */
export function lotTimeline(s: AppData, lot: Lot): LotEvent[] {
  const site = s.sites.find((x) => x.id === lot.siteId);
  const registered: LotEvent = {
    id: `REG-${lot.id}`,
    lotId: lot.id,
    kind: "Registered",
    actor: s.org.contact,
    role: "Miner",
    date: lot.created,
    detail: `${fmtKg(lot.quantityKg)} ${lot.mineral} at ${site?.name ?? lot.siteId} · declared grade ${lot.grade}% · token #${tokenId(lot.id)} minted`,
    hash: simHash(`REG${lot.id}${lot.created}`),
  };
  const own = s.events.filter((e) => e.lotId === lot.id);
  // Inspections without a stored event (older sample data) still show on the passport.
  const fromInspections = s.inspections
    .filter((i) => i.lotId === lot.id && i.result && !own.some((e) => e.kind === "Inspected"))
    .map<LotEvent>((i) => ({
      id: `INSP-${i.id}`,
      lotId: lot.id,
      kind: "Inspected",
      actor: i.inspector ?? "Inspector",
      role: "Inspector",
      date: i.result!.date,
      detail: `${i.type} · measured grade ${i.result!.grade}% · ${i.status.toLowerCase()}`,
      hash: simHash(`INSP${i.id}`),
    }));
  return [registered, ...fromInspections, ...own].sort((a, b) => parseDate(a.date) - parseDate(b.date));
}

/** Who physically holds the lot now. */
export function lotCustody(s: AppData, lot: Lot) {
  const site = s.sites.find((x) => x.id === lot.siteId);
  const open = s.transfers.filter((t) => t.lotId === lot.id && t.status !== "Cancelled");
  const latest = open[0];
  const party = latest && s.parties.find((p) => p.id === latest.partyId);
  if (!latest || latest.status === "Awaiting handover") return { holder: s.org.name, place: site?.name ?? "Mine site", state: "At mine site" as const };
  if (latest.status === "In transit") return { holder: party?.name ?? "Transporter", place: `${latest.from} → ${latest.to}`, state: "In transit" as const };
  if (latest.status === "Stored") return { holder: party?.name ?? "Warehouse", place: latest.to, state: "In storage" as const };
  return { holder: latest.to, place: latest.to, state: "Delivered" as const };
}

export const activeLien = (s: AppData, lotId: string) => s.loans.find((l) => l.lotId === lotId && l.status === "Active");
export const activePolicies = (s: AppData, lotId: string) => s.policies.filter((p) => p.lotId === lotId && p.status === "Active");
export const lotSold = (s: AppData, lotId: string) => s.escrows.some((e) => e.lotId === lotId) || s.listings.some((l) => l.lotId === lotId && l.status === "Sold");

/* -------------------------------------------------------- price guidance */

// Indicative reference prices (USD/kg at the reference grade). Replace with
// the AI price service once the backend provides it.
const reference: Record<string, { usd: number; grade: number }> = {
  Gold: { usd: 82_000, grade: 99 },
  Coltan: { usd: 42, grade: 30 },
  Tantalum: { usd: 160, grade: 95 },
  Tin: { usd: 31, grade: 95 },
  Cassiterite: { usd: 18, grade: 65 },
  Wolframite: { usd: 14.5, grade: 60 },
};

export function priceGuidance(s: AppData, mineral: string, grade: number) {
  const ref = reference[mineral] ?? { usd: 10, grade: grade || 1 };
  const gradeFactor = Math.min(1.25, Math.max(0.6, grade / ref.grade));
  const requests = s.requests.filter((r) => r.mineral === mineral);
  const demand = requests.length ? requests.reduce((n, r) => n + r.pricePerKg, 0) / requests.length : null;
  // Blend the reference price with what buyers are currently offering.
  const base = ref.usd * gradeFactor;
  const mid = demand ? base * 0.6 + demand * 0.4 : base;
  const round = (n: number) => (n >= 1000 ? Math.round(n / 10) * 10 : Math.round(n * 100) / 100);
  return {
    low: round(mid * 0.92),
    mid: round(mid),
    high: round(mid * 1.08),
    basis: `Reference ${mineral} price adjusted for ${grade}% grade${demand ? `, blended with ${requests.length} open buyer request(s)` : ""}.`,
  };
}

/* ----------------------------------------------------- listing checklist */

export type CheckItem = { label: string; ok: boolean; hint: string; href?: string };

/** What a lot still needs before it can be listed on the marketplace. */
export function listingChecklist(s: AppData, lot: Lot): CheckItem[] {
  const site = s.sites.find((x) => x.id === lot.siteId);
  const cert = s.docs.some((d) => d.kind === "Certificate" && d.name.includes(lot.id));
  const inspection = s.inspections.find((i) => i.lotId === lot.id);
  const listed = s.listings.some((l) => l.lotId === lot.id && l.status === "Active");
  return [
    { label: "Organisation validated by RMB", ok: orgCanAct(s), hint: orgCanAct(s) ? `Valid until ${s.org.validatedUntil}` : `Status: ${s.org.status}`, href: "/miner/licence" },
    {
      label: "Site licence valid",
      ok: !!site && licenceState(site.licenceExpiry) !== "Expired",
      hint: site ? `${site.licence} · expires ${site.licenceExpiry}` : "Unknown site",
      href: "/miner/licence",
    },
    {
      label: "Inspected and verified",
      ok: lot.status === "Verified",
      hint: lot.status === "Verified" ? "Grade attested by an inspector" : inspection ? `Inspection ${inspection.id} is ${inspection.status.toLowerCase()}` : "No inspection requested yet",
      href: inspection ? `/miner/inspections/${inspection.id}` : `/miner/inspections/new?lot=${lot.id}&return=/miner/mineral-lots/${lot.id}`,
    },
    { label: "Conflict-free certificate uploaded", ok: cert, hint: cert ? "Certificate on file" : `Upload a certificate that names ${lot.id}`, href: `/miner/documents/new?lot=${lot.id}&return=/miner/mineral-lots/${lot.id}` },
    { label: "Not already listed or sold", ok: !listed && !lotSold(s, lot.id), hint: listed ? "This lot already has an active listing" : lotSold(s, lot.id) ? "This lot has been sold" : "Available" },
  ];
}

/* --------------------------------------------------------------- anomalies */

export type Anomaly = { lotId: string; severity: "high" | "medium"; text: string };

/** Rule-based checks standing in for the AI anomaly model. */
export function anomalies(s: AppData): Anomaly[] {
  const out: Anomaly[] = [];
  for (const lot of s.lots) {
    // 1. Grade far from this site's history for the same mineral.
    const peers = s.lots.filter((l) => l.id !== lot.id && l.mineral === lot.mineral);
    if (peers.length) {
      const avg = peers.reduce((n, l) => n + l.grade, 0) / peers.length;
      const diff = Math.abs(lot.grade - avg);
      if (diff > Math.max(10, avg * 0.25))
        out.push({ lotId: lot.id, severity: "high", text: `Declared grade ${lot.grade}% is far from the ${avg.toFixed(1)}% average for your other ${lot.mineral} lots.` });
    }
    // 2. Inspected grade differs from the declared grade.
    const insp = s.inspections.find((i) => i.lotId === lot.id && i.result);
    if (insp?.result && Math.abs(insp.result.grade - lot.grade) > 3)
      out.push({ lotId: lot.id, severity: "high", text: `Inspector measured ${insp.result.grade}% but ${lot.grade}% was declared.` });
    // 3. Mass balance: lot heavier than the approved extraction at its site.
    const extracted = s.records.filter((r) => r.siteId === lot.siteId && r.mineral === lot.mineral && r.status === "Approved").reduce((n, r) => n + r.quantityKg, 0);
    const lotted = s.lots.filter((l) => l.siteId === lot.siteId && l.mineral === lot.mineral).reduce((n, l) => n + l.quantityKg, 0);
    if (lotted > extracted && s.lots.filter((l) => l.siteId === lot.siteId && l.mineral === lot.mineral)[0]?.id === lot.id)
      out.push({ lotId: lot.id, severity: "medium", text: `${fmtKg(lotted)} of ${lot.mineral} lotted at this site but only ${fmtKg(extracted)} of approved extraction records.` });
    // 4. Registered at a site whose licence has expired.
    const site = s.sites.find((x) => x.id === lot.siteId);
    if (site && licenceState(site.licenceExpiry) === "Expired" && lot.status === "Pending")
      out.push({ lotId: lot.id, severity: "medium", text: `${site.name} licence ${site.licence} expired on ${site.licenceExpiry}.` });
  }
  return out;
}
