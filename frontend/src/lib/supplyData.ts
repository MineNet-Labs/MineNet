// Supply chain operator: shipments, warehouse inventory, processing,
// refining and export. Types and sample data only (no store import), so the
// main seed can include it; actions live in ./supply.ts.

export type ShipmentStatus = "Pending" | "Dispatched" | "In Transit" | "Receiving" | "Delivered" | "Delayed" | "Discrepancy";
export type ShipEvent = { status: ShipmentStatus; date: string; note?: string };
export type Shipment = {
  id: string; lotId: string; mineral: string; origin: string; destination: string; qtyKg: number; status: ShipmentStatus; departed: string; eta: string; note?: string;
  carrier: string; vehicle: string; driver: string; seal: string; receivedKg?: number; history: ShipEvent[];
};

export type StockStatus = "Available" | "In Transit" | "Pending" | "Reserved";
export type StockLot = { id: string; mineral: string; qtyKg: number; location: string; status: StockStatus; origin: string; updated: string };

export type BatchStatus = "Pending" | "In Progress" | "Quality Check" | "Completed" | "Rejected";
export type ProcBatch = { id: string; lotId: string; mineral: string; inputT: number; progress: number; status: BatchStatus; started: string; outputT?: number };

export type RefineStage = "Intake" | "Refining" | "Quality Testing" | "Refined";
export type RefBatch = { id: string; lotId: string; batchId: string; mineral: string; qtyT: number; progress: number; stage: RefineStage; purity?: number; started: string };

export type DeclStatus = "Draft" | "Submitted" | "Under Review" | "Requires Action" | "Cleared" | "Exported";
/** Papers customs needs before a declaration can be submitted. */
export const EXPORT_DOCS = ["Commercial invoice", "Packing list", "Certificate of origin", "ICGLR regional certificate", "Assay certificate", "RMB export permit"] as const;
export type ExportDocName = (typeof EXPORT_DOCS)[number];
export type ExportDecl = { id: string; lotId: string; mineral: string; qtyKg: number; destination: string; status: DeclStatus; submitted: string; buyer: string; valueUsd: number; royaltyPaid: boolean; docs: Partial<Record<ExportDocName, string>> };

export type ScArea = "shipment" | "inventory" | "processing" | "refinery" | "export";
export type ScActivity = { id: string; area: ScArea; text: string; date: string };

export type Schedule = { id: string; report: string; frequency: "Weekly" | "Monthly" | "Quarterly"; next: string; status: "Active" | "Paused" };

export const WAREHOUSES = ["Main Warehouse", "Regional Depot", "Remote Storage", "Kigali Bonded Store", "Rubavu Depot"];
/** Storage capacity in kg. */
export const CAPACITY: Record<string, number> = { "Main Warehouse": 2500, "Regional Depot": 2000, "Remote Storage": 800, "Kigali Bonded Store": 1500, "Rubavu Depot": 1000, "Kigali Warehouse": 2000 };
export const CARRIERS = ["Kigali Mineral Haulage", "Great Lakes Logistics", "Bollore Transport", "Rwanda Secure Freight"];
/** Royalty paid to RMB before export, as a share of declared value. */
export const ROYALTY: Record<string, number> = { Gold: 0.06, Coltan: 0.04, Tantalum: 0.04, Tin: 0.04, Cassiterite: 0.04, Wolframite: 0.04 };
/** Indicative USD per kg, for declared value suggestions. */
export const USD_PER_KG: Record<string, number> = { Gold: 62000, Coltan: 48, Tantalum: 160, Tin: 26, Cassiterite: 18, Wolframite: 22 };
export const DESTINATIONS = ["Dubai, UAE", "Antwerp, BE", "Shanghai, CN", "Istanbul, TR", "Johannesburg, ZA"];
export const TRANSPORT_POINTS = ["Kigali Warehouse", "Kigali Port", "Mombasa", "Dar es Salaam", "Dubai"];

