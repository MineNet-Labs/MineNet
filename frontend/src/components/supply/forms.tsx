"use client";

import { CancelButton, Field, Modal, SubmitButton, formValues, inputClass, toast } from "@/components/ui";
import { Select } from "@/components/ui/Select";
import { useStore } from "@/lib/store";
import { useRouter } from "next/navigation";
import { CARRIERS, DESTINATIONS, ROYALTY, TRANSPORT_POINTS, USD_PER_KG, WAREHOUSES, createShipment, newBatch, newDeclaration, receiveShipment, registerStock, roomKg, startRefining } from "@/lib/supply";
import { getState } from "@/lib/store";
import { fmtInputDate } from "@/lib/domain";

type Close = { onClose: () => void };
const MINERALS = ["Gold", "Coltan", "Tantalum", "Tin", "Wolframite", "Cassiterite"];
const footer = (form: string, label: string, onClose: () => void) => (
  <>
    <CancelButton onClick={onClose} />
    <SubmitButton form={form}>{label}</SubmitButton>
  </>
);

export function CreateShipmentModal({ onClose, lotId }: Close & { lotId?: string }) {
  const stock = useStore((s) => s.stock);
  return (
    <Modal title="Create Shipment" subtitle="Assign a lot to a transport. It starts as Pending until it is dispatched." onClose={onClose} footer={footer("ship-form", "Create shipment", onClose)}>
      <form
        id="ship-form"
        className="grid grid-cols-2 gap-4"
        onSubmit={(e) => {
          const v = formValues(e);
          const lot = stock.find((l) => l.id === v.lot);
          const qty = Number(v.qty);
          if (lot && qty > lot.qtyKg) return toast(`${lot.id} only has ${lot.qtyKg} kg`, "error");
          if (qty > roomKg(getState(), v.destination)) return toast(`${v.destination} has room for ${roomKg(getState(), v.destination)} kg only`, "error");
          const id = createShipment({ lotId: v.lot, mineral: lot?.mineral ?? "", origin: v.origin, destination: v.destination, qtyKg: qty, eta: fmtInputDate(v.eta), carrier: v.carrier, vehicle: v.vehicle.toUpperCase(), driver: v.driver, seal: v.seal.toUpperCase() });
          toast(`Shipment ${id} created`);
          onClose();
        }}
      >
        <Field label="Mineral lot" className="col-span-2">
          <Select name="lot" required defaultValue={lotId ?? ""}>
            <option value="" disabled>Select lot</option>
            {stock.map((l) => <option key={l.id} value={l.id}>{l.id} · {l.mineral} · {l.qtyKg} kg · {l.location}</option>)}
          </Select>
        </Field>
        <Field label="From"><Select name="origin" defaultValue={WAREHOUSES[0]}>{[...WAREHOUSES, "Kigali Site", "Nyabihu Site"].map((w) => <option key={w}>{w}</option>)}</Select></Field>
        <Field label="To"><Select name="destination" defaultValue={TRANSPORT_POINTS[1]}>{TRANSPORT_POINTS.map((w) => <option key={w}>{w}</option>)}</Select></Field>
        <Field label="Quantity (kg)"><input name="qty" type="number" min={1} required className={inputClass} /></Field>
        <Field label="Expected arrival"><input name="eta" type="date" required className={inputClass} /></Field>
        <Field label="Carrier"><Select name="carrier" defaultValue={CARRIERS[0]}>{CARRIERS.map((c) => <option key={c}>{c}</option>)}</Select></Field>
        <Field label="Vehicle plate"><input name="vehicle" required placeholder="RAD 123A" className={inputClass} /></Field>
        <Field label="Driver"><input name="driver" required className={inputClass} /></Field>
        <Field label="Seal number" hint="Checked again at receiving"><input name="seal" required placeholder="SEAL-70421" className={inputClass} /></Field>
      </form>
    </Modal>
  );
}

