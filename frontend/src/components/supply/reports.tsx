// Report catalogue for the supply chain portal. Every report is built from
// the same store data, and one detail page renders any of them.
import { IconArrowsExchange, IconBox, IconBuildingFactory2, IconScale, IconShip, IconTrendingUp, IconTruck, type Icon as TablerIcon } from "@tabler/icons-react";
import type { AppData } from "@/lib/data";
import { traceLot } from "@/lib/supply";
import { GREEN, GREY, ORANGE } from "./common";

export type ReportFilters = { mineral: string; status: string };
export type BuiltReport = {
  total: number;
  totalLabel: string;
  stats: { label: string; value: string }[];
  split: { label: string; value: number; color: string }[];
  splitTitle: string;
  splitCenter: string;
  breakdownTitle: string;
  breakdown: { label: string; value: number }[];
  trendTitle: string;
  trendKind: "area" | "bars";
  trend: { name: string; color: string; values: number[] }[];
  tableTitle: string;
  cols: string[];
  rows: (string | number)[][];
  statusOptions: string[];
  insight: string;
};

export type ReportDef = { slug: string; title: string; blurb: string; subtitle: string; icon: TablerIcon; tint: string; build: (s: AppData, f: ReportFilters) => BuiltReport };

const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun"];
export const REPORT_MONTHS = MONTHS;
const pct = (a: number, b: number) => (b ? Math.round((a / b) * 100) : 0);
const groupSum = <T,>(rows: T[], key: (r: T) => string, val: (r: T) => number) =>
  [...new Set(rows.map(key))].map((label) => ({ label, value: rows.filter((r) => key(r) === label).reduce((n, r) => n + val(r), 0) })).sort((a, b) => b.value - a.value);
/** Sample history for earlier months; the last month is the live figure. */
const history = (now: number, shape = [0.55, 0.65, 0.75, 0.88, 0.86]) => [...shape.map((k) => Math.round(now * k)), now];

