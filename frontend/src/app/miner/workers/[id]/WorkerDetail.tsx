"use client";

import Link from "next/link";
import { withConfirm } from "@/components/ui/Confirm";
import { Select } from "@/components/ui/Select";
import { useParams } from "next/navigation";
import { IconCash, IconMapPin, IconPlayerPause, IconPlayerPlay, IconQrcode, IconUser } from "@tabler/icons-react";
import { Card, CardTitle, Empty, Initials, StatusBadge, statusTone, toast } from "@/components/ui";
import { DetailHeader, Facts, NotFound } from "@/components/DetailShell";
import { WORK_CATEGORIES, fmtNum, type Worker } from "@/lib/data";
import { siteName, update, useStore } from "@/lib/store";

export function WorkerDetail() {
  const { id } = useParams<{ id: string }>();
  const state = useStore((s) => s);
  const w = state.workers.find((x) => x.id === id);
  if (!w) return <NotFound what="Worker" id={id} back="/miner/workers" backLabel="Workers" />;

  const payments = state.txns.filter((t) => t.direction === "out" && t.party === w.name);
  const paid = payments.filter((t) => t.status === "Paid").reduce((n, t) => n + t.amount, 0);
  const set = (patch: Partial<Worker>, msg: string) => {
    update((s) => ({ workers: s.workers.map((x) => (x.id === w.id ? { ...x, ...patch } : x)) }));
    toast(msg, "info");
  };

  return (
    <>
      <DetailHeader
        back="/miner/workers"
        backLabel="Workers"
        title={<span className="flex items-center gap-4"><Initials name={w.name} className="size-12 text-base" />{w.name}</span>}
        badge={<StatusBadge tone={w.status === "Active" ? "success" : "neutral"}>{w.status}</StatusBadge>}
        subtitle={`${w.id} · ${w.category} · ${siteName(state, w.siteId)}`}
        actions={
          <>
            {w.access === "Setup pending" && (
              <button onClick={() => set({ access: "QR ready" }, `QR access code sent to ${w.name} (${w.phone})`)} className="inline-flex items-center gap-2 rounded-2xl bg-[#1F5B3A] px-4 py-3 text-[15px] font-medium text-white">
                <IconQrcode className="size-5" /> Send QR access code
              </button>
            )}
            {w.status === "Active" ? (
              <button onClick={withConfirm({ title: "Deactivate worker?", message: `${w.name} will lose site access until reactivated.`, confirmLabel: "Deactivate", tone: "danger" }, () => set({ status: "Inactive" }, `${w.name} deactivated`))} className="inline-flex items-center gap-2 rounded-2xl border border-gray-200 bg-white px-4 py-3 text-[15px] text-danger hover:bg-page">
                <IconPlayerPause className="size-5" /> Deactivate
              </button>
            ) : (
              <button onClick={() => set({ status: "Active" }, `${w.name} reactivated`)} className="inline-flex items-center gap-2 rounded-2xl border border-gray-200 bg-white px-4 py-3 text-[15px] hover:bg-page">
                <IconPlayerPlay className="size-5" /> Reactivate
              </button>
            )}
          </>
        }
      />

      <div className="grid items-start gap-5 xl:grid-cols-[1fr_380px]">
        <Card className="p-5">
          <CardTitle icon={IconUser} iconClass="text-[#1F5B3A]">Profile</CardTitle>
          <div className="mt-5">
            <Facts
              items={[
                ["Worker ID", w.id],
                ["Phone", w.phone],
                ["Joined", w.joined],
                ["Account access", w.access],
                ["Status", w.status],
                ["Site", <Link key="s" href={`/miner/mining-sites/${w.siteId}`} className="text-accent hover:underline">{siteName(state, w.siteId)}</Link>],
              ]}
            />
          </div>
          <div className="mt-6 grid grid-cols-2 gap-4 border-t border-gray-100 pt-5">
            <label className="space-y-2 text-sm">
              <span className="text-ink/60">Work category</span>
              <Select value={w.category} onChange={(e) => set({ category: e.target.value }, `${w.name} is now ${e.target.value}`)} className="h-11 w-full rounded-xl border border-gray-200 px-3">
                {WORK_CATEGORIES.map((c) => <option key={c}>{c}</option>)}
              </Select>
            </label>
            <label className="space-y-2 text-sm">
              <span className="flex items-center gap-1 text-ink/60"><IconMapPin className="size-4" /> Assigned site</span>
              <Select value={w.siteId} onChange={(e) => set({ siteId: e.target.value }, `${w.name} moved to ${siteName(state, e.target.value)}`)} className="h-11 w-full rounded-xl border border-gray-200 px-3">
                {state.sites.map((s) => <option key={s.id} value={s.id}>{s.name}</option>)}
              </Select>
            </label>
          </div>
        </Card>

        <Card className="self-start p-5">
          <CardTitle icon={IconCash} iconClass="text-[#B5551A]">Salary payments</CardTitle>
          <p className="mt-3 text-sm text-ink/70">Paid so far: <b>RWF {fmtNum(paid)}</b></p>
          {payments.length === 0 ? (
            <Empty>No salary payments recorded.</Empty>
          ) : (
            <ul className="mt-3 space-y-2 text-sm">
              {payments.map((t) => (
                <li key={t.id} className="flex justify-between rounded-xl bg-page px-3 py-2">
                  <span>{t.ref}<span className="block text-xs text-ink/60">{t.date} · {t.method}</span></span>
                  <span className="text-right">RWF {fmtNum(t.amount)}<span className="block"><StatusBadge tone={statusTone(t.status)}>{t.status}</StatusBadge></span></span>
                </li>
              ))}
            </ul>
          )}
        </Card>
      </div>
    </>
  );
}
