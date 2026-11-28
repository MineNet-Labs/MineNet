"use client";

import Link from "next/link";
import { useRouter, useSearchParams } from "next/navigation";
import { useState } from "react";
import { IconArrowRight, IconChartBar, IconCircleCheck, IconClock, IconDownload, IconFileText, IconHistory, IconPlayerPause, IconPlayerPlay, IconPlus, IconShieldCheck, IconTrash } from "@tabler/icons-react";
import { CancelButton, Card, CardTitle, DateRange, Empty, Field, FilterSelect, Modal, PageHeader, Pagination, PrimaryButton, RowMenu, StatusBadge, SubmitButton, formValues, statusTone, toast, usePaged } from "@/components/ui";
import { Select } from "@/components/ui/Select";
import { withConfirm } from "@/components/ui/Confirm";
import { Donut, Sparkline } from "@/components/ui/charts";
import { GREEN, TH } from "@/components/supply/common";
import { REPORTS } from "@/components/supply/reports";
import { downloadCSV, downloadFile } from "@/lib/csv";
import { today } from "@/lib/data";
import { addDays } from "@/lib/domain";
import { nextId, update, useStore } from "@/lib/store";
import { traceLot, type Schedule } from "@/lib/supply";

const TABS = ["Reports", "Documents", "Audit Logs", "Compliance Records", "Data Exports"];

