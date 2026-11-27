"use client";

import Link from "next/link";
import { useMemo, useState } from "react";
import { IconCalendarCheck, IconChecks, IconDownload, IconUserCheck, IconUserOff, IconUserX } from "@tabler/icons-react";
import { Card, CardTitle, Empty, FilterSelect, Initials, PageHeader, PrimaryButton, StatCard, inputClass, toast } from "@/components/ui";
import { withConfirm } from "@/components/ui/Confirm";
import type { AttendanceStatus } from "@/lib/data";
import { nextId, siteName, update, useStore } from "@/lib/store";
import { downloadCSV } from "@/lib/csv";

const STATUSES: AttendanceStatus[] = ["Present", "Half day", "Absent", "Leave"];
const chip: Record<AttendanceStatus, string> = {
  Present: "border-[#1F5B3A] bg-success-soft text-[#1F5B3A]",
  "Half day": "border-accent bg-accent-soft text-accent",
  Absent: "border-danger bg-danger-soft text-danger",
  Leave: "border-violet bg-violet-soft text-violet",
};

/** Daily attendance per worker. QR check-ins fill this automatically once the scanners are connected. */
export default function AttendancePage() {
  const state = useStore((s) => s);
  const { workers, attendance, sites } = state;
  const latest = useMemo(() => attendance.reduce((m, a) => (a.date > m ? a.date : m), "2025-08-29"), [attendance]);
  const [date, setDate] = useState(latest);
  const [site, setSite] = useState("");

  const active = workers.filter((w) => w.status === "Active" && (!site || siteName(state, w.siteId) === site));
  const byWorker = new Map(attendance.filter((a) => a.date === date).map((a) => [a.workerId, a]));
  const count = (st: AttendanceStatus) => active.filter((w) => byWorker.get(w.id)?.status === st).length;
  const unmarked = active.filter((w) => !byWorker.has(w.id)).length;

  // Month-to-date days worked per worker (half days count 0.5).
  const month = date.slice(0, 7);
  const monthDays = (id: string) =>
    attendance.filter((a) => a.workerId === id && a.date.startsWith(month)).reduce((n, a) => n + (a.status === "Present" ? 1 : a.status === "Half day" ? 0.5 : 0), 0);

  const mark = (workerId: string, status: AttendanceStatus) =>
    update((s) => {
      const existing = s.attendance.find((a) => a.workerId === workerId && a.date === date);
      if (existing) return { attendance: s.attendance.map((a) => (a === existing ? { ...a, status } : a)) };
      return { attendance: [...s.attendance, { id: nextId(s.attendance.map((a) => a.id), "ATT-", 5), workerId, date, status }] };
    });

  const markAll = () => {
    update((s) => {
      let list = [...s.attendance];
      for (const w of active) {
        if (list.some((a) => a.workerId === w.id && a.date === date)) continue;
        list = [...list, { id: nextId(list.map((a) => a.id), "ATT-", 5), workerId: w.id, date, status: "Present" as const }];
      }
      return { attendance: list };
    });
    toast(`Unmarked workers marked present for ${date}`);
  };

  return (
    <>
      <PageHeader
        title="Attendance"
        subtitle="Who worked each day. It feeds payroll. QR check-ins at the site gate fill this in once the scanners are connected."
        actions={
          <div className="flex flex-wrap items-center gap-3">
            <input type="date" value={date} max={new Date().toISOString().slice(0, 10)} onChange={(e) => e.target.value && setDate(e.target.value)} className={`${inputClass} w-44`} aria-label="Attendance date" />
            <PrimaryButton
              icon={IconChecks}
              disabled={!unmarked}
              onClick={withConfirm({ title: "Mark everyone present?", message: `${unmarked} unmarked worker(s) will be marked present for ${date}.`, confirmLabel: "Mark present" }, markAll)}
              className="disabled:opacity-50"
            >
              Mark rest present
            </PrimaryButton>
          </div>
        }
      />

      <div className="grid grid-cols-1 gap-5 sm:grid-cols-2 xl:grid-cols-4">
        <StatCard deltaDir="none" icon={IconUserCheck} tone="green" label="Present" value={count("Present") + count("Half day")} delta={`${count("Half day")} half day`} note="" spark={[5, 6, 6, 7, 6, 7, 7]} />
        <StatCard deltaDir="none" icon={IconUserX} tone="orange" label="Absent" value={count("Absent")} delta="" note="no reason given" spark={[1, 2, 1, 1, 2, 1, 1]} />
        <StatCard deltaDir="none" icon={IconCalendarCheck} tone="violet" label="On leave" value={count("Leave")} delta="" note="approved leave" spark={[0, 1, 1, 0, 1, 1, 1]} />
        <StatCard deltaDir="none" icon={IconUserOff} tone="gray" label="Not marked" value={unmarked} delta="" note={`of ${active.length} active`} spark={[2, 1, 1, 0, 1, 0, 0]} />
      </div>

      <Card className="pt-5">
        <div className="flex flex-wrap items-center justify-between gap-3 px-5">
          <CardTitle icon={IconCalendarCheck} iconClass="text-[#1F5B3A]">{new Date(date).toLocaleDateString("en-US", { weekday: "long", month: "long", day: "numeric", year: "numeric" })}</CardTitle>
          <div className="flex gap-3">
            <FilterSelect label="All sites" options={sites.map((s) => s.name)} value={site} onChange={setSite} />
            <button
              aria-label="Export attendance"
              onClick={() => {
                downloadCSV(`attendance-${month}`, active, [
                  ["Worker ID", (w) => w.id],
                  ["Name", (w) => w.name],
                  ["Site", (w) => siteName(state, w.siteId)],
                  [date, (w) => byWorker.get(w.id)?.status ?? "Not marked"],
                  [`Days worked (${month})`, (w) => monthDays(w.id)],
                ]);
                toast("Attendance exported");
              }}
              className="grid size-10 place-items-center rounded-xl border border-gray-200 hover:bg-page"
            >
              <IconDownload className="size-5" />
            </button>
          </div>
        </div>
        <div className="mt-4 overflow-x-auto px-2 pb-4">
          {active.length === 0 ? (
            <Empty>No active workers.</Empty>
          ) : (
            <table className="w-full text-left text-sm">
              <thead className="bg-head">
                <tr>{["Worker", "Site", "Category", "Status", `Days worked in ${month}`].map((h) => <th key={h} className="px-3 py-3 text-[13px] font-medium">{h}</th>)}</tr>
              </thead>
              <tbody>
                {active.map((w) => {
                  const cur = byWorker.get(w.id)?.status;
                  return (
                    <tr key={w.id} className="border-b border-gray-100 last:border-0">
                      <td className="px-3 py-2.5"><Link href={`/miner/workers/${w.id}`} className="flex items-center gap-3 font-medium hover:underline"><Initials name={w.name} className="size-8 text-xs" />{w.name}</Link></td>
                      <td className="px-3">{siteName(state, w.siteId)}</td>
                      <td className="px-3">{w.category}</td>
                      <td className="px-3">
                        <div className="flex gap-1.5">
                          {STATUSES.map((st) => (
                            <button key={st} onClick={() => mark(w.id, st)} className={`rounded-full border px-2.5 py-1 text-xs ${cur === st ? `${chip[st]} font-medium` : "border-gray-200 text-ink/60 hover:bg-page"}`}>
                              {st}
                            </button>
                          ))}
                        </div>
                      </td>
                      <td className="px-3">{monthDays(w.id)}</td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          )}
        </div>
      </Card>
    </>
  );
}