const FLOW: ShipmentStatus[] = ["Pending", "Dispatched", "In Transit", "Receiving", "Delivered"];
const sh = (id: string, lotId: string, mineral: string, origin: string, destination: string, qtyKg: number, status: ShipmentStatus, departed: string, eta: string): Shipment => {
  const n = Number(id.slice(-2));
  const upTo = status === "Delayed" || status === "Discrepancy" ? FLOW.indexOf(status === "Delayed" ? "In Transit" : "Receiving") : FLOW.indexOf(status);
  const history: Shipment["history"] = FLOW.slice(0, upTo + 1).map((st, i) => ({ status: st, date: i === 0 ? "Jun 14, 2025" : st === "Delivered" ? eta : departed }));
  if (status === "Delayed") history.push({ status, date: eta, note: "Held at Rusumo border" });
  if (status === "Discrepancy") history.push({ status, date: eta, note: "Weight mismatch at receiving" });
  return {
    id, lotId, mineral, origin, destination, qtyKg, status, departed, eta,
    carrier: ["Kigali Mineral Haulage", "Great Lakes Logistics", "Bollore Transport", "Rwanda Secure Freight"][n % 4],
    vehicle: `RAD ${100 + n * 7}${"ABCDEFGH"[n % 8]}`,
    driver: ["Emmanuel Habyarimana", "Jean Bosco Niyonzima", "Olivier Mugabo", "Fabrice Ndayisaba"][n % 4],
    seal: `SEAL-${70300 + n * 13}`,
    receivedKg: status === "Delivered" ? qtyKg : status === "Discrepancy" ? Math.round(qtyKg * 0.94) : undefined,
    note: status === "Delayed" ? "Held at Rusumo border" : status === "Discrepancy" ? "Weight mismatch at receiving" : undefined,
    history,
  };
};
const ALL_DOCS = { "Commercial invoice": "invoice.pdf", "Packing list": "packing-list.pdf", "Certificate of origin": "coo.pdf", "ICGLR regional certificate": "icglr.pdf", "Assay certificate": "assay.pdf", "RMB export permit": "permit.pdf" };

