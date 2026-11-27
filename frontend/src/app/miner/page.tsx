"use client";

import Link from "next/link";
import { useState } from "react";
import {
  IconAlertTriangle,
  IconBox,
  IconCalendar,
  IconChartBar,
  IconCheck,
  IconClock,
  IconFileText,
  IconMapPin,
  IconPick,
  IconPlus,
  IconShieldCheck,
  IconTruck,
} from "@tabler/icons-react";
import {
  Card,
  CardTitle,
  DateRange,
  MiniSelect,
  PageHeader,
  PrimaryButton,
  StatCard,
  StatusBadge,
  ViewAll,
  statusTone,
} from "@/components/ui";
import { Donut, GroupedBars, LiveBadge } from "@/components/ui/charts";
import { CreateLotModal } from "@/components/forms";
import { fmtKg } from "@/lib/data";
import { siteName, useStore } from "@/lib/store";

export default function MinerOverview() {
  const state = useStore((s) => s);
  const { sites, lots, records, inspections } = state;
  const [open, setOpen] = useState(false);

  const active = sites.filter((s) => s.status === "Active").length;
  const extracted = records.filter((r) => r.status === "Approved").reduce((t, r) => t + r.quantityKg, 0);
  const pendingInspections = inspections.filter((i) => i.status === "Pending" || i.status === "Scheduled").length;

  return (
    <>
      <PageHeader
        title="Good morning, Jean"
        subtitle="Here's what's happening in your mining operations."
        actions={
          <>
            <DateRange />
            <PrimaryButton icon={IconPlus} onClick={() => setOpen(true)}>Register Mineral Lot</PrimaryButton>
          </>
        }
      />

      <div className="grid grid-cols-2 gap-5 xl:grid-cols-4">
        <Link href="/miner/mining-sites" className="block"><StatCard icon={IconPick} tone="orange" label="Registered Sites" value={sites.length} delta="+1" spark={[3, 4, 3.5, 5, 4.5, 6, 9]} /></Link>
        <Link href="/miner/mineral-lots" className="block"><StatCard icon={IconBox} tone="orange" label="Mineral Lots" value={lots.length} delta="+12%" spark={[3, 3.5, 4, 4.5, 5, 6, 9]} /></Link>
        <Link href="/miner/extraction-records" className="block"><StatCard icon={IconTruck} tone="green" label="Extraction Recorded" value={fmtKg(extracted)} delta="+8%" spark={[3, 4, 3.2, 5, 4, 6, 5, 8]} /></Link>
        <Link href="/miner/inspections" className="block">
          <StatCard
            icon={IconShieldCheck}
            tone="orange"
            label="Pending Inspections"
            value={pendingInspections}
            deltaDir="none"
            delta={<span className="flex items-center gap-1 text-accent"><IconClock className="size-3.5" stroke={2.5} /> Due soon</span>}
            note=""
            spark={[3, 3.5, 3.2, 4, 3.8, 5, 8]}
          />
        </Link>
      </div>

      <div className="grid gap-5 xl:grid-cols-[1fr_392px]">
        <Card className="p-6">
          <CardTitle icon={IconChartBar} action={<MiniSelect options={["Last 6 Months", "Last 3 Months", "This year"]} />}>
            <span className="flex items-center gap-3">Production Overview <LiveBadge /></span>
          </CardTitle>
          <div className="mt-3 mb-2 flex justify-end gap-6 text-[15px]">
            <span className="flex items-center gap-2"><i className="size-2.5 rounded-full bg-[#1F5B3A]" /> Gold</span>
            <span className="flex items-center gap-2 text-accent"><i className="size-2.5 rounded-full bg-[#F0913F]" /> Coltan</span>
          </div>
          <GroupedBars
            labels={["Jan", "Feb", "Mar", "Apr", "May", "Jun"]}
            names={["Gold", "Coltan"]}
            series={[
              { color: "#1F5B3A", values: [11.5, 14, 15.8, 16.5, 15, 17] },
              { color: "#F0913F", values: [9.5, 12.5, 14.5, 15.2, 13.5, 15.2] },
            ]}
          />
        </Card>

        <Card className="p-6">
          <CardTitle icon={IconMapPin} action={<ViewAll href="/miner/mining-sites" />}>Site Status</CardTitle>
          <div className="mt-6 flex items-center gap-8 pl-4">
            <Donut
              size={152}
              thickness={14}
              labels={["Active", "Inactive"]}
              segments={[
                { value: active, color: "#1F5B3A" },
                { value: sites.length - active, color: "#F7D7BD" },
              ]}
            >
              <div>
                <p className="font-heading text-3xl font-bold">{sites.length}</p>
                <p className="text-[13px] text-ink/80">Total Sites</p>
              </div>
            </Donut>
            <ul className="space-y-4 text-[15px]">
              <li className="flex items-center gap-3"><i className="size-2.5 rounded-full bg-[#1F5B3A]" /> Active <b className="ml-6 font-semibold">{active}</b></li>
              <li className="flex items-center gap-3"><i className="size-2.5 rounded-full bg-[#F7D7BD]" /> Inactive <b className="ml-4 font-semibold">{sites.length - active}</b></li>
            </ul>
          </div>
          <div className="mt-6 flex items-center gap-4 rounded-2xl bg-primary-soft px-4 py-4">
            <span className="grid size-8 place-items-center rounded-full bg-[#1F5B3A]"><IconCheck className="size-4 text-white" stroke={3} /></span>
            <p className="text-sm text-ink/90">
              <b className="font-semibold text-[#1F5B3A]">{Math.round((active / Math.max(1, sites.length)) * 100)}%</b> of mining sites<br />are operational
            </p>
          </div>
        </Card>
      </div>

      <div className="grid gap-5 xl:grid-cols-[1fr_392px]">
        <Card className="p-4 pt-6">
          <div className="px-2">
            <CardTitle icon={IconBox} action={<ViewAll href="/miner/mineral-lots" />}>Recent Mineral Lots</CardTitle>
          </div>
          <div className="overflow-x-auto">
            <table className="mt-5 w-full text-left text-[15px] [&_td]:whitespace-nowrap">
              <thead className="bg-head text-ink">
                <tr>{["Lot ID", "Mineral", "Site", "Weight", "Status", "Date"].map((h) => <th key={h} className="px-3 py-3 font-medium">{h}</th>)}</tr>
              </thead>
              <tbody>
                {lots.slice(0, 4).map((l) => (
                  <tr key={l.id} className="border-b border-gray-100 last:border-0">
                    <td className="px-3 py-3">
                      <Link href={`/miner/mineral-lots?q=${l.id}`} className="hover:text-[#1F5B3A] hover:underline">{l.id}</Link>
                    </td>
                    <td className="px-3">{l.mineral}</td>
                    <td className="px-3">
                      <Link href={`/miner/mining-sites/${l.siteId}`} className="hover:text-[#1F5B3A] hover:underline">{siteName(state, l.siteId)}</Link>
                    </td>
                    <td className="px-3">{fmtKg(l.quantityKg)}</td>
                    <td className="px-3"><StatusBadge tone={statusTone(l.status)}>{l.status}</StatusBadge></td>
                    <td className="px-3">{l.created}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </Card>

        <Card className="p-6">
          <CardTitle icon={IconAlertTriangle} action={<ViewAll href="/miner/inspections" />}>Action Required</CardTitle>
          <ul className="mt-5 space-y-2 border-b border-gray-200 pb-5">
            {[
              { icon: IconCalendar, title: "Inspection due", sub: "ML-2025-1047 – Kigali Site", when: "Today", href: "/miner/inspections" },
              { icon: IconFileText, title: "Licence expiry reminder", sub: "Musanze Site Licence", when: "In 7 days", href: "/miner/documents" },
            ].map(({ icon: Icon, title, sub, when, href }) => (
              <li key={title}>
                <Link href={href} className="-mx-2 flex items-center gap-3 rounded-xl px-2 py-1.5 hover:bg-page">
                  <span className="grid size-10 place-items-center rounded-full bg-accent-soft"><Icon className="size-5 text-accent" stroke={1.8} /></span>
                  <div className="flex-1">
                    <p className="text-[15px] font-medium">{title}</p>
                    <p className="text-[13px] text-ink/70">{sub}</p>
                  </div>
                  <span className="rounded-full bg-accent-soft px-3 py-1 text-sm text-accent">{when}</span>
                </Link>
              </li>
            ))}
          </ul>
          <p className="mt-5 flex items-center gap-2 text-[17px] font-medium"><IconClock className="size-5" /> Recent Activity</p>
          <div className="mt-4 flex gap-4 text-sm">
            <span className="mt-1.5 size-2 rounded-full bg-accent" />
            <b className="font-medium">2h ago</b>
            <div>
              <p>New mineral lot registered</p>
              <p className="text-[13px] text-ink/60">{lots[0]?.id} – {lots[0]?.mineral}</p>
            </div>
          </div>
        </Card>
      </div>

      {open && <CreateLotModal onClose={() => setOpen(false)} />}
    </>
  );
}
