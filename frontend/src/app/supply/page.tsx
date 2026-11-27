"use client";

import Link from "next/link";
import { useState } from "react";
import { IconAlertTriangle, IconBox, IconBuildingFactory2, IconBuildingWarehouse, IconCalendarDue, IconDatabase, IconHistory, IconPick, IconPlus, IconSettings, IconShieldCheck, IconShip, IconTruck } from "@tabler/icons-react";
import { Card, CardTitle, DateRange, PageHeader, PrimaryButton, StatCard, StatusBadge, ViewAll } from "@/components/ui";
import { Pipeline, TH, kg, shipTone, tonnes } from "@/components/supply/common";
import { CreateShipmentModal } from "@/components/supply/forms";
import { useStore } from "@/lib/store";

export default function SupplyOverview() {
  const s = useStore((x) => x);
  const [open, setOpen] = useState(false);
  const active = s.shipments.filter((x) => !["Delivered", "Pending"].includes(x.status));
  const transit = s.shipments.filter((x) => x.status === "In Transit");
  const totalKg = s.stock.reduce((n, l) => n + l.qtyKg, 0);
  const byStatus = (st: string) => s.stock.filter((l) => l.status === st).reduce((n, l) => n + l.qtyKg, 0);
  const procActive = s.batches.filter((b) => b.status === "In Progress" || b.status === "Pending");
  const refActive = s.refinery.filter((r) => r.stage !== "Refined");
  const pendingDeliveries = s.shipments.filter((x) => x.status === "Receiving" || x.status === "Dispatched");
  const pendingVerif = s.stock.filter((l) => l.status === "Pending");
  const exportsOpen = s.declarations.filter((d) => d.status !== "Exported" && d.status !== "Draft");

  const attention = [
    ...s.shipments.filter((x) => x.status === "Receiving").map((x) => ({ text: `Confirm warehouse receiving ${x.id}`, tag: "Due now", href: "/supply/shipments?tab=Receiving" })),
    ...s.declarations.filter((d) => d.status === "Requires Action").map((d) => ({ text: `Fix export declaration ${d.id}`, tag: "Action", href: "/supply/export" })),
    ...s.shipments.filter((x) => x.status === "Discrepancy").map((x) => ({ text: `Resolve weight discrepancy ${x.id}`, tag: "Review", href: "/supply/shipments?tab=Discrepancies" })),
    ...s.shipments.filter((x) => x.status === "Delayed").map((x) => ({ text: `Delayed shipment ${x.id}`, tag: "Late", href: "/supply/shipments?tab=Delayed" })),
  ];

  return (
    <>
      <PageHeader
        crumb={{ icon: IconTruck, label: "Supply chain" }}
        title="Supply Chain Overview"
        subtitle="A connected view of mineral movement, handling and clearance."
        actions={<><DateRange label="Last 30 days" /><PrimaryButton icon={IconPlus} onClick={() => setOpen(true)}>Create shipment</PrimaryButton></>}
      />

      <div className="grid grid-cols-1 gap-5 sm:grid-cols-2 xl:grid-cols-3 2xl:grid-cols-6">
        <Link href="/supply/shipments"><StatCard icon={IconTruck} tone="green" label="Active shipments" value={active.length} delta="+8%" spark={[3, 4, 3, 5, 4, 6, 7]} /></Link>
        <Link href="/supply/shipments?tab=In Transit"><StatCard icon={IconBox} tone="orange" label="Lots in transit" value={transit.length} deltaDir="none" delta="" note="on the road" spark={[2, 3, 3, 4, 3, 5, 6]} /></Link>
        <Link href="/supply/inventory"><StatCard icon={IconDatabase} tone="green" label="Total inventory" value={tonnes(totalKg)} deltaDir="none" delta="" note="all warehouses" spark={[4, 4, 5, 5, 6, 6, 7]} /></Link>
        <Link href="/supply/processing"><StatCard icon={IconSettings} tone="orange" label="Processing batches" value={procActive.length} deltaDir="none" delta="" note="running" spark={[3, 4, 3, 5, 4, 5, 6]} /></Link>
        <Link href="/supply/shipments?tab=Receiving"><StatCard icon={IconCalendarDue} tone="green" label="Pending deliveries" value={pendingDeliveries.length} deltaDir="none" delta="" note="to receive" spark={[2, 3, 2, 4, 3, 4, 5]} /></Link>
        <Link href="/supply/inventory"><StatCard icon={IconShieldCheck} tone="orange" label="Pending verifications" value={pendingVerif.length} deltaDir="none" delta="" note="lots" spark={[1, 2, 2, 3, 2, 3, 3]} /></Link>
      </div>

      <Card className="p-5">
        <CardTitle icon={IconTruck} iconClass="text-accent">Supply chain flow</CardTitle>
        <p className="mt-1 text-sm text-ink/60">Live movement across connected stages</p>
        <Pipeline
          steps={[
            { icon: IconPick, label: "Mining site", value: s.lots.length, badge: <span className="text-sm text-ink/60">lots at origin</span>, done: true },
            { icon: IconTruck, label: "Transport", value: transit.length, badge: <span className="text-sm text-ink/60">in transit</span>, done: true },
            { icon: IconBuildingWarehouse, label: "Warehouse", value: tonnes(byStatus("Available") + byStatus("Pending")), badge: <span className="text-sm text-ink/60">in storage</span>, done: true },
            { icon: IconSettings, label: "Processing", value: procActive.length, badge: <span className="text-sm text-ink/60">batches</span>, done: true },
            { icon: IconBuildingFactory2, label: "Refinery", value: refActive.length, badge: <span className="text-sm text-ink/60">batches</span>, done: true },
            { icon: IconShip, label: "Export", value: exportsOpen.length, badge: <span className="text-sm text-ink/60">in clearance</span> },
          ]}
        />
      </Card>

      <div className="grid items-start gap-5 xl:grid-cols-[1fr_420px]">
        <Card className="pt-5">
          <div className="px-5"><CardTitle icon={IconHistory} iconClass="text-accent" action={<ViewAll href="/supply/shipments" />}>Recent shipment activity</CardTitle></div>
          <div className="mt-4 px-2 pb-4">
            <table className="w-full text-left text-sm">
              <TH cols={["Shipment", "Mineral lot", "Route", "Quantity", "Status", "ETA"]} />
              <tbody>
                {s.shipments.slice(0, 5).map((x) => (
                  <tr key={x.id} className="border-b border-gray-100 last:border-0">
                    <td className="px-3 py-3 font-medium">{x.id}</td>
                    <td className="px-3"><Link href={`/supply/traceability?lot=${x.lotId}`} className="hover:text-[#1F5B3A] hover:underline">{x.lotId}</Link></td>
                    <td className="px-3">{x.origin} → {x.destination}</td>
                    <td className="px-3">{kg(x.qtyKg)}</td>
                    <td className="px-3"><StatusBadge tone={shipTone[x.status]}>{x.status}</StatusBadge></td>
                    <td className="px-3 text-ink/70">{x.eta}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </Card>

        <div className="space-y-5">
          <Card className="p-5">
            <CardTitle icon={IconAlertTriangle} iconClass="text-accent">Needs attention</CardTitle>
            <ul className="mt-4 divide-y divide-gray-100 text-sm">
              {attention.slice(0, 5).map((a) => (
                <li key={a.text}>
                  <Link href={a.href} className="flex items-center justify-between gap-3 py-3 hover:text-[#1F5B3A]">
                    <span>{a.text}</span><StatusBadge tone="pending">{a.tag}</StatusBadge>
                  </Link>
                </li>
              ))}
              {attention.length === 0 && <li className="py-3 text-ink/60">Nothing needs attention.</li>}
            </ul>
          </Card>
          <Card className="p-5">
            <CardTitle icon={IconBox}>Inventory snapshot</CardTitle>
            <div className="mt-4 flex flex-wrap items-center gap-6">
              <b className="text-4xl font-semibold">{tonnes(totalKg)}</b>
              <div className="min-w-[200px] flex-1">
                <div className="flex h-2 overflow-hidden rounded-full">
                  {[["Available", "#1F5B3A"], ["Reserved", "#F08A2C"], ["In Transit", "#CBD5E1"]].map(([k, c]) => <span key={k} style={{ width: `${(byStatus(k) / (totalKg || 1)) * 100}%`, background: c }} />)}
                </div>
                <div className="mt-2 flex justify-between text-xs text-ink/70">
                  {["Available", "Reserved", "In Transit"].map((k) => <span key={k}>{k}<b className="block text-sm font-medium text-ink">{tonnes(byStatus(k))}</b></span>)}
                </div>
              </div>
            </div>
          </Card>
        </div>
      </div>

      {open && <CreateShipmentModal onClose={() => setOpen(false)} />}
    </>
  );
}
