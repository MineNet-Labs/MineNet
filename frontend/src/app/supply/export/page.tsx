"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useState } from "react";
import { IconArrowRight, IconBox, IconChartBar, IconCircleCheck, IconFileText, IconMapPin, IconPlus, IconRoute, IconSearch, IconShieldCheck, IconShip, IconTruck, IconWorld } from "@tabler/icons-react";
import { Card, CardTitle, DateRange, Empty, FilterSelect, PageHeader, Pagination, PrimaryButton, RowMenu, StatusBadge, ViewAll, toast, usePaged } from "@/components/ui";
import { ActivityFeed, DonutLegend, GREEN, GREY, ORANGE, Pipeline, QuickActions, ShareBars, TH, declTone, kg } from "@/components/supply/common";
import { NewDeclarationModal } from "@/components/supply/forms";
import { downloadFile } from "@/lib/csv";
import { useStore } from "@/lib/store";
import { type DeclStatus, type ExportDecl } from "@/lib/supply";

const certificate = (d: ExportDecl) =>
  downloadFile(`${d.id}-declaration.txt`, `EXPORT DECLARATION ${d.id}\n\nLot: ${d.lotId}\nMineral: ${d.mineral}\nQuantity: ${d.qtyKg} kg\nDestination: ${d.destination}\nBuyer: ${d.buyer}\nStatus: ${d.status}\nSubmitted: ${d.submitted}\n\nTraceability: every stage of ${d.lotId} is recorded on MineNet.`);

export default function ExportPage() {
  const router = useRouter();
  const decls = useStore((s) => s.declarations);
  const [status, setStatus] = useState("");
  const [open, setOpen] = useState(false);
  const rows = decls.filter((d) => !status || d.status === status);
  const { rows: page, pager } = usePaged(rows, 6);
  const n = (...st: DeclStatus[]) => decls.filter((d) => st.includes(d.status)).length;
  const dest = [...new Set(decls.map((d) => d.destination))].map((label) => ({ label, value: decls.filter((d) => d.destination === label).reduce((t, d) => t + d.qtyKg, 0) })).sort((a, b) => b.value - a.value);

  return (
    <>
      <PageHeader crumb={{ icon: IconShip, label: "Export" }} title="Export" subtitle="Manage export declarations, customs clearance and international shipments." actions={<><DateRange label="Last 30 days" /><PrimaryButton icon={IconPlus} onClick={() => setOpen(true)}>New Export Declaration</PrimaryButton></>} />

      <div className="grid items-start gap-5 xl:grid-cols-[1fr_440px]">
        <div className="min-w-0 space-y-5">
          <Card className="p-5">
            <CardTitle icon={IconWorld} iconClass="text-accent">Export Pipeline</CardTitle>
            <Pipeline
              steps={[
                { icon: IconFileText, label: "Declaration Submitted", value: n("Submitted"), done: true },
                { icon: IconShieldCheck, label: "Under Review (Customs)", value: n("Under Review", "Requires Action") },
                { icon: IconCircleCheck, label: "Cleared", value: n("Cleared") },
                { icon: IconTruck, label: "Exported", value: n("Exported") },
              ]}
            />
          </Card>
          <Card className="pt-5">
            <div className="flex flex-wrap items-center justify-between gap-3 px-5">
              <CardTitle icon={IconBox} iconClass="text-accent">Export Declarations</CardTitle>
              <FilterSelect label="All statuses" options={["Draft", "Submitted", "Under Review", "Requires Action", "Cleared", "Exported"]} value={status} onChange={setStatus} />
            </div>
            <div className="mt-4 px-2">
              {page.length === 0 ? (
                <Empty>No declarations with this status.</Empty>
              ) : (
                <table className="w-full text-left text-sm">
                  <TH cols={["Declaration ID", "Mineral", "Quantity", "Destination", "Status", "Submitted", ""]} />
                  <tbody>
                    {page.map((d) => {
                      return (
                        <tr key={d.id} className="border-b border-gray-100 last:border-0">
                          <td className="px-3 py-3 font-medium"><Link href={`/supply/export/${d.id}`} className="hover:text-[#1F5B3A] hover:underline">{d.id}</Link><span className="block text-xs font-normal text-ink/60">{d.lotId}</span></td>
                          <td className="px-3">{d.mineral}</td>
                          <td className="px-3">{kg(d.qtyKg)}</td>
                          <td className="px-3">{d.destination}<span className="block text-xs text-ink/60">{d.buyer}</span></td>
                          <td className="px-3"><StatusBadge tone={declTone[d.status]}>{d.status}</StatusBadge></td>
                          <td className="px-3 text-ink/70">{d.submitted}</td>
                          <td className="px-3 text-right">
                            <RowMenu
                              items={[
                                { label: d.status === "Draft" || d.status === "Requires Action" ? "Open to complete" : "Open declaration", icon: IconArrowRight, onClick: () => router.push(`/supply/export/${d.id}`) },
                                { label: "Track lot", icon: IconRoute, onClick: () => router.push(`/supply/traceability?lot=${d.lotId}`) },
                                { label: "Download declaration", icon: IconFileText, onClick: () => (certificate(d), toast("Declaration downloaded")) },
                              ]}
                            />
                          </td>
                        </tr>
                      );
                    })}
                  </tbody>
                </table>
              )}
            </div>
            <Pagination {...pager} noun="declarations" />
          </Card>
        <ActivityFeed area="export" />
        </div>
        <div className="min-w-0 space-y-5">
          <Card className="p-5">
            <CardTitle icon={IconChartBar} iconClass="text-accent">Export Summary</CardTitle>
            <DonutLegend
              center={`${Math.round(((n("Cleared", "Exported")) / (decls.length || 1)) * 100)}%`}
              sub="Cleared"
              segments={[{ label: "Cleared", value: n("Cleared", "Exported"), color: GREEN }, { label: "Pending Review", value: n("Submitted", "Under Review", "Draft"), color: ORANGE }, { label: "Requires Action", value: n("Requires Action"), color: GREY }]}
            />
          </Card>
          <div className="space-y-5">
            <Card className="p-5">
              <CardTitle icon={IconMapPin} iconClass="text-accent" action={<ViewAll href="/supply/reports/export" label="View Report" />}>Exports by Destination</CardTitle>
              <ShareBars rows={dest} />
            </Card>
            <QuickActions
              items={[
                { icon: IconFileText, label: "Submit Declaration", onClick: () => setOpen(true) },
                { icon: IconSearch, label: "Track Export", href: "/supply/traceability" },
                { icon: IconShieldCheck, label: "Manage Certificates", href: "/supply/reports?tab=Documents" },
                { icon: IconBox, label: "View Export Records", href: "/supply/reports/export" },
              ]}
            />
          </div>
        </div>
      </div>

      {open && <NewDeclarationModal onClose={() => setOpen(false)} />}
    </>
  );
}
