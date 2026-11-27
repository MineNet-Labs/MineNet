"use client";

import { can } from "@/lib/roles";

import { useQueryParam } from "@/lib/useQueryParam";

import { useCallback, useMemo, useState } from "react";
import { confirmAction } from "@/components/ui/Confirm";
import {
  IconArrowDown,
  IconArrowDownLeft,
  IconArrowUp,
  IconArrowUpRight,
  IconArrowsExchange,
  IconCircleCheck,
  IconClock,
  IconDownload,
  IconPlus,
  IconRefresh,
  IconTrendingDown,
  IconTrendingUp,
  IconUsers,
  type Icon as TablerIcon,
} from "@tabler/icons-react";
import {
  Card,
  DateRange,
  Empty,
  FilterSelect,
  PageHeader,
  Pagination,
  PrimaryButton,
  RowMenu,
  StatusBadge,
  statusTone,
  toast,
  usePaged,
} from "@/components/ui";
import { Sparkline } from "@/components/ui/charts";
import { fmtNum, type Txn } from "@/lib/data";
import { update, useStore, useMe } from "@/lib/store";
import { downloadCSV, downloadFile } from "@/lib/csv";
import { RecordPaymentModal } from "./RecordPaymentModal";
import { EscrowCard } from "./EscrowCard";

/* ------------------------------------------------------------ KPI tile */

const tileTones = {
  green: { chip: "bg-primary-soft text-[#1F5B3A]", line: "#1F5B3A" },
  orange: { chip: "bg-accent-soft text-accent", line: "#F0913F" },
  violet: { chip: "bg-violet-soft text-violet", line: "#8B7CF6" },
  red: { chip: "bg-danger-soft text-danger", line: "#EF6A6A" },
};

function FinanceTile({
  icon: Icon, tone, label, currency, value, delta, up, good, note = "this month", spark,
}: {
  icon: TablerIcon; tone: keyof typeof tileTones; label: string; currency?: string; value: string;
  delta: string; up: boolean; good: boolean; note?: string; spark: number[];
}) {
  const t = tileTones[tone];
  const Arrow = up ? IconArrowUp : IconArrowDown;
  return (
    <Card className="p-4">
      <div className="flex items-start justify-between">
        <span className={`grid size-11 place-items-center rounded-full ${t.chip}`}><Icon className="size-5" stroke={2} /></span>
        <Sparkline values={spark} color={t.line} width={88} height={40} />
      </div>
      <p className="mt-3 truncate text-[15px] font-medium">{label}</p>
      <p className="font-heading text-[26px] leading-tight font-bold">
        {currency && <span className="mr-1 font-sans text-sm font-medium text-ink/70">{currency}</span>}
        {value}
      </p>
      <p className={`flex items-center gap-1 text-[13px] ${good ? "text-[#1F5B3A]" : "text-danger"}`}>
        <Arrow className="size-3.5" stroke={2.5} />{delta}<span className="ml-1 text-ink/60">{note}</span>
      </p>
    </Card>
  );
}

const millions = (n: number) => `${(n / 1_000_000).toFixed(1)}M`;
const USD_RWF = 1400; // indicative rate for totals only
const amountText = (t: Txn) => (t.currency === "USD" ? fmtNum(t.amount, 2) : fmtNum(t.amount));

