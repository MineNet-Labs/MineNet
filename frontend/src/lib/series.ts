// Chart data built from the store, so charts grow when a new mineral or
// month appears in the records.

import { MONTHS, parseDate, type ExtractionRecord } from "./data";

const PALETTE: Record<string, string> = {
  Gold: "#1F5B3A",
  Coltan: "#F0913F",
  Cassiterite: "#8B5CF6",
  Tantalum: "#0E7490",
  Wolframite: "#B5551A",
  Tin: "#64748B",
};
const EXTRA = ["#2563EB", "#DB2777", "#CA8A04", "#059669", "#7C3AED", "#DC2626"];

/** Stable colour per mineral; unknown minerals get one from a spare palette. */
export function mineralColor(name: string) {
  if (PALETTE[name]) return PALETTE[name];
  let h = 0;
  for (const c of name) h = (h * 31 + c.charCodeAt(0)) >>> 0;
  return EXTRA[h % EXTRA.length];
}

/** Last `n` months ending at the newest record: approved tonnes per mineral. */
export function monthlyByMineral(records: ExtractionRecord[], n = 6, onlyApproved = true) {
  const list = records.filter((r) => !onlyApproved || r.status === "Approved");
  const latest = list.reduce((m, r) => Math.max(m, parseDate(r.date)), 0) || Date.now();
  const end = new Date(latest);
  const keys: string[] = [];
  const labels: string[] = [];
  for (let i = n - 1; i >= 0; i--) {
    const d = new Date(end.getFullYear(), end.getMonth() - i, 1);
    keys.push(`${d.getFullYear()}-${d.getMonth()}`);
    labels.push(MONTHS[d.getMonth()]);
  }
  const minerals = [...new Set(list.map((r) => r.mineral))].sort();
  const series = minerals.map((m) => {
    const values = keys.map(() => 0);
    list.forEach((r) => {
      if (r.mineral !== m) return;
      const d = new Date(parseDate(r.date));
      const i = keys.indexOf(`${d.getFullYear()}-${d.getMonth()}`);
      if (i >= 0) values[i] += r.quantityKg / 1000;
    });
    return { name: m, color: mineralColor(m), values: values.map((v) => +v.toFixed(2)) };
  });
  const totals = keys.map((_, i) => +series.reduce((t, s) => t + s.values[i], 0).toFixed(2));
  return { labels, series, totals };
}
