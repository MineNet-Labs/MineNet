"use client";

import { useMemo, useState } from "react";
import { IconCash, IconClock, IconDownload, IconFileInvoice, IconPlus, IconReceipt, IconUsers } from "@tabler/icons-react";
import { Card, CardTitle, Empty, PageHeader, PrimaryButton, StatCard, StatusBadge, toast } from "@/components/ui";
import { Select } from "@/components/ui/Select";
import { confirmAction } from "@/components/ui/Confirm";
import { MONTHS, fmtNum, today, type PayLine, type PayRun } from "@/lib/data";
import { DEDUCTION_PCT, rateFor } from "@/lib/people";
import { makeNotice } from "@/lib/domain";
import { getState, nextId, update, useStore } from "@/lib/store";
import { downloadCSV, downloadFile } from "@/lib/csv";

const monthLabel = (m: string) => `${MONTHS[Number(m.slice(5, 7)) - 1]} ${m.slice(0, 4)}`;

/** Monthly salaries from attendance: days worked × daily rate, minus RSSB pension. */
export default function PayrollPage() {
  const state = useStore((s) => s);
  const { payruns, workers, attendance } = state;
  const months = useMemo(() => [...new Set(attendance.map((a) => a.date.slice(0, 7)))].sort().reverse(), [attendance]);
  const [month, setMonth] = useState(months[0] ?? "2025-08");
  const [openId, setOpenId] = useState<string | null>(payruns[0]?.id ?? null);
  const run = payruns.find((r) => r.id === openId);
  const worker = (id: string) => workers.find((w) => w.id === id);

  const buildLines = (m: string): PayLine[] =>
    getState()
      .workers.map((w) => {
        const days = getState()
          .attendance.filter((a) => a.workerId === w.id && a.date.startsWith(m))
          .reduce((n, a) => n + (a.status === "Present" || a.status === "Leave" ? 1 : a.status === "Half day" ? 0.5 : 0), 0);
        const rate = rateFor(w.category);
        const gross = Math.round(days * rate);
        const deductions = Math.round(gross * DEDUCTION_PCT);
        return { workerId: w.id, days, rate, gross, deductions, net: gross - deductions };
      })
      .filter((l) => l.days > 0);

  const createRun = async () => {
    const id = `PAY-${month}`;
    if (getState().payruns.some((r) => r.id === id)) {
      setOpenId(id);
      return toast(`A pay run for ${monthLabel(month)} already exists`, "info");
    }
    const lines = buildLines(month);
    if (!lines.length) return toast("No attendance recorded for that month", "error");
    if (!(await confirmAction({ title: `Prepare ${monthLabel(month)} payroll?`, message: `${lines.length} workers, calculated from attendance. You can review it before paying.`, confirmLabel: "Prepare" }))) return;
    update((s) => ({ payruns: [{ id, month, status: "Draft" as const, lines, created: today() }, ...s.payruns] }));
    setOpenId(id);
    toast(`Draft payroll ${id} prepared`);
  };

  const recalc = (r: PayRun) => {
    update((s) => ({ payruns: s.payruns.map((x) => (x.id === r.id ? { ...x, lines: buildLines(r.month) } : x)) }));
    toast("Recalculated from the latest attendance", "info");
  };

  const pay = async (r: PayRun) => {
    const total = r.lines.reduce((n, l) => n + l.net, 0);
    if (!(await confirmAction({ title: "Pay all salaries?", message: `RWF ${fmtNum(total)} goes to ${r.lines.length} workers by mobile money. This can't be undone.`, confirmLabel: "Pay now" }))) return;
    update((s) => {
      let txns = [...s.txns];
      for (const l of r.lines) {
        const w = s.workers.find((x) => x.id === l.workerId);
        txns = [{ id: nextId(txns.filter((t) => t.direction === "out").map((t) => t.id), "TXN-OUT-2511-", 3), direction: "out" as const, party: w?.name ?? l.workerId, ref: `Salary · ${monthLabel(r.month)}`, amount: l.net, currency: "RWF" as const, method: "MTN Mobile Money", date: today(), status: "Paid" as const }, ...txns];
      }
      return {
        txns,
        payruns: s.payruns.map((x) => (x.id === r.id ? { ...x, status: "Paid" as const, paid: today() } : x)),
        notices: [makeNotice(s, "payment", `Payroll ${r.id} paid: RWF ${fmtNum(total)} to ${r.lines.length} workers`, "/miner/payroll"), ...s.notices],
      };
    });
    toast(`Payroll ${r.id} paid`);
  };

  const payslip = (r: PayRun, l: PayLine) => {
    const w = worker(l.workerId);
    downloadFile(
      `payslip-${l.workerId}-${r.month}.txt`,
      [
        `PAYSLIP · ${state.org.name}`,
        `Period: ${monthLabel(r.month)}`,
        `Worker: ${w?.name} (${l.workerId}) · ${w?.category}`,
        "",
        `Days worked: ${l.days}`,
        `Daily rate: RWF ${fmtNum(l.rate)}`,
        `Gross: RWF ${fmtNum(l.gross)}`,
        `RSSB pension (3%): RWF ${fmtNum(l.deductions)}`,
        `Net pay: RWF ${fmtNum(l.net)}`,
        "",
        `Status: ${r.status}${r.paid ? ` on ${r.paid}` : ""}`,
      ].join("\n"),
    );
    toast("Payslip downloaded");
  };

  const totals = (r?: PayRun) => ({ gross: r?.lines.reduce((n, l) => n + l.gross, 0) ?? 0, net: r?.lines.reduce((n, l) => n + l.net, 0) ?? 0 });
  const t = totals(run);

  return (
    <>
      <PageHeader
        title="Payroll"
        subtitle="Salaries are calculated from attendance: days worked × daily rate, minus the 3% RSSB pension. Review, then pay everyone by mobile money."
        actions={
          <div className="flex items-center gap-3">
            <div className="w-40">
              <Select value={month} onChange={(e) => setMonth(e.target.value)} aria-label="Payroll month">
                {months.map((m) => <option key={m} value={m}>{monthLabel(m)}</option>)}
              </Select>
            </div>
            <PrimaryButton icon={IconPlus} onClick={createRun}>Prepare payroll</PrimaryButton>
          </div>
        }
      />

      <div className="grid grid-cols-1 gap-5 sm:grid-cols-2 xl:grid-cols-4">
        <StatCard deltaDir="none" icon={IconUsers} tone="green" label="Workers in run" value={run?.lines.length ?? 0} delta="" note={run ? monthLabel(run.month) : ""} spark={[3, 4, 4, 5, 5, 6, 6]} />
        <StatCard deltaDir="none" icon={IconCash} tone="orange" label="Gross (RWF)" value={fmtNum(t.gross)} delta="" note="before deductions" spark={[3, 4, 3, 5, 4, 6, 6]} />
        <StatCard deltaDir="none" icon={IconReceipt} tone="violet" label="Net pay (RWF)" value={fmtNum(t.net)} delta="" note="to workers" spark={[3, 4, 3, 5, 4, 6, 6]} />
        <StatCard deltaDir="none" icon={IconClock} tone="gray" label="Runs waiting" value={payruns.filter((r) => r.status !== "Paid").length} delta="" note="not paid yet" spark={[1, 1, 2, 1, 1, 1, 1]} />
      </div>

      <div className="grid items-start gap-5 xl:grid-cols-[300px_1fr]">
        <Card className="p-4">
          <CardTitle icon={IconFileInvoice}>Pay runs</CardTitle>
          <ul className="mt-3 space-y-1.5">
            {payruns.map((r) => (
              <li key={r.id}>
                <button onClick={() => setOpenId(r.id)} className={`flex w-full items-center justify-between rounded-xl px-3 py-2.5 text-left text-sm ${r.id === openId ? "bg-primary-soft" : "hover:bg-page"}`}>
                  <span><b className="font-medium">{monthLabel(r.month)}</b><span className="block text-xs text-ink/60">{r.lines.length} workers</span></span>
                  <StatusBadge tone={r.status === "Paid" ? "success" : r.status === "Approved" ? "blue" : "pending"}>{r.status}</StatusBadge>
                </button>
              </li>
            ))}
            {payruns.length === 0 && <li className="text-sm text-ink/60">No pay runs yet.</li>}
          </ul>
        </Card>

        <Card className="pt-6">
          {!run ? (
            <div className="p-6"><Empty>Prepare a payroll to see it here.</Empty></div>
          ) : (
            <>
              <div className="flex flex-wrap items-center justify-between gap-3 px-6">
                <CardTitle icon={IconCash} iconClass="text-[#1F5B3A]">{monthLabel(run.month)} · {run.id}</CardTitle>
                <div className="flex gap-2">
                  <button
                    onClick={() => {
                      downloadCSV(run.id, run.lines, [
                        ["Worker ID", (l) => l.workerId],
                        ["Name", (l) => worker(l.workerId)?.name ?? ""],
                        ["Days", (l) => l.days],
                        ["Daily rate", (l) => l.rate],
                        ["Gross", (l) => l.gross],
                        ["RSSB", (l) => l.deductions],
                        ["Net", (l) => l.net],
                      ]);
                      toast("Payroll exported");
                    }}
                    className="inline-flex items-center gap-1.5 rounded-full border border-gray-200 px-4 py-2 text-sm hover:bg-page"
                  >
                    <IconDownload className="size-4" /> Export
                  </button>
                  {run.status === "Draft" && (
                    <button onClick={() => recalc(run)} className="rounded-full border border-gray-200 px-4 py-2 text-sm hover:bg-page">Recalculate</button>
                  )}
                  {run.status !== "Paid" && (
                    <button onClick={() => pay(run)} className="rounded-full bg-[#1F5B3A] px-5 py-2 text-sm font-medium text-white hover:bg-primary">Pay RWF {fmtNum(t.net)}</button>
                  )}
                </div>
              </div>
              <div className="mt-4 overflow-x-auto px-3 pb-4">
                <table className="w-full text-left text-sm">
                  <thead className="bg-head">
                    <tr>{["Worker", "Category", "Days", "Daily rate", "Gross", "RSSB 3%", "Net", ""].map((h) => <th key={h} className="px-3 py-3 text-[13px] font-medium">{h}</th>)}</tr>
                  </thead>
                  <tbody>
                    {run.lines.map((l) => (
                      <tr key={l.workerId} className="border-b border-gray-100 last:border-0">
                        <td className="px-3 py-2.5 font-medium">{worker(l.workerId)?.name ?? l.workerId}</td>
                        <td className="px-3">{worker(l.workerId)?.category}</td>
                        <td className="px-3">{l.days}</td>
                        <td className="px-3">{fmtNum(l.rate)}</td>
                        <td className="px-3">{fmtNum(l.gross)}</td>
                        <td className="px-3">{fmtNum(l.deductions)}</td>
                        <td className="px-3 font-medium">{fmtNum(l.net)}</td>
                        <td className="px-3 text-right"><button onClick={() => payslip(run, l)} className="text-xs font-medium text-accent hover:underline">Payslip</button></td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </>
          )}
        </Card>
      </div>
    </>
  );
}
