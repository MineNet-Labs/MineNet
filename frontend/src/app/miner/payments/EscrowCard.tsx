"use client";

import Link from "next/link";
import { withConfirm } from "@/components/ui/Confirm";
import { IconLock, IconLockOpen } from "@tabler/icons-react";
import { Card, CardTitle, Empty, StatusBadge, toast } from "@/components/ui";
import { releaseEscrow } from "@/components/chain-forms";
import { fmtNum } from "@/lib/data";
import { useStore } from "@/lib/store";

/** Sale proceeds held by the escrow contract: locked until the buyer accepts delivery. */
export function EscrowCard() {
  const escrows = useStore((s) => s.escrows);
  const sum = (st: string) => escrows.filter((e) => e.status === st && e.currency === "USD").reduce((n, e) => n + e.amount, 0);
  const locked = sum("Locked");
  const released = sum("Released");
  const repaid = escrows.reduce((n, e) => n + (e.lienRepaid ?? 0), 0);

  return (
    <Card className="pt-5">
      <div className="px-5">
        <CardTitle icon={IconLock} iconClass="text-violet">Escrow</CardTitle>
        <p className="mt-1 text-sm text-ink/70">When a buyer purchases, their payment is locked. It is released to you when they accept delivery, after repaying any loan on the lot.</p>
        <div className="mt-5 grid grid-cols-3 gap-4">
          <div className="rounded-2xl bg-violet-soft px-4 py-3">
            <p className="flex items-center gap-1.5 text-sm text-violet"><IconLock className="size-4" /> Locked</p>
            <p className="font-heading text-2xl font-bold">USD {fmtNum(locked)}</p>
          </div>
          <div className="rounded-2xl bg-success-soft px-4 py-3">
            <p className="flex items-center gap-1.5 text-sm text-[#1F5B3A]"><IconLockOpen className="size-4" /> Released to you</p>
            <p className="font-heading text-2xl font-bold">USD {fmtNum(released - repaid)}</p>
          </div>
          <div className="rounded-2xl bg-page px-4 py-3">
            <p className="text-sm text-ink/70">Used to repay loans</p>
            <p className="font-heading text-2xl font-bold">USD {fmtNum(repaid)}</p>
          </div>
        </div>
      </div>
      <div className="mt-5 overflow-x-auto px-2 pb-4">
        {escrows.length === 0 ? (
          <Empty>No escrow yet. It starts when a buyer accepts one of your offers.</Empty>
        ) : (
          <table className="w-full text-left text-sm">
            <thead className="bg-head">
              <tr>{["Escrow", "Lot", "Buyer", "Amount", "Locked", "Released", "Status", ""].map((h) => <th key={h} className="px-3 py-3 text-[13px] font-medium">{h}</th>)}</tr>
            </thead>
            <tbody>
              {escrows.map((e) => (
                <tr key={e.id} className="border-b border-gray-100 last:border-0">
                  <td className="px-3 py-3 font-medium">{e.id}</td>
                  <td className="px-3"><Link href={`/miner/mineral-lots/${e.lotId}`} className="hover:underline">{e.lotId}</Link></td>
                  <td className="px-3">{e.buyer}</td>
                  <td className="px-3">{e.currency} {fmtNum(e.amount)}{e.lienRepaid ? <span className="block text-xs text-ink/60">{fmtNum(e.lienRepaid)} repaid a loan</span> : null}</td>
                  <td className="px-3">{e.locked}</td>
                  <td className="px-3">{e.released ?? "—"}</td>
                  <td className="px-3"><StatusBadge tone={e.status === "Locked" ? "info" : e.status === "Released" ? "success" : "neutral"}>{e.status}</StatusBadge></td>
                  <td className="px-3 text-right">
                    {e.status === "Locked" && (
                      <button onClick={withConfirm({ title: "Release escrow? (demo)", message: "This stands in for the buyer accepting delivery: escrow repays any loan, then pays you.", confirmLabel: "Release" }, () => (releaseEscrow(e.id), toast("Buyer accepted delivery: escrow released (demo)", "info")))} className="text-xs text-accent underline">
                        Demo: buyer accepts delivery
                      </button>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>
    </Card>
  );
}
