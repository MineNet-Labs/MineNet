"use client";

import { useState } from "react";
import {
  IconAlertTriangle,
  IconChartBar,
  IconChartPie,
  IconCheck,
  IconClock,
  IconDownload,
  IconEye,
  IconFileText,
  IconFilter,
  IconFlame,
  IconGauge,
  IconRefresh,
  IconRoute,
  IconShieldCheck,
} from "@tabler/icons-react";
import { ComplianceGauges, ExtractionHeatmap, InspectionFunnel, SupplyChainSankey } from "@/components/ui/analytics";
import {
  Card,
  CardTitle,
  DateRange,
  MiniSelect,
  Modal,
  PageHeader,
  PrimaryButton,
  RowMenu,
  StatCard,
  StatusBadge,
  statusTone,
  toast,
} from "@/components/ui";
import { AreaChart, Donut, LiveBadge } from "@/components/ui/charts";
import { fmtKg } from "@/lib/data";
import { siteName, useStore } from "@/lib/store";
import { downloadCSV, downloadFile } from "@/lib/csv";

type Report = { id: string; name: string; type: "Mining Activity" | "Compliance" | "Safety" | "Other"; period: string; generated: string; status: "Completed" | "Pending" };

const icons = {
  "Mining Activity": { icon: IconChartBar, cls: "text-accent" },
  Compliance: { icon: IconShieldCheck, cls: "text-[#1F5B3A]" },
  Safety: { icon: IconAlertTriangle, cls: "text-[#3B6FB6]" },
  Other: { icon: IconFileText, cls: "text-ink/60" },
};

const initialReports: Report[] = [
  { id: "RPT-048", name: "Mining Activity Report – Kigali Site", type: "Mining Activity", period: "Jul – Aug 2025", generated: "Aug 28, 2025", status: "Completed" },
  { id: "RPT-047", name: "Compliance Report – Nyabihu", type: "Compliance", period: "Jul – Aug 2025", generated: "Aug 27, 2025", status: "Completed" },
  { id: "RPT-046", name: "Safety Report – Musanze Site", type: "Safety", period: "Jul – Aug 2025", generated: "Aug 25, 2025", status: "Pending" },
  { id: "RPT-045", name: "Mining Activity Report – Gatumba Mine", type: "Mining Activity", period: "Jul 2025", generated: "Aug 04, 2025", status: "Completed" },
  { id: "RPT-044", name: "Compliance Report – Ruhango", type: "Compliance", period: "Jul 2025", generated: "Aug 02, 2025", status: "Completed" },
  { id: "RPT-043", name: "Export Summary – Q2 2025", type: "Other", period: "Apr – Jun 2025", generated: "Jul 05, 2025", status: "Completed" },
];

