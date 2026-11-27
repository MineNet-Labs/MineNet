"use client";

import { CancelButton, Field, Modal, SubmitButton, formValues, inputClass, toast } from "@/components/ui";
import { Select } from "@/components/ui/Select";
import { confirmAction } from "@/components/ui/Confirm";
import { fmtKg, fmtNum, type Claim, type Policy } from "@/lib/data";
import { activeLien, lotCustody } from "@/lib/domain";
import { decideClaim, declineRequest, sendQuote } from "@/lib/insurer";
import { siteName, useStore } from "@/lib/store";

/** Insurer prices a cover request. The suggestion uses the insurer's own rates. */
export function QuoteModal({ policy, onClose }: { policy: Policy; onClose: () => void }) {
  const state = useStore((s) => s);
  const rate = state.insurerRates[policy.insurerId]?.[policy.cover] ?? 0.005;
  const lot = state.lots.find((l) => l.id === policy.lotId);
  const flags: string[] = [];
  if (lot && lot.status !== "Verified") flags.push("Lot is not verified by an inspector");
  if (lot && activeLien(state, lot.id)) flags.push("Lot has an active lien (financier is a loss payee)");
  if (state.incidents.some((i) => i.siteId === lot?.siteId && i.status !== "Closed")) flags.push("Open safety incident at the origin site");

  return (
    <Modal
      title={`Quote ${policy.id}`}
      subtitle={`${policy.cover} cover for ${policy.lotId} · declared value ${policy.currency} ${fmtNum(policy.sumInsured)}`}
      onClose={onClose}
      footer={<><CancelButton onClick={onClose} /><SubmitButton form="quote-form">Send quote</SubmitButton></>}
    >
      <form
        id="quote-form"
        className="grid grid-cols-2 gap-4"
        onSubmit={async (e) => {
          const v = formValues(e);
          const premium = Number(v.premium);
          const months = Number(v.months);
          if (!(await confirmAction({ title: "Send quote?", message: `${state.org.name} is offered ${policy.cover.toLowerCase()} cover on ${policy.lotId} for ${policy.currency} ${fmtNum(premium)} over ${months} month(s).`, confirmLabel: "Send quote" }))) return;
          sendQuote(policy.id, premium, months);
          toast(`Quote sent to ${state.org.name}`);
          onClose();
        }}
      >
        {lot && (
          <div className="col-span-2 grid grid-cols-3 gap-3 rounded-2xl bg-page px-4 py-3 text-sm">
            <div><p className="text-ink/60">Lot</p><p className="font-medium">{lot.mineral} · {fmtKg(lot.quantityKg)} · {lot.grade}%</p></div>
            <div><p className="text-ink/60">Origin</p><p className="font-medium">{siteName(state, lot.siteId)}</p></div>
            <div><p className="text-ink/60">Custody now</p><p className="font-medium">{lotCustody(state, lot).state}</p></div>
          </div>
        )}
        {flags.length > 0 && (
          <ul className="col-span-2 space-y-1 rounded-xl bg-accent-soft px-4 py-3 text-sm text-[#9a4a12]">
            {flags.map((f) => <li key={f}>• {f}</li>)}
          </ul>
        )}
        <Field label={`Premium per month (${policy.currency})`} hint={`Your rate for ${policy.cover.toLowerCase()}: ${(rate * 100).toFixed(2)}% of value per month`}>
          <input name="premium" type="number" min={1} required defaultValue={Math.round(policy.sumInsured * rate)} className={inputClass} />
        </Field>
        <Field label="Period">
          <Select name="months" defaultValue="1">
            <option value="1">1 month</option>
            <option value="3">3 months</option>
            <option value="6">6 months</option>
          </Select>
        </Field>
      </form>
    </Modal>
  );
}

export function DeclineModal({ policy, onClose }: { policy: Policy; onClose: () => void }) {
  return (
    <Modal title={`Decline ${policy.id}?`} subtitle="The client sees your reason." onClose={onClose} footer={<><CancelButton onClick={onClose} /><SubmitButton form="decline-form">Decline request</SubmitButton></>}>
      <form
        id="decline-form"
        onSubmit={(e) => {
          const v = formValues(e);
          declineRequest(policy.id, v.reason);
          toast(`Request ${policy.id} declined`, "info");
          onClose();
        }}
      >
        <Field label="Reason">
          <Select name="reason" required defaultValue="">
            <option value="" disabled>Select a reason</option>
            <option>Lot not yet verified</option>
            <option>Route or storage outside our cover area</option>
            <option>Value above our limit</option>
            <option>Incomplete documents</option>
          </Select>
        </Field>
      </form>
    </Modal>
  );
}

export function ClaimDecisionModal({ claim, approve, onClose }: { claim: Claim; approve: boolean; onClose: () => void }) {
  return (
    <Modal
      title={approve ? `Approve ${claim.id}` : `Reject ${claim.id}`}
      subtitle={`${claim.lotId} · claimed ${claim.currency} ${fmtNum(claim.amount)}`}
      onClose={onClose}
      footer={<><CancelButton onClick={onClose} /><SubmitButton form="claim-decision">{approve ? "Approve and pay" : "Reject claim"}</SubmitButton></>}
    >
      <form
        id="claim-decision"
        className="grid gap-4"
        onSubmit={async (e) => {
          const v = formValues(e);
          const payout = approve ? Number(v.payout) : undefined;
          const ok = await confirmAction({
            title: approve ? "Pay this claim?" : "Reject this claim?",
            message: approve ? `${claim.currency} ${fmtNum(payout!)} is paid to the client now.` : "The client is told the claim was rejected.",
            confirmLabel: approve ? "Pay" : "Reject",
            tone: approve ? "primary" : "danger",
          });
          if (!ok) return;
          decideClaim(claim.id, approve, v.note, payout);
          toast(`Claim ${claim.id} ${approve ? "approved and paid" : "rejected"}`);
          onClose();
        }}
      >
        {approve && (
          <Field label={`Payout (${claim.currency})`} hint="You can pay less than claimed, e.g. after an excess">
            <input name="payout" type="number" min={1} max={claim.amount} required defaultValue={claim.amount} className={inputClass} />
          </Field>
        )}
        <Field label={approve ? "Note to the client" : "Reason"}>
          <textarea name="note" required rows={3} className={`${inputClass} h-auto py-3`} defaultValue={approve ? "Assessed and approved." : ""} />
        </Field>
      </form>
    </Modal>
  );
}
