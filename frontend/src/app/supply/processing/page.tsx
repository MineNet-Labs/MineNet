"use client";

import { useState } from "react";
import { IconBox, IconCircleCheck, IconClock, IconFlask, IconPlayerPlay, IconPlus, IconSettings, IconShieldCheck, IconStack2, IconTruck, IconX } from "@tabler/icons-react";
import { Card, CardTitle, DateRange, Empty, FilterSelect, PageHeader, Pagination, PrimaryButton, RowMenu, StatCard, StatusBadge, toast, usePaged } from "@/components/ui";
import { withConfirm } from "@/components/ui/Confirm";
import { ActivityFeed, DonutLegend, GREEN, ORANGE, Pipeline, Progress, TH, batchTone, fmtT } from "@/components/supply/common";
import { NewBatchModal } from "@/components/supply/forms";
import { useStore } from "@/lib/store";
import { advanceBatch } from "@/lib/supply";

export default function ProcessingPage() {
  const batches = useStore((s) => s.batches);
  const [status, setStatus] = useState("");
  const [open, setOpen] = useState(false);
  const rows = batches.filter((b) => !status || b.status === status);
  const { rows: page, pager } = usePaged(rows, 6);
  const t = (f: (b: (typeof batches)[number]) => boolean, k: "inputT" | "outputT" = "inputT") => batches.filter(f).reduce((n, b) => n + (b[k] ?? 0), 0);
  const passed = t((b) => b.status === "Completed", "outputT");
  const rejected = t((b) => b.status === "Rejected");
  const passRate = passed + rejected ? Math.round((passed / (passed + rejected)) * 1000) / 10 : 100;
  const running = batches.filter((b) => b.status === "In Progress" || b.status === "Pending");
  const qc = batches.filter((b) => b.status === "Quality Check");

  return (
    <>
      <PageHeader title="Processing" subtitle="Monitor and manage mineral processing batches and outputs." actions={<><DateRange label="Last 30 days" /><PrimaryButton icon={IconPlus} onClick={() => setOpen(true)}>New Batch</PrimaryButton></>} />

      <div className="grid grid-cols-1 gap-5 sm:grid-cols-2 xl:grid-cols-5">
        <StatCard icon={IconFlask} tone="green" label="Active Batches" value={running.length} delta="+17%" spark={[3, 4, 3, 5, 4, 6, 7]} />
        <StatCard icon={IconCircleCheck} tone="green" label="Completed Batches" value={batches.filter((b) => b.status === "Completed").length} delta="+12%" spark={[3, 4, 4, 5, 5, 6, 7]} />
        <StatCard icon={IconClock} tone="orange" label="Pending Verification" value={qc.length} deltaDir="down" delta="-29%" spark={[5, 4, 4, 3, 3, 2, 2]} />
        <StatCard icon={IconBox} tone="green" label="Processed Output" value={fmtT(passed)} delta="+8%" spark={[3, 3, 4, 5, 5, 6, 6]} />
        <StatCard icon={IconShieldCheck} tone="green" label="Quality Pass Rate" value={`${passRate}%`} delta="+0.4%" spark={[4, 4, 5, 5, 5, 6, 6]} />
      </div>

      <Card className="p-5">
        <CardTitle icon={IconStack2} iconClass="text-accent">Processing Pipeline</CardTitle>
        <Pipeline
          steps={[
            { icon: IconTruck, label: "Input Received", value: fmtT(t(() => true)), done: true },
            { icon: IconSettings, label: "Processing", value: fmtT(t((b) => b.status === "In Progress" || b.status === "Pending")), badge: <StatusBadge tone="success">In Progress</StatusBadge>, done: true },
            { icon: IconShieldCheck, label: "Quality Check", value: fmtT(t((b) => b.status === "Quality Check")), badge: <StatusBadge tone="pending">Pending</StatusBadge>, done: true },
            { icon: IconStack2, label: "Outputs Generated", value: fmtT(passed) },
          ]}
        />
      </Card>

      <div className="grid items-start gap-5 xl:grid-cols-[1fr_420px]">
        <Card className="pt-5">
          <div className="flex flex-wrap items-center justify-between gap-3 px-5">
            <CardTitle icon={IconBox} iconClass="text-accent">Batches</CardTitle>
            <FilterSelect label="All statuses" options={["Pending", "In Progress", "Quality Check", "Completed", "Rejected"]} value={status} onChange={setStatus} />
          </div>
          <div className="mt-4 px-2">
            {page.length === 0 ? (
              <Empty>No batches with this status.</Empty>
            ) : (
              <table className="w-full text-left text-sm">
                <TH cols={["Batch ID", "Mineral", "Input", "Progress", "Status", ""]} />
                <tbody>
                  {page.map((b) => (
                    <tr key={b.id} className="border-b border-gray-100 last:border-0">
                      <td className="px-3 py-3 font-medium">{b.id}<span className="block text-xs font-normal text-ink/60">{b.lotId}</span></td>
                      <td className="px-3">{b.mineral}</td>
                      <td className="px-3">{fmtT(b.inputT)}{b.outputT !== undefined && <span className="block text-xs text-ink/60">out {fmtT(b.outputT)}</span>}</td>
                      <td className="px-3"><Progress value={b.progress} /></td>
                      <td className="px-3"><StatusBadge tone={batchTone[b.status]}>{b.status}</StatusBadge></td>
                      <td className="px-3 text-right">
                        {(b.status === "Pending" || b.status === "In Progress") && (
                          <button onClick={() => (advanceBatch(b), toast(`${b.id} updated`))} className="inline-flex items-center gap-1 rounded-full border border-gray-200 px-3 py-1.5 text-xs font-medium hover:bg-page">
                            <IconPlayerPlay className="size-3.5" /> {b.status === "Pending" ? "Start" : "Record progress"}
                          </button>
                        )}
                        {b.status === "Quality Check" && (
                          <RowMenu
                            items={[
                              { label: "Pass quality check", icon: IconCircleCheck, onClick: withConfirm({ title: "Pass quality check?", message: `${b.id} output (about ${fmtT(b.inputT * 0.96)}) becomes ready for the refinery.`, confirmLabel: "Pass" }, () => (advanceBatch(b, true), toast(`${b.id} passed`))) },
                              { label: "Reject batch", icon: IconX, danger: true, onClick: withConfirm({ title: "Reject batch?", message: `${b.id} failed quality check and goes no further.`, confirmLabel: "Reject", tone: "danger" }, () => (advanceBatch(b, false), toast(`${b.id} rejected`, "info"))) },
                            ]}
                          />
                        )}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            )}
          </div>
          <Pagination {...pager} noun="batches" />
        </Card>

        <div className="space-y-5">
          <Card className="p-5">
            <CardTitle icon={IconShieldCheck} iconClass="text-accent">Quality Overview</CardTitle>
            <DonutLegend center={`${passRate}%`} sub="Pass rate" segments={[{ label: `Passed · ${fmtT(passed)}`, value: passed, color: GREEN }, { label: `Rejected · ${fmtT(rejected)}`, value: rejected, color: ORANGE }]} />
          </Card>
          <ActivityFeed area="processing" />
        </div>
      </div>

      {open && <NewBatchModal onClose={() => setOpen(false)} />}
    </>
  );
}