export const supplySeed = {
  shipments: [
    sh("SHP-2026-00330", "LOT-2026-00490", "Gold", "Kigali Site", "Kigali Port", 620, "In Transit", "Jun 27, 2025", "Jun 29, 2025"),
    sh("SHP-2026-00329", "LOT-2026-00489", "Coltan", "Ruhango", "Mombasa", 480, "Delayed", "Jun 24, 2025", "Jun 28, 2025"),
    sh("SHP-2026-00328", "LOT-2026-00488", "Tantalum", "Nyabihu", "Dar es Salaam", 750, "Dispatched", "Jun 26, 2025", "Jun 30, 2025"),
    sh("SHP-2026-00327", "LOT-2026-00487", "Gold", "Musanze", "Kigali Warehouse", 850, "Receiving", "Jun 24, 2025", "Jun 26, 2025"),
    sh("SHP-2026-00326", "LOT-2026-00486", "Tin", "Rubavu", "Dubai", 920, "Delivered", "Jun 18, 2025", "Jun 25, 2025"),
    sh("SHP-2026-00325", "LOT-2026-00485", "Tantalum", "Karongi", "Mombasa", 610, "In Transit", "Jun 21, 2025", "Jun 24, 2025"),
    sh("SHP-2026-00324", "LOT-2026-00484", "Gold", "Nyagatare", "Dar es Salaam", 700, "Pending", "—", "Jul 02, 2025"),
    sh("SHP-2026-00323", "LOT-2026-00483", "Coltan", "Gicumbi", "Mombasa", 540, "Delivered", "Jun 15, 2025", "Jun 22, 2025"),
    sh("SHP-2026-00322", "LOT-2026-00482", "Coltan", "Rusizi", "Kigali Warehouse", 85, "Discrepancy", "Jun 19, 2025", "Jun 21, 2025"),
    sh("SHP-2026-00318", "LOT-2026-00481", "Gold", "Nyabihu Site", "Kigali Warehouse", 500, "Delivered", "Jun 17, 2025", "Jun 18, 2025"),
  ] as Shipment[],

  stock: [
    { id: "LOT-2026-00481", mineral: "Gold", qtyKg: 120, location: "Main Warehouse", status: "Available", origin: "Nyabihu Site", updated: "Jun 29, 2025" },
    { id: "LOT-2026-00482", mineral: "Coltan", qtyKg: 85, location: "Regional Depot", status: "In Transit", origin: "Rusizi", updated: "Jun 28, 2025" },
    { id: "LOT-2026-00483", mineral: "Tantalum", qtyKg: 200, location: "Main Warehouse", status: "Pending", origin: "Gicumbi", updated: "Jun 27, 2025" },
    { id: "LOT-2026-00484", mineral: "Tin", qtyKg: 150, location: "Remote Storage", status: "Available", origin: "Nyagatare", updated: "Jun 26, 2025" },
    { id: "LOT-2026-00486", mineral: "Tin", qtyKg: 920, location: "Kigali Bonded Store", status: "Reserved", origin: "Rubavu", updated: "Jun 25, 2025" },
    { id: "LOT-2026-00487", mineral: "Gold", qtyKg: 850, location: "Main Warehouse", status: "Pending", origin: "Musanze", updated: "Jun 26, 2025" },
    { id: "LOT-2026-00470", mineral: "Coltan", qtyKg: 1300, location: "Regional Depot", status: "Available", origin: "Ruhango", updated: "Jun 20, 2025" },
    { id: "LOT-2026-00468", mineral: "Wolframite", qtyKg: 640, location: "Rubavu Depot", status: "Available", origin: "Gatumba", updated: "Jun 18, 2025" },
  ] as StockLot[],

  batches: [
    { id: "BATCH-2026-00130", lotId: "LOT-2026-00487", mineral: "Gold", inputT: 10, progress: 70, status: "In Progress", started: "Jun 29, 2025" },
    { id: "BATCH-2026-00129", lotId: "LOT-2026-00470", mineral: "Coltan", inputT: 8, progress: 60, status: "In Progress", started: "Jun 27, 2025" },
    { id: "BATCH-2026-00128", lotId: "LOT-2026-00483", mineral: "Tantalum", inputT: 12, progress: 100, status: "Quality Check", started: "Jun 24, 2025" },
    { id: "BATCH-2026-00127", lotId: "LOT-2026-00484", mineral: "Tin", inputT: 6, progress: 40, status: "Pending", started: "Jun 26, 2025" },
    { id: "BATCH-2026-00126", lotId: "LOT-2026-00481", mineral: "Gold", inputT: 0.5, progress: 100, status: "Completed", started: "Jun 19, 2025", outputT: 0.48 },
    { id: "BATCH-2026-00125", lotId: "LOT-2026-00468", mineral: "Wolframite", inputT: 5, progress: 100, status: "Rejected", started: "Jun 12, 2025" },
  ] as ProcBatch[],

  refinery: [
    { id: "REF-2026-00058", lotId: "LOT-2026-00487", batchId: "BATCH-2026-00130", mineral: "Gold", qtyT: 9.5, progress: 70, stage: "Refining", started: "Jun 29, 2025" },
    { id: "REF-2026-00057", lotId: "LOT-2026-00470", batchId: "BATCH-2026-00129", mineral: "Coltan", qtyT: 7.8, progress: 60, stage: "Refining", started: "Jun 28, 2025" },
    { id: "REF-2026-00056", lotId: "LOT-2026-00483", batchId: "BATCH-2026-00128", mineral: "Tantalum", qtyT: 11.6, progress: 100, stage: "Quality Testing", started: "Jun 25, 2025" },
    { id: "REF-2026-00055", lotId: "LOT-2026-00484", batchId: "BATCH-2026-00127", mineral: "Tin", qtyT: 5.8, progress: 40, stage: "Intake", started: "Jun 27, 2025" },
    { id: "REF-2026-00054", lotId: "LOT-2026-00481", batchId: "BATCH-2026-00126", mineral: "Gold", qtyT: 0.48, progress: 100, stage: "Refined", purity: 99.5, started: "Jun 21, 2025" },
  ] as RefBatch[],

  declarations: [
    { id: "EXP-2026-00081", lotId: "LOT-2026-00481", mineral: "Gold", qtyKg: 480, destination: "Dubai, UAE", status: "Exported", submitted: "Jun 24, 2025", buyer: "Emirates Gold Refinery" , valueUsd: 29760000, royaltyPaid: true, docs: { ...ALL_DOCS } },
    { id: "EXP-2026-00080", lotId: "LOT-2026-00470", mineral: "Coltan", qtyKg: 800, destination: "Antwerp, BE", status: "Under Review", submitted: "Jun 26, 2025", buyer: "Umicore Trading" , valueUsd: 38400, royaltyPaid: false, docs: { ...ALL_DOCS } },
    { id: "EXP-2026-00079", lotId: "LOT-2026-00483", mineral: "Tantalum", qtyKg: 600, destination: "Shanghai, CN", status: "Submitted", submitted: "Jun 27, 2025", buyer: "Ningxia Orient" , valueUsd: 96000, royaltyPaid: false, docs: { ...ALL_DOCS } },
    { id: "EXP-2026-00078", lotId: "LOT-2026-00486", mineral: "Tin", qtyKg: 1000, destination: "Istanbul, TR", status: "Cleared", submitted: "Jun 20, 2025", buyer: "Anatolia Metals" , valueUsd: 26000, royaltyPaid: true, docs: { ...ALL_DOCS } },
    { id: "EXP-2026-00077", lotId: "LOT-2026-00468", mineral: "Wolframite", qtyKg: 750, destination: "Johannesburg, ZA", status: "Draft", submitted: "—", buyer: "Rand Minerals" , valueUsd: 16500, royaltyPaid: false, docs: { "Commercial invoice": "invoice.pdf", "Packing list": "packing-list.pdf" } },
    { id: "EXP-2026-00076", lotId: "LOT-2026-00484", mineral: "Tin", qtyKg: 900, destination: "Dubai, UAE", status: "Requires Action", submitted: "Jun 18, 2025", buyer: "Gulf Metals" , valueUsd: 23400, royaltyPaid: false, docs: { ...ALL_DOCS } },
  ] as ExportDecl[],

  scActivity: [
    { id: "ACT-0012", area: "export", text: "Export declaration EXP-2026-00081 cleared by customs", date: "Jun 29, 2025 · 09:24" },
    { id: "ACT-0011", area: "refinery", text: "Refining batch REF-2026-00058 started", date: "Jun 29, 2025 · 10:24" },
    { id: "ACT-0010", area: "processing", text: "Batch BATCH-2026-00130 started", date: "Jun 29, 2025 · 09:15" },
    { id: "ACT-0009", area: "inventory", text: "Received 50 kg of Gold at Main Warehouse", date: "Jun 29, 2025 · 08:02" },
    { id: "ACT-0008", area: "export", text: "Documents updated for declaration EXP-2026-00080", date: "Jun 28, 2025 · 15:17" },
    { id: "ACT-0007", area: "refinery", text: "Quality test completed for batch REF-2026-00057", date: "Jun 28, 2025 · 16:12" },
    { id: "ACT-0006", area: "inventory", text: "Transferred 120 kg to Processing Facility", date: "Jun 28, 2025 · 12:40" },
    { id: "ACT-0005", area: "shipment", text: "Shipment SHP-2026-00329 delayed at Rusumo border", date: "Jun 28, 2025 · 11:05" },
    { id: "ACT-0004", area: "processing", text: "Batch BATCH-2026-00128 sent to quality check", date: "Jun 27, 2025 · 17:30" },
    { id: "ACT-0003", area: "shipment", text: "Shipment SHP-2026-00330 left Kigali Site", date: "Jun 27, 2025 · 07:10" },
  ] as ScActivity[],

  schedules: [
    { id: "SCH-001", report: "Compliance Report", frequency: "Monthly", next: "Jul 31, 2025", status: "Active" },
    { id: "SCH-002", report: "Shipment Report", frequency: "Weekly", next: "Jul 04, 2025", status: "Active" },
  ] as Schedule[],
};
