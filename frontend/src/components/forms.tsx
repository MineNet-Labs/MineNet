"use client";

// Create/edit forms shared across miner pages. Each saves to the store and
// confirms with a toast; the calling page decides when to open it.

import { useMemo, useState } from "react";
import { CancelButton, Field, Modal, SubmitButton, formValues, inputClass, toast } from "@/components/ui";
import { MINERALS, WORK_CATEGORIES, fmtKg, today, type BuyerRequest, type Doc } from "@/lib/data";
import { getState, nextId, update, useStore } from "@/lib/store";

type Close = { onClose: () => void };

const sel = `${inputClass} pr-8`;

/* ------------------------------------------------------------------ lot */

export function CreateLotModal({ onClose, siteId }: Close & { siteId?: string }) {
  const sites = useStore((s) => s.sites);
  return (
    <Modal
      title="Register Mineral Lot"
      subtitle="A lot gets its digital passport once registered. Request an inspection to verify it."
      onClose={onClose}
      footer={<><CancelButton onClick={onClose} /><SubmitButton form="lot-form">Register Lot</SubmitButton></>}
    >
      <form
        id="lot-form"
        className="grid grid-cols-2 gap-4"
        onSubmit={(e) => {
          const v = formValues(e);
          const id = nextId(getState().lots.map((l) => l.id), "LOT-");
          update((s) => ({
            lots: [
              { id, mineral: v.mineral, quantityKg: Number(v.quantity), grade: Number(v.grade), siteId: v.site, status: "Pending", created: today() },
              ...s.lots,
            ],
          }));
          toast(`Lot ${id} registered — pending verification`);
          onClose();
        }}
      >
        <Field label="Mining site">
          <select name="site" required defaultValue={siteId ?? ""} className={sel}>
            <option value="" disabled>Select site</option>
            {sites.filter((s) => s.status === "Active").map((s) => <option key={s.id} value={s.id}>{s.name}</option>)}
          </select>
        </Field>
        <Field label="Mineral">
          <select name="mineral" required defaultValue="" className={sel}>
            <option value="" disabled>Select mineral</option>
            {MINERALS.map((m) => <option key={m}>{m}</option>)}
          </select>
        </Field>
        <Field label="Quantity (kg)">
          <input name="quantity" type="number" min={1} step="any" required className={inputClass} placeholder="e.g. 500" />
        </Field>
        <Field label="Declared grade (%)">
          <input name="grade" type="number" min={0} max={100} step="0.1" required className={inputClass} placeholder="e.g. 65.5" />
        </Field>
      </form>
    </Modal>
  );
}

/* ----------------------------------------------------------------- site */

export function RegisterSiteModal({ onClose }: Close) {
  return (
    <Modal
      title="Register Mineral Site"
      subtitle="The site needs a valid mining licence issued by the regulator."
      onClose={onClose}
      footer={<><CancelButton onClick={onClose} /><SubmitButton form="site-form">Register Site</SubmitButton></>}
    >
      <form
        id="site-form"
        className="grid grid-cols-2 gap-4"
        onSubmit={(e) => {
          const v = formValues(e);
          const id = v.name.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/(^-|-$)/g, "") + "-" + Date.now().toString(36).slice(-4);
          update((s) => ({
            sites: [
              {
                id,
                name: v.name,
                district: v.district,
                location: v.district,
                lat: Number(v.lat),
                lng: Number(v.lng),
                status: "Active",
                areaHa: Number(v.area),
                lastActivity: today(),
                minerals: [v.mineral],
                licence: v.licence,
                licenceExpiry: v.expiry ? new Date(v.expiry).toLocaleDateString("en-US", { month: "short", day: "2-digit", year: "numeric" }) : "—",
                manager: v.manager,
              },
              ...s.sites,
            ],
          }));
          toast(`${v.name} registered`);
          onClose();
        }}
      >
        <Field label="Site name" className="col-span-2">
          <input name="name" required className={inputClass} placeholder="e.g. Karongi Gold Site" />
        </Field>
        <Field label="District">
          <input name="district" required className={inputClass} placeholder="e.g. Karongi" />
        </Field>
        <Field label="Main mineral">
          <select name="mineral" required defaultValue="" className={sel}>
            <option value="" disabled>Select mineral</option>
            {MINERALS.map((m) => <option key={m}>{m}</option>)}
          </select>
        </Field>
        <Field label="Latitude" hint="Rwanda is between -2.84 and -1.05">
          <input name="lat" type="number" step="any" min={-2.84} max={-1.05} required className={inputClass} placeholder="-2.06" />
        </Field>
        <Field label="Longitude" hint="Rwanda is between 28.86 and 30.90">
          <input name="lng" type="number" step="any" min={28.86} max={30.9} required className={inputClass} placeholder="29.35" />
        </Field>
        <Field label="Total area (ha)">
          <input name="area" type="number" min={0.1} step="0.1" required className={inputClass} />
        </Field>
        <Field label="Site manager">
          <input name="manager" required className={inputClass} />
        </Field>
        <Field label="Mining licence number">
          <input name="licence" required className={inputClass} placeholder="ML-2025-…" />
        </Field>
        <Field label="Licence expiry">
          <input name="expiry" type="date" className={inputClass} />
        </Field>
      </form>
    </Modal>
  );
}

