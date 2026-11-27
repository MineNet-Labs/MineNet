"use client";

import Link from "next/link";
import { IconAlertTriangle, IconCash, IconChartPie, IconInbox, IconUmbrella } from "@tabler/icons-react";
import { Card, CardTitle, PageHeader, StatCard, ViewAll } from "@/components/ui";
import { Donut } from "@/components/ui/charts";
import { PolicyBadge, useInsurer } from "@/components/insurer/common";
import { fmtNum } from "@/lib/data";

export default function InsurerOverview() {
  const { me, policies, claims } = useInsurer();
  const active = policies.filter((p) => p.status === "Active");
  const requests = policies.filter((p) => p.status === "Requested");
  const exposure = active.reduce((n, p) => n + p.sumInsured, 0);
  const premiums = policies.filter((p) => p.status === "Active" || p.status === "Expired").reduce((n, p) => n + p.premium, 0);
  const paid = claims.filter((c) => c.status === "Approved").reduce((n, c) => n + c.amount, 0);
  const lossRatio = premiums ? Math.round((paid / premiums) * 100) : 0;

  const byCover = (() => {
    const m = new Map<string, number>();
    active.forEach((p) => m.set(p.cover, (m.get(p.cover) ?? 0) + p.sumInsured));
    const colors: Record<string, string> = { Storage: "#1F5B3A", Transit: "#F0913F", "Storage & transit": "#0e7490" };
    return [...m].map(([name, v]) => ({ name, v, color: colors[name] }));
  })();

  return (
    <>
      <PageHeader title={`Welcome, ${me.name}`} subtitle="Cover requests to price, policies in force and claims to decide." />

      <div className="grid grid-cols-1 gap-5 sm:grid-cols-2 xl:grid-cols-4">
        <StatCard deltaDir="none" icon={IconInbox} tone="orange" label="Requests to quote" value={requests.length} delta="" note="waiting" spark={[1, 2, 1, 2, 3, 2, 3]} />
        <StatCard deltaDir="none" icon={IconUmbrella} tone="green" label="Exposure (USD)" value={fmtNum(exposure)} delta={`${active.length}`} note="active policies" spark={[3, 4, 4, 5, 5, 6, 6]} />
        <StatCard deltaDir="none" icon={IconCash} tone="violet" label="Premiums written (USD)" value={fmtNum(premiums)} delta="" note="active and past" spark={[2, 3, 3, 4, 4, 5, 5]} />
        <StatCard deltaDir="none" icon={IconAlertTriangle} tone="gray" label="Loss ratio" value={`${lossRatio}%`} delta={`${claims.filter((c) => c.status === "Filed").length}`} note="open claims" spark={[1, 1, 2, 1, 2, 2, 1]} />
      </div>

      <div className="grid items-start gap-5 xl:grid-cols-[1fr_380px]">
        <Card className="p-6">
          <CardTitle icon={IconInbox} iconClass="text-accent" action={<ViewAll href="/insurer/requests" />}>Waiting for your quote</CardTitle>
          <ul className="mt-4 divide-y divide-gray-100 text-sm">
            {requests.slice(0, 5).map((p) => (
              <li key={p.id}>
                <Link href="/insurer/requests" className="flex items-center justify-between rounded-xl px-2 py-3 hover:bg-page">
                  <span><b className="font-medium">{p.id}</b> · {p.lotId} · {p.cover}</span>
                  <span>USD {fmtNum(p.sumInsured)}</span>
                </Link>
              </li>
            ))}
            {requests.length === 0 && <li className="py-6 text-center text-ink/60">Nothing waiting.</li>}
          </ul>
        </Card>
        <Card className="p-6">
          <CardTitle icon={IconChartPie}>Exposure by cover</CardTitle>
          {byCover.length ? (
            <div className="mt-6 flex items-center gap-6">
              <Donut size={130} thickness={18} gap={3} labels={byCover.map((b) => b.name)} segments={byCover.map((b) => ({ value: b.v, color: b.color }))}>
                <div><p className="font-heading text-xl font-bold">{active.length}</p><p className="text-xs text-ink/60">policies</p></div>
              </Donut>
              <ul className="flex-1 space-y-3 text-sm">
                {byCover.map((b) => <li key={b.name} className="flex justify-between"><span className="flex items-center gap-2"><i className="size-2.5 rounded-full" style={{ background: b.color }} />{b.name}</span><b className="font-medium">{fmtNum(b.v)}</b></li>)}
              </ul>
            </div>
          ) : (
            <p className="mt-6 text-sm text-ink/60">No active cover yet.</p>
          )}
        </Card>
      </div>

      <div className="grid items-start gap-5 xl:grid-cols-2">
        <Card className="p-6">
          <CardTitle icon={IconAlertTriangle} iconClass="text-danger" action={<ViewAll href="/insurer/claims" />}>Open claims</CardTitle>
          <ul className="mt-4 divide-y divide-gray-100 text-sm">
            {claims.filter((c) => c.status === "Filed").map((c) => (
              <li key={c.id}>
                <Link href={`/insurer/claims/${c.id}`} className="flex justify-between rounded-xl px-2 py-3 hover:bg-page"><span><b className="font-medium">{c.id}</b> · {c.lotId}</span><span>{c.currency} {fmtNum(c.amount)}</span></Link>
              </li>
            ))}
            {!claims.some((c) => c.status === "Filed") && <li className="py-6 text-center text-ink/60">No open claims.</li>}
          </ul>
        </Card>
        <Card className="p-6">
          <CardTitle icon={IconUmbrella} iconClass="text-[#0e7490]" action={<ViewAll href="/insurer/policies" />}>Recent policies</CardTitle>
          <ul className="mt-4 divide-y divide-gray-100 text-sm">
            {policies.filter((p) => p.status !== "Requested").slice(0, 5).map((p) => (
              <li key={p.id}>
                <Link href={`/insurer/policies/${p.id}`} className="flex items-center justify-between rounded-xl px-2 py-3 hover:bg-page"><span><b className="font-medium">{p.id}</b> · {p.lotId} · {p.cover}</span><PolicyBadge status={p.status} /></Link>
              </li>
            ))}
          </ul>
        </Card>
      </div>
    </>
  );
}
