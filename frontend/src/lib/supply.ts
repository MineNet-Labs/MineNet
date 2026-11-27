// Supply chain actions. Every change also writes an activity line so the
// overview, activity feeds and reports stay in step with the work.
import { today } from "./data";
import { getState, nextId, update } from "./store";
import type { AppData } from "./data";
import { CAPACITY, EXPORT_DOCS, ROYALTY, type DeclStatus, type ExportDecl, type ExportDocName, type ProcBatch, type RefBatch, type ScArea, type Shipment, type ShipmentStatus, type StockLot } from "./supplyData";

export * from "./supplyData";

export const SUPPLY_AUDIENCE = "supply";
const stamp = () => `${today()} · ${new Date().toTimeString().slice(0, 5)}`;

function log(s: AppData, area: ScArea, text: string, notify = false): Partial<AppData> {
  const id = nextId(s.scActivity.map((a) => a.id), "ACT-", 4);
  const out: Partial<AppData> = { scActivity: [{ id, area, text, date: stamp() }, ...s.scActivity] };
  if (notify) out.notices = [{ id: `N-${String(s.notices.length + 1).padStart(4, "0")}`, kind: "custody", text, href: `/supply/${area === "shipment" ? "shipments" : area}`, date: today(), read: false, audience: SUPPLY_AUDIENCE }, ...s.notices];
  return out;
}

const fmtT = (t: number) => `${t.toFixed(1)} t`;
export { fmtT };

/* ------------------------------------------------------------ shipments */

export const NEXT_SHIPMENT: Partial<Record<ShipmentStatus, ShipmentStatus>> = { Pending: "Dispatched", Dispatched: "In Transit", "In Transit": "Receiving", Delayed: "In Transit", Receiving: "Delivered" };

export function createShipment(v: Omit<Shipment, "id" | "status" | "departed" | "history">) {
  const s = getState();
  const id = nextId(s.shipments.map((x) => x.id), "SHP-2026-", 5);
  update((x) => ({
    shipments: [{ ...v, id, status: "Pending" as const, departed: "—", history: [{ status: "Pending" as const, date: today() }] }, ...x.shipments],
    stock: x.stock.map((l) => (l.id === v.lotId ? { ...l, status: "Reserved" as const, updated: today() } : l)),
    ...log(x, "shipment", `Shipment ${id} created for ${v.lotId} to ${v.destination} (${v.carrier}, seal ${v.seal})`),
  }));
  return id;
}

/** Weigh-in at the destination: a difference over 0.5% holds the shipment as a discrepancy. */
export const TOLERANCE = 0.005;
export function receiveShipment(sh: Shipment, measuredKg: number, sealIntact: boolean) {
  const off = Math.abs(measuredKg - sh.qtyKg) / sh.qtyKg;
  if (!sealIntact || off > TOLERANCE) {
    setShipmentStatus(sh, "Discrepancy", !sealIntact ? "Seal broken or not matching" : `Weighed ${measuredKg} kg, expected ${sh.qtyKg} kg`, measuredKg);
    return false;
  }
  setShipmentStatus(sh, "Delivered", `Weighed ${measuredKg} kg, seal intact`, measuredKg);
  return true;
}

export function setShipmentStatus(sh: Shipment, status: ShipmentStatus, note?: string, receivedKg?: number) {
  update((s) => {
    const kg = receivedKg ?? sh.receivedKg ?? sh.qtyKg;
    const out: Partial<AppData> = {
      shipments: s.shipments.map((x) => (x.id === sh.id ? { ...x, status, note: note ?? x.note, receivedKg: receivedKg ?? x.receivedKg, departed: status === "Dispatched" ? today() : x.departed, history: [...x.history, { status, date: today(), note }] } : x)),
      ...log(s, "shipment", `Shipment ${sh.id} ${status === "Discrepancy" ? "flagged with a discrepancy" : `is now ${status.toLowerCase()}`}`, status === "Delayed" || status === "Discrepancy"),
    };
    // A delivered shipment lands in the warehouse it was sent to.
    if (status === "Delivered") {
      const exists = s.stock.some((l) => l.id === sh.lotId);
      out.stock = exists
        ? s.stock.map((l) => (l.id === sh.lotId ? { ...l, qtyKg: kg, status: "Available" as const, location: sh.destination, updated: today() } : l))
        : [{ id: sh.lotId, mineral: sh.mineral, qtyKg: kg, location: sh.destination, status: "Available" as const, origin: sh.origin, updated: today() }, ...s.stock];
    }
    return out;
  });
}

/* ------------------------------------------------------------ inventory */