export default function RecordsReportsPage() {
  const router = useRouter();
  const q = useSearchParams();
  const s = useStore((x) => x);
  const [tab, setTab] = useState(TABS.includes(q.get("tab") ?? "") ? q.get("tab")! : "Reports");
  const [area, setArea] = useState(q.get("area") ?? "");
  const [scheduling, setScheduling] = useState(false);

  const lots = [...new Set([...s.stock.map((l) => l.id), ...s.shipments.map((x) => x.lotId)])].map((id) => traceLot(s, id)!).filter(Boolean);
  const verified = s.stock.filter((l) => l.status !== "Pending").length;
  const compliance = Math.round((verified / (s.stock.length || 1)) * 1000) / 10;
  const ready = Math.round((s.declarations.filter((d) => d.status === "Cleared" || d.status === "Exported").length / (s.declarations.length || 1)) * 1000) / 10;

  const logs = s.scActivity.filter((a) => !area || a.area === area);
  const { rows: logPage, pager: logPager } = usePaged(logs, 8);
  const docs = [
    ...s.declarations.map((d) => ({ name: `Export Declaration ${d.id}`, kind: "Export", ref: d.lotId, date: d.submitted, status: d.status })),
    ...s.declarations.filter((d) => d.status === "Cleared" || d.status === "Exported").map((d) => ({ name: `Certificate of Origin ${d.id.replace("EXP", "COO")}`, kind: "Certificate", ref: d.lotId, date: d.submitted, status: "Issued" })),
    ...s.refinery.filter((r) => r.purity).map((r) => ({ name: `Assay Certificate ${r.id}`, kind: "Assay", ref: r.lotId, date: r.started, status: `${r.purity}% purity` })),
  ];
  const { rows: docPage, pager: docPager } = usePaged(docs, 8);
  const { rows: lotPage, pager: lotPager } = usePaged(lots, 8);

  const setSchedule = (id: string, patch: Partial<Schedule> | null) => update((x) => ({ schedules: patch ? x.schedules.map((r) => (r.id === id ? { ...r, ...patch } : r)) : x.schedules.filter((r) => r.id !== id) }));
  const exportsList: [string, () => void][] = [
    ["Shipments", () => downloadCSV("shipments", s.shipments, [["ID", (x) => x.id], ["Lot", (x) => x.lotId], ["Mineral", (x) => x.mineral], ["From", (x) => x.origin], ["To", (x) => x.destination], ["Kg", (x) => x.qtyKg], ["Status", (x) => x.status], ["ETA", (x) => x.eta]])],
    ["Inventory", () => downloadCSV("inventory", s.stock, [["Lot", (x) => x.id], ["Mineral", (x) => x.mineral], ["Kg", (x) => x.qtyKg], ["Warehouse", (x) => x.location], ["Status", (x) => x.status]])],
    ["Processing batches", () => downloadCSV("processing", s.batches, [["Batch", (x) => x.id], ["Lot", (x) => x.lotId], ["Mineral", (x) => x.mineral], ["Input t", (x) => x.inputT], ["Output t", (x) => x.outputT], ["Status", (x) => x.status]])],
    ["Refinery batches", () => downloadCSV("refinery", s.refinery, [["Batch", (x) => x.id], ["Lot", (x) => x.lotId], ["Mineral", (x) => x.mineral], ["Tonnes", (x) => x.qtyT], ["Stage", (x) => x.stage], ["Purity", (x) => x.purity]])],
    ["Export declarations", () => downloadCSV("exports", s.declarations, [["ID", (x) => x.id], ["Lot", (x) => x.lotId], ["Mineral", (x) => x.mineral], ["Kg", (x) => x.qtyKg], ["Destination", (x) => x.destination], ["Buyer", (x) => x.buyer], ["Status", (x) => x.status]])],
    ["Audit log", () => downloadCSV("audit-log", s.scActivity, [["ID", (x) => x.id], ["Area", (x) => x.area], ["What happened", (x) => x.text], ["When", (x) => x.date]])],
  ];

  return (
    <>
      <PageHeader title="Records & Reports" subtitle="Access operational records and generate reports across the entire mineral lifecycle." actions={<><DateRange label="Last 12 Months" /><PrimaryButton icon={IconDownload} onClick={() => router.push("/supply/reports/supply-chain")}>Export Report</PrimaryButton></>} />

      <Card className="flex flex-wrap gap-2 p-2">
        {TABS.map((t) => (
          <button key={t} onClick={() => setTab(t)} className={`rounded-2xl px-5 py-3 text-[15px] ${tab === t ? "bg-accent-soft font-medium text-accent" : "hover:bg-page"}`}>{t}</button>
        ))}
      </Card>

      {tab === "Reports" && (
        <>
          <div className="grid items-start gap-5 xl:grid-cols-[400px_1fr]">
            <Card className="p-5">
              <CardTitle>Report Catalogue</CardTitle>
              <ul className="mt-3 divide-y divide-gray-100">
                {REPORTS.map((r) => (
                  <li key={r.slug}>
                    <Link href={`/supply/reports/${r.slug}`} className="flex items-center gap-3 py-3 hover:text-[#1F5B3A]">
                      <span className={`grid size-12 shrink-0 place-items-center rounded-xl ${r.tint}`}><r.icon className="size-6" /></span>
                      <span className="flex-1"><b className="block font-medium">{r.title}</b><span className="text-sm text-ink/60">{r.blurb}</span></span>
                      <IconArrowRight className="size-5" />
                    </Link>
                  </li>
                ))}
              </ul>
            </Card>

            <div className="space-y-5">
              <Card className="bg-primary-soft/50 p-5">
                <StatusBadge tone="success" dot={false}>Featured Report</StatusBadge>
                <h2 className="mt-3 text-2xl font-semibold">Mineral Supply Chain Report</h2>
                <p className="mt-2 max-w-lg text-ink/70">A complete view of each mineral&apos;s journey from origin to export.</p>
                <ul className="mt-4 space-y-2 text-[15px]">
                  {["Track mineral lots across all stages", "View custody transfers and status", "Export detailed journey reports"].map((x) => <li key={x} className="flex items-center gap-2"><IconCircleCheck className="size-5 text-[#1F5B3A]" />{x}</li>)}
                </ul>
                <PrimaryButton icon={IconChartBar} className="mt-5 rounded-full" onClick={() => router.push("/supply/reports/supply-chain")}>Generate Report</PrimaryButton>
              </Card>

              <div className="grid gap-5 md:grid-cols-3">
                <Card className="p-5">
                  <p className="text-sm">Total Mineral Lots Tracked</p>
                  <b className="mt-1 block text-3xl font-semibold">{lots.length}</b>
                  <Sparkline values={[3, 4, 4, 5, 6, 7, lots.length]} color={GREEN} width={160} live={false} />
                </Card>
                <Card className="flex items-center justify-between gap-3 p-5">
                  <span><span className="text-sm">Compliance Rate</span><b className="mt-1 block text-3xl font-semibold">{compliance}%</b></span>
                  <Donut size={64} thickness={8} segments={[{ value: compliance, color: GREEN }, { value: 100 - compliance, color: "#E5E7EB" }]} />
                </Card>
                <Card className="flex items-center justify-between gap-3 p-5">
                  <span><span className="text-sm">Export Readiness</span><b className="mt-1 block text-3xl font-semibold">{ready}%</b></span>
                  <Donut size={64} thickness={8} segments={[{ value: ready, color: "#1D4ED8" }, { value: 100 - ready, color: "#E5E7EB" }]} />
                </Card>
              </div>

              <Card className="pt-5">
                <div className="px-5"><CardTitle icon={IconClock} iconClass="text-accent" action={<button onClick={() => setScheduling(true)} className="flex items-center gap-1 text-[15px] text-accent hover:underline"><IconPlus className="size-4" /> Add schedule</button>}>Scheduled Reports</CardTitle></div>
                <div className="mt-4 px-2 pb-4">
                  {s.schedules.length === 0 ? (
                    <Empty>No scheduled reports.</Empty>
                  ) : (
                    <table className="w-full text-left text-sm">
                      <TH cols={["Report Name", "Frequency", "Next Run", "Status", ""]} />
                      <tbody>
                        {s.schedules.map((r) => (
                          <tr key={r.id} className="border-b border-gray-100 last:border-0">
                            <td className="px-3 py-3 font-medium">{r.report}</td>
                            <td className="px-3">{r.frequency}</td>
                            <td className="px-3">{r.next}</td>
                            <td className="px-3"><StatusBadge tone={r.status === "Active" ? "success" : "neutral"}>{r.status}</StatusBadge></td>
                            <td className="px-3 text-right">
                              <RowMenu
                                items={[
                                  { label: "Open report", icon: IconFileText, onClick: () => router.push(`/supply/reports/${REPORTS.find((x) => x.title === r.report)?.slug ?? "supply-chain"}`) },
                                  r.status === "Active" ? { label: "Pause", icon: IconPlayerPause, onClick: () => (setSchedule(r.id, { status: "Paused" }), toast("Schedule paused", "info")) } : { label: "Resume", icon: IconPlayerPlay, onClick: () => (setSchedule(r.id, { status: "Active" }), toast("Schedule resumed")) },
                                  { label: "Delete", icon: IconTrash, danger: true, onClick: withConfirm({ title: "Delete schedule?", message: `${r.report} will no longer be sent ${r.frequency.toLowerCase()}.`, confirmLabel: "Delete", tone: "danger" }, () => (setSchedule(r.id, null), toast("Schedule deleted", "info"))) },
                                ]}
                              />
                            </td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  )}
                </div>
              </Card>
            </div>
          </div>
        </>
      )}

      {tab === "Documents" && (
        <Card className="pt-5">
          <div className="px-5"><CardTitle icon={IconFileText} iconClass="text-accent">Export and quality documents</CardTitle></div>
          <div className="mt-4 px-2">
            <table className="w-full text-left text-sm">
              <TH cols={["Document", "Type", "Lot", "Date", "Status", ""]} />
              <tbody>
                {docPage.map((d) => (
                  <tr key={d.name} className="border-b border-gray-100 last:border-0">
                    <td className="px-3 py-3 font-medium">{d.name}</td>
                    <td className="px-3">{d.kind}</td>
                    <td className="px-3"><Link href={`/supply/traceability?lot=${d.ref}`} className="hover:text-[#1F5B3A] hover:underline">{d.ref}</Link></td>
                    <td className="px-3 text-ink/70">{d.date}</td>
                    <td className="px-3"><StatusBadge tone={statusTone(d.status)}>{d.status}</StatusBadge></td>
                    <td className="px-3 text-right">
                      <button aria-label={`Download ${d.name}`} onClick={() => (downloadFile(`${d.name.replace(/\s+/g, "-")}.txt`, `${d.name}\nType: ${d.kind}\nLot: ${d.ref}\nDate: ${d.date}\nStatus: ${d.status}`), toast("Document downloaded"))} className="grid size-9 place-items-center rounded-full border border-gray-200 hover:bg-page">
                        <IconDownload className="size-4" />
                      </button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <Pagination {...docPager} noun="documents" />
        </Card>
      )}

      {tab === "Audit Logs" && (
        <Card className="pt-5">
          <div className="flex flex-wrap items-center justify-between gap-3 px-5">
            <CardTitle icon={IconHistory} iconClass="text-accent">Audit log</CardTitle>
            <FilterSelect label="All areas" options={["shipment", "inventory", "processing", "refinery", "export"]} value={area} onChange={setArea} />
          </div>
          <div className="mt-4 px-2">
            <table className="w-full text-left text-sm">
              <TH cols={["When", "Area", "What happened"]} />
              <tbody>
                {logPage.map((a) => (
                  <tr key={a.id} className="border-b border-gray-100 last:border-0">
                    <td className="px-3 py-3 text-ink/70">{a.date}</td>
                    <td className="px-3 capitalize">{a.area}</td>
                    <td className="px-3">{a.text}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <Pagination {...logPager} noun="entries" />
        </Card>
      )}

      {tab === "Compliance Records" && (
        <Card className="pt-5">
          <div className="px-5"><CardTitle icon={IconShieldCheck} iconClass="text-accent">Traceability per lot</CardTitle></div>
          <div className="mt-4 px-2">
            <table className="w-full text-left text-sm">
              <TH cols={["Lot", "Mineral", "Origin", "Stages done", "Discrepancies", "Status", ""]} />
              <tbody>
                {lotPage.map((t) => (
                  <tr key={t.id} className="border-b border-gray-100 last:border-0">
                    <td className="px-3 py-3 font-medium">{t.id}</td>
                    <td className="px-3">{t.mineral}</td>
                    <td className="px-3">{t.origin}</td>
                    <td className="px-3">{t.stages.filter((x) => x.done).length}/5</td>
                    <td className={`px-3 ${t.discrepancies ? "font-medium text-danger" : ""}`}>{t.discrepancies}</td>
                    <td className="px-3"><StatusBadge tone={t.discrepancies ? "danger" : t.complete ? "success" : "pending"}>{t.discrepancies ? "Review" : t.complete ? "Fully traced" : "In progress"}</StatusBadge></td>
                    <td className="px-3 text-right"><Link href={`/supply/traceability?lot=${t.id}`} className="text-sm font-medium text-accent hover:underline">Trace</Link></td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <Pagination {...lotPager} noun="lots" />
        </Card>
      )}

      {tab === "Data Exports" && (
        <Card className="p-5">
          <CardTitle icon={IconDownload} iconClass="text-accent">Download data as CSV</CardTitle>
          <div className="mt-4 grid gap-3 sm:grid-cols-2 xl:grid-cols-3">
            {exportsList.map(([label, run]) => (
              <button key={label} onClick={() => (run(), toast(`${label} exported`))} className="flex items-center justify-between rounded-2xl border border-gray-100 px-4 py-4 text-left hover:bg-page">
                <span className="font-medium">{label}</span><IconDownload className="size-5 text-accent" />
              </button>
            ))}
          </div>
        </Card>
      )}

      {scheduling && (
        <Modal title="Schedule a report" subtitle="It is generated and emailed to you on each run." onClose={() => setScheduling(false)} footer={<><CancelButton onClick={() => setScheduling(false)} /><SubmitButton form="sched-form">Add schedule</SubmitButton></>}>
          <form
            id="sched-form"
            className="grid grid-cols-2 gap-4"
            onSubmit={(e) => {
              const v = formValues(e);
              const freq = v.frequency as Schedule["frequency"];
              update((x) => ({ schedules: [...x.schedules, { id: nextId(x.schedules.map((r) => r.id), "SCH-", 3), report: v.report, frequency: freq, next: addDays(today(), freq === "Weekly" ? 7 : freq === "Monthly" ? 30 : 90), status: "Active" as const }] }));
              toast(`${v.report} scheduled ${freq.toLowerCase()}`);
              setScheduling(false);
            }}
          >
            <Field label="Report" className="col-span-2"><Select name="report" defaultValue={REPORTS[0].title}>{REPORTS.map((r) => <option key={r.slug}>{r.title}</option>)}</Select></Field>
            <Field label="Frequency" className="col-span-2"><Select name="frequency" defaultValue="Monthly">{["Weekly", "Monthly", "Quarterly"].map((f) => <option key={f}>{f}</option>)}</Select></Field>
          </form>
        </Modal>
      )}
    </>
  );
}
