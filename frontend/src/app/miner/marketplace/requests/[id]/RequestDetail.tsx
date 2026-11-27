"use client";

import Link from "next/link";
import { useParams } from "next/navigation";
import { useState } from "react";
import { IconBox, IconRosetteDiscountCheck, IconSend2, IconShoppingCart } from "@tabler/icons-react";
import { Bar, Card, CardTitle, Empty, PrimaryButton, StatusBadge, statusTone } from "@/components/ui";
import { DetailHeader, Facts, NotFound } from "@/components/DetailShell";
import { MakeOfferModal } from "@/components/forms";
import { fmtKg } from "@/lib/data";
import { orgCanAct } from "@/lib/domain";
import { siteName, useStore } from "@/lib/store";

export function RequestDetail() {
  const { id } = useParams<{ id: string }>();
  const state = useStore((s) => s);
  const [offering, setOffering] = useState(false);
  const req = state.requests.find((r) => r.id === id);
  if (!req) return <NotFound what="Buyer request" id={id} back="/miner/marketplace" backLabel="Marketplace" />;

  const matching = state.lots.filter((l) => l.status === "Verified" && l.mineral === req.mineral);
  const mine = state.offers.filter((o) => o.requestId === req.id);
  const filled = Math.round(((req.requiredT - req.remainingT) / req.requiredT) * 100);

  return (
    <>
      <DetailHeader
        back="/miner/marketplace"
        backLabel="Marketplace"
        title={req.buyer}
        badge={req.verified ? <StatusBadge tone="success" icon={IconRosetteDiscountCheck}>Verified buyer</StatusBadge> : <StatusBadge tone="pending">Verification in progress</StatusBadge>}
        subtitle={`${req.id} · wants ${req.requiredT} t of ${req.mineral} (${req.grade}) · ${req.city}, ${req.country}`}
        actions={<PrimaryButton icon={IconSend2} disabled={!orgCanAct(state)} onClick={() => setOffering(true)} className="disabled:opacity-50">Make offer</PrimaryButton>}
      />

      <div className="grid items-start gap-5 xl:grid-cols-[1fr_380px]">
        <div className="space-y-5">
          <Card className="p-5">
            <CardTitle icon={IconShoppingCart} iconClass="text-[#1F5B3A]">Request</CardTitle>
            <div className="mt-5">
              <Facts
                items={[
                  ["Mineral", req.mineral],
                  ["Grade", req.grade],
                  ["Indicative price", `$${req.pricePerKg}/kg`],
                  ["Required", `${req.requiredT} t`],
                  ["Still needed", `${req.remainingT} t`],
                  ["Deadline", `${req.deadline} (in ${req.inDays} days)`],
                  ["Delivery", `${req.city}, ${req.country}`],
                  ["Offers received", req.offers],
                  ["Buyer status", req.verified ? "Verified" : "Pending verification"],
                ]}
              />
            </div>
            <div className="mt-5 space-y-2">
              <p className="flex justify-between text-sm"><span>Filled</span><span>{filled}%</span></p>
              <Bar value={filled} color="#1F5B3A" />
            </div>
            <p className="mt-5 rounded-xl bg-page px-4 py-3 text-sm">{req.notes}</p>
          </Card>

          <Card className="pt-5">
            <div className="px-5"><CardTitle icon={IconSend2}>Your offers on this request</CardTitle></div>
            <div className="mt-4 px-2 pb-4">
              {mine.length === 0 ? (
                <Empty>You haven&apos;t made an offer yet.</Empty>
              ) : (
                <ul className="divide-y divide-gray-100">
                  {mine.map((o) => (
                    <li key={o.id}>
                      <Link href={`/miner/marketplace/offers/${o.id}`} className="flex items-center justify-between rounded-xl px-3 py-3 hover:bg-page">
                        <span><b className="font-medium">{o.id}</b> · {o.lotId} · {fmtKg(o.quantityKg)} at ${o.pricePerKg}/kg</span>
                        <StatusBadge tone={statusTone(o.status)}>{o.status}</StatusBadge>
                      </Link>
                    </li>
                  ))}
                </ul>
              )}
            </div>
          </Card>
        </div>

        <Card className="self-start p-5">
          <CardTitle icon={IconBox} iconClass="text-[#B5551A]">Your matching lots</CardTitle>
          {matching.length === 0 ? (
            <p className="mt-4 text-sm text-ink/70">No verified {req.mineral} lots. Register one and get it inspected.</p>
          ) : (
            <ul className="mt-4 space-y-2 text-sm">
              {matching.map((l) => (
                <li key={l.id}>
                  <Link href={`/miner/mineral-lots/${l.id}`} className="flex justify-between rounded-xl bg-page px-3 py-2.5 hover:bg-cream">
                    <span><b className="font-medium">{l.id}</b> · {siteName(state, l.siteId)}</span>
                    <span>{fmtKg(l.quantityKg)} · {l.grade}%</span>
                  </Link>
                </li>
              ))}
            </ul>
          )}
        </Card>
      </div>

      {offering && <MakeOfferModal request={req} onClose={() => setOffering(false)} />}
    </>
  );
}
