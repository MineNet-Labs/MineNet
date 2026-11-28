"use client";

import Link from "next/link";
import { useParams } from "next/navigation";
import { useState } from "react";
import { IconAlertTriangle, IconArrowRight, IconCircleCheck, IconClock, IconDownload, IconFileText, IconRoute, IconScale, IconTruck } from "@tabler/icons-react";
import { Card, CardTitle, PrimaryButton, StatusBadge, toast } from "@/components/ui";
import { withConfirm } from "@/components/ui/Confirm";
import { DetailHeader, Facts, NotFound } from "@/components/DetailShell";
import { kg, shipTone } from "@/components/supply/common";
import { ReceiveModal } from "@/components/supply/forms";
import { downloadFile } from "@/lib/csv";
import { useStore } from "@/lib/store";
import { NEXT_SHIPMENT, setShipmentStatus, type Shipment } from "@/lib/supply";

const docs = (x: Shipment): [string, string[]][] => [
  ["Waybill", [`Carrier: ${x.carrier}`, `Vehicle: ${x.vehicle} · Driver: ${x.driver}`, `From ${x.origin} to ${x.destination}`, `Cargo: ${x.qtyKg} kg ${x.mineral}, lot ${x.lotId}`, `Seal: ${x.seal}`, `Expected arrival: ${x.eta}`]],
  ["Packing list", [`Lot ${x.lotId}`, `Mineral: ${x.mineral}`, `Declared weight: ${x.qtyKg} kg`, `Packages sealed with ${x.seal}`]],
  ["Chain of custody", ["HANDOVERS", ...x.history.map((h) => `  ${h.date}  ${h.status}${h.note ? ` · ${h.note}` : ""}`), "", x.receivedKg !== undefined ? `Received weight: ${x.receivedKg} kg` : "Not received yet"]],
];

export function ShipmentDetail() {
  const { id } = useParams<{ id: string }>();
  const x = useStore((s) => s.shipments.find((v) => v.id === id));
  const [receiving, setReceiving] = useState(false);
  if (!x) return <NotFound what="Shipment" id={id} back="/supply/shipments" backLabel="Shipments" />;
  const next = NEXT_SHIPMENT[x.status];
  const diff = x.receivedKg !== undefined ? x.receivedKg - x.qtyKg : undefined;

  return (
    <>
      <DetailHeader
        back="/supply/shipments"
        backLabel="Shipments"
        title={x.id}
        badge={<StatusBadge tone={shipTone[x.status]}>{x.status}</StatusBadge>}
        subtitle={`${x.mineral} · ${kg(x.qtyKg)} · ${x.origin} → ${x.destination}`}
        actions={
          <>
            <Link href={`/supply/traceability?lot=${x.lotId}`} className="inline-flex items-center gap-2 rounded-2xl border border-gray-200 bg-white px-5 py-3 text-[15px] hover:bg-page"><IconRoute className="size-5" /> Track lot</Link>
            {x.status === "Receiving" && <PrimaryButton icon={IconScale} onClick={() => setReceiving(true)}>Weigh in and receive</PrimaryButton>}
            {next && x.status !== "Receiving" && (
              <PrimaryButton icon={IconArrowRight} onClick={withConfirm({ title: `Mark ${next.toLowerCase()}?`, message: `${x.id} moves to ${next}.`, confirmLabel: "Confirm" }, () => (setShipmentStatus(x, next), toast(`${x.id}: ${next}`)))}>
                Mark {next.toLowerCase()}
              </PrimaryButton>
            )}
          </>
        }
      />

      <div className="grid items-start gap-5 xl:grid-cols-[1fr_380px]">
        <div className="space-y-5">
          <Card className="p-5">
            <CardTitle icon={IconTruck} iconClass="text-accent">Transport</CardTitle>
            <div className="mt-4">
              <Facts
                items={[
                  ["Lot", <Link key="l" href={`/supply/traceability?lot=${x.lotId}`} className="text-accent hover:underline">{x.lotId}</Link>],
                  ["Carrier", x.carrier],
                  ["Vehicle", x.vehicle],
                  ["Driver", x.driver],
                  ["Seal", x.seal],
                  ["Departed", x.departed],
                  ["Expected arrival", x.eta],
                  ["Declared weight", kg(x.qtyKg)],
                  ["Received weight", x.receivedKg !== undefined ? `${kg(x.receivedKg)}${diff ? ` (${diff > 0 ? "+" : ""}${diff} kg)` : ""}` : "—"],
                ]}
              />
            </div>
            {x.status === "Discrepancy" && (
              <div className="mt-5 flex flex-wrap items-center justify-between gap-3 rounded-2xl bg-danger-soft p-4 text-sm">
                <span className="flex items-center gap-2 text-danger"><IconAlertTriangle className="size-5" /> {x.note}</span>
                <button
                  onClick={withConfirm({ title: "Resolve discrepancy?", message: `After re-weighing and checking the seal, ${x.lotId} is received with ${kg(x.receivedKg ?? x.qtyKg)}.`, confirmLabel: "Resolve and receive" }, () => (setShipmentStatus(x, "Delivered", "Resolved after investigation"), toast(`${x.id} resolved`)))}
                  className="rounded-full bg-[#1F5B3A] px-4 py-2 font-medium text-white"
                >
                  Resolve and receive
                </button>
              </div>
            )}
          </Card>

          <Card className="p-5">
            <CardTitle icon={IconClock} iconClass="text-accent">Custody timeline</CardTitle>
            <ol className="mt-4 space-y-3 border-l-2 border-gray-100 pl-5 text-sm">
              {x.history.map((h, i) => (
                <li key={i} className="relative flex flex-wrap justify-between gap-2">
                  <i className="absolute top-1.5 -left-[27px] size-3 rounded-full bg-[#1F5B3A]" />
                  <span><b className="font-medium">{h.status}</b>{h.note && <span className="text-ink/70"> · {h.note}</span>}</span>
                  <span className="text-ink/60">{h.date}</span>
                </li>
              ))}
            </ol>
          </Card>
        </div>

        <Card className="p-5">
          <CardTitle icon={IconFileText} iconClass="text-accent">Transport documents</CardTitle>
          <ul className="mt-4 space-y-3">
            {docs(x).map(([name, lines]) => (
              <li key={name} className="flex items-center justify-between gap-3 rounded-2xl border border-gray-100 p-3">
                <span><b className="block font-medium">{name}</b><span className="text-xs text-ink/60">{x.id} · PDF</span></span>
                <button aria-label={`Download ${name}`} onClick={() => (downloadFile(`${x.id}-${name.replace(/\s+/g, "-")}.txt`, [`${name.toUpperCase()} · ${x.id}`, "", ...lines].join("\n")), toast(`${name} downloaded`))} className="grid size-9 place-items-center rounded-full border border-gray-200 hover:bg-page">
                  <IconDownload className="size-4" />
                </button>
              </li>
            ))}
          </ul>
          {x.status === "Delivered" && <p className="mt-4 flex items-center gap-2 text-sm text-[#1F5B3A]"><IconCircleCheck className="size-5" /> In stock at {x.destination}</p>}
        </Card>
      </div>

      {receiving && <ReceiveModal shipment={x} onClose={() => setReceiving(false)} />}
    </>
  );
}