/* --------------------------------------------------- extraction record */

export function NewRecordModal({ onClose, siteId }: Close & { siteId?: string }) {
  const sites = useStore((s) => s.sites);
  const shafts = useStore((s) => s.shafts);
  const [site, setSite] = useState(siteId ?? "");
  return (
    <Modal
      title="New Extraction Record"
      subtitle="Records are approved after the site supervisor confirms the weighbridge reading."
      onClose={onClose}
      footer={<><CancelButton onClick={onClose} /><SubmitButton form="rec-form">Save Record</SubmitButton></>}
    >
      <form
        id="rec-form"
        className="grid grid-cols-2 gap-4"
        onSubmit={(e) => {
          const v = formValues(e);
          const id = nextId(getState().records.map((r) => r.id), "ER-2025-", 4);
          update((s) => ({
            records: [
              { id, siteId: v.site, shaftId: v.shaft || undefined, mineral: v.mineral, quantityKg: Number(v.quantity), date: today(), status: "Pending" },
              ...s.records,
            ],
          }));
          toast(`Extraction record ${id} saved`);
          onClose();
        }}
      >
        <Field label="Mining site">
          <select name="site" required value={site} onChange={(e) => setSite(e.target.value)} className={sel}>
            <option value="" disabled>Select site</option>
            {sites.map((s) => <option key={s.id} value={s.id}>{s.name}</option>)}
          </select>
        </Field>
        <Field label="Mine shaft">
          <select name="shaft" defaultValue="" className={sel}>
            <option value="">Not shaft-specific</option>
            {shafts.filter((s) => s.siteId === site).map((s) => <option key={s.id} value={s.id}>{s.name}</option>)}
          </select>
        </Field>
        <Field label="Mineral">
          <select name="mineral" required defaultValue="" className={sel}>
            <option value="" disabled>Select mineral</option>
            {MINERALS.map((m) => <option key={m}>{m}</option>)}
          </select>
        </Field>
        <Field label="Quantity (kg)">
          <input name="quantity" type="number" min={1} step="any" required className={inputClass} />
        </Field>
      </form>
    </Modal>
  );
}

/* --------------------------------------------------------------- worker */

