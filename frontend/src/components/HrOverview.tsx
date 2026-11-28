"use client";

import Link from "next/link";
import { IconBeach, IconCalendarCheck, IconCash, IconQrcode, IconUsers } from "@tabler/icons-react";
import { Card, CardTitle, PageHeader, StatCard, ViewAll } from "@/components/ui";
import { MONTHS, fmtNum } from "@/lib/data";
import { useMe, useStore } from "@/lib/store";

/** HR's home: people, attendance, leave and payroll at a glance. */
export function HrOverview() {
  const me = useMe();
  const state = useStore((s) => s);
  const { workers, attendance, leaves, payruns } = state;
  const active = workers.filter((w) => w.status === "Active");
  const lastDay = attendance.reduce((m, a) => (a.date > m ? a.date : m), "");
  const present = attendance.filter((a) => a.date === lastDay && (a.status === "Present" || a.status === "Half day")).length;
  const pendingLeave = leaves.filter((l) => l.status === "Pending");
  const setup = workers.filter((w) => w.access === "Setup pending");
  const latestRun = payruns[0];
  const month = lastDay.slice(0, 7);
  const hasRun = payruns.some((r) => r.month === month);

  return (
    <>
      <PageHeader title={`Hello, ${me.name.split(" ")[0]}`} subtitle="People, attendance, leave and payroll for the whole company." />
      <div className="grid grid-cols-1 gap-5 sm:grid-cols-2 xl:grid-cols-4">
        <StatCard deltaDir="none" icon={IconUsers} tone="green" label="Active workers" value={active.length} delta={`${workers.length - active.length}`} note="inactive" spark={[3, 4, 4, 5, 5, 6, 6]} />
        <StatCard deltaDir="none" icon={IconCalendarCheck} tone="orange" label={`Present on ${lastDay}`} value={present} delta="" note={`of ${active.length}`} spark={[5, 6, 6, 7, 6, 7, 7]} />
        <StatCard deltaDir="none" icon={IconBeach} tone="violet" label="Leave to decide" value={pendingLeave.length} delta="" note="requests" spark={[1, 2, 1, 2, 2, 3, 2]} />
        <StatCard deltaDir="none" icon={IconQrcode} tone="gray" label="Access setup pending" value={setup.length} delta="" note="workers" spark={[2, 1, 2, 1, 1, 1, 1]} />
      </div>
      <div className="grid items-start gap-5 xl:grid-cols-3">
        <Card className="p-5">
          <CardTitle icon={IconCash} iconClass="text-[#1F5B3A]" action={<ViewAll href="/miner/payroll" />}>Payroll</CardTitle>
          {hasRun ? (
            <p className="mt-4 text-sm">{MONTHS[Number(month.slice(5)) - 1]} payroll is prepared ({payruns.find((r) => r.month === month)?.status}).</p>
          ) : (
            <p className="mt-4 text-sm">{MONTHS[Number(month.slice(5)) - 1]} payroll is not prepared yet. <Link href="/miner/payroll" className="font-medium text-accent hover:underline">Prepare it</Link></p>
          )}
          {latestRun && <p className="mt-2 text-xs text-ink/60">Last run {latestRun.id}: RWF {fmtNum(latestRun.lines.reduce((n, l) => n + l.net, 0))} · {latestRun.status}</p>}
        </Card>
        <Card className="p-5">
          <CardTitle icon={IconBeach} iconClass="text-violet" action={<ViewAll href="/miner/leave" />}>Leave requests</CardTitle>
          <ul className="mt-4 space-y-2 text-sm">
            {pendingLeave.map((l) => (
              <li key={l.id} className="rounded-xl bg-page px-3 py-2">{workers.find((w) => w.id === l.workerId)?.name} · {l.type} · {l.days} day(s)</li>
            ))}
            {pendingLeave.length === 0 && <li className="text-ink/60">Nothing to decide.</li>}
          </ul>
        </Card>
        <Card className="p-5">
          <CardTitle icon={IconQrcode} iconClass="text-accent" action={<ViewAll href="/miner/workers" />}>Needs QR access</CardTitle>
          <ul className="mt-4 space-y-2 text-sm">
            {setup.map((w) => (
              <li key={w.id}><Link href={`/miner/workers/${w.id}`} className="block rounded-xl bg-page px-3 py-2 hover:bg-cream">{w.name} · {w.category}</Link></li>
            ))}
            {setup.length === 0 && <li className="text-ink/60">Everyone has access.</li>}
          </ul>
        </Card>
      </div>
    </>
  );
}