export default function ReportsPage() {
  const state = useStore((s) => s);
  const [reports, setReports] = useState(initialReports);
  const [showAll, setShowAll] = useState(false);
  const [preview, setPreview] = useState<Report | null>(null);
  const shown = showAll ? reports : reports.slice(0, 3);

  const reportText = (r: Report) => {
    const lots = state.lots.slice(0, 8).map((l) => `  ${l.id}  ${l.mineral.padEnd(12)} ${fmtKg(l.quantityKg).padStart(9)}  ${l.status}  ${siteName(state, l.siteId)}`).join("\n");
    return `MINENET · ${r.name}\nReport ${r.id} · ${r.type} · ${r.period}\nGenerated ${r.generated} · Status: ${r.status}\n\nSites: ${state.sites.length} (${state.sites.filter((s) => s.status === "Active").length} active)\nWorkers: ${state.workers.length}\nMineral lots: ${state.lots.length}\nApproved extraction: ${fmtKg(state.records.filter((x) => x.status === "Approved").reduce((t, x) => t + x.quantityKg, 0))}\n\nRecent lots:\n${lots}\n`;
  };

  const download = (r: Report) => {
    if (r.status !== "Completed") {
      toast(`${r.name} is still being generated`, "info");
      return;
    }
    downloadFile(`${r.id}_${r.type.replace(/ /g, "_")}.txt`, reportText(r));
    toast(`${r.name} downloaded`);
  };

  return (
    <>
      <PageHeader
        title="Reports"
        subtitle="View detailed reports, insights and analytics across the platform"
        crumb={{ icon: IconChartBar, label: "Reports" }}
        actions={
          <>
            <DateRange />
            <PrimaryButton
              icon={IconDownload}
              onClick={() => {
                downloadCSV("minenet-reports", reports, [
                  ["Report ID", (r) => r.id],
                  ["Name", (r) => r.name],
                  ["Type", (r) => r.type],
                  ["Period", (r) => r.period],
                  ["Generated", (r) => r.generated],
                  ["Status", (r) => r.status],
                ]);
                toast(`${reports.length} reports exported`);
              }}
            >
              Export All Reports
            </PrimaryButton>
          </>
        }
      />

      <div className="grid grid-cols-2 gap-5 xl:grid-cols-4">
        <StatCard icon={IconChartBar} tone="orange" label="Total Reports" value="48" delta="+12%" deltaDir="none" note="this period" spark={[3, 3.5, 3.2, 4, 3.8, 5, 8]} />
        <StatCard icon={IconCheck} tone="green" label="Completed" value="42" delta="+8%" deltaDir="none" note="this period" spark={[3, 4, 4.5, 4, 5, 4.5, 8]} />
        <StatCard icon={IconClock} tone="orange" label="Pending" value="6" delta="-25%" deltaDir="none" deltaClass="text-danger" note="this period" spark={[3, 3.5, 3.2, 5, 4.2, 5, 8]} />
        <StatCard icon={IconFileText} tone="gray" label="Scheduled" value="3" delta="+1" deltaDir="none" deltaClass="text-ink" note="this period" spark={[3, 4.5, 4, 6, 5.5, 7, 8]} />
      </div>

      <div className="grid gap-5 xl:grid-cols-[1fr_402px]">
        <Card className="p-6">
          <CardTitle
            icon={IconChartBar}
            action={
              <div className="flex items-center gap-6 text-[15px]">
                <span className="flex items-center gap-2"><i className="size-2.5 rounded-full bg-[#E8792B]" />Generated</span>
                <span className="flex items-center gap-2"><i className="size-2.5 rounded-full bg-[#1F5B3A]" />Completed</span>
                <MiniSelect options={["Last 3 Months", "Last 6 Months", "This year"]} />
              </div>
            }
          >
            <span className="flex items-center gap-3">Reports Overview <LiveBadge /></span>
          </CardTitle>
          <div className="mt-4">
            <AreaChart
              height={240}
              yMax={50}
              yTicks={[0, 10, 20, 30, 40, 50]}
              xLabels={["Jun", "Jul", "Aug (early)", "Aug"]}
              series={[
                { name: "Generated", color: "#E8792B", values: [19, 40, 34, 45.5], fillOpacity: 0.15 },
                { name: "Completed", color: "#1F5B3A", values: [11, 34, 26.5, 38.5], fillOpacity: 0.2 },
              ]}
            />
          </div>
        </Card>

        <Card className="p-6">
          <CardTitle icon={IconChartPie}>Reports by Type</CardTitle>
          <div className="mt-14 flex items-center gap-7">
            <Donut
              size={150}
              thickness={24}
              gap={3}
              labels={["Mining Activity", "Compliance", "Safety", "Other"]}
              segments={[{ value: 40, color: "#E07B39" }, { value: 30, color: "#1F5B3A" }, { value: 20, color: "#E5E7EB" }, { value: 10, color: "#4B5563" }]}
            >
              <div>
                <p className="font-heading text-2xl font-bold">48</p>
                <p className="text-[13px] text-ink/70">Total</p>
              </div>
            </Donut>
            <ul className="flex-1 space-y-4 text-sm">
              {[["Mining Activity", "40%", "#E07B39"], ["Compliance", "30%", "#1F5B3A"], ["Safety", "20%", "#E5E7EB"], ["Other", "10%", "#4B5563"]].map(([l, v, c]) => (
                <li key={l} className="flex justify-between">
                  <span className="flex items-center gap-3"><i className="size-2.5 rounded-full" style={{ background: c }} />{l}</span>
                  <span className="text-[15px]">{v}</span>
                </li>
              ))}
            </ul>
          </div>
        </Card>
      </div>

      <Card className="p-6">
        <CardTitle
          icon={IconFileText}
          action={
            <button onClick={() => setShowAll((s) => !s)} className="text-[15px] text-accent hover:underline">
              {showAll ? "Show less" : "View All →"}
            </button>
          }
        >
          Recent Reports
        </CardTitle>
        <div className="overflow-x-auto">
          <table className="mt-5 w-full text-left text-base [&_td]:whitespace-nowrap">
            <thead className="bg-head text-ink/80">
              <tr>
                {["Report Name", "Type", "Period", "Generated On", "Status"].map((h) => <th key={h} className="px-4 py-3 font-normal">{h}</th>)}
                <th className="px-4 text-right font-normal">Actions</th>
              </tr>
            </thead>
            <tbody>
              {shown.map((r) => {
                const I = icons[r.type];
                return (
                  <tr key={r.id} className="border-b border-gray-100">
                    <td className="px-4 py-4"><span className="flex items-center gap-3"><I.icon className={`size-5 ${I.cls}`} />{r.name}</span></td>
                    <td className="px-4 text-ink/70">{r.type}</td>
                    <td className="px-4 text-ink/70">{r.period}</td>
                    <td className="px-4 text-ink/70">{r.generated}</td>
                    <td className="px-4"><StatusBadge tone={statusTone(r.status)}>{r.status}</StatusBadge></td>
                    <td className="px-4">
                      <span className="flex items-center justify-end gap-4">
                        <button onClick={() => download(r)} className="flex items-center gap-2 hover:text-[#1F5B3A]"><IconDownload className="size-4" /> Download</button>
                        <RowMenu
                          items={[
                            { label: "Preview", icon: IconEye, onClick: () => setPreview(r) },
                            {
                              label: "Regenerate",
                              icon: IconRefresh,
                              onClick: () => {
                                setReports((list) => list.map((x) => (x.id === r.id ? { ...x, status: "Completed", generated: new Date().toLocaleDateString("en-US", { month: "short", day: "2-digit", year: "numeric" }) } : x)));
                                toast(`${r.name} regenerated`);
                              },
                            },
                          ]}
                        />
                      </span>
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      </Card>

      {/* Supply-chain analytics — beyond the Figma */}
      <div className="flex items-center gap-3 pt-2 pl-2">
        <h2>Supply Chain Analytics</h2>
        <LiveBadge />
      </div>

      <Card className="p-6">
        <CardTitle icon={IconRoute}>Chain of Custody Flow</CardTitle>
        <p className="mt-1 text-sm text-ink/70">Tonnes moving from mine sites through inspection, storage, processing and refining to buyers.</p>
        <div className="mt-4"><SupplyChainSankey /></div>
      </Card>

      <div className="grid gap-5 xl:grid-cols-2">
        <Card className="p-6">
          <CardTitle icon={IconGauge}>Compliance Health</CardTitle>
          <ComplianceGauges items={[{ label: "Lots verified", value: 89, color: "#1F5B3A" }, { label: "Inspection pass rate", value: 84, color: "#4F8A66" }, { label: "Licences valid", value: 93, color: "#E8792B" }]} />
        </Card>
        <Card className="p-6">
          <CardTitle icon={IconFilter}>Inspection Pipeline</CardTitle>
          <InspectionFunnel stages={[{ label: "Requested", value: 24 }, { label: "Scheduled", value: 20 }, { label: "Inspected", value: 17 }, { label: "Approved", value: 15 }, { label: "Certified", value: 12 }]} />
        </Card>
      </div>

      <Card className="p-6">
        <CardTitle icon={IconFlame}>Extraction Activity by Site (kg / day)</CardTitle>
        <ExtractionHeatmap sites={["Kigali Gold Mine", "Musanze Mine", "Nyabihu Mine", "Ruhango Mine", "Gatumba Mine", "Rusizi Site"]} />
      </Card>

      {preview && (
        <Modal title={preview.name} subtitle={`${preview.id} · ${preview.period}`} onClose={() => setPreview(null)} width={720}>
          <pre className="max-h-[50vh] overflow-auto rounded-xl bg-page p-4 text-xs leading-relaxed whitespace-pre-wrap">{reportText(preview)}</pre>
        </Modal>
      )}
    </>
  );
}
