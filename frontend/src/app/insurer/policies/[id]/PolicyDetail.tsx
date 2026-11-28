"use client";

import Link from "next/link";
import { useParams } from "next/navigation";
import { useState } from "react";
import { IconRoute, IconShieldCheck, IconUmbrella } from "@tabler/icons-react";
import { Card, CardTitle, StatusBadge } from "@/components/ui";
import { DetailHeader, Facts, NotFound } from "@/components/DetailShell";
import { PolicyBadge, claimTone, useInsurer } from "@/components/insurer/common";
import { DeclineModal, QuoteModal } from "@/components/insurer/forms";
import { fmtKg, fmtNum } from "@/lib/data";
import { activeLien, lotCustody, lotTimeline, tokenId } from "@/lib/domain";
import { siteName } from "@/lib/store";

/** One policy with the insured lot's passport, so the insurer sees custody and history. */
export function PolicyDetail() {
  const { id } = useParams<{ id: string }>();
  const { state, policies, claims } = useInsurer();
  const [modal, setModal] = useState<"quote" | "decline" | null>(null);
  const p = policies.find((x) => x.id === id);
  if (!p) return <NotFound what="Policy" id={id} back="/insurer/policies" backLabel="Policies" />;

  const lot = state.lots.find((l) => l.id === p.lotId);
  const custody = lot ? lotCustody(state, lot) : null;
  const lien = lot ? activeLien(state, lot.id) : undefined;
  const timeline = lot ? lotTimeline(state, lot) : [];
  const own = claims.filter((c) => c.policyId === p.id);

  return (
    <>
      <DetailHeader
        back={p.status === "Requested" ? "/insurer/requests" : "/insurer/policies"}
        backLabel={p.status === "Requested" ? "Cover Requests" : "Policies"}
        title={p.id}
        badge={<PolicyBadge status={p.status} />}
        subtitle={`${p.cover} cover · ${state.org.name} · ${p.lotId}`}
        actions={
          p.status === "Requested" && (
            <>
              <button onClick={() => setModal("decline")} className="rounded-2xl border border-gray-200 bg-white px-5 py-3 text-[15px] hover:bg-page">Decline</button>
              <button onClick={() => setModal("quote")} className="rounded-2xl bg-[#1F5B3A] px-5 py-3 text-[15px] font-medium text-white hover:bg-primary">Send quote</button>
            </>
          )
        }
      />

      <div className="grid items-start gap-5 xl:grid-cols-[1fr_380px]">
        <div className="space-y-5">
          <Card className="p-5">
            <CardTitle icon={IconUmbrella} iconClass="text-[#0e7490]">Policy</CardTitle>
            <div className="mt-5">
              <Facts
                items={[
                  ["Insured", state.org.name],
                  ["Cover", p.cover],
                  ["Sum insured", `${p.currency} ${fmtNum(p.sumInsured)}`],
                  ["Premium", p.status === "Requested" ? "Not quoted yet" : `${p.currency} ${fmtNum(p.premium)}`],
                  ["Period", `${p.from} – ${p.to}`],
                  ["Loss payee", lien ? `${state.parties.find((x) => x.id === lien.financierId)?.name} (lien ${lien.id})` : "The insured"],
                ]}
              />
            </div>
          </Card>
          <Card className="p-5">
            <CardTitle icon={IconRoute} iconClass="text-[#B5551A]">Lot passport</CardTitle>
            <p className="mt-1 text-xs text-ink/60">Signed history of the insured lot (read-only).</p>
            <ol className="relative mt-5 space-y-4 border-l-2 border-gray-100 pl-6">
              {[...timeline].reverse().map((e) => (
                <li key={e.id} className="relative">
                  <span className="absolute top-1 -left-[31px] size-3 rounded-full bg-[#1F5B3A] ring-4 ring-white" />
                  <p className="font-medium">{e.kind}</p>
                  <p className="text-sm text-ink/80">{e.detail}</p>
                  <p className="text-xs text-ink/55">{e.date} · {e.actor} ({e.role})</p>
                </li>
              ))}
            </ol>
          </Card>
        </div>
        <div className="space-y-5">
          {lot && (
            <Card className="p-5">
              <CardTitle icon={IconShieldCheck}>Insured lot</CardTitle>
              <div className="mt-4">
                <Facts
                  cols={2}
                  items={[
                    ["Lot", `${lot.id} (token #${tokenId(lot.id)})`],
                    ["Mineral", `${lot.mineral} · ${lot.grade}%`],
                    ["Quantity", fmtKg(lot.quantityKg)],
                    ["Inspection", lot.status],
                    ["Origin", siteName(state, lot.siteId)],
                    ["Custody", custody ? `${custody.state} · ${custody.holder}` : "—"],
                  ]}
                />
              </div>
            </Card>
          )}
          <Card className="p-5">
            <CardTitle>Claims on this policy</CardTitle>
            <ul className="mt-4 space-y-2 text-sm">
              {own.map((c) => (
                <li key={c.id}>
                  <Link href={`/insurer/claims/${c.id}`} className="flex justify-between rounded-xl bg-page px-3 py-2.5 hover:bg-cream">
                    <span>{c.id} · {c.currency} {fmtNum(c.amount)}</span>
                    <StatusBadge tone={claimTone[c.status]}>{c.status}</StatusBadge>
                  </Link>
                </li>
              ))}
              {own.length === 0 && <li className="text-ink/60">No claims.</li>}
            </ul>
          </Card>
        </div>
      </div>
      {modal === "quote" && <QuoteModal policy={p} onClose={() => setModal(null)} />}
      {modal === "decline" && <DeclineModal policy={p} onClose={() => setModal(null)} />}
    </>
  );
}
