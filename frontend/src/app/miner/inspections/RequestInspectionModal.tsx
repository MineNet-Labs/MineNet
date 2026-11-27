"use client";

import { useState } from "react";
import { IconCloudUpload, IconFileText, IconX } from "@tabler/icons-react";
import { CancelButton, Field, Modal, SubmitButton, inputClass, toast } from "@/components/ui";
import { getState, nextId, update, useStore } from "@/lib/store";

const types = [
  { key: "Grade Verification", desc: "Confirms the declared grade of the lot" },
  { key: "Purity Assay", desc: "Lab analysis of mineral concentration" },
  { key: "Site Compliance", desc: "Checks site safety and licence conditions" },
  { key: "Pre-export Certification", desc: "Full inspection for an export certificate" },
];

export function RequestInspectionModal({ onClose }: { onClose: () => void }) {
  const lots = useStore((s) => s.lots);
  const shafts = useStore((s) => s.shafts);
  const [type, setType] = useState(types[0].key);
  const [lotId, setLotId] = useState("");
  const [files, setFiles] = useState(["Extraction_Record_N03_Aug.pdf", "Mining_Licence_ML-2025-087.pdf"]);
  const lot = lots.find((l) => l.id === lotId);

  return (
    <Modal
      title="Request Inspection"
      subtitle="An inspector is assigned within 2 working days of your request."
      onClose={onClose}
      width={680}
      footer={<><CancelButton onClick={onClose} /><SubmitButton form="ins-form">Submit Request</SubmitButton></>}
    >
      <form
        id="ins-form"
        className="space-y-4"
        onSubmit={(e) => {
          e.preventDefault();
          const fd = new FormData(e.currentTarget);
          if (!lot) return;
          const id = nextId(getState().inspections.map((i) => i.id), "INS-2025-", 4);
          const shaft = shafts.find((s) => s.siteId === lot.siteId);
          update((s) => ({
            inspections: [
              {
                id,
                lotId: lot.id,
                mineral: lot.mineral,
                siteId: lot.siteId,
                shaft: shaft?.name ?? "—",
                submitted: new Date(String(fd.get("date") || Date.now())).toLocaleDateString("en-US", { month: "short", day: "2-digit", year: "numeric" }),
                type,
                status: "Pending",
              },
              ...s.inspections,
            ],
          }));
          toast(`Inspection ${id} requested for ${lot.id}`);
          onClose();
        }}
      >
        <div className="grid grid-cols-2 gap-3">
          {types.map((t) => {
            const active = t.key === type;
            return (
              <label key={t.key} className={`flex cursor-pointer gap-3 rounded-xl border px-4 py-4 ${active ? "border-accent bg-accent-soft" : "border-gray-200"}`}>
                <input type="radio" name="type" checked={active} onChange={() => setType(t.key)} className="mt-6 size-4 accent-[#1F5B3A]" />
                <span>
                  <span className="block text-[15px] font-medium">{t.key}</span>
                  <span className="block text-[13px] text-ink/70">{t.desc}</span>
                </span>
              </label>
            );
          })}
        </div>

        <Field label="Mineral lot">
          <select required value={lotId} onChange={(e) => setLotId(e.target.value)} className={inputClass}>
            <option value="" disabled>Select a lot to inspect</option>
            {lots.map((l) => <option key={l.id} value={l.id}>{l.id} · {l.mineral} · {l.status}</option>)}
          </select>
        </Field>

        <div className="grid grid-cols-2 gap-3">
          <Field label="Preferred inspection date" hint="Earliest available: Sep 02, 2025">
            <input name="date" type="date" required min="2025-09-02" className={inputClass} />
          </Field>
          <Field label="Preferred time">
            <input name="time" type="time" className={inputClass} />
          </Field>
        </div>

        <div className="space-y-2">
          <span className="text-label">Supporting documents</span>
          <label className="flex cursor-pointer flex-col items-center gap-1 rounded-xl border border-gray-300 bg-page py-5 text-center hover:border-[#1F5B3A]/40">
            <IconCloudUpload className="size-6 text-accent" />
            <span className="text-[15px] font-medium">Drop files here or browse</span>
            <span className="text-xs text-ink/60">PDF, JPG or PNG · up to 10 MB each</span>
            <input type="file" multiple accept=".pdf,.jpg,.jpeg,.png" className="hidden" onChange={(e) => setFiles((f) => [...f, ...Array.from(e.target.files ?? []).map((x) => x.name)])} />
          </label>
          {files.map((f) => (
            <div key={f} className="flex items-center gap-3 rounded-xl border border-gray-200 px-4 py-2.5 text-sm">
              <IconFileText className="size-4 text-danger" />
              <span className="flex-1">{f}</span>
              <button type="button" aria-label={`Remove ${f}`} onClick={() => setFiles((x) => x.filter((n) => n !== f))}>
                <IconX className="size-4 text-ink/60" />
              </button>
            </div>
          ))}
        </div>

        <Field label="Additional notes">
          <textarea rows={3} placeholder="Access instructions, contact person on site, or anything the inspector should know" className="w-full resize-none rounded-xl border border-gray-200 px-4 py-3 text-sm outline-none placeholder:text-gray-400 focus:border-[#1F5B3A]" />
        </Field>
      </form>
    </Modal>
  );
}
