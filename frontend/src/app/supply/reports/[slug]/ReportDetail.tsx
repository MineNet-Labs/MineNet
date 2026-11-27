"use client";

import Link from "next/link";
import { useParams } from "next/navigation";
import { useMemo, useState } from "react";
import { IconArrowLeft, IconChartBar, IconCheck, IconDownload, IconMapPin, IconTrendingUp } from "@tabler/icons-react";
import { Card, CardTitle, Empty, Field, PageHeader, PrimaryButton, StatusBadge, statusTone, toast } from "@/components/ui";
import { Select } from "@/components/ui/Select";
import { AreaChart, GroupedBars } from "@/components/ui/charts";
import { DonutLegend, ShareBars, TH } from "@/components/supply/common";
import { REPORTS, REPORT_MONTHS } from "@/components/supply/reports";
import { downloadCSV, downloadFile } from "@/lib/csv";
import { useStore } from "@/lib/store";

type Row = (string | number)[];

/** Any report from the catalogue: filters, overview, breakdown, trend and records. */
export function ReportDetail() {
  const { slug } = useParams<{ slug: string }>();
  const def = REPORTS.find((r) => r.slug === slug);
  const state = useStore((s) => s);
  const [period, setPeriod] = useState("Last 6 Months");
  const [mineral, setMineral] = useState("");
  const [status, setStatus] = useState("");
  const [ready, setReady] = useState(false);
  const r = useMemo(() => def?.build(state, { mineral, status }), [def, state, mineral, status]);
  const minerals = [...new Set([...state.stock, ...state.shipments, ...state.declarations].map((x) => x.mineral))];

  if (!def || !r) {
    return (
      <Card className="p-10 text-center">
        <h2>Report not found</h2>
        <Link href="/supply/reports" className="mt-4 inline-block text-accent hover:underline">Back to Reports</Link>
      </Card>
    );
  }

  const csv = () => downloadCSV<Row>(`${def.slug}-report`, r.rows, r.cols.map((c, i) => [c, (row: Row) => row[i]]));
  const summary = () =>
    downloadFile(
      `${def.slug}-report.txt`,
      [def.title.toUpperCase(), `Period: ${period}${mineral ? ` · ${mineral}` : ""}${status ? ` · ${status}` : ""}`, "", `${r.totalLabel}: ${r.total}`, ...r.stats.map((x) => `${x.label}: ${x.value}`), "", `${r.breakdownTitle}:`, ...r.breakdown.map((b) => `  ${b.label}: ${b.value}`), "", r.insight].join("\n"),
    );

  return (
    <>
      <div className="pl-2">
        <Link href="/supply/reports" className="inline-flex items-center gap-2 rounded-full border border-gray-200 bg-white px-5 py-2.5 text-[15px] font-medium shadow-sm hover:bg-page">
          <IconArrowLeft className="size-5" /> Back to Reports
        </Link>
      </div>
      <PageHeader
        title={def.title}
        subtitle={def.subtitle}
        actions={
          <button onClick={() => (summary(), toast("Report exported"))} className="inline-flex items-center gap-2 rounded-2xl border border-gray-200 bg-white px-5 py-3 text-[15px] hover:bg-page">
            <IconDownload className="size-5" /> Export Report
          </button>
        }
      />

      <Card className="flex flex-wrap items-end gap-4 p-5">
        <Field label="Time Period" className="w-44">
          <Select value={period} onChange={(e) => setPeriod(e.target.value)}>{["Last 30 days", "Last 6 Months", "Last 12 Months"].map((p) => <option key={p}>{p}</option>)}</Select>
        </Field>
        <Field label="Mineral Type" className="w-44">
          <Select value={mineral} onChange={(e) => setMineral(e.target.value)}>
            <option value="">All Minerals</option>
            {minerals.map((m) => <option key={m}>{m}</option>)}
          </Select>
        </Field>
        {r.statusOptions.length > 0 && (
          <Field label="Status" className="w-44">
            <Select value={status} onChange={(e) => setStatus(e.target.value)}>
              <option value="">All Statuses</option>
              {r.statusOptions.map((m) => <option key={m}>{m}</option>)}
            </Select>
          </Field>
        )}
        <PrimaryButton icon={IconChartBar} className="ml-auto" onClick={() => (csv(), setReady(true), toast("Report generated"))}>Generate Report</PrimaryButton>
      </Card>

      <div className="grid items-start gap-5 xl:grid-cols-[1fr_460px]">
        <div className="min-w-0 space-y-5">
          <Card className="p-5">
            <CardTitle icon={IconChartBar} iconClass="text-accent">{r.splitTitle}</CardTitle>
            <div className="mt-2 flex flex-wrap items-center gap-8">
              <div className="min-w-[160px]">
                <b className="block text-5xl font-semibold">{r.total}</b>
                <span className="text-ink/70">{r.totalLabel}</span>
                {r.stats.map((x) => (
                  <p key={x.label} className="mt-2 text-sm"><b className="font-medium">{x.value}</b> <span className="text-ink/60">{x.label.toLowerCase()}</span></p>
                ))}
              </div>
              <div className="flex-1"><DonutLegend center={r.splitCenter} sub="" segments={r.split} /></div>
            </div>
          </Card>
        <Card className="p-5">
          <CardTitle icon={IconTrendingUp} iconClass="text-accent">{r.trendTitle}</CardTitle>
          <div className="mt-2 flex gap-4 text-sm">
            {r.trend.map((t) => <span key={t.name} className="flex items-center gap-1.5"><i className="size-2.5 rounded-full" style={{ background: t.color }} />{t.name}</span>)}
          </div>
          {r.trendKind === "area" ? <AreaChart height={240} live={false} xLabels={REPORT_MONTHS} series={r.trend} /> : <GroupedBars height={240} live={false} labels={REPORT_MONTHS} names={r.trend.map((t) => t.name)} series={r.trend} />}
        </Card>
          <Card className="pt-5">
            <div className="px-5"><CardTitle icon={IconDownload} iconClass="text-accent">{r.tableTitle}</CardTitle></div>
            <div className="mt-4 px-2 pb-4">
              {r.rows.length === 0 ? (
                <Empty>No records match these filters.</Empty>
              ) : (
                <table className="w-full text-left text-sm">
                  <TH cols={r.cols} />
                  <tbody>
                    {r.rows.slice(0, 10).map((row, i) => (
                      <tr key={i} className="border-b border-gray-100 last:border-0">
                        {row.map((c, j) => (
                          <td key={j} className={`px-3 py-3 ${j === 0 ? "font-medium" : ""}`}>
                            {r.cols[j] === "Status" || r.cols[j] === "Stage" ? <StatusBadge tone={statusTone(String(c))}>{c}</StatusBadge> : c}
                          </td>
                        ))}
                      </tr>
                    ))}
                  </tbody>
                </table>
              )}
              {r.rows.length > 10 && <p className="px-3 pt-3 text-sm text-ink/60">Showing 10 of {r.rows.length}. Generate the report to get every row.</p>}
            </div>
          </Card>
        </div>
        <div className="min-w-0 space-y-5">
          <Card className="p-5">
            <CardTitle icon={IconMapPin} iconClass="text-accent">{r.breakdownTitle}</CardTitle>
            {r.breakdown.length ? <ShareBars rows={r.breakdown.slice(0, 5)} /> : <Empty>Nothing to break down.</Empty>}
          </Card>
          <Card className={`p-6 text-center ${ready ? "bg-primary-soft" : "bg-accent-soft/60"}`}>
            {ready ? (
              <>
                <span className="mx-auto grid size-14 place-items-center rounded-full bg-[#1F5B3A] text-white"><IconCheck className="size-7" /></span>
                <p className="mt-3 text-lg font-semibold">Report Ready</p>
                <p className="text-sm text-ink/70">{def.title} generated and downloaded.</p>
              </>
            ) : (
              <>
                <p className="text-lg font-semibold">Insights</p>
                <p className="mt-2 text-sm text-ink/70">{r.insight}</p>
              </>
            )}
          </Card>
        </div>
      </div>
    </>
  );
}
