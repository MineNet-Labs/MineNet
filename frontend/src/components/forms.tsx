"use client";

import { confirmAction } from "@/components/ui/Confirm";

// Create/edit forms shared across miner pages. Each saves to the store and
// confirms with a toast; the calling page decides when to open it.

import { useMemo, useState } from "react";
import { Select } from "@/components/ui/Select";
import {
  CancelButton,
  Field,
  Modal,
  SubmitButton,
  formValues,
  inputClass,
  toast,
} from "@/components/ui";
import {
  MINERALS,
  WORK_CATEGORIES,
  fmtKg,
  today,
  type BuyerRequest,
  type Doc,
} from "@/lib/data";
import { getState, nextId, siteName, update, useStore } from "@/lib/store";
import { addOrRequest, needsApproval } from "@/lib/approvals";
import {
  fmtInputDate,
  listingChecklist,
  makeEvent,
  makeNotice,
  orgCanAct,
  priceGuidance,
  siteCanRegister,
} from "@/lib/domain";
import { extractDocument } from "@/lib/ai";
import {
  IconCircleCheck,
  IconCircleDashed,
  IconSparkles,
} from "@tabler/icons-react";
import Link from "next/link";

type Close = { onClose: () => void };

const sel = `${inputClass} pr-8`;

/* ------------------------------------------------------------------ lot */