export const usedKg = (s: AppData, wh: string) => s.stock.filter((l) => l.location === wh).reduce((n, l) => n + l.qtyKg, 0);
/** Room left in a warehouse (kg); Infinity for places without a set capacity. */
export const roomKg = (s: AppData, wh: string) => (CAPACITY[wh] ?? Infinity) - usedKg(s, wh);

export function registerStock(v: Omit<StockLot, "status" | "updated">) {
  update((s) => ({ stock: [{ ...v, status: "Pending" as const, updated: today() }, ...s.stock], ...log(s, "inventory", `Received ${v.qtyKg} kg of ${v.mineral} at ${v.location}`) }));
}

export function setStock(lot: StockLot, patch: Partial<StockLot>, text: string) {
  update((s) => ({ stock: s.stock.map((l) => (l.id === lot.id ? { ...l, ...patch, updated: today() } : l)), ...log(s, "inventory", text) }));
}

/* ----------------------------------------------------------- processing */

export function newBatch(lot: StockLot, inputT: number) {
  const s = getState();
  const id = nextId(s.batches.map((b) => b.id), "BATCH-2026-", 5);
  update((x) => ({
    batches: [{ id, lotId: lot.id, mineral: lot.mineral, inputT, progress: 0, status: "Pending" as const, started: today() }, ...x.batches],
    stock: x.stock.map((l) => (l.id === lot.id ? { ...l, status: "Reserved" as const, updated: today() } : l)),
    ...log(x, "processing", `Batch ${id} created from ${lot.id} (${fmtT(inputT)})`),
  }));
  return id;
}

/** Moves a batch forward: +25% progress, then quality check, then pass/fail. */
export function advanceBatch(b: ProcBatch, pass?: boolean) {
  update((s) => {
    let next: ProcBatch;
    if (b.status === "Quality Check") next = { ...b, status: pass ? "Completed" : "Rejected", outputT: pass ? +(b.inputT * 0.96).toFixed(2) : undefined };
    else {
      const progress = Math.min(100, b.progress + 25);
      next = { ...b, progress, status: progress === 100 ? "Quality Check" : "In Progress" };
    }
    const msg = next.status === "Completed" ? `Batch ${b.id} passed quality check: ${fmtT(next.outputT ?? 0)} output` : next.status === "Rejected" ? `Batch ${b.id} failed quality check` : next.status === "Quality Check" ? `Batch ${b.id} sent to quality check` : `Batch ${b.id} at ${next.progress}%`;
    return { batches: s.batches.map((x) => (x.id === b.id ? next : x)), ...log(s, "processing", msg) };
  });
}

/* -------------------------------------------------------------- refinery */

export function startRefining(b: ProcBatch) {
  const s = getState();
  const id = nextId(s.refinery.map((r) => r.id), "REF-2026-", 5);
  update((x) => ({ refinery: [{ id, lotId: b.lotId, batchId: b.id, mineral: b.mineral, qtyT: b.outputT ?? b.inputT, progress: 0, stage: "Intake" as const, started: today() }, ...x.refinery], ...log(x, "refinery", `Refining batch ${id} started from ${b.id}`) }));
  return id;
}

export function advanceRefining(r: RefBatch, purity?: number) {
  update((s) => {
    let next: RefBatch;
    if (r.stage === "Quality Testing") next = { ...r, stage: "Refined", purity };
    else if (r.stage === "Intake") next = { ...r, stage: "Refining", progress: 25 };
    else {
      const progress = Math.min(100, r.progress + 25);
      next = { ...r, progress, stage: progress === 100 ? "Quality Testing" : "Refining" };
    }
    const msg = next.stage === "Refined" ? `${r.id} refined at ${purity}% purity` : next.stage === "Quality Testing" ? `${r.id} sent to quality testing` : `${r.id} refining at ${next.progress}%`;
    return { refinery: s.refinery.map((x) => (x.id === r.id ? next : x)), ...log(s, "refinery", msg) };
  });
}

/* ---------------------------------------------------------------- export */

export const NEXT_DECL: Partial<Record<DeclStatus, DeclStatus>> = { Draft: "Submitted", Submitted: "Under Review", "Requires Action": "Under Review", "Under Review": "Cleared", Cleared: "Exported" };

export const missingDocs = (d: Pick<ExportDecl, "docs">) => EXPORT_DOCS.filter((k) => !d.docs[k]);
export const royaltyUsd = (d: Pick<ExportDecl, "mineral" | "valueUsd">) => Math.round(d.valueUsd * (ROYALTY[d.mineral] ?? 0.04));

