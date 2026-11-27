"use client";

import { useRouter } from "next/navigation";
import { useState } from "react";
import { IconAlertTriangle, IconBox, IconBuildingWarehouse, IconChartBar, IconCircleCheck, IconClock, IconMapPin, IconPlus, IconRoute, IconShieldCheck, IconTruck } from "@tabler/icons-react";
import { CancelButton, Card, CardTitle, DateRange, Empty, Field, FilterSelect, Modal, PageHeader, Pagination, PrimaryButton, RowMenu, StatCard, StatusBadge, SubmitButton, formValues, toast, usePaged } from "@/components/ui";
import { Select } from "@/components/ui/Select";
import { withConfirm } from "@/components/ui/Confirm";
import { AreaChart } from "@/components/ui/charts";
import { ActivityFeed, DonutLegend, GREEN, GREY, ORANGE, TH, kg, stockTone, tonnes } from "@/components/supply/common";
import { CreateShipmentModal, RegisterStockModal } from "@/components/supply/forms";
import { useStore } from "@/lib/store";
import { CAPACITY, WAREHOUSES, roomKg, setStock, type StockLot } from "@/lib/supply";
import { getState } from "@/lib/store";

export default function InventoryPage() {
  const router = useRouter();
  const stock = useStore((s) => s.stock);
  const [status, setStatus] = useState("");
  const [modal, setModal] = useState<null | "register" | { ship: string } | { move: StockLot }>(null);
  const rows = stock.filter((l) => !status || l.status === status);
  const { rows: page, pager } = usePaged(rows, 6);
  const sum = (f: (l: StockLot) => boolean) => stock.filter(f).reduce((n, l) => n + l.qtyKg, 0);
  const total = sum(() => true);
  const available = sum((l) => l.status === "Available");
  const byWh = WAREHOUSES.map((w) => ({ label: w, value: sum((l) => l.location === w) })).filter((w) => w.value > 0);
  const colors = [GREEN, ORANGE, GREY, "#94A3B8", "#F7C08A"];
  // History is sample data; the latest month is today's stock.
  const months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun"];
  const tTotal = [3.1, 3.6, 3.9, 4.4, 4.5, +(total / 1000).toFixed(1)];
  const tAvail = [2.0, 2.5, 2.8, 3.2, 3.3, +(available / 1000).toFixed(1)];

  return (
    <>
      <PageHeader
        title="Inventory"
        subtitle="Track and manage mineral inventory across warehouses and locations."
        actions={<><DateRange label="Last 30 days" /><PrimaryButton icon={IconPlus} onClick={() => setModal("register")}>Register Inventory</PrimaryButton></>}
      />

      <div className="grid grid-cols-1 gap-5 sm:grid-cols-2 xl:grid-cols-5">
        <StatCard icon={IconBox} tone="orange" label="Total Inventory" value={tonnes(total)} delta="+6%" spark={[3, 4, 4, 5, 5, 6, 7]} />
        <StatCard icon={IconCircleCheck} tone="green" label="Available Stock" value={tonnes(available)} delta="+8%" spark={[3, 3, 4, 5, 5, 6, 6]} />
        <StatCard icon={IconClock} tone="orange" label="In Transit" value={tonnes(sum((l) => l.status === "In Transit"))} delta="+2%" spark={[2, 3, 2, 3, 3, 4, 4]} />
        <StatCard icon={IconBuildingWarehouse} tone="green" label="Reserved" value={tonnes(sum((l) => l.status === "Reserved"))} deltaDir="none" delta="" note="for processing or export" spark={[2, 3, 3, 4, 4, 5, 5]} />
        <StatCard icon={IconAlertTriangle} tone="gray" label="Pending Verification" value={tonnes(sum((l) => l.status === "Pending"))} deltaDir="down" delta="-20%" spark={[5, 4, 4, 3, 3, 2, 2]} />
      </div>

      <div className="grid items-start gap-5 xl:grid-cols-[1fr_400px]">
        <div className="space-y-5">
          <Card className="p-5">
            <CardTitle icon={IconChartBar} iconClass="text-accent">Inventory Trend (t)</CardTitle>
            <div className="mt-2 flex gap-4 text-sm">
              <span className="flex items-center gap-1.5"><i className="size-2.5 rounded-full bg-[#1F5B3A]" />Total</span>
              <span className="flex items-center gap-1.5"><i className="size-2.5 rounded-full bg-accent" />Available</span>
            </div>
            <AreaChart height={240} xLabels={months} yTicks={[0, 1, 2, 3, 4, 5, 6]} yMax={6} live={false} unit=" t" series={[{ name: "Total", color: GREEN, values: tTotal }, { name: "Available", color: ORANGE, values: tAvail }]} />
          </Card>
          <Card className="pt-5">
            <div className="flex flex-wrap items-center justify-between gap-3 px-5">
              <CardTitle icon={IconBox} iconClass="text-accent">Mineral Lots</CardTitle>
              <FilterSelect label="All statuses" options={["Available", "In Transit", "Pending", "Reserved"]} value={status} onChange={setStatus} />
            </div>
            <div className="mt-4 px-2">
              {page.length === 0 ? (
                <Empty>No lots with this status.</Empty>
              ) : (
                <table className="w-full text-left text-sm">
                  <TH cols={["Lot ID", "Mineral", "Quantity", "Location", "Status", "Last Updated", ""]} />
                  <tbody>
                    {page.map((l) => (
                      <tr key={l.id} className="border-b border-gray-100 last:border-0">
                        <td className="px-3 py-3 font-medium">{l.id}<span className="block text-xs font-normal text-ink/60">from {l.origin}</span></td>
                        <td className="px-3">{l.mineral}</td>
                        <td className="px-3">{kg(l.qtyKg)}</td>
                        <td className="px-3">{l.location}</td>
                        <td className="px-3"><StatusBadge tone={stockTone[l.status]}>{l.status}</StatusBadge></td>
                        <td className="px-3 text-ink/70">{l.updated}</td>
                        <td className="px-3 text-right">
                          <RowMenu
                            items={[
                              { label: "Track lot", icon: IconRoute, onClick: () => router.push(`/supply/traceability?lot=${l.id}`) },
                              ...(l.status === "Pending" ? [{ label: "Verify weight and grade", icon: IconShieldCheck, onClick: withConfirm({ title: "Verify this lot?", message: `${l.id}: ${kg(l.qtyKg)} of ${l.mineral} was checked at ${l.location}. It becomes available.`, confirmLabel: "Verify" }, () => (setStock(l, { status: "Available" }, `${l.id} verified at ${l.location}`), toast(`${l.id} verified`))) }] : []),
                              ...(l.status === "Available" ? [{ label: "Move to warehouse", icon: IconBuildingWarehouse, onClick: () => setModal({ move: l }) }, { label: "Create shipment", icon: IconTruck, onClick: () => setModal({ ship: l.id }) }] : []),
                            ]}
                          />
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              )}
            </div>
            <Pagination {...pager} noun="lots" />
          </Card>
        </div>
        <div className="space-y-5">
          <Card className="p-5">
            <CardTitle icon={IconMapPin} iconClass="text-accent">Storage Locations</CardTitle>
            <DonutLegend center={String(byWh.length)} sub="Warehouses" segments={byWh.map((w, i) => ({ ...w, color: colors[i % colors.length] }))} />
            <p className="mt-5 text-sm font-medium">Capacity used</p>
            <ul className="mt-2 space-y-2 text-sm">
              {WAREHOUSES.map((w) => {
                const used = sum((l) => l.location === w);
                const pct = Math.min(100, Math.round((used / CAPACITY[w]) * 100));
                return (
                  <li key={w}>
                    <span className="flex justify-between"><span>{w}</span><span className={pct >= 90 ? "font-medium text-danger" : "text-ink/70"}>{kg(used)} / {kg(CAPACITY[w])}</span></span>
                    <span className="mt-1 block h-1.5 rounded-full bg-gray-100"><span className={`block h-1.5 rounded-full ${pct >= 90 ? "bg-danger" : "bg-[#1F5B3A]"}`} style={{ width: `${pct}%` }} /></span>
                  </li>
                );
              })}
            </ul>
          </Card>
          <ActivityFeed area="inventory" title="Recent Movements" limit={5} />
        </div>
      </div>

      {modal === "register" && <RegisterStockModal onClose={() => setModal(null)} />}
      {modal && typeof modal === "object" && "ship" in modal && <CreateShipmentModal lotId={modal.ship} onClose={() => setModal(null)} />}
      {modal && typeof modal === "object" && "move" in modal && (
        <Modal title={`Move ${modal.move.id}`} subtitle={`Currently at ${modal.move.location}.`} onClose={() => setModal(null)} footer={<><CancelButton onClick={() => setModal(null)} /><SubmitButton form="move-form">Move lot</SubmitButton></>}>
          <form
            id="move-form"
            onSubmit={(e) => {
              const v = formValues(e);
              if (modal.move.qtyKg > roomKg(getState(), v.to)) return toast(`${v.to} has room for ${roomKg(getState(), v.to)} kg only`, "error");
              setStock(modal.move, { location: v.to }, `Transferred ${kg(modal.move.qtyKg)} of ${modal.move.mineral} to ${v.to}`);
              toast(`${modal.move.id} moved to ${v.to}`);
              setModal(null);
            }}
          >
            <Field label="New warehouse">
              <Select name="to" required defaultValue="">
                <option value="" disabled>Select warehouse</option>
                {WAREHOUSES.filter((w) => w !== modal.move.location).map((w) => <option key={w} value={w}>{w} · {kg(Math.max(0, roomKg(getState(), w)))} free</option>)}
              </Select>
            </Field>
          </form>
        </Modal>
      )}
    </>
  );
}