export function CreateLotModal({
  onClose,
  siteId,
}: Close & { siteId?: string }) {
  const state = useStore((s) => s);
  const sites = state.sites;
  if (!orgCanAct(state)) {
    return (
      <Modal
        title="Register Mineral Lot"
        subtitle="Lot registration is blocked"
        onClose={onClose}
        footer={<CancelButton onClick={onClose} />}
      >
        <p className="text-sm text-ink/80">
          Your organisation is <b>{state.org.status.toLowerCase()}</b> with RMB.
          Lots can only be registered while your validation is valid.{" "}
          <Link
            href="/miner/licence"
            onClick={onClose}
            className="font-medium text-accent hover:underline"
          >
            See Licence & Validation
          </Link>
        </p>
      </Modal>
    );
  }
  return (
    <Modal
      title="Register Mineral Lot"
      subtitle="A lot gets its digital passport once registered. Request an inspection to verify it."
      onClose={onClose}
      footer={
        <>
          <CancelButton onClick={onClose} />
          <SubmitButton form="lot-form">Register Lot</SubmitButton>
        </>
      }
    >
      <form
        id="lot-form"
        className="grid grid-cols-2 gap-4"
        onSubmit={(e) => {
          const v = formValues(e);
          const id = nextId(
            getState().lots.map((l) => l.id),
            "LOT-",
          );
          update((s) => ({
            lots: [
              {
                id,
                mineral: v.mineral,
                quantityKg: Number(v.quantity),
                grade: Number(v.grade),
                siteId: v.site,
                status: "Pending",
                created: today(),
              },
              ...s.lots,
            ],
            notices: [
              makeNotice(
                s,
                "inspection",
                `Lot ${id} registered: request an inspection to verify it`,
                `/miner/mineral-lots/${id}`,
              ),
              ...s.notices,
            ],
          }));
          toast(`Lot ${id} registered — pending verification`);
          onClose();
        }}
      >
        {siteId ? (
          <Field label="Mining site">
            <input type="hidden" name="site" value={siteId} />
            <input
              readOnly
              value={
                getState().sites.find((x) => x.id === siteId)?.name ?? siteId
              }
              className={`${inputClass} bg-page`}
            />
          </Field>
        ) : (
          <Field label="Mining site">
            <Select
              name="site"
              required
              defaultValue={siteId ?? ""}
              className={sel}
            >
              <option value="" disabled>
                Select site
              </option>
              {sites
                .filter((s) => s.status === "Active")
                .map((s) => (
                  <option
                    key={s.id}
                    value={s.id}
                    disabled={!siteCanRegister(state, s)}
                  >
                    {s.name}
                    {siteCanRegister(state, s) ? "" : " (licence expired)"}
                  </option>
                ))}
            </Select>
          </Field>
        )}
        <Field label="Mineral">
          <Select name="mineral" required defaultValue="" className={sel}>
            <option value="" disabled>
              Select mineral
            </option>
            {MINERALS.map((m) => (
              <option key={m}>{m}</option>
            ))}
          </Select>
        </Field>
        <Field label="Quantity (kg)">
          <input
            name="quantity"
            type="number"
            min={1}
            step="any"
            required
            className={inputClass}
            placeholder="e.g. 500"
          />
        </Field>
        <Field label="Declared grade (%)">
          <input
            name="grade"
            type="number"
            min={0}
            max={100}
            step="0.1"
            required
            className={inputClass}
            placeholder="e.g. 65.5"
          />
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
      footer={
        <>
          <CancelButton onClick={onClose} />
          <SubmitButton form="site-form">Register Site</SubmitButton>
        </>
      }
    >
      <form
        id="site-form"
        className="grid grid-cols-2 gap-4"
        onSubmit={(e) => {
          const v = formValues(e);
          const id =
            v.name
              .toLowerCase()
              .replace(/[^a-z0-9]+/g, "-")
              .replace(/(^-|-$)/g, "") +
            "-" +
            Date.now().toString(36).slice(-4);
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
                licenceExpiry: v.expiry
                  ? new Date(v.expiry).toLocaleDateString("en-US", {
                      month: "short",
                      day: "2-digit",
                      year: "numeric",
                    })
                  : "—",
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
          <input
            name="name"
            required
            className={inputClass}
            placeholder="e.g. Karongi Gold Site"
          />
        </Field>
        <Field label="District">
          <input
            name="district"
            required
            className={inputClass}
            placeholder="e.g. Karongi"
          />
        </Field>
        <Field label="Main mineral">
          <Select name="mineral" required defaultValue="" className={sel}>
            <option value="" disabled>
              Select mineral
            </option>
            {MINERALS.map((m) => (
              <option key={m}>{m}</option>
            ))}
          </Select>
        </Field>
        <Field label="Latitude" hint="Rwanda is between -2.84 and -1.05">
          <input
            name="lat"
            type="number"
            step="any"
            min={-2.84}
            max={-1.05}
            required
            className={inputClass}
            placeholder="-2.06"
          />
        </Field>
        <Field label="Longitude" hint="Rwanda is between 28.86 and 30.90">
          <input
            name="lng"
            type="number"
            step="any"
            min={28.86}
            max={30.9}
            required
            className={inputClass}
            placeholder="29.35"
          />
        </Field>
        <Field label="Total area (ha)">
          <input
            name="area"
            type="number"
            min={0.1}
            step="0.1"
            required
            className={inputClass}
          />
        </Field>
        <Field label="Site manager">
          <input name="manager" required className={inputClass} />
        </Field>
        <Field label="Mining licence number">
          <input
            name="licence"
            required
            className={inputClass}
            placeholder="ML-2025-…"
          />
        </Field>
        <Field label="Licence expiry">
          <input name="expiry" type="date" className={inputClass} />
        </Field>
      </form>
    </Modal>
  );
}

/* --------------------------------------------------- extraction record */

export function NewRecordModal({
  onClose,
  siteId,
}: Close & { siteId?: string }) {
  const sites = useStore((s) => s.sites);
  const shafts = useStore((s) => s.shafts);
  const [site, setSite] = useState(siteId ?? "");
  return (
    <Modal
      title="New Extraction Record"
      subtitle="Records are approved after the site supervisor confirms the weighbridge reading."
      onClose={onClose}
      footer={
        <>
          <CancelButton onClick={onClose} />
          <SubmitButton form="rec-form">Save Record</SubmitButton>
        </>
      }
    >
      <form
        id="rec-form"
        className="grid grid-cols-2 gap-4"
        onSubmit={(e) => {
          const v = formValues(e);
          const id = nextId(
            getState().records.map((r) => r.id),
            "ER-2025-",
            4,
          );
          update((s) => ({
            records: [
              {
                id,
                siteId: v.site,
                shaftId: v.shaft || undefined,
                mineral: v.mineral,
                quantityKg: Number(v.quantity),
                date: today(),
                status: "Pending",
              },
              ...s.records,
            ],
          }));
          toast(`Extraction record ${id} saved`);
          onClose();
        }}
      >
        {siteId ? (
          <Field label="Mining site">
            <input type="hidden" name="site" value={siteId} />
            <input
              readOnly
              value={
                getState().sites.find((x) => x.id === siteId)?.name ?? siteId
              }
              className={`${inputClass} bg-page`}
            />
          </Field>
        ) : (
          <Field label="Mining site">
            <Select
              name="site"
              required
              value={site}
              onChange={(e) => setSite(e.target.value)}
              className={sel}
            >
              <option value="" disabled>
                Select site
              </option>
              {sites.map((s) => (
                <option key={s.id} value={s.id}>
                  {s.name}
                </option>
              ))}
            </Select>
          </Field>
        )}
        <Field label="Mine shaft">
          <Select name="shaft" defaultValue="" className={sel}>
            <option value="">Not shaft-specific</option>
            {shafts
              .filter((s) => s.siteId === site)
              .map((s) => (
                <option key={s.id} value={s.id}>
                  {s.name}
                </option>
              ))}
          </Select>
        </Field>
        <Field label="Mineral">
          <Select name="mineral" required defaultValue="" className={sel}>
            <option value="" disabled>
              Select mineral
            </option>
            {MINERALS.map((m) => (
              <option key={m}>{m}</option>
            ))}
          </Select>
        </Field>
        <Field label="Quantity (kg)">
          <input
            name="quantity"
            type="number"
            min={1}
            step="any"
            required
            className={inputClass}
          />
        </Field>
      </form>
    </Modal>
  );
}

/* --------------------------------------------------------------- worker */

export function AddWorkerModal({
  onClose,
  siteId,
}: Close & { siteId?: string }) {
  const sites = useStore((s) => s.sites);
  return (
    <Modal
      title="Add Worker"
      subtitle="The worker gets a QR access code linked to their site for first sign-in."
      onClose={onClose}
      footer={
        <>
          <CancelButton onClick={onClose} />
          <SubmitButton form="wrk-form">Add Worker</SubmitButton>
        </>
      }
    >
      <form
        id="wrk-form"
        className="grid grid-cols-2 gap-4"
        onSubmit={(e) => {
          const v = formValues(e);
          const id = nextId(
            getState().workers.map((w) => w.id),
            "WRK-",
            4,
          );
          const item = { id, name: v.name, siteId: v.site, category: v.category, access: "Setup pending" as const, status: "Active" as const, phone: v.phone, joined: today() };
          if (addOrRequest("New worker", `Hire ${v.name} as ${v.category}`, v.site, [{ to: "workers", item }])) toast(`${v.name} added — QR access pending first sign-in`);
          else toast("Sent to the owner for approval", "info");
          onClose();
        }}
      >
        <Field label="Full name" className="col-span-2">
          <input name="name" required className={inputClass} />
        </Field>
        <Field label="Phone number">
          <input
            name="phone"
            type="tel"
            required
            className={inputClass}
            placeholder="+250 7XX XXX XXX"
          />
        </Field>
        {siteId ? (
          <Field label="Site">
            <input type="hidden" name="site" value={siteId} />
            <input
              readOnly
              value={
                getState().sites.find((x) => x.id === siteId)?.name ?? siteId
              }
              className={`${inputClass} bg-page`}
            />
          </Field>
        ) : (
          <Field label="Site">
            <Select
              name="site"
              required
              defaultValue={siteId ?? ""}
              className={sel}
            >
              <option value="" disabled>
                Select site
              </option>
              {sites.map((s) => (
                <option key={s.id} value={s.id}>
                  {s.name}
                </option>
              ))}
            </Select>
          </Field>
        )}
        <Field label="Work category" className="col-span-2">
          <Select name="category" required defaultValue="" className={sel}>
            <option value="" disabled>
              Select category
            </option>
            {WORK_CATEGORIES.map((c) => (
              <option key={c}>{c}</option>
            ))}
          </Select>
        </Field>
      </form>
    </Modal>
  );
}

/* ---------------------------------------------------------------- shaft */

export function AddShaftModal({
  onClose,
  siteId,
}: Close & { siteId?: string }) {
  const sites = useStore((s) => s.sites);
  return (
    <Modal
      title="Add Mine Shaft"
      onClose={onClose}
      footer={
        <>
          <CancelButton onClick={onClose} />
          <SubmitButton form="shaft-form">Add Shaft</SubmitButton>
        </>
      }
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
          const item = { id: code, siteId: v.site, name: `Shaft ${code}`, depthM: Number(v.depth), mineral: v.mineral, status: "Operational" as const, lastInspection: "—" };
          if (addOrRequest("New shaft", `Open shaft ${code} (${v.mineral}, ${v.depth} m)`, v.site, [{ to: "shafts", item }])) toast(`Shaft ${code} added`);
          else toast("Sent to the owner for approval", "info");
          onClose();
        }}
      >
        {siteId ? (
          <Field label="Site">
            <input type="hidden" name="site" value={siteId} />
            <input
              readOnly
              value={
                getState().sites.find((x) => x.id === siteId)?.name ?? siteId
              }
              className={`${inputClass} bg-page`}
            />
          </Field>
        ) : (
          <Field label="Site">
            <Select
              name="site"
              required
              defaultValue={siteId ?? ""}
              className={sel}
            >
              <option value="" disabled>
                Select site
              </option>
              {sites.map((s) => (
                <option key={s.id} value={s.id}>
                  {s.name}
                </option>
              ))}
            </Select>
          </Field>
        )}
        <Field label="Shaft code">
          <input
            name="code"
            required
            className={inputClass}
            placeholder="e.g. K-05"
          />
        </Field>
        <Field label="Depth (m)">
          <input
            name="depth"
            type="number"
            min={1}
            required
            className={inputClass}
          />
        </Field>
        <Field label="Mineral">
          <Select name="mineral" required defaultValue="" className={sel}>
            <option value="" disabled>
              Select mineral
            </option>
            {MINERALS.map((m) => (
              <option key={m}>{m}</option>
            ))}
          </Select>
        </Field>
      </form>
    </Modal>
  );
}

