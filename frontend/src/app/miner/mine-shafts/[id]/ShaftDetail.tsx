"use client";

import Link from "next/link";
import { withConfirm } from "@/components/ui/Confirm";
import { useParams } from "next/navigation";
import { useState } from "react";
import { IconClipboardList, IconPick, IconPlus, IconShieldCheck, IconTool } from "@tabler/icons-react";
import { Card, CardTitle, Empty, PrimaryButton, StatusBadge, statusTone, toast } from "@/components/ui";
import { DetailHeader, Facts, NotFound } from "@/components/DetailShell";
import { NewRecordModal } from "@/components/forms";
import { fmtKg, type ShaftStatus } from "@/lib/data";
import { siteName, update, useStore } from "@/lib/store";

export function ShaftDetail() {
  const { id } = useParams<{ id: string }>();
  const state = useStore((s) => s);
  const [adding, setAdding] = useState(false);
  const shaft = state.shafts.find((s) => s.id === id);
  if (!shaft) return <NotFound what="Shaft" id={id} back="/miner/mine-shafts" backLabel="Mine Shafts" />;

  const records = state.records.filter((r) => r.shaftId === shaft.id);
  const inspections = state.inspections.filter((i) => i.shaft === shaft.name);
  const total = records.filter((r) => r.status === "Approved").reduce((n, r) => n + r.quantityKg, 0);
  const setStatus = (status: ShaftStatus) => {
    update((s) => ({ shafts: s.shafts.map((x) => (x.id === shaft.id ? { ...x, status } : x)) }));
    toast(`${shaft.name} set to ${status}`, "info");
  };

  return (
    <>
      <DetailHeader
        back="/miner/mine-shafts"
        backLabel="Mine Shafts"
        title={shaft.name}
        badge={<StatusBadge tone={statusTone(shaft.status)}>{shaft.status}</StatusBadge>}
        subtitle={<><Link href={`/miner/mining-sites/${shaft.siteId}`} className="hover:underline">{siteName(state, shaft.siteId)}</Link> · {shaft.mineral} · {shaft.depthM} m deep</>}
        actions={
          <>
            {(["Operational", "Maintenance", "Closed"] as ShaftStatus[])
              .filter((s) => s !== shaft.status)
              .map((s) => (
                <button key={s} onClick={withConfirm({ title: `Mark ${s.toLowerCase()}?`, message: `${shaft.name} will be set to ${s}.`, confirmLabel: "Confirm", tone: s === "Closed" ? "danger" : "primary" }, () => setStatus(s))} className="inline-flex items-center gap-2 rounded-2xl border border-gray-200 bg-white px-4 py-3 text-[15px] hover:bg-page">
                  <IconTool className="size-5" /> Mark {s.toLowerCase()}
                </button>
              ))}
            <PrimaryButton icon={IconPlus} disabled={shaft.status === "Closed"} onClick={() => setAdding(true)} className="disabled:opacity-50">New record</PrimaryButton>
          </>
        }
      />

      <Card className="p-5">
        <CardTitle icon={IconPick} iconClass="text-[#1F5B3A]">Shaft</CardTitle>
        <div className="mt-5">
          <Facts
            cols={4}
            items={[
              ["Shaft ID", shaft.id],
              ["Mineral", shaft.mineral],
              ["Depth", `${shaft.depthM} m`],
              ["Last inspection", shaft.lastInspection],
              ["Approved extraction", fmtKg(total)],
              ["Records", records.length],
              ["Site", siteName(state, shaft.siteId)],
              ["Status", shaft.status],
            ]}
          />
        </div>
      </Card>

      <div className="grid items-start gap-5 xl:grid-cols-[1fr_380px]">
        <Card className="pt-5">
          <div className="px-5"><CardTitle icon={IconClipboardList} iconClass="text-[#B5551A]">Extraction records</CardTitle></div>
          <div className="mt-4 overflow-x-auto px-2 pb-4">
            {records.length === 0 ? (
              <Empty>No extraction records for this shaft yet.</Empty>
            ) : (
              <table className="w-full text-left text-sm">
                <thead className="bg-head"><tr>{["Record", "Mineral", "Quantity", "Date", "Status"].map((h) => <th key={h} className="px-3 py-3 text-[13px] font-medium">{h}</th>)}</tr></thead>
                <tbody>
                  {records.map((r) => (
                    <tr key={r.id} className="border-b border-gray-100 last:border-0">
                      <td className="px-3 py-3">{r.id}</td>
                      <td className="px-3">{r.mineral}</td>
                      <td className="px-3">{fmtKg(r.quantityKg)}</td>
                      <td className="px-3">{r.date}</td>
                      <td className="px-3"><StatusBadge tone={statusTone(r.status)}>{r.status}</StatusBadge></td>
                    </tr>
                  ))}
                </tbody>
              </table>
            )}
          </div>
        </Card>
        <Card className="self-start p-5">
          <CardTitle icon={IconShieldCheck}>Inspections</CardTitle>
          <ul className="mt-4 space-y-2 text-sm">
            {inspections.map((i) => (
              <li key={i.id}>
                <Link href={`/miner/inspections/${i.id}`} className="flex justify-between rounded-xl px-2 py-1.5 hover:bg-page">
                  <span>{i.id} · {i.type}</span>
                  <StatusBadge tone={statusTone(i.status)}>{i.status}</StatusBadge>
                </Link>
              </li>
            ))}
            {inspections.length === 0 && <li className="text-ink/60">No inspections at this shaft.</li>}
          </ul>
        </Card>
      </div>

      {adding && <NewRecordModal siteId={shaft.siteId} onClose={() => setAdding(false)} />}
    </>
  );
}
