"use client";

import Link from "next/link";
import { useState } from "react";
import { IconDownload, IconFileCertificate } from "@tabler/icons-react";
import { Card, CardTitle, Empty, FilterSelect, PageHeader, toast } from "@/components/ui";
import { PolicyBadge, useInsurer } from "@/components/insurer/common";
import { fmtNum } from "@/lib/data";
import { downloadCSV } from "@/lib/csv";

export default function InsurerPoliciesPage() {
  const { policies } = useInsurer();
  const [status, setStatus] = useState("");
  const [cover, setCover] = useState("");
  const rows = policies.filter((p) => p.status !== "Requested" && (!status || p.status === status) && (!cover || p.cover === cover));

  return (
    <>
      <PageHeader title="Policies" subtitle="Quotes you sent and policies in force." />
      <Card className="pt-5">
        <div className="flex flex-wrap items-center justify-between gap-3 px-5">
          <CardTitle icon={IconFileCertificate} iconClass="text-[#0e7490]">All policies</CardTitle>
          <div className="flex gap-3">
            <FilterSelect label="All statuses" options={["Quoted", "Active", "Expired", "Declined"]} value={status} onChange={setStatus} />
            <FilterSelect label="All cover" options={["Storage", "Transit", "Storage & transit"]} value={cover} onChange={setCover} />
            <button
              aria-label="Export policies"
              onClick={() => {
                downloadCSV("policies", rows, [["Policy", (p) => p.id], ["Lot", (p) => p.lotId], ["Cover", (p) => p.cover], ["Sum insured", (p) => p.sumInsured], ["Premium", (p) => p.premium], ["From", (p) => p.from], ["To", (p) => p.to], ["Status", (p) => p.status]]);
                toast("Policies exported");
              }}
              className="grid size-10 place-items-center rounded-xl border border-gray-200 hover:bg-page"
            >
              <IconDownload className="size-5" />
            </button>
          </div>
        </div>
        <div className="mt-4 overflow-x-auto px-2 pb-4">
          {rows.length === 0 ? (
            <Empty>No policies match.</Empty>
          ) : (
            <table className="w-full text-left text-sm">
              <thead className="bg-head"><tr>{["Policy", "Lot", "Cover", "Sum insured", "Premium", "Period", "Status"].map((h) => <th key={h} className="px-3 py-3 text-[13px] font-medium">{h}</th>)}</tr></thead>
              <tbody>
                {rows.map((p) => (
                  <tr key={p.id} className="border-b border-gray-100 last:border-0">
                    <td className="px-3 py-3 font-medium"><Link href={`/insurer/policies/${p.id}`} className="hover:text-[#1F5B3A] hover:underline">{p.id}</Link></td>
                    <td className="px-3">{p.lotId}</td>
                    <td className="px-3">{p.cover}</td>
                    <td className="px-3">{p.currency} {fmtNum(p.sumInsured)}</td>
                    <td className="px-3">{p.currency} {fmtNum(p.premium)}</td>
                    <td className="px-3">{p.from} – {p.to}</td>
                    <td className="px-3"><PolicyBadge status={p.status} /></td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </div>
      </Card>
    </>
  );
}