/* ------------------------------------------------------------- document */

export function UploadDocModal({ onClose, lotId, siteId }: Close & { lotId?: string; siteId?: string }) {
  const state = useStore((s) => s);
  const kinds: Doc["kind"][] = [
    "Mining Licence",
    "Export Permit",
    "Transport Permit",
    "Environmental",
    "Certificate",
    "Tax",
    "Company",
    "Other",
  ];
  const [f, setF] = useState({
    name: "",
    kind: "",
    number: "",
    issued: "",
    expires: "",
    site: siteId ?? "",
    lot: lotId ?? "",
  });
  const [ai, setAi] = useState<{ busy: boolean; found: string[] } | null>(null);
  const set = (k: keyof typeof f) => (e: { target: { value: string } }) =>
    setF((x) => ({ ...x, [k]: e.target.value }));

  const onFile = async (file: File | undefined) => {
    if (!file) return;
    setAi({ busy: true, found: [] });
    const r = await extractDocument(file, getState());
    setF((x) => ({
      name: r.name ?? x.name,
      kind: r.kind ?? x.kind,
      number: r.number ?? x.number,
      issued: r.issued ?? x.issued,
      expires: r.expires ?? x.expires,
      site: siteId ?? r.siteId ?? x.site,
      lot: r.lotId ?? x.lot,
    }));
    setAi({ busy: false, found: r.found });
  };

  return (
    <Modal
      title="Upload Document"
      subtitle="Choose the file first: MineNet reads it and fills in what it can. Check every field before saving."
      onClose={onClose}
      footer={
        <>
          <CancelButton onClick={onClose} />
          <SubmitButton form="doc-form">Upload</SubmitButton>
        </>
      }
    >
      <form
        id="doc-form"
        className="grid grid-cols-2 gap-4"
        onSubmit={(e) => {
          const fd = new FormData(e.currentTarget);
          e.preventDefault();
          const file = fd.get("file") as File | null;
          const id = nextId(
            getState().docs.map((d) => d.id),
            "DOC-",
            3,
          );
          const name =
            f.lot && !f.name.includes(f.lot) ? `${f.name} – ${f.lot}` : f.name;
          const doc = { id, name, kind: f.kind as Doc["kind"], siteId: f.site || undefined, number: f.number, issued: fmtInputDate(f.issued) || today(), expires: fmtInputDate(f.expires) || undefined, fileName: file?.name || `${f.number}.pdf` };
          if (needsApproval()) {
            addOrRequest("Site document", `Add ${name}`, doc.siteId, [{ to: "docs", item: doc }]);
            toast("Sent to the owner for approval", "info");
            onClose();
            return;
          }
          update((s) => ({
            docs: [
              {
                id,
                name,
                kind: f.kind as Doc["kind"],
                siteId: f.site || undefined,
                number: f.number,
                issued: fmtInputDate(f.issued) || today(),
                expires: fmtInputDate(f.expires) || undefined,
                fileName: file?.name || `${f.number}.pdf`,
              },
              ...s.docs,
            ],
            events: f.lot
              ? [
                  ...s.events,
                  makeEvent(
                    s,
                    f.lot,
                    "Document added",
                    s.org.contact,
                    "Miner",
                    `${f.kind} ${f.number} attached`,
                  ),
                ]
              : s.events,
          }));
          toast(`${name} uploaded`);
          onClose();
        }}
      >
        <Field label="File" className="col-span-2">
          <input
            name="file"
            type="file"
            required
            accept=".pdf,.jpg,.jpeg,.png,.txt"
            onChange={(e) => onFile(e.target.files?.[0])}
            className="block w-full text-sm file:mr-3 file:rounded-full file:border-0 file:bg-primary-soft file:px-4 file:py-2 file:text-[#1F5B3A]"
          />
        </Field>
        {ai && (
          <p
            className={`col-span-2 flex items-start gap-2 rounded-xl px-3 py-2 text-sm ${ai.found.length ? "bg-violet-soft" : "bg-page"}`}
          >
            <IconSparkles className="mt-0.5 size-4 shrink-0 text-violet" />
            {ai.busy
              ? "Reading the document…"
              : ai.found.length
                ? `Filled in from the document: ${ai.found.join(", ")}. Please check before saving.`
                : "Couldn't read details from this file. Please fill in the fields."}
          </p>
        )}
        <Field label="Document name" className="col-span-2">
          <input
            name="name"
            required
            value={f.name}
            onChange={set("name")}
            className={inputClass}
          />
        </Field>
        <Field label="Type">
          <Select
            name="kind"
            required
            value={f.kind}
            onChange={set("kind")}
            className={sel}
          >
            <option value="" disabled>
              Select type
            </option>
            {kinds.map((k) => (
              <option key={k}>{k}</option>
            ))}
          </Select>
        </Field>
        <Field label="Reference number">
          <input
            name="number"
            required
            value={f.number}
            onChange={set("number")}
            className={inputClass}
          />
        </Field>
        <Field label="Issued">
          <input
            name="issued"
            type="date"
            required
            value={f.issued}
            onChange={set("issued")}
            className={inputClass}
          />
        </Field>
        <Field label="Expires (optional)">
          <input
            name="expires"
            type="date"
            value={f.expires}
            onChange={set("expires")}
            className={inputClass}
          />
        </Field>
        <Field label="Site" hint={siteId ? undefined : "Leave as company-wide for tax, registration and other papers not tied to a site"}>
          {siteId ? (
            <input readOnly value={siteName(state, siteId)} className={`${inputClass} bg-page`} />
          ) : (
          <Select
            name="site"
            value={f.site}
            onChange={set("site")}
            className={sel}
          >
            <option value="">Company-wide (general)</option>
            {state.sites.map((s) => (
              <option key={s.id} value={s.id}>
                {s.name}
              </option>
            ))}
          </Select>
          )}
        </Field>
        <Field
          label="Related lot (optional)"
          hint="Certificates linked to a lot count towards listing it"
        >
          <Select
            name="lot"
            value={f.lot}
            onChange={set("lot")}
            className={sel}
          >
            <option value="">None</option>
            {state.lots.map((l) => (
              <option key={l.id} value={l.id}>
                {l.id} · {l.mineral}
              </option>
            ))}
          </Select>
        </Field>
      </form>
    </Modal>
  );
}

