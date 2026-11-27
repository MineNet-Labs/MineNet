"use client";

import Link from "next/link";
import { useRouter, useSearchParams } from "next/navigation";
import { useState } from "react";
import { IconBox, IconBuildingFactory2, IconChartBar, IconCheck, IconClock, IconDownload, IconFileText, IconPick, IconSearch, IconSettings, IconShieldCheck, IconShip, IconTruck, type Icon as TablerIcon } from "@tabler/icons-react";
import { Card, CardTitle, Empty, PageHeader, StatusBadge, toast } from "@/components/ui";
import { MineralThumb } from "@/components/ui";
import { downloadFile } from "@/lib/csv";
import { useStore } from "@/lib/store";
import { traceLot } from "@/lib/supply";

const ICON: Record<string, TablerIcon> = { mining: IconPick, logistics: IconTruck, processing: IconSettings, refinery: IconBuildingFactory2, export: IconShip };

export default function TraceabilityPage() {
  const router = useRouter();
  const q = useSearchParams();
  const state = useStore((s) => s);
  const lotId = q.get("lot") ?? "LOT-2026-00481";
  const [input, setInput] = useState(lotId);
  const [seen, setSeen] = useState(lotId);
  if (seen !== lotId) {
    setSeen(lotId);
    setInput(lotId);
  }
  const t = traceLot(state, lotId);
  const docs = t
    ? [
        ...(t.decl ? [{ name: "Export Declaration", ref: t.decl.id, size: "245 KB" }] : []),
        ...(t.decl && (t.decl.status === "Cleared" || t.decl.status === "Exported") ? [{ name: "Certificate of Origin", ref: t.decl.id.replace("EXP", "COO"), size: "180 KB" }] : []),
        ...(t.ref?.purity ? [{ name: "Assay Certificate", ref: t.ref.id, size: "96 KB" }] : []),
      ]
    : [];

  return (
    <>
      <PageHeader crumb={{ icon: IconShip, label: "Export" }} title="Traceability" subtitle="Follow the complete journey of any mineral from origin to destination." />

      <form
        className="flex gap-3"
        onSubmit={(e) => {
          e.preventDefault();
          if (input.trim()) router.push(`/supply/traceability?lot=${encodeURIComponent(input.trim().toUpperCase())}`);
        }}
      >
        <label className="flex h-11 flex-1 items-center gap-3 rounded-2xl bg-white px-4 shadow-[0_2px_12px_rgba(17,24,39,0.05)]">
          <IconSearch className="size-5 text-ink/60" />
          <input value={input} onChange={(e) => setInput(e.target.value)} placeholder="Enter Mineral Lot ID (e.g. LOT-2026-00481)" aria-label="Mineral lot ID" className="min-w-0 flex-1 bg-transparent text-[15px] outline-none" />
        </label>
        <button type="submit" className="rounded-full bg-[#1F5B3A] px-8 font-medium text-white hover:bg-primary">Track</button>
      </form>

      {!t ? (
        <Card className="p-5"><Empty>No records found for {lotId}. Check the lot ID, or pick one from Inventory.</Empty></Card>
      ) : (
        <>
          <div className="grid grid-cols-1 gap-5 sm:grid-cols-5">
            {t.stages.map((s) => {
              const Icon = ICON[s.key];
              const current = !s.done && t.stages.filter((x) => x.done).length === t.stages.indexOf(s);
              return (
                <Link key={s.key} href={s.href} className={`relative rounded-2xl border px-3 py-2.5 text-center ${current || (s.key === "export" && s.done) ? "border-[#1F5B3A] bg-primary-soft" : "border-transparent bg-white"} shadow-[0_4px_24px_rgba(17,24,39,0.04)]`}>
                  <Icon className={`mx-auto size-5 ${s.done ? "text-[#1F5B3A]" : "text-ink/40"}`} />
                  <p className="mt-1 text-sm font-medium">{s.label}</p>
                  <p className="text-xs text-ink/60">{s.date ?? (s.done ? "Done" : "Not yet")}</p>
                  {s.done && <span className="absolute top-2 right-2 grid size-4 place-items-center rounded-full bg-[#1F5B3A] text-white"><IconCheck className="size-3" stroke={3} /></span>}
                </Link>
              );
            })}
          </div>

          <div className="grid items-start gap-5 xl:grid-cols-[420px_1fr]">
        <div className="min-w-0 space-y-5">
              <Card className="p-5">
                <CardTitle icon={IconBox} iconClass="text-accent">Mineral Details</CardTitle>
                <div className="mt-4 flex items-center gap-4">
                  <MineralThumb size={52} />
                  <div>
                    <p className="font-semibold">{t.id}</p>
                    <StatusBadge tone={t.complete ? "success" : "pending"} icon={t.complete ? IconCheck : IconClock}>{t.complete ? "Exported" : t.stages.find((s) => !s.done)?.label}</StatusBadge>
                    <p className="mt-1 text-ink/70">{t.mineral} · {t.qtyKg} kg{t.destination ? ` · ${t.destination}` : ""}</p>
                  </div>
                </div>
                <dl className="mt-4 space-y-2 border-t border-gray-100 pt-3 text-sm">
                  {[["Origin", t.origin], ["Shipment", t.ship[0]?.id], ["Processing Batch", t.batch?.id], ["Refinery Batch", t.ref?.id], ["Export Declaration", t.decl?.id]].map(([k, v]) => (
                    <div key={k} className="flex justify-between gap-4"><dt className="text-ink/70">{k}</dt><dd className="font-medium">{v ?? "—"}</dd></div>
                  ))}
                </dl>
                <div className={`mt-4 flex items-start gap-3 rounded-2xl p-3 ${t.complete && !t.discrepancies ? "bg-primary-soft" : "bg-accent-soft"}`}>
                  <IconShieldCheck className={`size-6 shrink-0 ${t.complete && !t.discrepancies ? "text-[#1F5B3A]" : "text-accent"}`} />
                  <p className="text-sm">
                    <b className="block font-medium">{t.complete && !t.discrepancies ? "Full traceability verified" : t.discrepancies ? "Discrepancy on record" : "Journey in progress"}</b>
                    {t.complete && !t.discrepancies ? "This lot has a complete and verified history." : t.discrepancies ? "One of the stages flagged a problem. Check the timeline." : "Stages still to come are shown as pending."}
                  </p>
                </div>
              </Card>
              <Card className="p-5">
                <CardTitle icon={IconFileText} iconClass="text-accent">Related Records</CardTitle>
                <div className="mt-4 grid grid-cols-2 gap-3 text-center text-sm">
                  {t.stages.filter((s) => s.ref && s.key !== "mining").map((s) => {
                    const Icon = ICON[s.key];
                    return (
                      <Link key={s.key} href={s.href} className="rounded-2xl border border-gray-100 p-2.5 hover:bg-page">
                        <Icon className="mx-auto size-5 text-[#1F5B3A]" />
                        <b className="mt-1 block font-medium">{s.label}</b>
                        <span className="text-xs text-ink/60">{s.ref}</span>
                      </Link>
                    );
                  })}
                </div>
              </Card>
              <Card className="p-5">
                <CardTitle icon={IconChartBar} iconClass="text-accent">Quick Insights</CardTitle>
                <div className="mt-5 grid grid-cols-3 gap-3 text-center">
                  <div><b className="block text-2xl font-semibold text-[#1F5B3A]">{Math.round((t.stages.filter((s) => s.done).length / t.stages.length) * 100)}%</b><span className="text-sm text-ink/70">Traceability</span></div>
                  <div><b className="block text-2xl font-semibold">{t.stages.length}</b><span className="text-sm text-ink/70">Total stages</span></div>
                  <div><b className={`block text-2xl font-semibold ${t.discrepancies ? "text-danger" : ""}`}>{t.discrepancies}</b><span className="text-sm text-ink/70">Discrepancies</span></div>
                </div>
              </Card>
        </div>
        <div className="min-w-0 space-y-5">
              <Card className="p-5">
                <CardTitle icon={IconClock} iconClass="text-accent">Journey Timeline</CardTitle>
                <ol className="mt-4 space-y-3 border-l-2 border-gray-100 pl-6">
                  {t.stages.map((s) => {
                    const Icon = ICON[s.key];
                    return (
                      <li key={s.key} className="relative flex flex-wrap items-center justify-between gap-3">
                        <i className={`absolute top-2.5 -left-[31px] size-3 rounded-full border-2 border-[#1F5B3A] ${s.done ? "bg-[#1F5B3A]" : "bg-white"}`} />
                        <span className="flex items-center gap-3">
                          <span className="grid size-8 place-items-center rounded-full bg-primary-soft text-[#1F5B3A]"><Icon className="size-4" /></span>
                          <span className="text-sm"><b className="block font-medium">{s.label}</b><span className="text-xs text-ink/70">{s.detail}</span></span>
                        </span>
                        <span className="flex items-center gap-3 text-sm text-ink/60">{s.date ?? "—"}<StatusBadge tone={s.done ? "success" : "neutral"}>{s.done ? "Completed" : "Pending"}</StatusBadge></span>
                      </li>
                    );
                  })}
                </ol>
              </Card>
              <Card className="p-5">
                <CardTitle icon={IconFileText} iconClass="text-accent">Export Documents</CardTitle>
                <ul className="mt-4 space-y-3">
                  {docs.map((d) => (
                    <li key={d.name} className="flex items-center justify-between gap-3 rounded-2xl border border-gray-100 p-3">
                      <span><b className="block font-medium">{d.name}</b><span className="text-xs text-ink/60">{d.ref} · PDF · {d.size}</span></span>
                      <button aria-label={`Download ${d.name}`} onClick={() => (downloadFile(`${d.ref}.txt`, `${d.name}\nReference: ${d.ref}\nLot: ${t.id}\nMineral: ${t.mineral}\nOrigin: ${t.origin}`), toast(`${d.name} downloaded`))} className="grid size-9 place-items-center rounded-full border border-gray-200 hover:bg-page">
                        <IconDownload className="size-4" />
                      </button>
                    </li>
                  ))}
                  {docs.length === 0 && <li className="text-sm text-ink/60">Documents appear once the lot is declared for export.</li>}
                </ul>
              </Card>
        </div>
      </div>
        </>
      )}
    </>
  );
}