export function RegisterStockModal({ onClose }: Close) {
  return (
    <Modal title="Register Inventory" subtitle="Stock received outside a MineNet shipment. It stays Pending until verified." onClose={onClose} footer={footer("stock-form", "Register", onClose)}>
      <form
        id="stock-form"
        className="grid grid-cols-2 gap-4"
        onSubmit={(e) => {
          const v = formValues(e);
          if (Number(v.qty) > roomKg(getState(), v.location)) return toast(`${v.location} has room for ${roomKg(getState(), v.location)} kg only`, "error");
          if (getState().stock.some((l) => l.id === v.id.toUpperCase())) return toast(`${v.id.toUpperCase()} is already in inventory`, "error");
          registerStock({ id: v.id.toUpperCase(), mineral: v.mineral, qtyKg: Number(v.qty), location: v.location, origin: v.origin });
          toast(`${v.id.toUpperCase()} registered`);
          onClose();
        }}
      >
        <Field label="Lot ID"><input name="id" required placeholder="LOT-2026-00500" className={inputClass} /></Field>
        <Field label="Mineral"><Select name="mineral" defaultValue="Gold">{MINERALS.map((m) => <option key={m}>{m}</option>)}</Select></Field>
        <Field label="Quantity (kg)"><input name="qty" type="number" min={1} required className={inputClass} /></Field>
        <Field label="Warehouse"><Select name="location" defaultValue={WAREHOUSES[0]}>{WAREHOUSES.map((w) => <option key={w}>{w}</option>)}</Select></Field>
        <Field label="Origin site" className="col-span-2"><input name="origin" required placeholder="e.g. Nyabihu Site" className={inputClass} /></Field>
      </form>
    </Modal>
  );
}

export function NewBatchModal({ onClose }: Close) {
  const stock = useStore((s) => s.stock).filter((l) => l.status === "Available");
  return (
    <Modal title="New Processing Batch" subtitle="Takes an available lot out of stock and starts processing it." onClose={onClose} footer={footer("batch-form", "Create batch", onClose)}>
      <form
        id="batch-form"
        className="grid grid-cols-2 gap-4"
        onSubmit={(e) => {
          const v = formValues(e);
          const lot = stock.find((l) => l.id === v.lot)!;
          const t = Number(v.input);
          if (t * 1000 > lot.qtyKg) return toast(`${lot.id} only has ${lot.qtyKg} kg`, "error");
          toast(`Batch ${newBatch(lot, t)} created`);
          onClose();
        }}
      >
        <Field label="Input lot" className="col-span-2">
          <Select name="lot" required defaultValue="">
            <option value="" disabled>{stock.length ? "Select an available lot" : "No available lots"}</option>
            {stock.map((l) => <option key={l.id} value={l.id}>{l.id} · {l.mineral} · {l.qtyKg} kg</option>)}
          </Select>
        </Field>
        <Field label="Input quantity (t)" className="col-span-2"><input name="input" type="number" step="0.01" min={0.01} required className={inputClass} /></Field>
      </form>
    </Modal>
  );
}

export function StartRefiningModal({ onClose }: Close) {
  const all = useStore((s) => s.batches);
  const refined = useStore((s) => s.refinery);
  const ready = all.filter((b) => b.status === "Completed" && !refined.some((r) => r.batchId === b.id));
  return (
    <Modal title="Start Refining Batch" subtitle="Processed output that passed its quality check goes to the refinery." onClose={onClose} footer={footer("ref-form", "Start batch", onClose)}>
      <form
        id="ref-form"
        onSubmit={(e) => {
          const v = formValues(e);
          toast(`Refining batch ${startRefining(ready.find((b) => b.id === v.batch)!)} started`);
          onClose();
        }}
      >
        <Field label="Processed batch" hint={ready.length ? undefined : "No processed batch is waiting. Complete a processing batch first."}>
          <Select name="batch" required defaultValue="">
            <option value="" disabled>{ready.length ? "Select batch" : "Nothing ready"}</option>
            {ready.map((b) => <option key={b.id} value={b.id}>{b.id} · {b.mineral} · {b.outputT} t output</option>)}
          </Select>
        </Field>
      </form>
    </Modal>
  );
}

