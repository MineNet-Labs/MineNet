// Client-side file downloads (CSV exports, generated documents).

export function downloadFile(fileName: string, content: string, type = "text/plain") {
  const blob = new Blob([content], { type });
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = fileName;
  document.body.appendChild(a);
  a.click();
  a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}

/** Download rows as CSV. Columns: [header, value getter]. */
export function downloadCSV<T>(fileName: string, rows: T[], columns: [string, (r: T) => unknown][]) {
  const esc = (v: unknown) => {
    const s = String(v ?? "");
    return /[",\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
  };
  const lines = [columns.map(([h]) => esc(h)).join(",")];
  for (const r of rows) lines.push(columns.map(([, get]) => esc(get(r))).join(","));
  // BOM so Excel opens UTF-8 (₂, ≥, accents) correctly
  downloadFile(fileName.endsWith(".csv") ? fileName : `${fileName}.csv`, "﻿" + lines.join("\n"), "text/csv");
}