export function AddWorkerModal({ onClose, siteId }: Close & { siteId?: string }) {
  const sites = useStore((s) => s.sites);
  return (
    <Modal
      title="Add Worker"
      subtitle="The worker gets a QR access code linked to their site for first sign-in."
      onClose={onClose}
      footer={<><CancelButton onClick={onClose} /><SubmitButton form="wrk-form">Add Worker</SubmitButton></>}
    >
      <form
        id="wrk-form"
        className="grid grid-cols-2 gap-4"
        onSubmit={(e) => {
          const v = formValues(e);
          const id = nextId(getState().workers.map((w) => w.id), "WRK-", 4);
          update((s) => ({
            workers: [
              { id, name: v.name, siteId: v.site, category: v.category, access: "Setup pending", status: "Active", phone: v.phone, joined: today() },
              ...s.workers,
            ],
          }));
          toast(`${v.name} added — QR access pending first sign-in`);
          onClose();
        }}
      >
        <Field label="Full name" className="col-span-2">
          <input name="name" required className={inputClass} />
        </Field>
        <Field label="Phone number">
          <input name="phone" type="tel" required className={inputClass} placeholder="+250 7XX XXX XXX" />
        </Field>
        <Field label="Site">
          <select name="site" required defaultValue={siteId ?? ""} className={sel}>
            <option value="" disabled>Select site</option>
            {sites.map((s) => <option key={s.id} value={s.id}>{s.name}</option>)}
          </select>
        </Field>
        <Field label="Work category" className="col-span-2">
          <select name="category" required defaultValue="" className={sel}>
            <option value="" disabled>Select category</option>
            {WORK_CATEGORIES.map((c) => <option key={c}>{c}</option>)}
          </select>
        </Field>
      </form>
    </Modal>
  );
}

/* ---------------------------------------------------------------- shaft */

export function AddShaftModal({ onClose, siteId }: Close & { siteId?: string }) {
  const sites = useStore((s) => s.sites);
  return (
    <Modal
      title="Add Mine Shaft"
      onClose={onClose}
      footer={<><CancelButton onClick={onClose} /><SubmitButton form="shaft-form">Add Shaft</SubmitButton></>}
    >
      <form
        id="shaft-form"
        className="grid grid-cols-2 gap-4"
        onSubmit={(e) => {
          const v = formValues(e);
          const code = v.code.toUpperCase();
          if (getState().shafts.some((s) => s.id === code)) {
            toast(`Shaft ${code} already exists`, "error");
            return;
          }
          update((s) => ({
            shafts: [
              { id: code, siteId: v.site, name: `Shaft ${code}`, depthM: Number(v.depth), mineral: v.mineral, status: "Operational", lastInspection: "—" },
              ...s.shafts,
            ],
          }));
          toast(`Shaft ${code} added`);
          onClose();
        }}
      >
        <Field label="Site">
          <select name="site" required defaultValue={siteId ?? ""} className={sel}>
            <option value="" disabled>Select site</option>
            {sites.map((s) => <option key={s.id} value={s.id}>{s.name}</option>)}
          </select>
        </Field>
        <Field label="Shaft code">
          <input name="code" required className={inputClass} placeholder="e.g. K-05" />
        </Field>
        <Field label="Depth (m)">
          <input name="depth" type="number" min={1} required className={inputClass} />
        </Field>
        <Field label="Mineral">
          <select name="mineral" required defaultValue="" className={sel}>
            <option value="" disabled>Select mineral</option>
            {MINERALS.map((m) => <option key={m}>{m}</option>)}
          </select>
        </Field>
      </form>
    </Modal>
  );
}

/* ------------------------------------------------------------- document */

