"use client";

import Link from "next/link";
import { withConfirm } from "@/components/ui/Confirm";
import { useParams } from "next/navigation";
import { IconCheck, IconMessage, IconSend2, IconX } from "@tabler/icons-react";
import { Card, CardTitle, Field, StatusBadge, inputClass, statusTone, toast } from "@/components/ui";
import { DetailHeader, Facts, NotFound } from "@/components/DetailShell";
import { acceptOffer } from "@/components/chain-forms";
import { fmtKg, fmtNum, today } from "@/lib/data";
import { orgCanAct, priceGuidance } from "@/lib/domain";
import { update, useStore } from "@/lib/store";

export function OfferDetail() {
  const { id } = useParams<{ id: string }>();
  const state = useStore((s) => s);
  const offer = state.offers.find((o) => o.id === id);
  if (!offer) return <NotFound what="Offer" id={id} back="/miner/marketplace" backLabel="Marketplace" />;

  const req = state.requests.find((r) => r.id === offer.requestId);
  const lot = state.lots.find((l) => l.id === offer.lotId);
  const history = offer.history?.length
    ? offer.history
    : [{ by: "You" as const, pricePerKg: offer.pricePerKg, quantityKg: offer.quantityKg, note: "Initial offer", date: offer.sent }];
  const last = history[history.length - 1];
  const open = offer.status === "Sent" || offer.status === "Countered";
  const escrow = state.escrows.find((e) => e.offerId === offer.id);
  const guide = lot ? priceGuidance(state, lot.mineral, lot.grade) : null;
  const canAct = orgCanAct(state);

  const send = (e: React.FormEvent<HTMLFormElement>) => {
    e.preventDefault();
    const fd = new FormData(e.currentTarget);
    const msg = { by: "You" as const, pricePerKg: Number(fd.get("price")), quantityKg: Number(fd.get("qty")), note: String(fd.get("note") || ""), date: today() };
    update((s) => ({ offers: s.offers.map((o) => (o.id === offer.id ? { ...o, status: "Sent" as const, history: [...history, msg] } : o)) }));
    toast(`Counter-offer sent to ${req?.buyer}`);
    e.currentTarget.reset();
  };

  return (
    <>
      <DetailHeader
        back="/miner/marketplace"
        backLabel="Marketplace"
        title={`Offer ${offer.id}`}
        badge={<StatusBadge tone={statusTone(offer.status)}>{offer.status}</StatusBadge>}
        subtitle={<>To <Link href={`/miner/marketplace/requests/${offer.requestId}`} className="hover:underline">{req?.buyer}</Link> · {req?.mineral} · sent {offer.sent}</>}
        actions={
          open && (
            <>
              {last.by === "Buyer" && lot?.status === "Verified" && (
                <button
                  disabled={!canAct}
                  onClick={withConfirm({ title: "Accept this price?", message: `You agree to sell ${fmtKg(last.quantityKg)} of ${offer.lotId} to ${req?.buyer} at $${last.pricePerKg}/kg (USD ${fmtNum(last.pricePerKg * last.quantityKg)}). The buyer\'s payment is then locked in escrow.`, confirmLabel: "Accept and sell" }, () => (acceptOffer(offer.id, "You"), toast(`Deal agreed: ${req?.buyer} locks the payment in escrow`)))}
                  className="inline-flex items-center gap-2 rounded-2xl bg-[#1F5B3A] px-5 py-3 text-[15px] font-medium text-white disabled:opacity-50"
                >
                  <IconCheck className="size-5" /> Accept ${last.pricePerKg}/kg
                </button>
              )}
              <button
                onClick={withConfirm({ title: "Withdraw offer?", message: `The negotiation with ${req?.buyer} ends. You can make a new offer later.`, confirmLabel: "Withdraw", tone: "danger" }, () => {
                  update((s) => ({ offers: s.offers.map((o) => (o.id === offer.id ? { ...o, status: "Declined" as const, history: [...history, { by: "You" as const, pricePerKg: last.pricePerKg, quantityKg: last.quantityKg, note: "Withdrawn", date: today() }] } : o)) }));
                  toast(`Offer ${offer.id} withdrawn`, "info");
                })}
                className="inline-flex items-center gap-2 rounded-2xl border border-gray-200 bg-white px-5 py-3 text-[15px] hover:bg-page"
              >
                <IconX className="size-5" /> Withdraw
              </button>
            </>
          )
        }
      />

      <div className="grid items-start gap-5 xl:grid-cols-[1fr_380px]">
        <Card className="p-6">
          <CardTitle icon={IconMessage} iconClass="text-[#1F5B3A]">Negotiation</CardTitle>
          <ol className="mt-5 space-y-3">
            {history.map((m, i) => (
              <li key={i} className={`max-w-[80%] rounded-2xl px-4 py-3 ${m.by === "You" ? "ml-auto bg-primary-soft" : "bg-page"}`}>
                <p className="text-xs text-ink/60">{m.by === "You" ? "You" : req?.buyer} · {m.date}</p>
                <p className="font-medium">${m.pricePerKg}/kg × {fmtKg(m.quantityKg)} = USD {fmtNum(m.pricePerKg * m.quantityKg)}</p>
                {m.note && <p className="text-sm text-ink/75">{m.note}</p>}
              </li>
            ))}
          </ol>
          {open && offer.status === "Sent" && last.by === "You" && (
            <p className="mt-4 text-sm text-ink/60">
              Waiting for {req?.buyer}.{" "}
              <button
                onClick={() => (acceptOffer(offer.id, "Buyer"), toast(`${req?.buyer} accepted (demo)`, "info"))}
                className="text-accent underline"
              >
                Demo: buyer accepts
              </button>{" "}
              ·{" "}
              <button
                onClick={() => {
                  const p = +(last.pricePerKg * 0.96).toFixed(2);
                  update((s) => ({ offers: s.offers.map((o) => (o.id === offer.id ? { ...o, status: "Countered" as const, history: [...history, { by: "Buyer" as const, pricePerKg: p, quantityKg: last.quantityKg, note: "Can you meet us at this price?", date: today() }] } : o)) }));
                  toast("Buyer countered (demo)", "info");
                }}
                className="text-accent underline"
              >
                Demo: buyer counters
              </button>
            </p>
          )}
          {open && (
            <form onSubmit={send} className="mt-5 grid grid-cols-[1fr_1fr_2fr_auto] items-end gap-3 border-t border-gray-100 pt-5">
              <Field label="Price / kg (USD)"><input name="price" type="number" step="0.01" min={0.01} required defaultValue={last.pricePerKg} className={inputClass} /></Field>
              <Field label="Quantity (kg)"><input name="qty" type="number" min={1} max={lot?.quantityKg} required defaultValue={last.quantityKg} className={inputClass} /></Field>
              <Field label="Message"><input name="note" className={inputClass} placeholder="Optional" /></Field>
              <button type="submit" disabled={!canAct} className="grid h-11 w-11 place-items-center rounded-xl bg-[#1F5B3A] text-white disabled:opacity-50" aria-label="Send counter-offer">
                <IconSend2 className="size-5" />
              </button>
            </form>
          )}
          {escrow && (
            <p className="mt-5 rounded-xl bg-violet-soft px-4 py-3 text-sm">
              {escrow.currency} {fmtNum(escrow.amount)} is {escrow.status.toLowerCase()} in escrow {escrow.id}.{" "}
              <Link href={`/miner/mineral-lots/${offer.lotId}`} className="font-medium text-violet underline">Dispatch the lot</Link>
            </p>
          )}
        </Card>

        <div className="space-y-5">
          <Card className="p-6">
            <CardTitle>Your lot</CardTitle>
            <div className="mt-4">
              <Facts
                cols={2}
                items={[
                  ["Lot", <Link key="l" href={`/miner/mineral-lots/${offer.lotId}`} className="text-accent hover:underline">{offer.lotId}</Link>],
                  ["Mineral", lot?.mineral ?? "—"],
                  ["Available", lot ? fmtKg(lot.quantityKg) : "—"],
                  ["Grade", lot ? `${lot.grade}%` : "—"],
                ]}
              />
            </div>
          </Card>
          <Card className="p-6">
            <CardTitle>Buyer request</CardTitle>
            <div className="mt-4">
              <Facts
                cols={2}
                items={[
                  ["Buyer", req?.buyer ?? "—"],
                  ["Grade wanted", req?.grade ?? "—"],
                  ["Still needed", req ? `${req.remainingT} t` : "—"],
                  ["Indicative price", req ? `$${req.pricePerKg}/kg` : "—"],
                  ["Delivery", req ? `${req.city}, ${req.country}` : "—"],
                  ["Deadline", req?.deadline ?? "—"],
                ]}
              />
            </div>
          </Card>
          {guide && (
            <Card className="p-6">
              <CardTitle>Price guidance</CardTitle>
              <p className="mt-3 font-heading text-xl font-bold">${guide.low} – ${guide.high} / kg</p>
              <p className="mt-1 text-xs text-ink/60">{guide.basis}</p>
            </Card>
          )}
        </div>
      </div>
    </>
  );
}
