"use client";

import Link from "next/link";
import {
  IconBox,
  IconBuildingFactory2,
  IconCheck,
  IconFileText,
  IconHome,
  IconSettings,
  IconShieldCheck,
  IconTruck,
  IconUpload,
  type Icon as TablerIcon,
} from "@tabler/icons-react";
import { Card, CardTitle, StatusBadge, ViewAll, type BadgeTone } from "@/components/ui";
import { Donut } from "@/components/ui/charts";
import type { NavItem } from "@/components/layout/Sidebar";
import { PortalTopbar } from "@/components/layout/PortalTopbar";
import { useStore } from "@/lib/store";
import { SUPPLY_AUDIENCE, type BatchStatus, type DeclStatus, type RefineStage, type ScArea, type ShipmentStatus, type StockStatus } from "@/lib/supply";

export const supplyNav: NavItem[] = [
  { label: "Overview", href: "/supply", icon: IconHome },
  { label: "Shipments", href: "/supply/shipments", icon: IconTruck },
  { label: "Inventory", href: "/supply/inventory", icon: IconBox },
  { label: "Processing", href: "/supply/processing", icon: IconSettings },
  { label: "Refinery", href: "/supply/refinery", icon: IconBuildingFactory2 },
  { label: "Export", href: "/supply/export", icon: IconUpload },
  { label: "Traceability", href: "/supply/traceability", icon: IconShieldCheck },
  { label: "Records & Reports", href: "/supply/reports", icon: IconFileText },
];

export const GREEN = "#1F5B3A";
export const ORANGE = "#F08A2C";
export const GREY = "#CBD5E1";

export function SupplyTopbar() {
  return (
    <PortalTopbar
      nav={supplyNav}
      home="/supply"
      name="Jean Uwimana"
      role="Supply Chain Operator"
      audience={SUPPLY_AUDIENCE}
      onSearch={(q) => `/supply/traceability?lot=${encodeURIComponent(q)}`}
    />
  );
}

/* ---------------------------------------------------------- status tones */

export const shipTone: Record<ShipmentStatus, BadgeTone> = { Pending: "neutral", Dispatched: "neutral", "In Transit": "success", Receiving: "blue", Delivered: "success", Delayed: "pending", Discrepancy: "danger" };
export const stockTone: Record<StockStatus, BadgeTone> = { Available: "success", "In Transit": "blue", Pending: "pending", Reserved: "neutral" };
export const batchTone: Record<BatchStatus, BadgeTone> = { Pending: "pending", "In Progress": "success", "Quality Check": "blue", Completed: "success", Rejected: "danger" };
export const refTone: Record<RefineStage, BadgeTone> = { Intake: "pending", Refining: "success", "Quality Testing": "blue", Refined: "success" };
export const declTone: Record<DeclStatus, BadgeTone> = { Draft: "neutral", Submitted: "pending", "Under Review": "blue", "Requires Action": "danger", Cleared: "success", Exported: "success" };

/* -------------------------------------------------------------- widgets */

/** Stage chain with icons and connectors (processing, refinery, export, overview). */
export function Pipeline({ steps }: { steps: { icon: TablerIcon; label: string; value?: React.ReactNode; badge?: React.ReactNode; active?: boolean; done?: boolean }[] }) {
  return (
    <div className="mt-6 flex flex-wrap items-start justify-between gap-y-6">
      {steps.map((s, i) => (
        <div key={s.label} className="flex flex-1 items-start">
          <div className="flex min-w-[110px] flex-1 flex-col items-center text-center">
            <span className={`relative grid size-14 place-items-center rounded-full ${s.active ? "bg-[#1F5B3A] text-white" : "bg-primary-soft text-[#1F5B3A]"}`}>
              <s.icon className="size-6" />
              {s.done && <span className="absolute -right-1 -bottom-1 grid size-5 place-items-center rounded-full bg-[#1F5B3A] text-white ring-2 ring-white"><IconCheck className="size-3" stroke={3} /></span>}
            </span>
            <p className="mt-3 text-[15px]">{s.label}</p>
            {s.value !== undefined && <p className="mt-1 text-2xl font-semibold">{s.value}</p>}
            {s.badge && <div className="mt-2">{s.badge}</div>}
          </div>
          {i < steps.length - 1 && <span className="mt-7 hidden h-px w-10 shrink bg-gray-200 sm:block xl:w-16" />}
        </div>
      ))}
    </div>
  );
}

