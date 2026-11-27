"use client";

import { useState } from "react";
import { IconAlertTriangle, IconFirstAidKit, IconPlus, IconShieldCheck, IconZoomCheck } from "@tabler/icons-react";
import { CancelButton, Card, CardTitle, Empty, Field, FilterSelect, Modal, PageHeader, PrimaryButton, StatCard, StatusBadge, SubmitButton, formValues, inputClass, toast, type BadgeTone } from "@/components/ui";
import { Select } from "@/components/ui/Select";
import { confirmAction } from "@/components/ui/Confirm";
import { INCIDENT_KINDS, today, type Incident, type IncidentStatus, type Severity } from "@/lib/data";
import { fmtInputDate, makeNotice } from "@/lib/domain";
import { getState, nextId, siteName, update, useMe, useStore } from "@/lib/store";

const sevTone: Record<Severity, BadgeTone> = { Low: "neutral", Medium: "pending", High: "danger" };
const stTone: Record<IncidentStatus, BadgeTone> = { Open: "danger", Investigating: "pending", Closed: "success" };

/** Safety incidents and near misses per site, with the follow-up actions taken. */
export default function IncidentsPage() {
  const state = useStore((s) => s);
  const me = useMe();
  const { incidents, sites, shafts } = state;
  const [status, setStatus] = useState("");
  const [adding, setAdding] = useState(false);
  const [site, setSite] = useState("");
  const [open, setOpen] = useState<Incident | null>(null);
  const rows = incidents.filter((i) => !status || i.status === status);
  const days = (() => {
    const last = incidents.filter((i) => i.severity !== "Low").map((i) => Date.parse(i.date)).sort((a, b) => b - a)[0];
    return last ? Math.max(0, Math.floor((Date.parse("Aug 29, 2025") - last) / 86_400_000)) : "—";
  })();

  const advance = async (i: Incident, next: IncidentStatus, actions?: string) => {
    if (!(await confirmAction({ title: next === "Closed" ? "Close incident?" : "Start investigation?", message: next === "Closed" ? `${i.id} is closed with the actions recorded.` : `${i.id} is marked under investigation.`, confirmLabel: next === "Closed" ? "Close incident" : "Investigate" }))) return;
    update((s) => ({ incidents: s.incidents.map((x) => (x.id === i.id ? { ...x, status: next, actions: actions ?? x.actions } : x)) }));
    setOpen(null);
    toast(`${i.id} ${next === "Closed" ? "closed" : "under investigation"}`);
  };

  return (
    <>
      <PageHeader
        title="Safety Incidents"
        subtitle="Report accidents and near misses on your sites, investigate them and record what was done. Serious ones alert the owner straight away."
        actions={<PrimaryButton icon={IconPlus} onClick={() => setAdding(true)}>Report incident</PrimaryButton>}
      />

      <div className="grid grid-cols-1 gap-5 sm:grid-cols-2 xl:grid-cols-4">
        <StatCard deltaDir="none" icon={IconAlertTriangle} tone="orange" label="Open" value={incidents.filter((i) => i.status !== "Closed").length} delta="" note="need follow-up" spark={[1, 2, 2, 1, 2, 1, 2]} />
        <StatCard deltaDir="none" icon={IconFirstAidKit} tone="violet" label="People injured" value={incidents.reduce((n, i) => n + i.injured, 0)} delta="" note="this period" spark={[0, 1, 0, 0, 1, 0, 1]} />
        <StatCard deltaDir="none" icon={IconShieldCheck} tone="green" label="Days since serious incident" value={days} delta="" note="medium or high" spark={[3, 4, 5, 1, 2, 3, 4]} />
        <StatCard deltaDir="none" icon={IconZoomCheck} tone="gray" label="Near misses" value={incidents.filter((i) => i.kind === "Near miss").length} delta="" note="reported" spark={[1, 1, 2, 1, 1, 2, 2]} />
      </div>

      <Card className="pt-6">
        <div className="flex items-center justify-between px-6">
          <CardTitle icon={IconFirstAidKit} iconClass="text-danger">Incidents</CardTitle>
          <FilterSelect label="All statuses" options={["Open", "Investigating", "Closed"]} value={status} onChange={setStatus} />
        </div>
        <div className="mt-4 overflow-x-auto px-3 pb-4">
          {rows.length === 0 ? (
            <Empty>No incidents. Keep it that way.</Empty>
          ) : (
            <table className="w-full text-left text-sm">
              <thead className="bg-head"><tr>{["Incident", "Site", "What happened", "Severity", "Injured", "Status", ""].map((h) => <th key={h} className="px-3 py-3 text-[13px] font-medium">{h}</th>)}</tr></thead>
              <tbody>
                {rows.map((i) => (
                  <tr key={i.id} className="border-b border-gray-100 last:border-0">
                    <td className="px-3 py-3 font-medium">{i.id}<span className="block text-xs font-normal text-ink/60">{i.date}</span></td>
                    <td className="px-3">{siteName(state, i.siteId)}{i.shaftId && <span className="block text-xs text-ink/60">Shaft {i.shaftId}</span>}</td>
                    <td className="max-w-[320px] truncate px-3" title={i.description}><b className="font-medium">{i.kind}</b> · {i.description}</td>
                    <td className="px-3"><StatusBadge tone={sevTone[i.severity]}>{i.severity}</StatusBadge></td>
                    <td className="px-3">{i.injured}</td>
                    <td className="px-3"><StatusBadge tone={stTone[i.status]}>{i.status}</StatusBadge></td>
                    <td className="px-3 text-right"><button onClick={() => setOpen(i)} className="text-xs font-medium text-accent hover:underline">Open</button></td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </div>
      </Card>

      {open && (
        <Modal
          title={`${open.id} · ${open.kind}`}
          subtitle={`${siteName(state, open.siteId)} · ${open.date} · reported by ${open.reportedBy}`}
          onClose={() => setOpen(null)}
          footer={
            open.status === "Closed" ? (
              <CancelButton onClick={() => setOpen(null)} />
            ) : (
              <>
                <CancelButton onClick={() => setOpen(null)} />
                {open.status === "Open" && <button onClick={() => advance(open, "Investigating")} className="rounded-full border border-gray-200 px-5 py-3 text-[15px] hover:bg-page">Start investigation</button>}
                <SubmitButton form="close-incident">Close incident</SubmitButton>
              </>
            )
          }
        >
          <div className="space-y-4 text-sm">
            <p>{open.description}</p>
            <p className="flex gap-3"><StatusBadge tone={sevTone[open.severity]}>{open.severity} severity</StatusBadge><StatusBadge tone={stTone[open.status]}>{open.status}</StatusBadge><span>{open.injured} injured</span></p>
            <form id="close-incident" onSubmit={(e) => { const v = formValues(e); void advance(open, "Closed", v.actions); }}>
              <Field label="Corrective actions">
                <textarea name="actions" required readOnly={open.status === "Closed"} defaultValue={open.actions} rows={3} className={`${inputClass} h-auto py-3`} placeholder="What was done so it doesn't happen again" />
              </Field>
            </form>
          </div>
        </Modal>
      )}

      {adding && (
        <Modal title="Report incident" subtitle="Report it the same day, even if nobody was hurt." onClose={() => setAdding(false)} footer={<><CancelButton onClick={() => setAdding(false)} /><SubmitButton form="incident-form">Report</SubmitButton></>}>
          <form
            id="incident-form"
            className="grid grid-cols-2 gap-4"
            onSubmit={async (e) => {
              const v = formValues(e);
              const sev = v.severity as Severity;
              if (sev === "High" && !(await confirmAction({ title: "Report a high-severity incident?", message: "The owner is alerted immediately. Remember that fatal or serious accidents must also be reported to RMB.", confirmLabel: "Report", tone: "danger" }))) return;
              const id = nextId(getState().incidents.map((i) => i.id), "INC-", 4);
              update((s) => ({
                incidents: [{ id, siteId: v.site, shaftId: v.shaft || undefined, date: fmtInputDate(v.date) || today(), kind: v.kind, severity: sev, injured: Number(v.injured), description: v.description, status: "Open" as const, reportedBy: me.name }, ...s.incidents],
                notices: sev === "Low" ? s.notices : [makeNotice(s, "alert", `${sev} incident ${id} at ${siteName(s, v.site)}: ${v.kind}`, "/miner/incidents"), ...s.notices],
              }));
              toast(`Incident ${id} reported`);
              setAdding(false);
            }}
          >
            <Field label="Site">
              <Select name="site" required value={site} onChange={(e) => setSite(e.target.value)}>
                <option value="" disabled>Select site</option>
                {sites.map((s) => <option key={s.id} value={s.id}>{s.name}</option>)}
              </Select>
            </Field>
            <Field label="Shaft (optional)">
              <Select name="shaft" defaultValue="" key={site}>
                <option value="">Not at a shaft</option>
                {shafts.filter((x) => x.siteId === site).map((x) => <option key={x.id} value={x.id}>{x.name}</option>)}
              </Select>
            </Field>
            <Field label="Type">
              <Select name="kind" required defaultValue="">
                <option value="" disabled>Select type</option>
                {INCIDENT_KINDS.map((k) => <option key={k}>{k}</option>)}
              </Select>
            </Field>
            <Field label="Severity">
              <Select name="severity" defaultValue="Low">
                <option>Low</option>
                <option>Medium</option>
                <option>High</option>
              </Select>
            </Field>
            <Field label="Date"><input name="date" type="date" required defaultValue={new Date().toISOString().slice(0, 10)} className={inputClass} /></Field>
            <Field label="People injured"><input name="injured" type="number" min={0} required defaultValue={0} className={inputClass} /></Field>
            <Field label="What happened" className="col-span-2"><textarea name="description" required rows={3} className={`${inputClass} h-auto py-3`} /></Field>
          </form>
        </Modal>
      )}
    </>
  );
}
