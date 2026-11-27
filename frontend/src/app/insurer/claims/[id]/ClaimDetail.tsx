"use client";

import Link from "next/link";
import { useParams } from "next/navigation";
import { useState } from "react";
import { IconAlertTriangle, IconRoute } from "@tabler/icons-react";
import { Card, CardTitle, StatusBadge } from "@/components/ui";
import { DetailHeader, Facts, NotFound } from "@/components/DetailShell";
import { claimTone, useInsurer } from "@/components/insurer/common";
import { ClaimDecisionModal } from "@/components/insurer/forms";
import { fmtNum } from "@/lib/data";
import { lotCustody, lotTimeline } from "@/lib/domain";

export function ClaimDetail() {
  const { id } = useParams<{ id: string }>();
  const { state, claims, policies } = useInsurer();
  const [decide, setDecide] = useState<boolean | null>(null);
  const c = claims.find((x) => x.id === id);
  if (!c) return <NotFound what="Claim" id={id} back="/insurer/claims" backLabel="Claims" />;

  const p = policies.find((x) => x.id === c.policyId);
  const lot = state.lots.find((l) => l.id === c.lotId);
  const events = lot ? lotTimeline(state, lot).filter((e) => p && Date.parse(e.date) >= Date.parse(p.from)) : [];
  const incidents = state.incidents.filter((i) => i.siteId === lot?.siteId);

  return (
    <>
      <DetailHeader
        back="/insurer/claims"
        backLabel="Claims"
        title={c.id}
        badge={<StatusBadge tone={claimTone[c.status]}>{c.status}</StatusBadge>}
        subtitle={`${state.org.name} · ${c.lotId} · filed ${c.filed}`}
        actions={
          c.status === "Filed" && (
            <>
              <button onClick={() => setDecide(false)} className="rounded-2xl border border-gray-200 bg-white px-5 py-3 text-[15px] hover:bg-page">Reject</button>
              <button onClick={() => setDecide(true)} className="rounded-2xl bg-[#1F5B3A] px-5 py-3 text-[15px] font-medium text-white hover:bg-primary">Approve & pay</button>
            </>
          )
        }
      />

      <div className="grid items-start gap-5 xl:grid-cols-[1fr_380px]">
        <div className="space-y-5">
          <Card className="p-6">
            <CardTitle icon={IconAlertTriangle} iconClass="text-danger">Claim</CardTitle>
            <p className="mt-4 rounded-xl bg-page px-4 py-3 text-[15px]">{c.reason}</p>
            <div className="mt-5">
              <Facts
                items={[
                  ["Amount claimed", `${c.currency} ${fmtNum(c.amount)}`],
                  ["Policy", p ? <Link key="p" href={`/insurer/policies/${p.id}`} className="text-accent hover:underline">{p.id} · {p.cover}</Link> : c.policyId],
                  ["Sum insured", p ? `${p.currency} ${fmtNum(p.sumInsured)}` : "—"],
                  ["Cover period", p ? `${p.from} – ${p.to}` : "—"],
                  ["Decided", c.decided ?? "Not yet"],
                  ["Note", c.note ?? "—"],
                ]}
              />
            </div>
          </Card>
          <Card className="p-6">
            <CardTitle icon={IconRoute} iconClass="text-[#B5551A]">Lot events during cover</CardTitle>
            <ul className="mt-4 space-y-3 text-sm">
              {events.map((e) => (
                <li key={e.id} className="rounded-xl bg-page px-3 py-2.5"><b className="font-medium">{e.kind}</b> · {e.detail}<span className="block text-xs text-ink/55">{e.date} · {e.actor}</span></li>
              ))}
              {events.length === 0 && <li className="text-ink/60">No signed events in the cover period.</li>}
            </ul>
          </Card>
        </div>
        <div className="space-y-5">
          {lot && (
            <Card className="p-6">
              <CardTitle>Where the lot is</CardTitle>
              <p className="mt-3 text-sm">{lotCustody(state, lot).state} · {lotCustody(state, lot).place}</p>
            </Card>
          )}
          <Card className="p-6">
            <CardTitle>Safety record at origin site</CardTitle>
            <ul className="mt-3 space-y-2 text-sm">
              {incidents.map((i) => <li key={i.id} className="rounded-xl bg-page px-3 py-2">{i.date} · {i.kind} · {i.severity}</li>)}
              {incidents.length === 0 && <li className="text-ink/60">No incidents reported.</li>}
            </ul>
          </Card>
        </div>
      </div>
      {decide !== null && <ClaimDecisionModal claim={c} approve={decide} onClose={() => setDecide(null)} />}
    </>
  );
}
