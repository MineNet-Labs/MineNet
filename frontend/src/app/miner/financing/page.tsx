"use client";

import { openForm } from "@/components/FormHost";


import { withConfirm } from "@/components/ui/Confirm";

import Link from "next/link";
import { IconBuildingBank, IconCash, IconClock, IconLock, IconPlus } from "@tabler/icons-react";
import { Card, CardTitle, Empty, PageHeader, PrimaryButton, StatCard, StatusBadge, toast, type BadgeTone } from "@/components/ui";
import { approveLoan } from "@/components/chain-forms";
import { fmtNum, type LoanStatus } from "@/lib/data";
import { orgCanAct } from "@/lib/domain";
import { update, useStore } from "@/lib/store";

const tone: Record<LoanStatus, BadgeTone> = { Requested: "pending", Active: "blue", Repaid: "success", Declined: "danger" };

export default function FinancingPage() {
  const state = useStore((s) => s);
  const { loans, parties } = state;
  const active = loans.filter((l) => l.status === "Active");
  const outstanding = active.reduce((n, l) => n + l.amount, 0);
  const requested = loans.filter((l) => l.status === "Requested");

  return (
    <>
      <PageHeader
        title="Financing"
        subtitle="Borrow against verified lots. The financier records a lien on the lot, and escrow repays it automatically when the lot sells."
        actions={<PrimaryButton icon={IconPlus} disabled={!orgCanAct(state)} onClick={() => openForm("financing")} className="disabled:opacity-50">Request financing</PrimaryButton>}
      />

      <div className="grid grid-cols-1 gap-5 sm:grid-cols-2 xl:grid-cols-4">
        <StatCard deltaDir="none" icon={IconCash} tone="green" label="Outstanding (USD)" value={fmtNum(outstanding)} delta={`${active.length}`} note="active loans" spark={[3, 4, 4, 5, 5, 6, 6]} />
        <StatCard deltaDir="none" icon={IconLock} tone="violet" label="Lots under lien" value={active.length} delta="" note="can still be sold" spark={[1, 2, 2, 1, 2, 2, 1]} />
        <StatCard deltaDir="none" icon={IconClock} tone="orange" label="Requests pending" value={requested.length} delta="" note="awaiting financier" spark={[1, 1, 2, 1, 1, 2, 1]} />
        <StatCard deltaDir="none" icon={IconBuildingBank} tone="gray" label="Repaid loans" value={loans.filter((l) => l.status === "Repaid").length} delta="" note="all time" spark={[1, 1, 1, 2, 2, 2, 2]} />
      </div>

      <Card className="pt-6">
        <div className="px-6"><CardTitle icon={IconBuildingBank} iconClass="text-[#1F5B3A]">Loans</CardTitle></div>
        <div className="mt-5 overflow-x-auto px-3 pb-4">
          {loans.length === 0 ? (
            <Empty>No loans yet.</Empty>
          ) : (
            <table className="w-full text-left text-sm">
              <thead className="bg-head">
                <tr>{["Loan", "Collateral lot", "Financier", "Amount", "Rate / term", "Requested", "Due", "Status", ""].map((h) => <th key={h} className="px-3 py-3 text-[13px] font-medium">{h}</th>)}</tr>
              </thead>
              <tbody>
                {loans.map((l) => (
                  <tr key={l.id} className="border-b border-gray-100 last:border-0">
                    <td className="px-3 py-3 font-medium">{l.id}<p className="text-xs font-normal text-ink/60">{l.purpose}</p></td>
                    <td className="px-3"><Link href={`/miner/mineral-lots/${l.lotId}`} className="hover:underline">{l.lotId}</Link></td>
                    <td className="px-3">{parties.find((p) => p.id === l.financierId)?.name}</td>
                    <td className="px-3">{l.currency} {fmtNum(l.amount)}</td>
                    <td className="px-3">{l.ratePct}% · {l.termDays} days</td>
                    <td className="px-3">{l.requested}</td>
                    <td className="px-3">{l.due ?? "—"}</td>
                    <td className="px-3"><StatusBadge tone={tone[l.status]}>{l.status}</StatusBadge></td>
                    <td className="px-3 text-right">
                      {l.status === "Requested" && (
                        <span className="flex justify-end gap-3 text-xs">
                          <button onClick={withConfirm({ title: "Approve loan? (demo)", message: "Stands in for the financier: the money is paid to you and a lien is recorded on the lot.", confirmLabel: "Approve" }, () => (approveLoan(l.id), toast("Loan approved: lien recorded (demo)", "info")))} className="text-accent underline">Demo: financier approves</button>
                          <button
                            onClick={withConfirm({ title: "Withdraw loan request?", message: `${l.id} will be cancelled.`, confirmLabel: "Withdraw", tone: "danger" }, () => {
                              update((s) => ({ loans: s.loans.filter((x) => x.id !== l.id) }));
                              toast(`Request ${l.id} withdrawn`, "info");
                            })}
                            className="text-ink/60 underline"
                          >
                            Withdraw
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
        <CardTitle icon={IconLock}>How a lien works</CardTitle>
        <ol className="mt-4 grid gap-4 text-sm md:grid-cols-3">
          {[
            ["1. Request", "Pick a verified lot as collateral. You can borrow up to 60% of its estimated value."],
            ["2. Lien recorded", "When the financier approves, a lien is added to the lot passport and the money is paid to you."],
            ["3. Automatic repayment", "When the lot sells, escrow repays the loan with interest first and sends you the rest."],
          ].map(([t, d]) => (
            <li key={t} className="rounded-2xl bg-page p-4"><p className="font-medium">{t}</p><p className="mt-1 text-ink/70">{d}</p></li>
          ))}
        </ol>
      </Card>

    </>
  );
}
