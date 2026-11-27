"use client";

import Link from "next/link";
import { useState } from "react";
import { IconAlertTriangle } from "@tabler/icons-react";
import { Card, Empty, PageHeader, StatusBadge } from "@/components/ui";
import { Tabs } from "@/components/ui/Tabs";
import { claimTone, useInsurer } from "@/components/insurer/common";
import { fmtNum } from "@/lib/data";

export default function InsurerClaimsPage() {
  const { claims } = useInsurer();
  const [tab, setTab] = useState("Filed");
  const rows = claims.filter((c) => tab === "All" || c.status === tab);

  return (
    <>
      <PageHeader title="Claims" subtitle="Losses reported by your clients. Review the lot's history, then pay or reject." />
      <Card className="pt-5">
        <div className="border-b border-gray-100 px-6">
          <Tabs value={tab} onChange={setTab} items={["Filed", "Approved", "Rejected", "All"].map((k) => ({ key: k, label: k === "Filed" ? "To decide" : k, count: k === "All" ? claims.length : claims.filter((c) => c.status === k).length }))} />
        </div>
        <div className="overflow-x-auto px-3 py-4">
          {rows.length === 0 ? (
            <Empty>No claims here.</Empty>
          ) : (
            <table className="w-full text-left text-sm">
              <thead className="bg-head"><tr>{["Claim", "Policy", "Lot", "What happened", "Amount", "Filed", "Status"].map((h) => <th key={h} className="px-3 py-3 text-[13px] font-medium">{h}</th>)}</tr></thead>
              <tbody>
                {rows.map((c) => (
                  <tr key={c.id} className="border-b border-gray-100 last:border-0">
                    <td className="px-3 py-3 font-medium"><Link href={`/insurer/claims/${c.id}`} className="hover:text-[#1F5B3A] hover:underline">{c.id}</Link></td>
                    <td className="px-3"><Link href={`/insurer/policies/${c.policyId}`} className="hover:underline">{c.policyId}</Link></td>
                    <td className="px-3">{c.lotId}</td>
                    <td className="max-w-[320px] truncate px-3" title={c.reason}>{c.reason}</td>
                    <td className="px-3">{c.currency} {fmtNum(c.amount)}</td>
                    <td className="px-3">{c.filed}</td>
                    <td className="px-3"><StatusBadge tone={claimTone[c.status]}>{c.status}</StatusBadge></td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </div>
      </Card>
      <p className="flex items-center gap-2 pl-2 text-xs text-ink/55"><IconAlertTriangle className="size-4" /> Open a claim to decide it.</p>
    </>
  );
}
