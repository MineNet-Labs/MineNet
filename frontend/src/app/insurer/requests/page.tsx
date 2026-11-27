"use client";

import Link from "next/link";
import { useState } from "react";
import { IconInbox } from "@tabler/icons-react";
import { Card, CardTitle, Empty, PageHeader } from "@/components/ui";
import { useInsurer } from "@/components/insurer/common";
import { DeclineModal, QuoteModal } from "@/components/insurer/forms";
import { fmtKg, fmtNum, type Policy } from "@/lib/data";
import { lotCustody } from "@/lib/domain";
import { siteName } from "@/lib/store";

export default function CoverRequestsPage() {
  const { state, policies } = useInsurer();
  const [quoting, setQuoting] = useState<Policy | null>(null);
  const [declining, setDeclining] = useState<Policy | null>(null);
  const requests = policies.filter((p) => p.status === "Requested");

  return (
    <>
      <PageHeader title="Cover Requests" subtitle="Miners asking you to cover a lot in storage or transit. Check the lot's passport, then quote or decline." />
      <Card className="pt-6">
        <div className="px-6"><CardTitle icon={IconInbox} iconClass="text-accent">Waiting for a quote</CardTitle></div>
        <div className="mt-4 overflow-x-auto px-3 pb-4">
          {requests.length === 0 ? (
            <Empty>No cover requests waiting.</Empty>
          ) : (
            <table className="w-full text-left text-sm">
              <thead className="bg-head"><tr>{["Request", "Client", "Lot", "Cover", "Where it is", "Declared value", "Received", ""].map((h) => <th key={h} className="px-3 py-3 text-[13px] font-medium">{h}</th>)}</tr></thead>
              <tbody>
                {requests.map((p) => {
                  const l = state.lots.find((x) => x.id === p.lotId);
                  return (
                    <tr key={p.id} className="border-b border-gray-100 last:border-0">
                      <td className="px-3 py-3 font-medium"><Link href={`/insurer/policies/${p.id}`} className="hover:underline">{p.id}</Link></td>
                      <td className="px-3">{state.org.name}</td>
                      <td className="px-3">{p.lotId}<span className="block text-xs text-ink/60">{l ? `${l.mineral} · ${fmtKg(l.quantityKg)} · ${l.grade}% · ${l.status}` : ""}</span></td>
                      <td className="px-3">{p.cover}</td>
                      <td className="px-3">{l ? lotCustody(state, l).place : "—"}<span className="block text-xs text-ink/60">{l ? siteName(state, l.siteId) : ""}</span></td>
                      <td className="px-3">{p.currency} {fmtNum(p.sumInsured)}</td>
                      <td className="px-3">{p.from}</td>
                      <td className="px-3 text-right">
                        <span className="flex justify-end gap-3">
                          <button onClick={() => setQuoting(p)} className="rounded-full bg-[#1F5B3A] px-4 py-1.5 text-xs font-medium text-white">Send quote</button>
                          <button onClick={() => setDeclining(p)} className="text-xs text-ink/60 underline">Decline</button>
                        </span>
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          )}
        </div>
      </Card>
      {quoting && <QuoteModal policy={quoting} onClose={() => setQuoting(null)} />}
      {declining && <DeclineModal policy={declining} onClose={() => setDeclining(null)} />}
    </>
  );
}