/* ----------------------------------------------------- marketplace: sell */

export function ListLotModal({
  onClose,
  onListed,
  lotId,
}: Close & { onListed?: () => void; lotId?: string }) {
  const state = useStore((s) => s);
  const { lots, listings, sites } = state;
  // Only verified lots that aren't already on the market can be listed.
  const available = useMemo(
    () =>
      lots.filter(
        (l) =>
          l.status === "Verified" &&
          !listings.some((x) => x.lotId === l.id && x.status === "Active"),
      ),
    [lots, listings],
  );
  const [chosen, setChosen] = useState(
    lotId && available.some((l) => l.id === lotId) ? lotId : "",
  );
  const lot = lots.find((l) => l.id === chosen);
  const site = sites.find((s) => s.id === lot?.siteId);
  const checks = lot ? listingChecklist(state, lot) : [];
  const ready = checks.every((c) => c.ok);
  const guide = lot ? priceGuidance(state, lot.mineral, lot.grade) : null;
  if (!orgCanAct(state)) {
    return (
      <Modal
        title="Sell on Marketplace"
        subtitle="Listing is blocked"
        onClose={onClose}
        footer={<CancelButton onClick={onClose} />}
      >
        <p className="text-sm text-ink/80">
          Your organisation is <b>{state.org.status.toLowerCase()}</b> with RMB,
          so you can&apos;t list lots.{" "}
          <Link
            href="/miner/licence"
            onClick={onClose}
            className="font-medium text-accent hover:underline"
          >
            See Licence & Validation
          </Link>
        </p>
      </Modal>
    );
  }

  return (
    <Modal
      title="Sell on Marketplace"
      subtitle="List a verified lot so buyers can see it and send you offers."
      onClose={onClose}
      footer={
        <>
          <CancelButton onClick={onClose} />
          {ready || !lot ? (
            <SubmitButton form="list-form">Publish Listing</SubmitButton>
          ) : (
            <span className="rounded-full bg-gray-100 px-6 py-3 text-[15px] text-ink/50">
              Complete the checklist to publish
            </span>
          )}
        </>
      }
    >
      {available.length === 0 ? (
        <p className="text-sm text-ink/70">
          You have no verified lots available to list. Lots must pass inspection
          before they can be sold.
        </p>
      ) : (
        <form
          id="list-form"
          className="grid grid-cols-2 gap-4"
          onSubmit={(e) => {
            const v = formValues(e);
            if (!ready) return;
            const l = lots.find((x) => x.id === v.lot)!;
            void confirmAction({
              title: "Publish listing?",
              message: `${l.id} (${fmtKg(Number(v.quantity))} of ${l.mineral}) will be visible to all buyers at ${v.currency} ${v.price}/kg.`,
              confirmLabel: "Publish",
            }).then((ok) => {
              if (!ok) return;
              const s = sites.find((x) => x.id === l.siteId);
              const id = nextId(
                getState().listings.map((x) => x.id),
                "LST-",
                4,
              );
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
                events: [
                  ...st.events,
                  makeEvent(
                    st,
                    l.id,
                    "Listed",
                    st.org.contact,
                    "Miner",
                    `Listed as ${id} at ${v.currency} ${v.price}/kg`,
                  ),
                ],
              }));
              toast(
                `${l.mineral} lot ${l.id} is now listed on the marketplace`,
              );
              onListed?.();
              onClose();
            });
          }}
        >
          <Field label="Verified lot" className="col-span-2">
            <Select
              name="lot"
              required
              value={chosen}
              onChange={(e) => setChosen(e.target.value)}
              className={sel}
            >
              <option value="" disabled>
                Select a lot
              </option>
              {available.map((l) => (
                <option key={l.id} value={l.id}>
                  {l.id} · {l.mineral} · {fmtKg(l.quantityKg)} · {l.grade}%
                </option>
              ))}
            </Select>
          </Field>
          {lot && (
            <div className="col-span-2 grid grid-cols-3 gap-4 rounded-2xl bg-page px-4 py-3 text-sm">
              <div>
                <p className="text-ink/60">Origin</p>
                <p className="font-medium">{site?.name}</p>
              </div>
              <div>
                <p className="text-ink/60">Grade</p>
                <p className="font-medium">{lot.grade}%</p>
              </div>
              <div>
                <p className="text-ink/60">Available</p>
                <p className="font-medium">{fmtKg(lot.quantityKg)}</p>
              </div>
            </div>
          )}
          {lot && (
            <ul className="col-span-2 space-y-1.5 rounded-2xl border border-gray-100 px-4 py-3 text-sm">
              <li className="flex items-center gap-2 pb-1 font-medium">
                <IconSparkles className="size-4 text-violet" /> Before you can
                list
              </li>
              {checks.map((c) => (
                <li key={c.label} className="flex items-start gap-2">
                  {c.ok ? (
                    <IconCircleCheck className="mt-0.5 size-4 shrink-0 text-[#1F5B3A]" />
                  ) : (
                    <IconCircleDashed className="mt-0.5 size-4 shrink-0 text-accent" />
                  )}
                  <span>
                    {c.label}
                    {!c.ok && (
                      <span className="text-ink/60">
                        {" "}
                        · {c.hint}
                        {c.href && (
                          <>
                            {" "}
                            ·{" "}
                            <Link
                              href={c.href}
                              onClick={onClose}
                              className="text-accent hover:underline"
                            >
                              Fix
                            </Link>
                          </>
                        )}
                      </span>
                    )}
                  </span>
                </li>
              ))}
            </ul>
          )}
          <Field label="Quantity to sell (kg)">
            <input
              name="quantity"
              type="number"
              min={1}
              max={lot?.quantityKg}
              step="any"
              required
              defaultValue={lot?.quantityKg}
              key={lot?.id}
              className={inputClass}
            />
          </Field>
          <Field
            label="Asking price per kg"
            hint={
              guide
                ? `Suggested: $${guide.low} – $${guide.high}/kg (AI guidance, indicative)`
                : undefined
            }
          >
            <div className="flex gap-2">
              <input
                name="price"
                type="number"
                min={0.01}
                step="0.01"
                required
                key={`p-${lot?.id}`}
                defaultValue={guide?.mid}
                className={inputClass}
              />
              <Select
                name="currency"
                defaultValue="USD"
                className={`${sel} w-28`}
              >
                <option>USD</option>
                <option>RWF</option>
              </Select>
            </div>
          </Field>
          <Field label="Notes for buyers (optional)" className="col-span-2">
            <input
              name="notes"
              className={inputClass}
              placeholder="e.g. collection from site, ITSCI tagged"
            />
          </Field>
        </form>
      )}
    </Modal>
  );
}