export const REPORTS: ReportDef[] = [
  {
    slug: "supply-chain",
    title: "Mineral Supply Chain Report",
    blurb: "End-to-end mineral journey overview",
    subtitle: "A complete view of every lot's journey from origin to export.",
    icon: IconTrendingUp,
    tint: "bg-primary-soft text-[#1F5B3A]",
    build: (s, f) => {
      const lots = [...new Set([...s.stock.map((l) => l.id), ...s.shipments.map((x) => x.lotId)])].map((id) => traceLot(s, id)!).filter((t) => t && (!f.mineral || t.mineral === f.mineral));
      const full = lots.filter((t) => t.complete).length;
      const stage = (i: number) => lots.filter((t) => t.stages.filter((x) => x.done).length === i).length;
      return {
        total: lots.length, totalLabel: "Lots tracked",
        stats: [{ label: "Fully traced", value: `${pct(full, lots.length)}%` }, { label: "With discrepancies", value: String(lots.filter((t) => t.discrepancies).length) }],
        splitTitle: "By current stage", splitCenter: `${pct(full, lots.length)}%`,
        split: [{ label: "Exported", value: full, color: GREEN }, { label: "Processing / refining", value: stage(2) + stage(3) + stage(4), color: ORANGE }, { label: "At origin or in transit", value: stage(1), color: GREY }],
        breakdownTitle: "By mineral", breakdown: groupSum(lots, (t) => t.mineral, () => 1),
        trendTitle: "Lots tracked", trendKind: "area", trend: [{ name: "Tracked", color: GREEN, values: history(lots.length) }, { name: "Exported", color: ORANGE, values: history(full) }],
        tableTitle: "Lots", cols: ["Lot", "Mineral", "Origin", "Stage", "Stages done"],
        rows: lots.map((t) => [t.id, t.mineral, t.origin, t.stages.find((x) => !x.done)?.label ?? "Exported", `${t.stages.filter((x) => x.done).length}/5`]),
        statusOptions: [], insight: `${full} of ${lots.length} lots have a complete, verified journey.`,
      };
    },
  },
  {
    slug: "inventory",
    title: "Inventory Report",
    blurb: "Stock levels and movement summary",
    subtitle: "Stock across warehouses, by status and mineral.",
    icon: IconBox,
    tint: "bg-accent-soft text-accent",
    build: (s, f) => {
      const rows = s.stock.filter((l) => (!f.mineral || l.mineral === f.mineral) && (!f.status || l.status === f.status));
      const kg = rows.reduce((n, l) => n + l.qtyKg, 0);
      const by = (st: string) => rows.filter((l) => l.status === st).reduce((n, l) => n + l.qtyKg, 0);
      return {
        total: Math.round(kg / 100) / 10, totalLabel: "Tonnes in stock",
        stats: [{ label: "Lots", value: String(rows.length) }, { label: "Warehouses", value: String(new Set(rows.map((l) => l.location)).size) }],
        splitTitle: "By status", splitCenter: `${pct(by("Available"), kg)}%`,
        split: [{ label: "Available", value: by("Available"), color: GREEN }, { label: "Reserved", value: by("Reserved"), color: ORANGE }, { label: "Pending / transit", value: by("Pending") + by("In Transit"), color: GREY }],
        breakdownTitle: "By warehouse", breakdown: groupSum(rows, (l) => l.location, (l) => l.qtyKg),
        trendTitle: "Stock (kg)", trendKind: "area", trend: [{ name: "Total", color: GREEN, values: history(kg) }, { name: "Available", color: ORANGE, values: history(by("Available")) }],
        tableTitle: "Lots in stock", cols: ["Lot", "Mineral", "Kg", "Warehouse", "Status"],
        rows: rows.map((l) => [l.id, l.mineral, l.qtyKg, l.location, l.status]),
        statusOptions: ["Available", "Reserved", "Pending", "In Transit"], insight: `${pct(by("Available"), kg)}% of stock is available to process or export.`,
      };
    },
  },
  {
    slug: "shipment",
    title: "Shipment Report",
    blurb: "Transport and delivery analytics",
    subtitle: "Track and analyse mineral shipments across your supply chain.",
    icon: IconTruck,
    tint: "bg-gray-100 text-ink",
    build: (s, f) => {
      const rows = s.shipments.filter((x) => (!f.mineral || x.mineral === f.mineral) && (!f.status || x.status === f.status));
      const late = rows.filter((x) => x.status === "Delayed" || x.status === "Discrepancy").length;
      const onTime = rows.length - late;
      return {
        total: rows.length, totalLabel: "Total shipments",
        stats: [{ label: "Delivered", value: String(rows.filter((x) => x.status === "Delivered").length) }, { label: "Kg moved", value: rows.reduce((n, x) => n + x.qtyKg, 0).toLocaleString() }],
        splitTitle: "Shipment overview", splitCenter: `${pct(onTime, rows.length)}%`,
        split: [{ label: "On time", value: onTime, color: GREEN }, { label: "Delayed", value: rows.filter((x) => x.status === "Delayed").length, color: ORANGE }, { label: "Discrepancy", value: rows.filter((x) => x.status === "Discrepancy").length, color: GREY }],
        breakdownTitle: "By destination", breakdown: groupSum(rows, (x) => x.destination, () => 1),
        trendTitle: "Shipment trend", trendKind: "area", trend: [{ name: "Total shipments", color: GREEN, values: history(rows.length) }, { name: "On time", color: ORANGE, values: history(onTime) }],
        tableTitle: "Recent shipments", cols: ["Shipment", "Mineral", "Kg", "Destination", "Status", "Departure"],
        rows: rows.map((x) => [x.id, x.mineral, x.qtyKg, x.destination, x.status, x.departed]),
        statusOptions: ["Pending", "Dispatched", "In Transit", "Receiving", "Delivered", "Delayed", "Discrepancy"], insight: `${pct(onTime, rows.length)}% of shipments are on time.`,
      };
    },
  },
  {
    slug: "processing",
    title: "Processing & Refining Report",
    blurb: "Batch performance and yields",
    subtitle: "Processing batches, refinery output and quality.",
    icon: IconBuildingFactory2,
    tint: "bg-gray-100 text-ink",
    build: (s, f) => {
      const b = s.batches.filter((x) => (!f.mineral || x.mineral === f.mineral) && (!f.status || x.status === f.status));
      const r = s.refinery.filter((x) => !f.mineral || x.mineral === f.mineral);
      const pass = b.filter((x) => x.status === "Completed").length;
      const fail = b.filter((x) => x.status === "Rejected").length;
      const pur = r.filter((x) => x.purity);
      return {
        total: b.length, totalLabel: "Processing batches",
        stats: [{ label: "Refining batches", value: String(r.length) }, { label: "Avg purity", value: pur.length ? `${(pur.reduce((n, x) => n + (x.purity ?? 0), 0) / pur.length).toFixed(1)}%` : "—" }],
        splitTitle: "Quality", splitCenter: `${pct(pass, pass + fail)}%`,
        split: [{ label: "Passed", value: pass, color: GREEN }, { label: "Rejected", value: fail, color: ORANGE }, { label: "Still running", value: b.length - pass - fail, color: GREY }],
        breakdownTitle: "Input by mineral (t)", breakdown: groupSum(b, (x) => x.mineral, (x) => x.inputT),
        trendTitle: "Batches per month", trendKind: "bars", trend: [{ name: "Processing", color: GREEN, values: history(b.length) }, { name: "Refining", color: ORANGE, values: history(r.length) }],
        tableTitle: "Batches", cols: ["Batch", "Lot", "Mineral", "Input (t)", "Status"],
        rows: b.map((x) => [x.id, x.lotId, x.mineral, x.inputT, x.status]),
        statusOptions: ["Pending", "In Progress", "Quality Check", "Completed", "Rejected"], insight: `${pct(pass, pass + fail)}% of finished batches passed quality check.`,
      };
    },
  },
  {
    slug: "compliance",
    title: "Compliance Report",
    blurb: "Inspections, findings and status",
    subtitle: "Lot verification, discrepancies and customs findings.",
    icon: IconScale,
    tint: "bg-primary-soft text-[#1F5B3A]",
    build: (s, f) => {
      const stock = s.stock.filter((l) => !f.mineral || l.mineral === f.mineral);
      const verified = stock.filter((l) => l.status !== "Pending").length;
      const issues = [...s.shipments.filter((x) => x.status === "Discrepancy").map((x) => [x.id, x.lotId, "Weight discrepancy", x.note ?? "Open"]), ...s.declarations.filter((d) => d.status === "Requires Action").map((d) => [d.id, d.lotId, "Customs requested changes", "Open"]), ...s.batches.filter((b) => b.status === "Rejected").map((b) => [b.id, b.lotId, "Failed quality check", "Closed"])];
      return {
        total: pct(verified, stock.length), totalLabel: "% of lots verified",
        stats: [{ label: "Open findings", value: String(issues.filter((i) => i[3] !== "Closed").length) }, { label: "Lots", value: String(stock.length) }],
        splitTitle: "Verification", splitCenter: `${pct(verified, stock.length)}%`,
        split: [{ label: "Verified", value: verified, color: GREEN }, { label: "Pending", value: stock.length - verified, color: ORANGE }],
        breakdownTitle: "Findings by type", breakdown: groupSum(issues, (i) => String(i[2]), () => 1),
        trendTitle: "Verified lots", trendKind: "area", trend: [{ name: "Verified", color: GREEN, values: history(verified) }],
        tableTitle: "Findings", cols: ["Record", "Lot", "Finding", "Status"],
        rows: issues as string[][],
        statusOptions: [], insight: issues.length ? `${issues.length} findings on record.` : "No findings. Everything is in order.",
      };
    },
  },
  {
    slug: "trade",
    title: "Trade & Commerce Report",
    blurb: "Transactions and commercial activity",
    subtitle: "Buyers, volumes and destinations of declared exports.",
    icon: IconArrowsExchange,
    tint: "bg-accent-soft text-accent",
    build: (s, f) => {
      const d = s.declarations.filter((x) => (!f.mineral || x.mineral === f.mineral) && (!f.status || x.status === f.status));
      const kg = d.reduce((n, x) => n + x.qtyKg, 0);
      return {
        total: d.length, totalLabel: "Trades declared",
        stats: [{ label: "Buyers", value: String(new Set(d.map((x) => x.buyer)).size) }, { label: "Kg traded", value: kg.toLocaleString() }],
        splitTitle: "By mineral", splitCenter: String(new Set(d.map((x) => x.mineral)).size),
        split: groupSum(d, (x) => x.mineral, (x) => x.qtyKg).slice(0, 3).map((g, i) => ({ ...g, color: [GREEN, ORANGE, GREY][i] })),
        breakdownTitle: "By buyer (kg)", breakdown: groupSum(d, (x) => x.buyer, (x) => x.qtyKg),
        trendTitle: "Kg traded", trendKind: "bars", trend: [{ name: "Kg", color: GREEN, values: history(kg) }],
        tableTitle: "Trades", cols: ["Declaration", "Buyer", "Mineral", "Kg", "Destination", "Status"],
        rows: d.map((x) => [x.id, x.buyer, x.mineral, x.qtyKg, x.destination, x.status]),
        statusOptions: ["Draft", "Submitted", "Under Review", "Requires Action", "Cleared", "Exported"], insight: `${kg.toLocaleString()} kg declared to ${new Set(d.map((x) => x.buyer)).size} buyers.`,
      };
    },
  },
  {
    slug: "export",
    title: "Export Report",
    blurb: "Export declarations and clearance",
    subtitle: "Detailed insights into mineral exports and clearance status.",
    icon: IconShip,
    tint: "bg-gray-100 text-ink",
    build: (s, f) => {
      const d = s.declarations.filter((x) => (!f.mineral || x.mineral === f.mineral) && (!f.status || x.status === f.status));
      const cleared = d.filter((x) => x.status === "Cleared" || x.status === "Exported").length;
      const pending = d.filter((x) => ["Submitted", "Under Review", "Requires Action"].includes(x.status)).length;
      return {
        total: d.length, totalLabel: "Total exports",
        stats: [{ label: "Clearance rate", value: `${pct(cleared, d.length)}%` }, { label: "Pending", value: String(pending) }],
        splitTitle: "By destination", splitCenter: `${new Set(d.map((x) => x.destination)).size}`,
        split: groupSum(d, (x) => x.destination, (x) => x.qtyKg).slice(0, 3).map((g, i) => ({ ...g, color: [GREEN, ORANGE, GREY][i] })),
        breakdownTitle: "By destination (kg)", breakdown: groupSum(d, (x) => x.destination, (x) => x.qtyKg),
        trendTitle: "Export trend", trendKind: "bars", trend: [{ name: "Exports", color: GREEN, values: history(d.length) }, { name: "Clearances", color: ORANGE, values: history(cleared) }],
        tableTitle: "Recent export declarations", cols: ["Declaration", "Mineral", "Kg", "Destination", "Status", "Date"],
        rows: d.map((x) => [x.id, x.mineral, x.qtyKg, x.destination, x.status, x.submitted]),
        statusOptions: ["Draft", "Submitted", "Under Review", "Requires Action", "Cleared", "Exported"], insight: `${pct(cleared, d.length)}% of declarations are cleared.`,
      };
    },
  },
];