export function UploadDocModal({ onClose }: Close) {
  const sites = useStore((s) => s.sites);
  const kinds: Doc["kind"][] = ["Mining Licence", "Export Permit", "Transport Permit", "Environmental", "Certificate", "Other"];
  return (
    <Modal
      title="Upload Document"
      subtitle="PDF, JPG or PNG · up to 10 MB. Only the file name is stored until the backend is connected."
      onClose={onClose}
      footer={<><CancelButton onClick={onClose} /><SubmitButton form="doc-form">Upload</SubmitButton></>}
    >
      <form
        id="doc-form"
        className="grid grid-cols-2 gap-4"
        onSubmit={(e) => {
          const fd = new FormData(e.currentTarget);
          const v = formValues(e);
          const file = fd.get("file") as File | null;
          const id = nextId(getState().docs.map((d) => d.id), "DOC-", 3);
          const fmt = (d: string) => (d ? new Date(d).toLocaleDateString("en-US", { month: "short", day: "2-digit", year: "numeric" }) : undefined);
          update((s) => ({
            docs: [
              { id, name: v.name, kind: v.kind as Doc["kind"], siteId: v.site || undefined, number: v.number, issued: fmt(v.issued) ?? today(), expires: fmt(v.expires), fileName: file?.name || `${v.number}.pdf` },
              ...s.docs,
            ],
          }));
          toast(`${v.name} uploaded`);
          onClose();
        }}
      >
        <Field label="Document name" className="col-span-2">
          <input name="name" required className={inputClass} />
        </Field>
        <Field label="Type">
          <select name="kind" required defaultValue="" className={sel}>
            <option value="" disabled>Select type</option>
            {kinds.map((k) => <option key={k}>{k}</option>)}
          </select>
        </Field>
        <Field label="Reference number">
          <input name="number" required className={inputClass} />
        </Field>
        <Field label="Issued">
          <input name="issued" type="date" required className={inputClass} />
        </Field>
        <Field label="Expires (optional)">
          <input name="expires" type="date" className={inputClass} />
        </Field>
        <Field label="Related site (optional)">
          <select name="site" defaultValue="" className={sel}>
            <option value="">None</option>
            {sites.map((s) => <option key={s.id} value={s.id}>{s.name}</option>)}
          </select>
        </Field>
        <Field label="File">
          <input name="file" type="file" required accept=".pdf,.jpg,.jpeg,.png" className="block w-full text-sm file:mr-3 file:rounded-full file:border-0 file:bg-primary-soft file:px-4 file:py-2 file:text-[#1F5B3A]" />
        </Field>
      </form>
    </Modal>
  );
}

/* ----------------------------------------------------- marketplace: sell */

export function ListLotModal({ onClose, onListed, lotId }: Close & { onListed?: () => void; lotId?: string }) {
  const lots = useStore((s) => s.lots);
  const listings = useStore((s) => s.listings);
  const sites = useStore((s) => s.sites);
  // Only verified lots that aren't already on the market can be listed.
  const available = useMemo(
    () => lots.filter((l) => l.status === "Verified" && !listings.some((x) => x.lotId === l.id && x.status === "Active")),
    [lots, listings],
  );
  const [chosen, setChosen] = useState(lotId && available.some((l) => l.id === lotId) ? lotId : "");
  const lot = lots.find((l) => l.id === chosen);
  const site = sites.find((s) => s.id === lot?.siteId);

  return (
    <Modal
      title="Sell on Marketplace"
      subtitle="List a verified lot so buyers can see it and send you offers."
      onClose={onClose}
      footer={<><CancelButton onClick={onClose} /><SubmitButton form="list-form">Publish Listing</SubmitButton></>}
    >
      {available.length === 0 ? (
        <p className="text-sm text-ink/70">
          You have no verified lots available to list. Lots must pass inspection before they can be sold.
        </p>
      ) : (
        <form
          id="list-form"
          className="grid grid-cols-2 gap-4"
          onSubmit={(e) => {
            const v = formValues(e);
            const l = lots.find((x) => x.id === v.lot)!;
            const s = sites.find((x) => x.id === l.siteId);
            const id = nextId(getState().listings.map((x) => x.id), "LST-", 4);
            update((st) => ({
              listings: [
                {
                  id,
                  lotId: l.id,
                  mineral: l.mineral,
                  quantityKg: Number(v.quantity),
                  pricePerKg: Number(v.price),
                  currency: v.currency as "USD" | "RWF",
                  location: s ? `${s.district}, Rwanda` : "Rwanda",
                  status: "Active",
                  offers: 0,
                  posted: today(),
                  notes: v.notes,
                },
                ...st.listings,
              ],
            }));
            toast(`${l.mineral} lot ${l.id} is now listed on the marketplace`);
            onListed?.();
            onClose();
          }}
        >
          <Field label="Verified lot" className="col-span-2">
            <select name="lot" required value={chosen} onChange={(e) => setChosen(e.target.value)} className={sel}>
              <option value="" disabled>Select a lot</option>
              {available.map((l) => (
                <option key={l.id} value={l.id}>
                  {l.id} · {l.mineral} · {fmtKg(l.quantityKg)} · {l.grade}%
                </option>
              ))}
            </select>
          </Field>
          {lot && (
            <div className="col-span-2 grid grid-cols-3 gap-4 rounded-2xl bg-page px-4 py-3 text-sm">
              <div><p className="text-ink/60">Origin</p><p className="font-medium">{site?.name}</p></div>
              <div><p className="text-ink/60">Grade</p><p className="font-medium">{lot.grade}%</p></div>
              <div><p className="text-ink/60">Available</p><p className="font-medium">{fmtKg(lot.quantityKg)}</p></div>
            </div>
          )}
          <Field label="Quantity to sell (kg)">
            <input name="quantity" type="number" min={1} max={lot?.quantityKg} step="any" required defaultValue={lot?.quantityKg} key={lot?.id} className={inputClass} />
          </Field>
          <Field label="Asking price per kg">
            <div className="flex gap-2">
              <input name="price" type="number" min={0.01} step="0.01" required className={inputClass} />
              <select name="currency" defaultValue="USD" className={`${sel} w-28`}>
                <option>USD</option>
                <option>RWF</option>
              </select>
            </div>
          </Field>
          <Field label="Notes for buyers (optional)" className="col-span-2">
            <input name="notes" className={inputClass} placeholder="e.g. collection from site, ITSCI tagged" />
          </Field>
        </form>
      )}
    </Modal>
  );
}

