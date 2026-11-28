"use client";

import Link from "next/link";
import { useRouter, useSearchParams } from "next/navigation";
import { useState } from "react";
import { IconAlertTriangle, IconArrowRight, IconBox, IconCircleCheck, IconClock, IconDownload, IconPlus, IconRoute, IconTruck } from "@tabler/icons-react";
import { Card, DateRange, Empty, FilterSelect, PageHeader, Pagination, PrimaryButton, RowMenu, StatCard, StatusBadge, toast, usePaged } from "@/components/ui";
import { withConfirm } from "@/components/ui/Confirm";
import { Tabs } from "@/components/ui/Tabs";
import { TH, kg, shipTone } from "@/components/supply/common";
import { CreateShipmentModal, ReceiveModal } from "@/components/supply/forms";
import { downloadCSV } from "@/lib/csv";
import { useStore } from "@/lib/store";
import { NEXT_SHIPMENT, setShipmentStatus, type Shipment } from "@/lib/supply";

const TABS: Record<string, (x: Shipment) => boolean> = {
  "All Shipments": () => true,
  "In Transit": (x) => x.status === "In Transit" || x.status === "Dispatched",
  Receiving: (x) => x.status === "Receiving",
  Completed: (x) => x.status === "Delivered",
  Delayed: (x) => x.status === "Delayed",
  Discrepancies: (x) => x.status === "Discrepancy",
};

