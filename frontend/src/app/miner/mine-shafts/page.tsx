"use client";

import Link from "next/link";
import { useMemo, useState } from "react";
import { IconBuildingFactory2, IconCircleCheck, IconDownload, IconLock, IconPick, IconPlus, IconRuler, IconTool, IconPlayerPlay } from "@tabler/icons-react";
import {
  Card,
  CardTitle,
  Empty,
  FilterSelect,
  PageHeader,
  Pagination,
  PrimaryButton,
  RowMenu,
  StatCard,
  StatusBadge,
  statusTone,
  toast,
  usePaged,
} from "@/components/ui";
import { AddShaftModal } from "@/components/forms";
import type { ShaftStatus } from "@/lib/data";
import { siteName, update, useStore } from "@/lib/store";
import { downloadCSV } from "@/lib/csv";

const shaftTone = (s: ShaftStatus) => statusTone(s === "Maintenance" ? "pending" : s);

export default function MineShaftsPage() {
  const state = useStore((s) => s);
  const { shafts, records, sites } = state;
  const [site, setSite] = useState("");
  const [status, setStatus] = useState("");
  const [open, setOpen] = useState(false);

  const rows = useMemo(
    () => shafts.filter((s) => (!site || siteName(state, s.siteId) === site) && (!status || s.status === status)),
    [shafts, site, status, state],
  );
  const { rows: page, pager } = usePaged(rows, 8);
  const output = (id: string) => records.filter((r) => r.shaftId === id && r.status === "Approved").reduce((t, r) => t + r.quantityKg, 0);

  const setStatusOf = (id: string, s: ShaftStatus) => {
    update((st) => ({ shafts: st.shafts.map((x) => (x.id === id ? { ...x, status: s } : x)) }));
    toast(`Shaft ${id} set to ${s.toLowerCase()}`, "info");
  };

  const count = (s: ShaftStatus) => shafts.filter((x) => x.status === s).length;
  const avgDepth = Math.round(shafts.reduce((t, s) => t + s.depthM, 0) / Math.max(1, shafts.length));

  return (
    <>
      <PageHeader
        title="Mine Shafts"
        subtitle="Monitor shaft status, depth and output across all your sites."
        actions={<PrimaryButton icon={IconPlus} onClick={() => setOpen(true)}>Add Shaft</PrimaryButton>}
      />

      <div className="grid grid-cols-2 gap-5 xl:grid-cols-4">
        <StatCard icon={IconPick} tone="orange" label="Total Shafts" value={shafts.length} delta="+1" spark={[3, 3.5, 4, 4, 5, 5.5, 7]} />
        <StatCard icon={IconCircleCheck} tone="green" label="Operational" value={count("Operational")} delta="+1" spark={[3, 4, 3.5, 5, 5, 6, 8]} />
        <StatCard icon={IconTool} tone="orange" label="Under Maintenance" value={count("Maintenance")} delta="0" deltaDir="none" deltaClass="text-ink/70" spark={[3, 4, 3, 4, 3.5, 4, 4]} />
        <StatCard icon={IconRuler} tone="violet" label="Average Depth" value={`${avgDepth} m`} delta="+4 m" spark={[3, 3.2, 3.6, 4, 4.4, 4.8, 5.2]} />
      </div>

      <Card className="pt-6">
        <div className="flex flex-wrap items-center justify-between gap-3 px-6">
          <CardTitle icon={IconBuildingFactory2}>All Shafts</CardTitle>
          <div className="flex gap-2">
            <FilterSelect label="All sites" options={sites.map((s) => s.name)} value={site} onChange={setSite} />
            <FilterSelect label="All statuses" options={["Operational", "Maintenance", "Closed"]} value={status} onChange={setStatus} />
            <button
              aria-label="Export shafts"
              onClick={() => {
                downloadCSV("mine-shafts", rows, [
                  ["Shaft", (s) => s.name],
                  ["Site", (s) => siteName(state, s.siteId)],
                  ["Mineral", (s) => s.mineral],
                  ["Depth (m)", (s) => s.depthM],
                  ["Status", (s) => s.status],
                  ["Approved output (kg)", (s) => output(s.id)],
                  ["Last inspection", (s) => s.lastInspection],
                ]);
                toast(`${rows.length} shafts exported`);
              }}
              className="grid size-10 place-items-center rounded-full border border-gray-200 hover:bg-page"
            >
              <IconDownload className="size-4" />
            </button>
          </div>
        </div>
        <div className="mt-5 overflow-x-auto px-3">
          {page.length === 0 ? (
            <Empty>No shafts match these filters.</Empty>
          ) : (
            <table className="w-full text-left text-[15px] [&_td]:whitespace-nowrap">
              <thead className="bg-head">
                <tr>{["Shaft", "Mining site", "Mineral", "Depth", "Approved output", "Last inspection", "Status", ""].map((h, i) => <th key={i} className="px-4 py-3.5 text-[13px] font-medium">{h}</th>)}</tr>
              </thead>
              <tbody>
                {page.map((s) => (
                  <tr key={s.id} className="border-b border-gray-100">
                    <td className="px-4 py-3.5 font-semibold">{s.name}</td>
                    <td className="px-4"><Link href={`/miner/mining-sites/${s.siteId}`} className="hover:text-[#1F5B3A] hover:underline">{siteName(state, s.siteId)}</Link></td>
                    <td className="px-4">{s.mineral}</td>
                    <td className="px-4">{s.depthM} m</td>
                    <td className="px-4">{output(s.id).toLocaleString()} kg</td>
                    <td className="px-4 text-ink/70">{s.lastInspection}</td>
                    <td className="px-4"><StatusBadge tone={shaftTone(s.status)}>{s.status}</StatusBadge></td>
                    <td className="px-4 text-right">
                      <RowMenu
                        items={[
                          ...(s.status !== "Operational" ? [{ label: "Mark operational", icon: IconPlayerPlay, onClick: () => setStatusOf(s.id, "Operational") }] : []),
                          ...(s.status !== "Maintenance" ? [{ label: "Set under maintenance", icon: IconTool, onClick: () => setStatusOf(s.id, "Maintenance") }] : []),
                          ...(s.status !== "Closed" ? [{ label: "Close shaft", icon: IconLock, danger: true, onClick: () => setStatusOf(s.id, "Closed") }] : []),
                        ]}
                      />
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </div>
        <Pagination {...pager} noun="shafts" />
      </Card>

      {open && <AddShaftModal onClose={() => setOpen(false)} />}
    </>
  );
}