export function NewDeclarationModal({ onClose }: Close) {
  const router = useRouter();
  const stock = useStore((s) => s.stock).filter((l) => l.status === "Available");
  return (
    <Modal title="New Export Declaration" subtitle="Saved as a draft. Attach the required documents and pay the royalty from the declaration page, then submit to customs." onClose={onClose} footer={footer("decl-form", "Save draft", onClose)}>
      <form
        id="decl-form"
        className="grid grid-cols-2 gap-4"
        onSubmit={(e) => {
          const v = formValues(e);
          const lot = stock.find((l) => l.id === v.lot)!;
          const qty = Number(v.qty);
          if (qty > lot.qtyKg) return toast(`${lot.id} only has ${lot.qtyKg} kg`, "error");
          const id = newDeclaration({ lotId: lot.id, mineral: lot.mineral, qtyKg: qty, destination: v.destination, buyer: v.buyer, valueUsd: Number(v.value) || qty * (USD_PER_KG[lot.mineral] ?? 0), royaltyPaid: false, docs: {} }, false);
          toast(`Draft ${id} saved`);
          onClose();
          router.push(`/supply/export/${id}`);
        }}
      >
        <Field label="Lot" className="col-span-2">
          <Select name="lot" required defaultValue="">
            <option value="" disabled>{stock.length ? "Select an available lot" : "No available lots"}</option>
            {stock.map((l) => <option key={l.id} value={l.id}>{l.id} · {l.mineral} · {l.qtyKg} kg</option>)}
          </Select>
        </Field>
        <Field label="Quantity (kg)"><input name="qty" type="number" min={1} required className={inputClass} /></Field>
        <Field label="Destination"><Select name="destination" defaultValue={DESTINATIONS[0]}>{DESTINATIONS.map((d) => <option key={d}>{d}</option>)}</Select></Field>
        <Field label="Buyer"><input name="buyer" required className={inputClass} /></Field>
        <Field label="Declared value (USD)" hint={`Leave empty to use the indicative price. Royalty: ${Math.round((ROYALTY.Gold ?? 0) * 100)}% gold, 4% other minerals.`}><input name="value" type="number" min={1} className={inputClass} /></Field>
      </form>
    </Modal>
  );
}

/** Weigh-in and seal check when a shipment arrives. */
export function ReceiveModal({ shipment, onClose }: Close & { shipment: import("@/lib/supply").Shipment }) {
  return (
    <Modal
      title={`Receive ${shipment.id}`}
      subtitle={`Expected ${shipment.qtyKg} kg of ${shipment.mineral} with seal ${shipment.seal}. A difference over 0.5% or a broken seal holds the lot for review.`}
      onClose={onClose}
      footer={footer("recv-form", "Record receipt", onClose)}
    >
      <form
        id="recv-form"
        className="grid grid-cols-2 gap-4"
        onSubmit={(e) => {
          const v = formValues(e);
          const ok = receiveShipment(shipment, Number(v.kg), v.seal === "yes");
          toast(ok ? `${shipment.id} received into ${shipment.destination}` : `${shipment.id} held: discrepancy recorded`, ok ? "success" : "info");
          onClose();
        }}
      >
        <Field label="Measured weight (kg)"><input name="kg" type="number" step="0.1" min={0} required defaultValue={shipment.qtyKg} className={inputClass} /></Field>
        <Field label={`Seal ${shipment.seal}`}>
          <Select name="seal" defaultValue="yes">
            <option value="yes">Intact and matching</option>
            <option value="no">Broken or not matching</option>
          </Select>
        </Field>
      </form>
    </Modal>
  );
}
