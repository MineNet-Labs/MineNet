"use client";

import { useState } from "react";
import { IconClock, IconNotes, IconPick, IconPlus, IconUsers } from "@tabler/icons-react";
import { CancelButton, Card, CardTitle, Empty, Field, FilterSelect, Modal, PageHeader, PrimaryButton, StatCard, SubmitButton, formValues, inputClass, toast } from "@/components/ui";
import { Select } from "@/components/ui/Select";
import { fmtKg, fmtNum, today } from "@/lib/data";
import { fmtInputDate } from "@/lib/domain";
import { getState, nextId, siteName, update, useMe, useStore } from "@/lib/store";
import { downloadCSV } from "@/lib/csv";

/** End-of-shift report from each site: crew, hours, output and notes. */
export default function ShiftReportsPage() {
  const state = useStore((s) => s);
  const me = useMe();
  const { shiftReports, sites } = state;
  const [site, setSite] = useState("");
  const [adding, setAdding] = useState(false);
  const rows = shiftReports.filter((r) => !site || siteName(state, r.siteId) === site);
  const output = rows.reduce((n, r) => n + r.outputKg, 0);
  const hours = rows.reduce((n, r) => n + r.hours * r.crew, 0);

  return (
    <>
      <PageHeader
        title="Shift Reports"
        subtitle="Each site manager closes every shift with crew, hours, output and anything the owner should know."
        actions={<PrimaryButton icon={IconPlus} onClick={() => setAdding(true)}>Submit shift report</PrimaryButton>}
      />

      <div className="grid grid-cols-1 gap-5 sm:grid-cols-2 xl:grid-cols-4">
        <StatCard deltaDir="none" icon={IconNotes} tone="green" label="Reports" value={rows.length} delta="" note="submitted" spark={[2, 3, 3, 4, 4, 5, 5]} />
        <StatCard deltaDir="none" icon={IconPick} tone="orange" label="Output reported" value={fmtKg(output)} delta="" note="all shifts" spark={[3, 4, 3, 5, 4, 6, 6]} />
        <StatCard deltaDir="none" icon={IconClock} tone="violet" label="Labour hours" value={fmtNum(hours)} delta="" note="crew × hours" spark={[3, 4, 4, 5, 5, 6, 6]} />
        <StatCard deltaDir="none" icon={IconUsers} tone="gray" label="kg per labour hour" value={hours ? (output / hours).toFixed(2) : "—"} delta="" note="productivity" spark={[2, 3, 2, 3, 3, 4, 3]} />
      </div>

      <Card className="pt-6">
        <div className="flex items-center justify-between px-6">
          <CardTitle icon={IconNotes} iconClass="text-[#1F5B3A]">Reports</CardTitle>
          <div className="flex gap-3">
            <FilterSelect label="All sites" options={sites.map((s) => s.name)} value={site} onChange={setSite} />
            <button
              onClick={() => {
                downloadCSV("shift-reports", rows, [
                  ["Report", (r) => r.id],
                  ["Site", (r) => siteName(state, r.siteId)],
                  ["Date", (r) => r.date],
                  ["Shift", (r) => r.shift],
                  ["Crew", (r) => r.crew],
                  ["Hours", (r) => r.hours],
                  ["Output kg", (r) => r.outputKg],
                  ["Notes", (r) => r.notes],
                  ["By", (r) => r.by],
                ]);
                toast("Shift reports exported");
              }}
              className="rounded-full border border-gray-200 px-4 py-2 text-sm hover:bg-page"
            >
              Export
            </button>
          </div>
        </div>
        <div className="mt-4 px-3 pb-4">
          {rows.length === 0 ? (
            <Empty>No shift reports yet.</Empty>
          ) : (
            <ul className="divide-y divide-gray-100">
              {rows.map((r) => (
                <li key={r.id} className="grid gap-2 px-3 py-4 md:grid-cols-[220px_1fr_auto]">
                  <div>
                    <p className="font-medium">{siteName(state, r.siteId)}</p>
                    <p className="text-xs text-ink/60">{r.date} · {r.shift} shift · {r.id}</p>
                  </div>
                  <p className="text-sm text-ink/80">{r.notes}<span className="block text-xs text-ink/55">by {r.by}</span></p>
                  <p className="text-right text-sm"><b className="font-heading text-lg">{fmtKg(r.outputKg)}</b><span className="block text-xs text-ink/60">{r.crew} crew · {r.hours} h</span></p>
                </li>
              ))}
            </ul>
          )}
        </div>
      </Card>

      {adding && (
        <Modal title="Submit shift report" subtitle="Output here is what the crew reports; official quantities still go in Extraction Records." onClose={() => setAdding(false)} footer={<><CancelButton onClick={() => setAdding(false)} /><SubmitButton form="shift-form">Submit</SubmitButton></>}>
          <form
            id="shift-form"
            className="grid grid-cols-2 gap-4"
            onSubmit={(e) => {
              const v = formValues(e);
              const id = nextId(getState().shiftReports.map((r) => r.id), "SR-", 4);
              update((s) => ({ shiftReports: [{ id, siteId: v.site, date: fmtInputDate(v.date) || today(), shift: v.shift as "Day" | "Night", crew: Number(v.crew), outputKg: Number(v.output), hours: Number(v.hours), notes: v.notes, by: me.name }, ...s.shiftReports] }));
              toast(`Shift report ${id} submitted`);
              setAdding(false);
            }}
          >
            <Field label="Site">
              <Select name="site" required defaultValue={sites.length === 1 ? sites[0].id : ""}>
                <option value="" disabled>Select site</option>
                {sites.map((s) => <option key={s.id} value={s.id}>{s.name}</option>)}
              </Select>
            </Field>
            <Field label="Shift">
              <Select name="shift" defaultValue="Day">
                <option>Day</option>
                <option>Night</option>
              </Select>
            </Field>
            <Field label="Date"><input name="date" type="date" required defaultValue={new Date().toISOString().slice(0, 10)} className={inputClass} /></Field>
            <Field label="Crew size"><input name="crew" type="number" min={1} required className={inputClass} /></Field>
            <Field label="Hours worked"><input name="hours" type="number" min={1} max={24} required defaultValue={9} className={inputClass} /></Field>
            <Field label="Output (kg)"><input name="output" type="number" min={0} required className={inputClass} /></Field>
            <Field label="Notes" className="col-span-2"><textarea name="notes" required rows={3} className={`${inputClass} h-auto py-3`} placeholder="Breakdowns, safety, geology, anything unusual" /></Field>
          </form>
        </Modal>
      )}
    </>
  );
}
