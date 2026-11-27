// Document extraction used to pre-fill forms. This is a rule-based stand-in
// for the AI extraction service in project.md §5.1: it reads the file name and
// any plain text in the file. The person always reviews before saving.

import type { AppData, Doc } from "./data";

export type Extracted = {
  kind?: Doc["kind"];
  number?: string;
  issued?: string; // yyyy-mm-dd
  expires?: string; // yyyy-mm-dd
  siteId?: string;
  lotId?: string;
  name?: string;
  found: string[];
};

const MONTHS = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"];
const iso = (y: number, m: number, d: number) => `${y}-${String(m).padStart(2, "0")}-${String(d).padStart(2, "0")}`;

function findDates(text: string) {
  const out: string[] = [];
  for (const m of text.matchAll(/\b(20\d{2})[-/.](\d{1,2})[-/.](\d{1,2})\b/g)) out.push(iso(+m[1], +m[2], +m[3]));
  for (const m of text.matchAll(/\b(\d{1,2})[-/.](\d{1,2})[-/.](20\d{2})\b/g)) out.push(iso(+m[3], +m[2], +m[1]));
  for (const m of text.matchAll(/\b([A-Za-z]{3})[a-z]*\.? (\d{1,2}),? (20\d{2})\b/g)) {
    const mi = MONTHS.indexOf(m[1].toLowerCase());
    if (mi >= 0) out.push(iso(+m[3], mi + 1, +m[2]));
  }
  return [...new Set(out)].sort();
}

/** "Mar 14, 2027" → "2027-03-14" */
const toIso = (d: string) => {
  const t = new Date(d);
  return Number.isNaN(t.getTime()) ? undefined : iso(t.getFullYear(), t.getMonth() + 1, t.getDate());
};

export async function extractDocument(file: File, s: AppData): Promise<Extracted> {
  let body = "";
  if (file.size < 2_000_000) {
    try {
      // Keep printable text only (works for .txt and text-based PDFs).
      body = (await file.text()).replace(/[^\x20-\x7E\n]+/g, " ").slice(0, 200_000);
    } catch {
      body = "";
    }
  }
  const text = `${file.name.replace(/[_]+/g, " ")}\n${body}`;
  const low = text.toLowerCase();
  const found: string[] = [];
  const r: Extracted = { found };

  if (/licen[cs]e|\bml-\d/.test(low)) r.kind = "Mining Licence";
  else if (/export|\bexp-\d/.test(low)) r.kind = "Export Permit";
  else if (/transport|\btrp-\d/.test(low)) r.kind = "Transport Permit";
  else if (/\beia\b|environment/.test(low)) r.kind = "Environmental";
  else if (/certificate|\bcfc-\d|icglr|conflict/.test(low)) r.kind = "Certificate";
  if (r.kind) found.push("type");

  const num = text.match(/\b([A-Z]{2,4}-\d{4}-\d{2,4})\b/);
  if (num) {
    r.number = num[1];
    found.push("reference number");
  }

  const lot = text.match(/\bLOT-\d{5}\b/);
  if (lot && s.lots.some((l) => l.id === lot[0])) {
    r.lotId = lot[0];
    found.push("lot");
  }

  const byLicence = r.number ? s.sites.find((x) => x.licence === r.number) : undefined;
  const site = byLicence ?? s.sites.find((x) => low.includes(x.name.toLowerCase()) || low.includes(x.district.toLowerCase()));
  if (site) {
    r.siteId = site.id;
    found.push("site");
  }

  const dates = findDates(text);
  if (dates.length) {
    r.issued = dates[0];
    if (dates.length > 1) r.expires = dates[dates.length - 1];
    found.push(dates.length > 1 ? "issue and expiry dates" : "issue date");
  } else if (byLicence) {
    r.expires = toIso(byLicence.licenceExpiry);
    if (r.expires) found.push("expiry date (from the RMB licence record)");
  }

  const subject = r.lotId ?? site?.name ?? r.number;
  if (r.kind) r.name = subject ? `${r.kind} – ${subject}` : r.kind;
  return r;
}