/* --------------------------------------------------- marketplace: offer */

export function MakeOfferModal({
  onClose,
  request,
}: Close & { request: BuyerRequest }) {
  const lots = useStore((s) => s.lots);
  const matching = lots.filter(
    (l) => l.status === "Verified" && l.mineral === request.mineral,
  );
  const max = Math.round(request.remainingT * 1000);
  return (
    <Modal
      title={`Make Offer · ${request.buyer}`}
      subtitle={`${request.mineral} · ${request.grade} · ${fmtKg(max)} still needed · delivers to ${request.city}`}
      onClose={onClose}
      footer={
        <>
          <CancelButton onClick={onClose} />
          <SubmitButton form="offer-form">Send Offer</SubmitButton>
        </>
      }
    >
      {matching.length === 0 ? (
        <p className="text-sm text-ink/70">
          You have no verified {request.mineral} lots to offer. Register a lot
          and get it inspected first.
        </p>
      ) : (
        <form
          id="offer-form"
          className="grid grid-cols-2 gap-4"
          onSubmit={(e) => {
            const v = formValues(e);
            const id = nextId(
              getState().offers.map((o) => o.id),
              "OFF-",
              4,
            );
            update((s) => ({
              offers: [
                {
                  id,
                  requestId: request.id,
                  lotId: v.lot,
                  quantityKg: Number(v.quantity),
                  pricePerKg: Number(v.price),
                  currency: "USD",
                  status: "Sent",
                  sent: today(),
                },
                ...s.offers,
              ],
              requests: s.requests.map((r) =>
                r.id === request.id ? { ...r, offers: r.offers + 1 } : r,
              ),
            }));
            toast(`Offer sent to ${request.buyer}`);
            onClose();
          }}
        >
          <Field label="Your lot" className="col-span-2">
            <Select name="lot" required defaultValue="" className={sel}>
              <option value="" disabled>
                Select a verified lot
              </option>
              {matching.map((l) => (
                <option key={l.id} value={l.id}>
                  {l.id} · {fmtKg(l.quantityKg)} · {l.grade}%
                </option>
              ))}
            </Select>
          </Field>
          <Field label="Quantity (kg)" hint={`Up to ${fmtKg(max)}`}>
            <input
              name="quantity"
              type="number"
              min={1}
              max={max}
              required
              className={inputClass}
            />
          </Field>
          <Field
            label="Price per kg (USD)"
            hint={`Buyer's indicative price: $${request.pricePerKg}`}
          >
            <input
              name="price"
              type="number"
              min={0.01}
              step="0.01"
              required
              defaultValue={request.pricePerKg}
              className={inputClass}
            />
          </Field>
        </form>
      )}
    </Modal>
  );
}