export default function ShipmentsPage() {
  const router = useRouter();
  const q = useSearchParams();
  const shipments = useStore((s) => s.shipments);
  const [tab, setTab] = useState(q.get("tab") && TABS[q.get("tab")!] ? q.get("tab")! : "All Shipments");
  const [mineral, setMineral] = useState("");
  const [open, setOpen] = useState(false);
  const [receiving, setReceiving] = useState<Shipment | null>(null);
  const rows = shipments.filter(TABS[tab]).filter((x) => !mineral || x.mineral === mineral);
  const { rows: page, pager } = usePaged(rows, 8);
  const count = (st: string) => shipments.filter((x) => x.status === st).length;

  return (
    <>
      <PageHeader
        crumb={{ icon: IconTruck, label: "Supply chain" }}
        title="Shipments"
        subtitle="Track and manage all mineral shipments across the supply chain."
        actions={<><DateRange label="Last 30 days" /><PrimaryButton icon={IconPlus} onClick={() => setOpen(true)}>Create Shipment</PrimaryButton></>}
      />

      <div className="grid grid-cols-1 gap-5 sm:grid-cols-2 xl:grid-cols-5">
        <StatCard icon={IconTruck} tone="green" label="Active Shipments" value={shipments.filter((x) => !["Delivered", "Pending"].includes(x.status)).length} delta="+8%" spark={[3, 4, 3, 5, 4, 6, 7]} />
        <StatCard icon={IconBox} tone="orange" label="In Transit" value={count("In Transit")} delta="+12%" spark={[2, 3, 3, 4, 3, 5, 6]} />
        <StatCard icon={IconCircleCheck} tone="green" label="Delivered" value={count("Delivered")} delta="+6%" spark={[3, 4, 5, 5, 6, 6, 7]} />
        <StatCard icon={IconClock} tone="orange" label="Delayed" value={count("Delayed")} deltaDir="down" delta="-25%" spark={[5, 4, 4, 3, 3, 2, 2]} />
        <StatCard icon={IconAlertTriangle} tone="green" label="Exceptions" value={count("Discrepancy")} deltaDir="down" delta="-50%" spark={[4, 3, 3, 2, 2, 1, 1]} />
      </div>

      <Card className="pt-5">
        <div className="flex flex-wrap items-end justify-between gap-3 border-b border-gray-100 px-5">
          <Tabs value={tab} onChange={setTab} items={Object.keys(TABS).map((k) => ({ key: k, label: k }))} />
          <div className="mb-3 flex gap-2">
            <FilterSelect label="All minerals" options={[...new Set(shipments.map((x) => x.mineral))]} value={mineral} onChange={setMineral} />
            <button
              onClick={() => {
                downloadCSV("shipments", rows, [["Shipment", (x) => x.id], ["Lot", (x) => x.lotId], ["Mineral", (x) => x.mineral], ["Origin", (x) => x.origin], ["Destination", (x) => x.destination], ["Kg", (x) => x.qtyKg], ["Status", (x) => x.status], ["ETA", (x) => x.eta]]);
                toast("Shipments exported");
              }}
              className="inline-flex items-center gap-1.5 rounded-full border border-gray-200 px-4 py-2 text-sm hover:bg-page"
            >
              <IconDownload className="size-4" /> Export
            </button>
          </div>
        </div>
        <div className="px-2 pt-4">
          {page.length === 0 ? (
            <Empty>No shipments here.</Empty>
          ) : (
            <table className="w-full text-left text-sm">
              <TH cols={["Shipment ID", "Mineral", "Origin", "Destination", "Quantity", "Status", "Expected Arrival", "Actions"]} />
              <tbody>
                {page.map((x) => {
                  const next = NEXT_SHIPMENT[x.status];
                  return (
                    <tr key={x.id} className="border-b border-gray-100 last:border-0">
                      <td className="px-3 py-3 font-medium"><Link href={`/supply/shipments/${x.id}`} className="hover:text-[#1F5B3A] hover:underline">{x.id}</Link><span className="block text-xs font-normal text-ink/60">{x.lotId}</span></td>
                      <td className="px-3">{x.mineral}</td>
                      <td className="px-3">{x.origin}</td>
                      <td className="px-3">{x.destination}</td>
                      <td className="px-3">{kg(x.qtyKg)}</td>
                      <td className="px-3"><StatusBadge tone={shipTone[x.status]}>{x.status}</StatusBadge>{x.note && <span className="block text-xs text-ink/60">{x.note}</span>}</td>
                      <td className="px-3 text-ink/70">{x.eta}</td>
                      <td className="px-3 text-right">
                        <RowMenu
                          items={[
                            { label: "Track lot", icon: IconRoute, onClick: () => router.push(`/supply/traceability?lot=${x.lotId}`) },
                            { label: "Open shipment", icon: IconTruck, onClick: () => router.push(`/supply/shipments/${x.id}`) },
                            ...(x.status === "Receiving" ? [{ label: "Weigh in and receive", icon: IconArrowRight, onClick: () => setReceiving(x) }] : next ? [{ label: `Mark ${next.toLowerCase()}`, icon: IconArrowRight, onClick: withConfirm({ title: `Mark ${x.id} ${next.toLowerCase()}?`, message: `${x.id} moves to ${next}.`, confirmLabel: "Confirm" }, () => (setShipmentStatus(x, next), toast(`${x.id}: ${next}`))) }] : []),
                            ...(x.status === "In Transit" || x.status === "Dispatched" ? [{ label: "Report delay", icon: IconClock, onClick: withConfirm({ title: "Report a delay?", message: `${x.id} is marked delayed and you are alerted until it moves again.`, confirmLabel: "Report delay" }, () => (setShipmentStatus(x, "Delayed"), toast(`${x.id} marked delayed`, "info"))) }] : []),
                            ...(x.status === "Discrepancy" ? [{ label: "Resolve and receive", icon: IconCircleCheck, onClick: withConfirm({ title: "Resolve discrepancy?", message: `The weight was checked. ${x.lotId} is received into ${x.destination}.`, confirmLabel: "Resolve" }, () => (setShipmentStatus(x, "Delivered", "Resolved after re-weighing"), toast(`${x.id} resolved`))) }] : []),
                          ]}
                        />
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          )}
        </div>
        <Pagination {...pager} noun="shipments" />
      </Card>

      {open && <CreateShipmentModal onClose={() => setOpen(false)} />}
      {receiving && <ReceiveModal shipment={receiving} onClose={() => setReceiving(null)} />}
    </>
  );
}
