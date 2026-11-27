"use client";

import { openForm } from "@/components/FormHost";

import Link from "next/link";
import { confirmAction } from "@/components/ui/Confirm";
import { useRouter } from "next/navigation";
import { useMemo, useState } from "react";
import { IconCalendarTime, IconCircleCheck, IconClipboardCheck, IconDownload, IconEye, IconHourglass, IconPlus, IconShieldCheck, IconX } from "@tabler/icons-react";
import {
  Card,
  Empty,
  FilterSelect,
  Initials,
  Modal,
  PageHeader,
  Pagination,
  PrimaryButton,
  RowMenu,
  StatCard,
  StatusBadge,
  toast,
  usePaged,
  type BadgeTone,
} from "@/components/ui";
import { Tabs } from "@/components/ui/Tabs";
import type { Inspection, InspectionStatus } from "@/lib/data";
import { siteName, update, useStore } from "@/lib/store";
import { downloadFile } from "@/lib/csv";

const tone: Record<InspectionStatus, BadgeTone> = {
  Pending: "pending",
  Scheduled: "info",
  "In Progress": "blue",
  Completed: "success",
  Rejected: "danger",
};
const tabs = ["All Requests", "Pending", "Scheduled", "In Progress", "Completed", "Rejected"];

export default function InspectionsPage() {
  const router = useRouter();
  const state = useStore((s) => s);
  const { inspections } = state;
  const [tab, setTab] = useState("All Requests");
  const [mineral, setMineral] = useState("");
  const [site, setSite] = useState("");
  const [type, setType] = useState("");
  const [view, setView] = useState<Inspection | null>(null);

  const rows = useMemo(
    () =>
      inspections.filter(
        (r) =>
          (tab === "All Requests" || r.status === tab) &&
          (!mineral || r.mineral === mineral) &&
          (!site || siteName(state, r.siteId) === site) &&
          (!type || r.type === type),
      ),
    [inspections, tab, mineral, site, type, state],
  );
  const { rows: page, pager } = usePaged(rows, 6);
  const count = (t: string) => (t === "All Requests" ? inspections.length : inspections.filter((r) => r.status === t).length);

  const cancel = async (r: Inspection) => {
    if (!(await confirmAction({ title: "Cancel inspection request?", message: `${r.id} for ${r.lotId} will be cancelled.`, confirmLabel: "Cancel request", tone: "danger" }))) return;
    update((s) => ({ inspections: s.inspections.filter((x) => x.id !== r.id) }));
    toast(`Request ${r.id} cancelled`, "info");
  };

  const certificate = (r: Inspection) => {
    downloadFile(
      `Certificate_${r.id}.txt`,
      `MINENET INSPECTION CERTIFICATE\n\nRequest: ${r.id}\nLot: ${r.lotId}\nMineral: ${r.mineral}\nSite: ${siteName(state, r.siteId)} · ${r.shaft}\nInspection type: ${r.type}\nInspector: ${r.inspector ?? "—"}\nResult: ${r.status}\nSubmitted: ${r.submitted}\n\n(Sample certificate — the official PDF comes from the inspection service.)`,
    );
    toast(`Certificate for ${r.id} downloaded`);
  };

  return (
    <>
      <PageHeader
        title="Inspections"
        subtitle="Request mineral inspections, follow their progress and access official results and certificates."
        actions={<PrimaryButton icon={IconPlus} className="rounded-full py-3.5" onClick={() => openForm("inspection")}>Request Inspection</PrimaryButton>}
      />

      <div className="grid grid-cols-2 gap-4 xl:grid-cols-4">
        <StatCard icon={IconClipboardCheck} tone="orange" label="Total Requests" value={inspections.length} delta="+4" spark={[3, 4, 3.5, 6, 5, 7, 9]} />
        <StatCard icon={IconCircleCheck} tone="green" label="Completed" value={count("Completed")} delta="+12%" spark={[3, 4, 3.5, 5, 5.5, 7, 9]} />
        <StatCard icon={IconCalendarTime} tone="violet" label="Scheduled" value={count("Scheduled")} delta="+2" spark={[3, 4, 3, 6, 5, 6.5, 8]} />
        <StatCard icon={IconHourglass} tone="orange" label="Awaiting Review" value={count("Pending") + count("In Progress")} delta="-1" deltaDir="down" deltaClass="text-danger" spark={[3, 4, 3, 6, 4, 6.5, 4.5]} />
      </div>

      <Card className="overflow-hidden pt-6">
        <div className="flex flex-wrap items-center justify-between gap-3 px-6">
          <h3 className="flex items-center gap-3 font-sans text-lg font-semibold"><IconShieldCheck className="size-5 text-accent" /> Inspection Requests</h3>
          <div className="flex gap-2">
            <FilterSelect label="All minerals" options={[...new Set(inspections.map((i) => i.mineral))]} value={mineral} onChange={setMineral} />
            <FilterSelect label="All mining sites" options={[...new Set(inspections.map((i) => siteName(state, i.siteId)))]} value={site} onChange={setSite} />
            <FilterSelect label="All types" options={[...new Set(inspections.map((i) => i.type))]} value={type} onChange={setType} />
          </div>
        </div>

        <div className="mt-4 border-b border-gray-100 px-7">
          <Tabs items={tabs.map((t) => ({ key: t, label: t, count: count(t) }))} value={tab} onChange={setTab} />
        </div>

        <div className="overflow-x-auto px-3">
          {page.length === 0 ? (
            <Empty>No inspection requests match these filters.</Empty>
          ) : (
            <table className="w-full text-left text-sm">
              <thead className="bg-head">
                <tr>
                  {["Request ID", "Mineral Lot", "Mining Site", "Mine Shaft", "Submitted", "Inspection Type", "Assigned Inspector", "Status", ""].map((h, i) => (
                    <th key={i} className="px-4 py-3.5 text-[13px] font-medium">{h}</th>
                  ))}
                </tr>
              </thead>
              <tbody>
                {page.map((r) => (
                  <tr key={r.id} className="border-b border-gray-100">
                    <td className="px-4 py-4 font-semibold"><Link href={`/miner/inspections/${r.id}`} className="hover:text-[#1F5B3A] hover:underline">{r.id}</Link></td>
                    <td className="px-4"><p><Link href={`/miner/mineral-lots/${r.lotId}`} className="hover:underline">{r.lotId}</Link></p><p className="text-xs text-ink/60">{r.mineral}</p></td>
                    <td className="px-4"><Link href={`/miner/mining-sites/${r.siteId}`} className="hover:text-[#1F5B3A] hover:underline">{siteName(state, r.siteId)}</Link></td>
                    <td className="px-4">{r.shaft}</td>
                    <td className="px-4">{r.submitted}</td>
                    <td className="px-4">{r.type}</td>
                    <td className="px-4">
                      {r.inspector ? <span className="flex items-center gap-2"><Initials name={r.inspector} />{r.inspector}</span> : <span className="text-ink/60">Not yet assigned</span>}
                    </td>
                    <td className="px-4"><StatusBadge tone={tone[r.status]}>{r.status}</StatusBadge></td>
                    <td className="px-4 text-right">
                      <RowMenu
                        items={[
                          { label: "View details", icon: IconEye, onClick: () => router.push(`/miner/inspections/${r.id}`) },
                          ...(r.status === "Completed" ? [{ label: "Download certificate", icon: IconDownload, onClick: () => certificate(r) }] : []),
                          ...(r.status === "Pending" ? [{ label: "Cancel request", icon: IconX, danger: true, onClick: () => cancel(r) }] : []),
                        ]}
                      />
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </div>
        <Pagination {...pager} noun="requests" />
      </Card>

      {view && (
        <Modal title={`Inspection ${view.id}`} subtitle={view.type} onClose={() => setView(null)}>
          <dl className="grid grid-cols-2 gap-4 text-sm">
            {[
              ["Mineral lot", `${view.lotId} · ${view.mineral}`],
              ["Mining site", siteName(state, view.siteId)],
              ["Mine shaft", view.shaft],
              ["Submitted", view.submitted],
              ["Inspector", view.inspector ?? "Not yet assigned"],
              ["Status", view.status],
            ].map(([k, v]) => <div key={k}><dt className="text-ink/60">{k}</dt><dd className="font-medium">{v}</dd></div>)}
          </dl>
        </Modal>
      )}
    </>
  );
}