/** Donut with a legend of labelled shares. */
export function DonutLegend({ segments, center, sub, size = 128 }: { segments: { label: string; value: number; color: string }[]; center: string; sub: string; size?: number }) {
  const total = segments.reduce((n, s) => n + s.value, 0) || 1;
  return (
    <div className="mt-5 flex flex-wrap items-center gap-6">
      <Donut size={size} thickness={16} segments={segments.map((s) => ({ value: s.value || 0.0001, color: s.color }))} labels={segments.map((s) => s.label)}>
        <span><b className="block text-xl font-semibold">{center}</b><span className="text-xs text-ink/60">{sub}</span></span>
      </Donut>
      <ul className="min-w-[180px] flex-1 space-y-3 text-[15px]">
        {segments.map((s) => (
          <li key={s.label} className="flex items-center justify-between gap-3">
            <span className="flex items-center gap-2"><i className="size-3 rounded-full" style={{ background: s.color }} />{s.label}</span>
            <b className="font-medium">{Math.round((s.value / total) * 100)}%</b>
          </li>
        ))}
      </ul>
    </div>
  );
}

export function Progress({ value }: { value: number }) {
  return (
    <span className="flex items-center gap-3">
      <span className="h-2 w-24 rounded-full bg-gray-200"><span className="block h-2 rounded-full bg-[#1F5B3A]" style={{ width: `${value}%` }} /></span>
      <span className="text-sm text-ink/70">{value}%</span>
    </span>
  );
}

/** Latest supply chain activity, optionally for one area. */
export function ActivityFeed({ area, limit = 4, title = "Recent Activity" }: { area?: ScArea; limit?: number; title?: string }) {
  const all = useStore((s) => s.scActivity);
  const rows = all.filter((a) => !area || a.area === area);
  return (
    <Card className="p-5">
      <CardTitle action={rows.length > limit ? <ViewAll href={`/supply/reports?tab=Audit Logs${area ? `&area=${area}` : ""}`} /> : undefined}>{title}</CardTitle>
      <ul className="mt-4 space-y-3 border-l-2 border-gray-100 pl-4 text-sm">
        {rows.slice(0, limit).map((a, i) => (
          <li key={a.id} className="relative">
            <i className={`absolute top-1.5 -left-[21px] size-2.5 rounded-full ${i % 2 ? "bg-accent" : "bg-[#1F5B3A]"}`} />
            <p>{a.text}</p>
            <p className="text-xs text-ink/60">{a.date}</p>
          </li>
        ))}
        {rows.length === 0 && <li className="text-ink/60">No activity yet.</li>}
      </ul>
    </Card>
  );
}

/** Square shortcut buttons. */
export function QuickActions({ items }: { items: { icon: TablerIcon; label: string; onClick?: () => void; href?: string }[] }) {
  return (
    <Card className="p-5">
      <CardTitle>Quick Actions</CardTitle>
      <div className="mt-4 grid grid-cols-1 gap-3 sm:grid-cols-2">
        {items.map((q) => {
          const inner = (
            <>
              <span className="grid size-10 shrink-0 place-items-center rounded-full bg-primary-soft text-[#1F5B3A]"><q.icon className="size-5" /></span>
              <span className="text-left text-sm font-medium">{q.label}</span>
            </>
          );
          const cls = "flex items-center gap-3 rounded-2xl border border-gray-100 px-3 py-3 hover:bg-page";
          return q.href ? <Link key={q.label} href={q.href} className={cls}>{inner}</Link> : <button key={q.label} onClick={q.onClick} className={cls}>{inner}</button>;
        })}
      </div>
    </Card>
  );
}

/** Horizontal share bars, e.g. exports by destination. */
export function ShareBars({ rows }: { rows: { label: string; value: number }[] }) {
  const total = rows.reduce((n, r) => n + r.value, 0) || 1;
  return (
    <ul className="mt-5 space-y-3 text-[15px]">
      {rows.map((r, i) => (
        <li key={r.label}>
          <span className="flex justify-between"><span>{r.label}</span><b className="font-medium">{Math.round((r.value / total) * 100)}%</b></span>
          <span className="mt-1 block h-2 rounded-full bg-gray-100"><span className="block h-2 rounded-full" style={{ width: `${(r.value / total) * 100}%`, background: i === 0 ? GREEN : i === 1 ? ORANGE : "#94A3B8" }} /></span>
        </li>
      ))}
    </ul>
  );
}

export const TH = ({ cols }: { cols: string[] }) => (
  <thead className="bg-head">
    <tr>{cols.map((h, i) => <th key={i} className="px-3 py-3 text-[13px] font-medium">{h}</th>)}</tr>
  </thead>
);

export const kg = (n: number) => (n >= 1000 ? `${(n / 1000).toFixed(1)} t` : `${n} kg`);
export const tonnes = (kgs: number) => `${(kgs / 1000).toFixed(1)} t`;
export { StatusBadge };
export { fmtT } from "@/lib/supply";