/* --------------------------------------------------- marketplace: offer */

export function MakeOfferModal({ onClose, request }: Close & { request: BuyerRequest }) {
  const lots = useStore((s) => s.lots);
  const matching = lots.filter((l) => l.status === "Verified" && l.mineral === request.mineral);
  const max = Math.round(request.remainingT * 1000);
  return (
    <Modal
      title={`Make Offer · ${request.buyer}`}
      subtitle={`${request.mineral} · ${request.grade} · ${fmtKg(max)} still needed · delivers to ${request.city}`}
      onClose={onClose}
      footer={<><CancelButton onClick={onClose} /><SubmitButton form="offer-form">Send Offer</SubmitButton></>}
    >
      {matching.length === 0 ? (
        <p className="text-sm text-ink/70">
          You have no verified {request.mineral} lots to offer. Register a lot and get it inspected first.
        </p>
      ) : (
        <form
          id="offer-form"
          className="grid grid-cols-2 gap-4"
          onSubmit={(e) => {
            const v = formValues(e);
            const id = nextId(getState().offers.map((o) => o.id), "OFF-", 4);
            update((s) => ({
              offers: [
                { id, requestId: request.id, lotId: v.lot, quantityKg: Number(v.quantity), pricePerKg: Number(v.price), currency: "USD", status: "Sent", sent: today() },
                ...s.offers,
              ],
              requests: s.requests.map((r) => (r.id === request.id ? { ...r, offers: r.offers + 1 } : r)),
            }));
            toast(`Offer sent to ${request.buyer}`);
            onClose();
          }}
        >
          <Field label="Your lot" className="col-span-2">
            <select name="lot" required defaultValue="" className={sel}>
              <option value="" disabled>Select a verified lot</option>
              {matching.map((l) => (
                <option key={l.id} value={l.id}>{l.id} · {fmtKg(l.quantityKg)} · {l.grade}%</option>
              ))}
            </select>
          </Field>
          <Field label="Quantity (kg)" hint={`Up to ${fmtKg(max)}`}>
            <input name="quantity" type="number" min={1} max={max} required className={inputClass} />
          </Field>
          <Field label="Price per kg (USD)" hint={`Buyer's indicative price: $${request.pricePerKg}`}>
            <input name="price" type="number" min={0.01} step="0.01" required defaultValue={request.pricePerKg} className={inputClass} />
          </Field>
        </form>
      )}
    </Modal>
  );
}
