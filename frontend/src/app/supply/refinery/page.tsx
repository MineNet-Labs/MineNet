"use client";

import { useState } from "react";
import { IconBox, IconBuildingFactory2, IconChartLine, IconCertificate, IconFileText, IconFlask, IconPlayerPlay, IconPlus, IconShieldCheck, IconStack2, IconTruck } from "@tabler/icons-react";
import { CancelButton, Card, CardTitle, DateRange, Empty, Field, Modal, PageHeader, Pagination, PrimaryButton, StatusBadge, SubmitButton, ViewAll, formValues, inputClass, toast, usePaged } from "@/components/ui";
import { AreaChart } from "@/components/ui/charts";
import { ActivityFeed, DonutLegend, GREEN, GREY, ORANGE, Pipeline, Progress, QuickActions, TH, fmtT, refTone } from "@/components/supply/common";
import { StartRefiningModal } from "@/components/supply/forms";
import { downloadCSV } from "@/lib/csv";
import { useStore } from "@/lib/store";
import { advanceRefining, type RefBatch } from "@/lib/supply";

export default function RefineryPage() {
  const refinery = useStore((s) => s.refinery);
  const [modal, setModal] = useState<null | "start" | RefBatch>(null);
  const { rows: page, pager } = usePaged(refinery, 6);
  const stage = (k: RefBatch["stage"]) => refinery.filter((r) => r.stage === k).length;
  const refined = refinery.filter((r) => r.purity);
  const avg = refined.length ? Math.round((refined.reduce((n, r) => n + (r.purity ?? 0), 0) / refined.length) * 10) / 10 : 0;
  const band = (lo: number, hi: number) => refined.filter((r) => (r.purity ?? 0) >= lo && (r.purity ?? 0) < hi).length;
  const badge = (n: number, label: string) => <StatusBadge tone={n ? "success" : "neutral"}>{n} {label}</StatusBadge>;

  return (
    <>
      <PageHeader title="Refinery" subtitle="Manage refinery intake, refining operations and outputs." actions={<><DateRange label="Last 30 days" /><PrimaryButton icon={IconPlus} onClick={() => setModal("start")}>Start batch</PrimaryButton></>} />

      <div className="grid items-start gap-5 xl:grid-cols-[1fr_440px]">
        <div className="min-w-0 space-y-5">
          <Card className="p-5">
            <CardTitle icon={IconBuildingFactory2} iconClass="text-accent">Refinery Workflow</CardTitle>
            <Pipeline
              steps={[
                { icon: IconTruck, label: "Intake Received", badge: badge(stage("Intake"), "waiting"), done: true },
                { icon: IconFlask, label: "Refining Process", badge: badge(stage("Refining"), "in progress"), active: true },
                { icon: IconShieldCheck, label: "Quality Testing", badge: badge(stage("Quality Testing"), "testing") },
                { icon: IconBox, label: "Refined Lots", badge: badge(stage("Refined"), "refined") },
              ]}
            />
          </Card>
          <Card className="pt-5">
            <div className="px-5">
              <CardTitle icon={IconStack2} iconClass="text-accent">Refining Batches</CardTitle>
            </div>
            <div className="mt-4 px-2">
              {page.length === 0 ? (
                <Empty>No refining batches yet.</Empty>
              ) : (
                <table className="w-full text-left text-sm">
                  <TH cols={["Batch ID", "Input Lot", "Mineral", "Quantity", "Progress", "Stage", ""]} />
                  <tbody>
                    {page.map((r) => (
                      <tr key={r.id} className="border-b border-gray-100 last:border-0">
                        <td className="px-3 py-3 font-medium">{r.id}<span className="block text-xs font-normal text-ink/60">from {r.batchId}</span></td>
                        <td className="px-3">{r.lotId}</td>
                        <td className="px-3">{r.mineral}</td>
                        <td className="px-3">{fmtT(r.qtyT)}</td>
                        <td className="px-3"><Progress value={r.stage === "Intake" ? 0 : r.progress} /></td>
                        <td className="px-3"><StatusBadge tone={refTone[r.stage]}>{r.stage}{r.purity ? ` · ${r.purity}%` : ""}</StatusBadge></td>
                        <td className="px-3 text-right">
                          {r.stage === "Quality Testing" ? (
                            <button onClick={() => setModal(r)} className="rounded-full bg-[#1F5B3A] px-3 py-1.5 text-xs font-medium text-white">Record results</button>
                          ) : r.stage !== "Refined" ? (
                            <button onClick={() => (advanceRefining(r), toast(`${r.id} updated`))} className="inline-flex items-center gap-1 rounded-full border border-gray-200 px-3 py-1.5 text-xs font-medium hover:bg-page">
                              <IconPlayerPlay className="size-3.5" /> {r.stage === "Intake" ? "Start refining" : "Record progress"}
                            </button>
                          ) : null}
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              )}
            </div>
            <Pagination {...pager} noun="batches" />
          </Card>
        <ActivityFeed area="refinery" />
        </div>
        <div className="min-w-0 space-y-5">
          <Card className="p-5">
            <CardTitle icon={IconChartLine} iconClass="text-accent">Refinery Performance</CardTitle>
            <div className="mt-2 flex gap-4 text-sm">
              <span className="flex items-center gap-1.5"><i className="size-2.5 rounded-full bg-[#1F5B3A]" />Output (t)</span>
              <span className="flex items-center gap-1.5"><i className="size-2.5 rounded-full bg-accent" />Quality yield (t)</span>
            </div>
            <AreaChart height={170} live={false} xLabels={["Jan", "Feb", "Mar", "Apr", "May", "Jun"]} series={[{ color: GREEN, values: [22, 26, 27, 28, 27, 31] }, { color: ORANGE, values: [19, 22, 24, 25, 24, 28] }]} unit=" t" />
          </Card>
          <div className="space-y-5">
            <Card className="p-5">
              <CardTitle icon={IconShieldCheck} iconClass="text-accent" action={<ViewAll href="/supply/reports/processing" label="View Report" />}>Quality Overview</CardTitle>
              <DonutLegend center={`${avg}%`} sub="Avg purity" segments={[{ label: "≥ 99%", value: band(99, 101), color: GREEN }, { label: "95 – 99%", value: band(95, 99), color: ORANGE }, { label: "< 95%", value: band(0, 95), color: GREY }]} />
            </Card>
            <QuickActions
              items={[
                { icon: IconFlask, label: "Start Batch", onClick: () => setModal("start") },
                { icon: IconFileText, label: "Record Results", onClick: () => { const r = refinery.find((x) => x.stage === "Quality Testing"); if (r) setModal(r); else toast("No batch is waiting for test results", "info"); } },
                { icon: IconCertificate, label: "View Certificates", href: "/supply/reports?tab=Documents" },
                { icon: IconBox, label: "Export Outputs", onClick: () => (downloadCSV("refined-outputs", refined, [["Batch", (r) => r.id], ["Lot", (r) => r.lotId], ["Mineral", (r) => r.mineral], ["Tonnes", (r) => r.qtyT], ["Purity %", (r) => r.purity]]), toast("Refined outputs exported")) },
              ]}
            />
          </div>
        </div>
      </div>

      {modal === "start" && <StartRefiningModal onClose={() => setModal(null)} />}
      {modal && typeof modal === "object" && (
        <Modal title={`Test results · ${modal.id}`} subtitle={`${modal.mineral} · ${fmtT(modal.qtyT)} from ${modal.lotId}`} onClose={() => setModal(null)} footer={<><CancelButton onClick={() => setModal(null)} /><SubmitButton form="purity-form">Save results</SubmitButton></>}>
          <form
            id="purity-form"
            onSubmit={(e) => {
              const v = formValues(e);
              advanceRefining(modal, Number(v.purity));
              toast(`${modal.id} refined at ${v.purity}%`);
              setModal(null);
            }}
          >
            <Field label="Measured purity (%)" hint="From the assay certificate."><input name="purity" type="number" step="0.01" min={50} max={100} required className={inputClass} /></Field>
          </form>
        </Modal>
      )}
    </>
  );
}
