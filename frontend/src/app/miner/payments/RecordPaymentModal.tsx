"use client";

import { useState } from "react";
import { Select } from "@/components/ui/Select";
import { CancelButton, Field, Modal, StatusBadge, SubmitButton, formValues, inputClass, toast } from "@/components/ui";
import { MONTHS } from "@/lib/data";
import { getState, siteName, update, useStore } from "@/lib/store";

const payout: Record<string, string> = {};

export function RecordPaymentModal({ onClose }: { onClose: () => void }) {
  const state = useStore((s) => s);
  const workers = state.workers.filter((w) => w.status === "Active");
  const [workerId, setWorkerId] = useState(workers[0]?.id ?? "");
  const w = workers.find((x) => x.id === workerId);

  return (
    <Modal
      title="Record Salary Payment"
      subtitle="The worker receives an SMS confirmation once the payment clears."
      onClose={onClose}
      footer={<><CancelButton onClick={onClose} /><SubmitButton form="pay-form">Record Payment</SubmitButton></>}
    >
      <form
        id="pay-form"
        className="space-y-4"
        onSubmit={(e) => {
          const v = formValues(e);
          if (!w) return;
          const [y, m] = v.period.split("-");
          const n = getState().txns.filter((t) => t.direction === "out").length + 105;
          const d = new Date(v.date);
          update((s) => ({
            txns: [
              {
                id: `TXN-OUT-${y.slice(2)}${m}-${n}`,
                direction: "out",
                party: w.name,
                ref: `Salary · ${MONTHS[Number(m) - 1]} ${y}${v.note ? ` · ${v.note}` : ""}`,
                amount: Number(v.amount),
                currency: "RWF",
                method: v.method,
                date: `${MONTHS[d.getMonth()]} ${String(d.getDate()).padStart(2, "0")}, ${d.getFullYear()}`,
                status: "Processing",
              },
              ...s.txns,
            ],
          }));
          toast(`Salary of RWF ${Number(v.amount).toLocaleString()} recorded for ${w.name}`);
          onClose();
        }}
      >
        <Field label="Worker">
          <Select value={workerId} onChange={(e) => setWorkerId(e.target.value)} className={inputClass}>
            {workers.map((x) => <option key={x.id} value={x.id}>{x.name} · {x.id}</option>)}
          </Select>
        </Field>

        {w && (
          <div className="grid grid-cols-2 gap-x-6 gap-y-4 rounded-2xl bg-page px-4 py-4 text-sm">
            <div><p className="text-ink/60">Mining site</p><p className="mt-0.5 font-medium">{siteName(state, w.siteId)}</p></div>
            <div><p className="text-ink/60">Role</p><p className="mt-0.5 font-medium">{w.category}</p></div>
            <div><p className="text-ink/60">Pays to</p><p className="mt-0.5 font-medium">{payout[w.id] ?? `MTN MoMo · ${w.phone}`}</p></div>
            <div><p className="text-ink/60">Current status</p><p className="mt-1"><StatusBadge tone="pending">Due</StatusBadge></p></div>
          </div>
        )}

        <div className="grid grid-cols-2 gap-4">
          <Field label="Amount (RWF)"><input name="amount" type="number" min={1} required inputMode="numeric" className={inputClass} /></Field>
          <Field label="Payment period"><input name="period" type="month" required defaultValue="2025-08" className={inputClass} /></Field>
          <Field label="Payment method">
            <Select name="method" required defaultValue="" className={inputClass}>
              <option value="" disabled>Select method</option>
              <option>MTN Mobile Money</option>
              <option>Airtel Money</option>
              <option>Bank Transfer</option>
              <option>Cash</option>
            </Select>
          </Field>
          <Field label="Payment date"><input name="date" type="date" required className={inputClass} /></Field>
        </div>

        <Field label="Note (optional)"><input name="note" placeholder="e.g. includes overtime for 12–16 Aug" className={inputClass} /></Field>
      </form>
    </Modal>
  );
}