export function attachExportDoc(d: ExportDecl, name: ExportDocName, file: string) {
  update((s) => ({ declarations: s.declarations.map((x) => (x.id === d.id ? { ...x, docs: { ...x.docs, [name]: file } } : x)), ...log(s, "export", `${name} attached to ${d.id}`) }));
}

export function payRoyalty(d: ExportDecl) {
  update((s) => ({ declarations: s.declarations.map((x) => (x.id === d.id ? { ...x, royaltyPaid: true } : x)), ...log(s, "export", `Royalty of USD ${royaltyUsd(d).toLocaleString()} paid to RMB for ${d.id}`) }));
}

export function newDeclaration(v: Omit<ExportDecl, "id" | "status" | "submitted">, submit: boolean) {
  const s = getState();
  const id = nextId(s.declarations.map((d) => d.id), "EXP-2026-", 5);
  update((x) => ({
    declarations: [{ ...v, id, status: submit ? ("Submitted" as const) : ("Draft" as const), submitted: submit ? today() : "—" }, ...x.declarations],
    stock: x.stock.map((l) => (l.id === v.lotId ? { ...l, status: "Reserved" as const, updated: today() } : l)),
    ...log(x, "export", `Declaration ${id} ${submit ? "submitted" : "saved as draft"} for ${v.lotId} to ${v.destination}`),
  }));
  return id;
}

export function setDeclStatus(d: ExportDecl, status: DeclStatus) {
  update((s) => ({
    declarations: s.declarations.map((x) => (x.id === d.id ? { ...x, status, submitted: x.submitted === "—" ? today() : x.submitted } : x)),
    ...log(s, "export", `Declaration ${d.id} ${status === "Requires Action" ? "needs action" : `is now ${status.toLowerCase()}`}`, status === "Requires Action"),
  }));
}

/* --------------------------------------------------------- traceability */

export type TraceStage = { key: string; label: string; date?: string; done: boolean; ref?: string; detail: string; href: string };

/** The journey of one lot through every stage, built from the records above. */
export function traceLot(s: AppData, lotId: string) {
  const id = lotId.trim().toUpperCase();
  const stock = s.stock.find((l) => l.id === id);
  const ship = s.shipments.filter((x) => x.lotId === id);
  const firstShip = ship[ship.length - 1];
  const batch = s.batches.find((b) => b.lotId === id);
  const ref = s.refinery.find((r) => r.lotId === id);
  const decl = s.declarations.find((d) => d.lotId === id);
  if (!stock && !ship.length && !batch && !ref && !decl) return null;
  const mineral = stock?.mineral ?? firstShip?.mineral ?? batch?.mineral ?? decl?.mineral ?? "";
  const origin = stock?.origin ?? firstShip?.origin ?? "—";
  const delivered = ship.find((x) => x.status === "Delivered");
  const stages: TraceStage[] = [
    { key: "mining", label: "Mining Operations", done: true, date: firstShip?.departed !== "—" ? firstShip?.departed : stock?.updated, detail: `Mineral extracted at ${origin}`, ref: id, href: "/supply/inventory" },
    { key: "logistics", label: "Logistics & Storage", done: !!delivered, date: delivered?.eta, ref: delivered?.id ?? firstShip?.id, detail: delivered ? `Received at ${delivered.destination}` : firstShip ? `Shipment ${firstShip.id}: ${firstShip.status}` : "Not shipped yet", href: "/supply/shipments" },
    { key: "processing", label: "Processing", done: batch?.status === "Completed", date: batch?.started, ref: batch?.id, detail: batch ? `Batch ${batch.id}: ${batch.status}` : "Not processed yet", href: "/supply/processing" },
    { key: "refinery", label: "Refinery", done: ref?.stage === "Refined", date: ref?.started, ref: ref?.id, detail: ref ? `Refinery batch ${ref.id}: ${ref.stage}${ref.purity ? ` · ${ref.purity}% purity` : ""}` : "Not refined yet", href: "/supply/refinery" },
    { key: "export", label: "Export", done: decl?.status === "Exported", date: decl?.submitted !== "—" ? decl?.submitted : undefined, ref: decl?.id, detail: decl ? `Declaration ${decl.id}: ${decl.status} · ${decl.destination}` : "No export declaration", href: "/supply/export" },
  ];
  const discrepancies = ship.filter((x) => x.status === "Discrepancy").length + (batch?.status === "Rejected" ? 1 : 0);
  return { id, mineral, origin, qtyKg: decl?.qtyKg ?? stock?.qtyKg ?? firstShip?.qtyKg ?? 0, destination: decl?.destination, stock, ship, batch, ref, decl, stages, discrepancies, complete: stages.every((x) => x.done) };
}