export default function PaymentsPage() {
  const me = useMe();
  const txns = useStore((s) => s.txns);
  const [tab, setTab] = useState<"in" | "out">("in");
  const [status, setStatus] = useState("");
  const [method, setMethod] = useState("");
  const [search, setSearch] = useState("");
  const [open, setOpen] = useState(false);

  useQueryParam("q", useCallback((v: string) => {
    setSearch(v);
    const hit = txns.find((t) => t.id === v);
    if (hit) setTab(hit.direction);
  }, [txns]));
  const list = useMemo(() => txns.filter((t) => t.direction === tab && (!search || `${t.id} ${t.party} ${t.ref}`.toLowerCase().includes(search.toLowerCase()))), [txns, tab, search]);
  const rows = useMemo(() => list.filter((t) => (!status || t.status === status) && (!method || t.method === method)), [list, status, method]);
  const { rows: page, pager } = usePaged(rows, 5);

  const rwf = (t: Txn) => (t.currency === "USD" ? t.amount * USD_RWF : t.amount);
  const income = txns.filter((t) => t.direction === "in" && t.status === "Received").reduce((a, t) => a + rwf(t), 0);
  const expenses = txns.filter((t) => t.direction === "out" && t.status === "Paid").reduce((a, t) => a + rwf(t), 0);
  const pending = txns.filter((t) => t.status === "Pending" || t.status === "Processing").reduce((a, t) => a + rwf(t), 0);
  const completed = txns.filter((t) => t.status === "Received" || t.status === "Paid").length;
  const unpaidSalaries = txns.filter((t) => t.direction === "out" && t.ref.startsWith("Salary") && t.status !== "Paid");

  const setTxnStatus = async (id: string, s: Txn["status"], msg: string) => {
    if (!(await confirmAction({ title: "Update payment?", message: `${id} will be marked ${s.toLowerCase()}.`, confirmLabel: "Update" }))) return;
    update((st) => ({ txns: st.txns.map((t) => (t.id === id ? { ...t, status: s } : t)) }));
    toast(msg, "info");
  };

  const receipt = (t: Txn) => {
    downloadFile(
      `${t.id}.txt`,
      `MINENET PAYMENT RECEIPT\n\nTransaction: ${t.id}\n${t.direction === "in" ? "From" : "To"}: ${t.party}\nReference: ${t.ref}\nAmount: ${t.currency} ${amountText(t)}\nMethod: ${t.method}\nDate: ${t.date}\nStatus: ${t.status}\n`,
    );
    toast(`Receipt ${t.id} downloaded`);
  };

  return (
    <>
      <PageHeader
        title="Payments & Escrow"
        subtitle="Track sale proceeds in escrow, income, company expenses and worker salaries in one place."
        actions={
          <>
            <DateRange label="01 Aug, 2025 – 31 Aug, 2025" />
            <PrimaryButton icon={IconPlus} className="rounded-full" onClick={() => setOpen(true)}>Record Payment</PrimaryButton>
          </>
        }
      />

      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-5">
        <FinanceTile icon={IconTrendingUp} tone="green" label="Total Income" currency="RWF" value={millions(income)} delta="+14%" up good spark={[3, 4, 3.5, 5, 4.5, 6, 8]} />
        <FinanceTile icon={IconTrendingDown} tone="orange" label="Total Expenses" currency="RWF" value={millions(expenses)} delta="+6%" up={false} good={false} spark={[3, 5, 3.5, 6, 4, 7, 5]} />
        <FinanceTile icon={IconClock} tone="orange" label="Pending Payments" currency="RWF" value={millions(pending)} delta="-9%" up={false} good={false} spark={[3, 7, 4, 6, 3.5, 4, 3]} />
        <FinanceTile icon={IconCircleCheck} tone="violet" label="Completed Payments" value={String(completed)} delta="+18" up good spark={[3, 3.5, 4.5, 4, 5.5, 6, 8]} />
        <FinanceTile icon={IconUsers} tone="red" label="Outstanding Salaries" currency="RWF" value={millions(unpaidSalaries.reduce((a, t) => a + t.amount, 0))} delta={`${unpaidSalaries.length} workers`} up={false} good={false} spark={[3, 3.5, 3.2, 5, 4.5, 6, 8]} />
      </div>

      {search && (
        <p className="pl-2 text-sm">
          Showing results for “{search}” ·{" "}
          <button onClick={() => setSearch("")} className="font-medium text-accent hover:underline">Clear</button>
        </p>
      )}

      {can.finance(me.role) && <EscrowCard />}

      <Card className="overflow-hidden pt-6">
        <div className="flex items-center justify-between px-6">
          <h3 className="flex items-center gap-3 font-sans text-lg font-semibold"><IconArrowsExchange className="size-6 text-accent" stroke={1.9} /> Transactions</h3>
          <div className="flex gap-2">
            <FilterSelect label="All statuses" options={[...new Set(list.map((t) => t.status))]} value={status} onChange={setStatus} />
            <FilterSelect label="All methods" options={[...new Set(list.map((t) => t.method))]} value={method} onChange={setMethod} />
            <button
              aria-label="Export transactions"
              onClick={() => {
                downloadCSV(`transactions-${tab === "in" ? "incoming" : "outgoing"}`, rows, [
                  ["Transaction ID", (t) => t.id],
                  [tab === "in" ? "Buyer / Source" : "Paid to", (t) => t.party],
                  ["Reference", (t) => t.ref],
                  ["Amount", (t) => t.amount],
                  ["Currency", (t) => t.currency],
                  ["Method", (t) => t.method],
                  ["Date", (t) => t.date],
                  ["Status", (t) => t.status],
                ]);
                toast(`${rows.length} transactions exported`);
              }}
              className="grid size-10 place-items-center rounded-full border border-gray-200 hover:bg-page"
            >
              <IconDownload className="size-4" />
            </button>
          </div>
        </div>

        <div className="mt-4 flex gap-8 border-b border-gray-100 px-7">
          {[
            { key: "in" as const, label: "Incoming Payments", icon: IconArrowDownLeft },
            { key: "out" as const, label: "Outgoing Payments", icon: IconArrowUpRight },
          ].map((t) => (
            <button
              key={t.key}
              onClick={() => (setTab(t.key), setStatus(""), setMethod(""))}
              className={`-mb-px flex items-center gap-2 border-b-2 pb-3 text-[15px] ${tab === t.key ? "border-accent font-medium text-accent" : "border-transparent text-ink/80 hover:text-ink"}`}
            >
              <t.icon className="size-4" stroke={2.2} />
              {t.label}
              
            </button>
          ))}
        </div>

        <div className="overflow-x-auto px-3">
          {page.length === 0 ? (
            <Empty>No transactions match these filters.</Empty>
          ) : (
            <table className="w-full min-w-[1000px] text-left text-sm">
              <thead className="bg-head">
                <tr>
                  <th className="px-4 py-3.5 text-[13px] font-medium">Transaction ID</th>
                  <th className="px-4 text-[13px] font-medium">{tab === "in" ? "Buyer / Source" : "Paid to"}</th>
                  <th className="px-4 text-[13px] font-medium">{tab === "in" ? "Mineral Lot / Sale" : "Purpose"}</th>
                  <th className="px-4 text-right text-[13px] font-medium">Amount</th>
                  {["Currency", "Method", "Date", "Status", ""].map((h, i) => <th key={i} className="px-4 text-[13px] font-medium">{h}</th>)}
                </tr>
              </thead>
              <tbody>
                {page.map((t) => (
                  <tr key={t.id} className="border-b border-gray-100">
                    <td className="px-4 py-4 font-medium">{t.id}</td>
                    <td className="px-4">{t.party}</td>
                    <td className="px-4 text-ink/80">{t.ref}</td>
                    <td className="px-4 text-right font-semibold tabular-nums">{amountText(t)}</td>
                    <td className="px-4">{t.currency}</td>
                    <td className="px-4">{t.method}</td>
                    <td className="px-4">{t.date}</td>
                    <td className="px-4"><StatusBadge tone={statusTone(t.status)}>{t.status}</StatusBadge></td>
                    <td className="px-4 text-right">
                      <RowMenu
                        items={[
                          { label: "Download receipt", icon: IconDownload, onClick: () => receipt(t) },
                          ...(t.status === "Failed" ? [{ label: "Retry payment", icon: IconRefresh, onClick: () => setTxnStatus(t.id, "Processing", `${t.id} resubmitted`) }] : []),
                          ...(t.status === "Pending" || t.status === "Processing"
                            ? [{ label: t.direction === "in" ? "Mark as received" : "Mark as paid", icon: IconCircleCheck, onClick: () => setTxnStatus(t.id, t.direction === "in" ? "Received" : "Paid", `${t.id} marked ${t.direction === "in" ? "received" : "paid"}`) }]
                            : []),
                        ]}
                      />
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </div>
        <Pagination {...pager} noun="transactions" />
      </Card>

      {open && <RecordPaymentModal onClose={() => (setOpen(false), setTab("out"))} />}
    </>
  );
}
