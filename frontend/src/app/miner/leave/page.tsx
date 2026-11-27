"use client";

import { useState } from "react";
import { IconBeach, IconCheck, IconClock, IconPlus, IconX } from "@tabler/icons-react";
import { CancelButton, Card, CardTitle, Empty, Field, Modal, PageHeader, PrimaryButton, StatCard, StatusBadge, SubmitButton, formValues, inputClass, toast, type BadgeTone } from "@/components/ui";
import { Select } from "@/components/ui/Select";
import { withConfirm } from "@/components/ui/Confirm";
import { Tabs } from "@/components/ui/Tabs";
import { today, type Leave, type LeaveStatus, type LeaveType } from "@/lib/data";
import { getState, nextId, siteName, update, useStore } from "@/lib/store";

const tone: Record<LeaveStatus, BadgeTone> = { Pending: "pending", Approved: "success", Rejected: "danger" };
const TYPES: LeaveType[] = ["Annual", "Sick", "Family", "Unpaid"];

function workdays(from: string, to: string) {
  let n = 0;
  for (let d = new Date(from); d <= new Date(to); d.setDate(d.getDate() + 1)) if (d.getDay() % 6 !== 0) n++;
  return n;
}

/** Leave requests: HR records and decides; approved days show as "Leave" in attendance. */
export default function LeavePage() {
  const state = useStore((s) => s);
  const { leaves, workers } = state;
  const [tab, setTab] = useState("Pending");
  const [adding, setAdding] = useState(false);
  const rows = leaves.filter((l) => tab === "All" || l.status === tab);
  const worker = (id: string) => workers.find((w) => w.id === id);

  const decide = (l: Leave, status: LeaveStatus) =>
    update((s) => {
      const out: Partial<typeof s> = { leaves: s.leaves.map((x) => (x.id === l.id ? { ...x, status } : x)) };
      if (status === "Approved") {
        // Approved leave appears in attendance for each workday.
        let att = [...s.attendance];
        for (let d = new Date(l.from); d <= new Date(l.to); d.setDate(d.getDate() + 1)) {
          if (d.getDay() % 6 === 0) continue;
          const date = d.toISOString().slice(0, 10);
          const hit = att.find((a) => a.workerId === l.workerId && a.date === date);
          att = hit ? att.map((a) => (a === hit ? { ...a, status: "Leave" as const } : a)) : [...att, { id: nextId(att.map((a) => a.id), "ATT-", 5), workerId: l.workerId, date, status: "Leave" as const }];
        }
        out.attendance = att;
      }
      return out;
    });

  return (
    <>
      <PageHeader
        title="Leave"
        subtitle="Record leave requests from workers and approve or reject them. Approved days appear in attendance and are paid in payroll (except unpaid leave)."
        actions={<PrimaryButton icon={IconPlus} onClick={() => setAdding(true)}>Record leave request</PrimaryButton>}
      />

      <div className="grid grid-cols-1 gap-5 sm:grid-cols-3">
        <StatCard deltaDir="none" icon={IconClock} tone="orange" label="Waiting for decision" value={leaves.filter((l) => l.status === "Pending").length} delta="" note="requests" spark={[1, 2, 1, 2, 2, 3, 2]} />
        <StatCard deltaDir="none" icon={IconBeach} tone="green" label="Approved days" value={leaves.filter((l) => l.status === "Approved").reduce((n, l) => n + l.days, 0)} delta="" note="this period" spark={[2, 3, 3, 4, 3, 5, 5]} />
        <StatCard deltaDir="none" icon={IconX} tone="gray" label="Rejected" value={leaves.filter((l) => l.status === "Rejected").length} delta="" note="requests" spark={[0, 1, 0, 0, 1, 0, 0]} />
      </div>

      <Card className="pt-5">
        <div className="border-b border-gray-100 px-6">
          <Tabs value={tab} onChange={setTab} items={["Pending", "Approved", "Rejected", "All"].map((k) => ({ key: k, label: k, count: k === "All" ? leaves.length : leaves.filter((l) => l.status === k).length }))} />
        </div>
        <div className="overflow-x-auto px-3 py-4">
          {rows.length === 0 ? (
            <Empty>No {tab === "All" ? "" : tab.toLowerCase()} leave requests.</Empty>
          ) : (
            <table className="w-full text-left text-sm">
              <thead className="bg-head"><tr>{["Request", "Worker", "Type", "Dates", "Days", "Reason", "Status", ""].map((h) => <th key={h} className="px-3 py-3 text-[13px] font-medium">{h}</th>)}</tr></thead>
              <tbody>
                {rows.map((l) => (
                  <tr key={l.id} className="border-b border-gray-100 last:border-0">
                    <td className="px-3 py-3 font-medium">{l.id}<span className="block text-xs font-normal text-ink/60">{l.requested}</span></td>
                    <td className="px-3">{worker(l.workerId)?.name}<span className="block text-xs text-ink/60">{worker(l.workerId) ? siteName(state, worker(l.workerId)!.siteId) : ""}</span></td>
                    <td className="px-3">{l.type}</td>
                    <td className="px-3">{l.from} → {l.to}</td>
                    <td className="px-3">{l.days}</td>
                    <td className="max-w-[260px] truncate px-3" title={l.reason}>{l.reason}</td>
                    <td className="px-3"><StatusBadge tone={tone[l.status]}>{l.status}</StatusBadge></td>
                    <td className="px-3 text-right">
                      {l.status === "Pending" && (
                        <span className="flex justify-end gap-2">
                          <button
                            onClick={withConfirm({ title: "Approve leave?", message: `${worker(l.workerId)?.name}: ${l.days} day(s) of ${l.type.toLowerCase()} leave, ${l.from} to ${l.to}.`, confirmLabel: "Approve" }, () => (decide(l, "Approved"), toast(`Leave ${l.id} approved`)))}
                            className="inline-flex items-center gap-1 rounded-full bg-[#1F5B3A] px-3 py-1.5 text-xs font-medium text-white"
                          >
                            <IconCheck className="size-3.5" /> Approve
                          </button>
                          <button
                            onClick={withConfirm({ title: "Reject leave?", message: `${worker(l.workerId)?.name}'s request ${l.id} will be rejected.`, confirmLabel: "Reject", tone: "danger" }, () => (decide(l, "Rejected"), toast(`Leave ${l.id} rejected`, "info")))}
                            className="text-xs text-ink/60 underline"
                          >
                            Reject
                          </button>
                        </span>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </div>
      </Card>

      <Card className="p-6">
        <CardTitle icon={IconBeach}>Leave balance (annual, 18 days per year)</CardTitle>
        <div className="mt-4 grid grid-cols-1 gap-2 text-sm sm:grid-cols-2 xl:grid-cols-4">
          {workers.filter((w) => w.status === "Active").map((w) => {
            const used = leaves.filter((l) => l.workerId === w.id && l.type === "Annual" && l.status === "Approved").reduce((n, l) => n + l.days, 0);
            return (
              <div key={w.id} className="flex justify-between rounded-xl bg-page px-3 py-2">
                <span>{w.name}</span>
                <b className="font-medium">{18 - used} left</b>
              </div>
            );
          })}
        </div>
      </Card>

      {adding && (
        <Modal title="Record leave request" subtitle="Entered by HR on behalf of the worker." onClose={() => setAdding(false)} footer={<><CancelButton onClick={() => setAdding(false)} /><SubmitButton form="leave-form">Save request</SubmitButton></>}>
          <form
            id="leave-form"
            className="grid grid-cols-2 gap-4"
            onSubmit={(e) => {
              const v = formValues(e);
              if (v.to < v.from) return toast("The end date is before the start date", "error");
              const id = nextId(getState().leaves.map((l) => l.id), "LV-", 4);
              update((s) => ({ leaves: [{ id, workerId: v.worker, type: v.type as LeaveType, from: v.from, to: v.to, days: workdays(v.from, v.to), reason: v.reason, status: "Pending" as const, requested: today() }, ...s.leaves] }));
              toast(`Leave request ${id} saved`);
              setAdding(false);
              setTab("Pending");
            }}
          >
            <Field label="Worker" className="col-span-2">
              <Select name="worker" required defaultValue="">
                <option value="" disabled>Select worker</option>
                {workers.filter((w) => w.status === "Active").map((w) => <option key={w.id} value={w.id}>{w.name} · {w.id}</option>)}
              </Select>
            </Field>
            <Field label="Type">
              <Select name="type" defaultValue="Annual">
                {TYPES.map((t) => <option key={t}>{t}</option>)}
              </Select>
            </Field>
            <div />
            <Field label="From"><input name="from" type="date" required className={inputClass} /></Field>
            <Field label="To"><input name="to" type="date" required className={inputClass} /></Field>
            <Field label="Reason" className="col-span-2"><input name="reason" required className={inputClass} /></Field>
          </form>
        </Modal>
      )}
    </>
  );
}
