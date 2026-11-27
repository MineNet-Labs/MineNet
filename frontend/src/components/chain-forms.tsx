"use client";

import { addOrRequest, needsApproval } from "@/lib/approvals";

import { insurerNotice } from "@/lib/insurer";

import { confirmAction } from "@/components/ui/Confirm";

// Forms for custody, financing and insurance. Each writes the record, adds
// a signed event to the lot passport and a notification.

import Link from "next/link";
import { Select } from "@/components/ui/Select";
import { useMemo, useState } from "react";
import {
  CancelButton,
  Field,
  Modal,
  SubmitButton,
  formValues,
  inputClass,
  toast,
} from "@/components/ui";
import { fmtKg, fmtNum, today, type Lot, type Policy } from "@/lib/data";
import {
  activeLien,
  addDays,
  lotCustody,
  lotSold,
  makeEvent,
  makeNotice,
  orgCanAct,
  priceGuidance,
} from "@/lib/domain";
import { getState, nextId, siteName, update, useStore } from "@/lib/store";

type Close = { onClose: () => void };
const sel = `${inputClass} pr-8`;

function Blocked({ onClose, title }: Close & { title: string }) {
  const status = useStore((s) => s.org.status);
  return (
    <Modal
      title={title}
      subtitle="Blocked by your validation status"
      onClose={onClose}
      footer={<CancelButton onClick={onClose} />}
    >
      <p className="text-sm text-ink/80">
        Your organisation is <b>{status.toLowerCase()}</b> with RMB, so you
        can&apos;t sign new events.{" "}
        <Link
          href="/miner/licence"
          onClick={onClose}
          className="font-medium text-accent hover:underline"
        >
          See Licence & Validation
        </Link>
      </p>
    </Modal>
  );
}

/** Estimated lot value in USD (price guidance mid point). */
export function lotValue(lot: Lot) {
  return Math.round(
    priceGuidance(getState(), lot.mineral, lot.grade).mid * lot.quantityKg,
  );
}

/* --------------------------------------------------------------- custody */

export function DispatchModal({ onClose, lot }: Close & { lot: Lot }) {
  const state = useStore((s) => s);
  const [kind, setKind] = useState<"Transport" | "Warehouse">("Transport");
  const parties = state.parties.filter(
    (p) => p.kind === (kind === "Transport" ? "Transporter" : "Warehouse"),
  );
  const custody = lotCustody(state, lot);
  const escrow = state.escrows.find(
    (e) => e.lotId === lot.id && e.status === "Locked",
  );
  if (!orgCanAct(state))
    return <Blocked onClose={onClose} title="Dispatch lot" />;

  return (
    <Modal
      title={`Dispatch ${lot.id}`}
      subtitle="Hand the lot to a transporter or a warehouse. Custody changes only when both sides confirm."
      onClose={onClose}
      footer={
        <>
          <CancelButton onClick={onClose} />
          <SubmitButton form="dispatch-form">Create handover</SubmitButton>
        </>
      }
    >
      <form
        id="dispatch-form"
        className="grid grid-cols-2 gap-4"
        onSubmit={(e) => {
          const v = formValues(e);
          const party = state.parties.find((p) => p.id === v.party)!;
          void confirmAction({
            title: "Create handover?",
            message: `${lot.id} will be handed to ${party.name} with seal ${v.seal}. Custody changes once you and ${party.name} both confirm.`,
            confirmLabel: "Create handover",
          }).then((ok) => {
            if (!ok) return;
            const id = nextId(
              getState().transfers.map((t) => t.id),
              "TRF-",
              4,
            );
            if (needsApproval()) {
              const item = { id, lotId: lot.id, kind, partyId: party.id, from: custody.place, to: kind === "Warehouse" ? party.name : v.to, seal: v.seal, vehicle: v.vehicle || undefined, status: "Awaiting handover" as const, senderConfirmed: false, receiverConfirmed: false, created: today() };
              addOrRequest("Mineral handover", `Hand ${lot.id} to ${party.name} (seal ${v.seal})`, lot.siteId, [{ to: "transfers", item }]);
              toast("Sent to the owner for approval", "info");
              onClose();
              return;
            }
            update((s) => ({
              transfers: [
                {
                  id,
                  lotId: lot.id,
                  kind,
                  partyId: party.id,
                  from: custody.place,
                  to: kind === "Warehouse" ? party.name : v.to,
                  seal: v.seal,
                  vehicle: v.vehicle || undefined,
                  status: "Awaiting handover",
                  senderConfirmed: false,
                  receiverConfirmed: false,
                  created: today(),
                },
                ...s.transfers,
              ],
              notices: [
                makeNotice(
                  s,
                  "custody",
                  `Handover ${id} for ${lot.id} created with ${party.name}: confirm it when the lot leaves`,
                  `/miner/mineral-lots/${lot.id}`,
                ),
                ...s.notices,
              ],
            }));
            toast(
              `Handover ${id} created. Confirm it when ${party.name} collects the lot.`,
            );
            onClose();
          });
        }}
      >
        <div className="col-span-2 grid grid-cols-2 gap-2 rounded-2xl bg-page p-1">
          {(["Transport", "Warehouse"] as const).map((k) => (
            <button
              key={k}
              type="button"
              onClick={() => setKind(k)}
              className={`rounded-xl py-2 text-sm ${kind === k ? "bg-white font-medium shadow-sm" : "text-ink/70"}`}
            >
              {k === "Transport"
                ? "Send with a transporter"
                : "Store in a warehouse"}
            </button>
          ))}
        </div>
        <Field
          label={kind === "Transport" ? "Transporter" : "Warehouse"}
          className="col-span-2"
        >
          <Select
            name="party"
            required
            defaultValue=""
            key={kind}
            className={sel}
          >
            <option value="" disabled>
              Select a validated{" "}
              {kind === "Transport" ? "transporter" : "warehouse"}
            </option>
            {parties.map((p) => (
              <option key={p.id} value={p.id}>
                {p.name} · {p.location} · {p.regulator} {p.licence}
              </option>
            ))}
          </Select>
        </Field>
        <Field label="From">
          <input
            value={custody.place}
            readOnly
            className={`${inputClass} bg-page`}
          />
        </Field>
        {kind === "Transport" ? (
          <Field label="Deliver to">
            <input
              name="to"
              required
              defaultValue={escrow ? `${escrow.buyer}` : ""}
              className={inputClass}
              placeholder="Buyer, warehouse or processor"
            />
          </Field>
        ) : (
          <Field label="Deliver to">
            <input
              value="The selected warehouse"
              readOnly
              className={`${inputClass} bg-page`}
            />
          </Field>
        )}
        <Field
          label="Seal ID"
          hint="Printed on the GPS seal fitted to the bags"
        >
          <input
            name="seal"
            required
            defaultValue={`SL-${48800 + getState().transfers.length * 7 + 13}`}
            className={inputClass}
          />
        </Field>
        <Field label="Vehicle plate (optional)">
          <input
            name="vehicle"
            className={inputClass}
            placeholder="e.g. RAD 412 K"
          />
        </Field>
      </form>
    </Modal>
  );
}

/** Advance a handover: your confirmation, the other side's, then delivery. */
export function confirmTransfer(
  transferId: string,
  side: "sender" | "receiver" | "delivered",
) {
  update((s) => {
    const t = s.transfers.find((x) => x.id === transferId)!;
    const party = s.parties.find((p) => p.id === t.partyId)!;
    let next = { ...t };
    const events = [...s.events];
    const notices = [...s.notices];
    if (side === "sender") next.senderConfirmed = true;
    if (side === "receiver") next.receiverConfirmed = true;
    if (side === "delivered") {
      next.status = "Delivered";
      events.push(
        makeEvent(
          { ...s, events },
          t.lotId,
          "Delivered",
          t.to,
          "Receiver",
          `Delivered to ${t.to} · seal ${t.seal} intact`,
        ),
      );
      notices.unshift(
        makeNotice(
          s,
          "custody",
          `${t.lotId} delivered to ${t.to}`,
          `/miner/mineral-lots/${t.lotId}`,
        ),
      );
    }
    if (
      next.senderConfirmed &&
      next.receiverConfirmed &&
      t.status === "Awaiting handover"
    ) {
      next = {
        ...next,
        status: t.kind === "Warehouse" ? "Stored" : "In transit",
      };
      events.push(
        makeEvent(
          { ...s, events },
          t.lotId,
          "Handover",
          party.name,
          t.kind === "Warehouse" ? "Warehouse" : "Transporter",
          `Custody to ${party.name} · seal ${t.seal} · both sides confirmed`,
        ),
      );
      if (t.kind === "Warehouse")
        events.push(
          makeEvent(
            { ...s, events },
            t.lotId,
            "Stored",
            party.name,
            "Warehouse",
            `Received at ${party.name}`,
          ),
        );
      notices.unshift(
        makeNotice(
          s,
          "custody",
          `${t.lotId} handed to ${party.name}`,
          `/miner/mineral-lots/${t.lotId}`,
        ),
      );
    }
    return {
      transfers: s.transfers.map((x) => (x.id === t.id ? next : x)),
      events,
      notices,
    };
  });
}

/* ---------------------------------------------------------------- escrow */

/** Buyer accepts delivery: escrow repays any lien first, then pays the miner. */
export function releaseEscrow(escrowId: string) {
  update((s) => {
    const esc = s.escrows.find((e) => e.id === escrowId)!;
    const lien = activeLien(s, esc.lotId);
    const repay = lien
      ? Math.min(
          esc.amount,
          Math.round(
            lien.amount * (1 + (lien.ratePct / 100) * (lien.termDays / 365)),
          ),
        )
      : 0;
    const events = [...s.events];
    events.push(
      makeEvent(
        { ...s, events },
        esc.lotId,
        "Delivered",
        esc.buyer,
        "Buyer",
        "Delivery accepted by the buyer",
      ),
    );
    if (lien)
      events.push(
        makeEvent(
          { ...s, events },
          esc.lotId,
          "Lien released",
          "Escrow contract",
          "System",
          `Loan ${lien.id} repaid: ${esc.currency} ${fmtNum(repay)}`,
        ),
      );
    events.push(
      makeEvent(
        { ...s, events },
        esc.lotId,
        "Escrow released",
        "Escrow contract",
        "System",
        `${esc.currency} ${fmtNum(esc.amount - repay)} paid to ${s.org.name}`,
      ),
    );
    const txnId = nextId(
      s.txns.filter((t) => t.direction === "in").map((t) => t.id),
      "TXN-IN-2511-",
      3,
    );
    return {
      escrows: s.escrows.map((e) =>
        e.id === esc.id
          ? {
              ...e,
              status: "Released" as const,
              released: today(),
              lienRepaid: repay || undefined,
            }
          : e,
      ),
      loans: lien
        ? s.loans.map((l) =>
            l.id === lien.id ? { ...l, status: "Repaid" as const } : l,
          )
        : s.loans,
      transfers: s.transfers.map((t) =>
        t.lotId === esc.lotId && t.status === "In transit"
          ? { ...t, status: "Delivered" as const }
          : t,
      ),
      txns: [
        {
          id: txnId,
          direction: "in" as const,
          party: esc.buyer,
          ref: `${esc.lotId} · Escrow ${esc.id}`,
          amount: esc.amount - repay,
          currency: esc.currency,
          method: "Escrow release",
          date: today(),
          status: "Received" as const,
        },
        ...s.txns,
      ],
      events,
      notices: [
        makeNotice(
          s,
          "payment",
          `${esc.currency} ${fmtNum(esc.amount - repay)} released from escrow for ${esc.lotId}${lien ? ` after repaying ${lien.id}` : ""}`,
          "/miner/payments",
        ),
        ...s.notices,
      ],
    };
  });
}

/* ------------------------------------------------------------- financing */

export function RequestLoanModal({
  onClose,
  lotId,
}: Close & { lotId?: string }) {
  const state = useStore((s) => s);
  const eligible = useMemo(
    () =>
      state.lots.filter(
        (l) =>
          l.status === "Verified" &&
          !activeLien(state, l.id) &&
          !state.loans.some(
            (x) => x.lotId === l.id && x.status === "Requested",
          ) &&
          !lotSold(state, l.id),
      ),
    [state],
  );
  const [chosen, setChosen] = useState(
    lotId && eligible.some((l) => l.id === lotId) ? lotId : "",
  );
  const lot = state.lots.find((l) => l.id === chosen);
  const value = lot ? lotValue(lot) : 0;
  const max = Math.round(value * 0.6);
  if (!orgCanAct(state))
    return <Blocked onClose={onClose} title="Request financing" />;

  return (
    <Modal
      title="Request financing"
      subtitle="Borrow against a verified lot. The financier records a lien on the lot, repaid from escrow when it sells."
      onClose={onClose}
      footer={
        eligible.length ? (
          <>
            <CancelButton onClick={onClose} />
            <SubmitButton form="loan-form">Send request</SubmitButton>
          </>
        ) : (
          <CancelButton onClick={onClose} />
        )
      }
    >
      {eligible.length === 0 ? (
        <p className="text-sm text-ink/70">
          No verified, unsold lots without a lien. Get a lot inspected first.
        </p>
      ) : (
        <form
          id="loan-form"
          className="grid grid-cols-2 gap-4"
          onSubmit={(e) => {
            const v = formValues(e);
            const fin = state.parties.find((p) => p.id === v.financier)!;
            void confirmAction({
              title: "Send loan request?",
              message: `You ask ${fin.name} for USD ${fmtNum(Number(v.amount))} over ${v.term} days, using ${chosen} as collateral. If approved, a lien is recorded on the lot.`,
              confirmLabel: "Send request",
            }).then((ok) => {
              if (!ok) return;
              const id = nextId(
                getState().loans.map((l) => l.id),
                "LN-",
                4,
              );
              update((s) => ({
                loans: [
                  {
                    id,
                    lotId: chosen,
                    financierId: fin.id,
                    amount: Number(v.amount),
                    currency: "USD",
                    ratePct: fin.id === "umurenge" ? 11 : 12,
                    termDays: Number(v.term),
                    status: "Requested",
                    requested: today(),
                    purpose: v.purpose,
                  },
                  ...s.loans,
                ],
                notices: [
                  makeNotice(
                    s,
                    "finance",
                    `Loan request ${id} sent to ${fin.name}`,
                    "/miner/financing",
                  ),
                  ...s.notices,
                ],
              }));
              toast(`Loan request ${id} sent to ${fin.name}`);
              onClose();
            });
          }}
        >
          <Field label="Collateral lot" className="col-span-2">
            <Select
              required
              value={chosen}
              onChange={(e) => setChosen(e.target.value)}
              className={sel}
            >
              <option value="" disabled>
                Select a verified lot
              </option>
              {eligible.map((l) => (
                <option key={l.id} value={l.id}>
                  {l.id} · {l.mineral} · {fmtKg(l.quantityKg)} ·{" "}
                  {siteName(state, l.siteId)}
                </option>
              ))}
            </Select>
          </Field>
          {lot && (
            <div className="col-span-2 grid grid-cols-2 gap-4 rounded-2xl bg-page px-4 py-3 text-sm">
              <div>
                <p className="text-ink/60">Estimated value</p>
                <p className="font-medium">USD {fmtNum(value)}</p>
              </div>
              <div>
                <p className="text-ink/60">Maximum loan (60%)</p>
                <p className="font-medium">USD {fmtNum(max)}</p>
              </div>
            </div>
          )}
          <Field label="Financier" className="col-span-2">
            <Select name="financier" required defaultValue="" className={sel}>
              <option value="" disabled>
                Select a BNR-licensed financier
              </option>
              {state.parties
                .filter((p) => p.kind === "Financier")
                .map((p) => (
                  <option key={p.id} value={p.id}>
                    {p.name} · {p.id === "umurenge" ? "11%" : "12%"} per year
                  </option>
                ))}
            </Select>
          </Field>
          <Field
            label="Amount (USD)"
            hint={lot ? `Up to USD ${fmtNum(max)}` : undefined}
          >
            <input
              name="amount"
              type="number"
              min={100}
              max={max || undefined}
              required
              key={chosen}
              defaultValue={max ? Math.round(max / 2) : undefined}
              className={inputClass}
            />
          </Field>
          <Field label="Term">
            <Select name="term" defaultValue="90" className={sel}>
              <option value="30">30 days</option>
              <option value="60">60 days</option>
              <option value="90">90 days</option>
            </Select>
          </Field>
          <Field label="Purpose" className="col-span-2">
            <input
              name="purpose"
              required
              className={inputClass}
              placeholder="e.g. Working capital, equipment hire"
            />
          </Field>
        </form>
      )}
    </Modal>
  );
}

/** Financier approves (demo: stands in for the financier's portal). */
export function approveLoan(loanId: string) {
  update((s) => {
    const loan = s.loans.find((l) => l.id === loanId)!;
    const fin = s.parties.find((p) => p.id === loan.financierId)!;
    return {
      loans: s.loans.map((l) =>
        l.id === loanId
          ? {
              ...l,
              status: "Active" as const,
              due: addDays(today(), l.termDays),
            }
          : l,
      ),
      events: [
        ...s.events,
        makeEvent(
          s,
          loan.lotId,
          "Financed",
          fin.name,
          "Financier",
          `Loan ${loan.id} · USD ${fmtNum(loan.amount)} · lien recorded`,
        ),
      ],
      txns: [
        {
          id: nextId(
            s.txns.filter((t) => t.direction === "in").map((t) => t.id),
            "TXN-IN-2511-",
            3,
          ),
          direction: "in" as const,
          party: fin.name,
          ref: `Loan ${loan.id} · ${loan.lotId}`,
          amount: loan.amount,
          currency: loan.currency,
          method: "Bank Transfer",
          date: today(),
          status: "Received" as const,
        },
        ...s.txns,
      ],
      notices: [
        makeNotice(
          s,
          "finance",
          `${fin.name} approved loan ${loan.id}: lien recorded on ${loan.lotId}`,
          "/miner/financing",
        ),
        ...s.notices,
      ],
    };
  });
}

/* ------------------------------------------------------------- insurance */

const RATES: Record<Policy["cover"], number> = {
  Storage: 0.004,
  Transit: 0.006,
  "Storage & transit": 0.009,
};

export function InsureModal({ onClose, lotId }: Close & { lotId?: string }) {
  const state = useStore((s) => s);
  const eligible = state.lots.filter(
    (l) =>
      l.status !== "Rejected" &&
      !(
        lotSold(state, l.id) &&
        state.escrows.some((e) => e.lotId === l.id && e.status === "Released")
      ),
  );
  const [chosen, setChosen] = useState(lotId ?? "");
  const [cover, setCover] = useState<Policy["cover"]>("Transit");
  const lot = state.lots.find((l) => l.id === chosen);
  const sum = lot ? lotValue(lot) : 0;
  const premium = Math.round(sum * RATES[cover]);
  if (!orgCanAct(state))
    return <Blocked onClose={onClose} title="Insure a lot" />;

  return (
    <Modal
      title="Get insurance cover"
      subtitle="Cover a lot while it is stored or moving. The policy is recorded on the lot passport."
      onClose={onClose}
      footer={
        <>
          <CancelButton onClick={onClose} />
          <SubmitButton form="ins-quote">Send request</SubmitButton>
        </>
      }
    >
      <form
        id="ins-quote"
        className="grid grid-cols-2 gap-4"
        onSubmit={(e) => {
          const v = formValues(e);
          const id = nextId(
            getState().policies.map((p) => p.id),
            "POL-",
            4,
          );
          const months = Number(v.months);
          update((s) => ({
            policies: [
              {
                id,
                lotId: chosen,
                insurerId: v.insurer,
                cover,
                sumInsured: sum,
                premium: premium * months,
                currency: "USD",
                status: "Requested",
                from: today(),
                to: addDays(today(), months * 30),
              },
              ...s.policies,
            ],
            notices: [
              makeNotice(
                s,
                "finance",
                `Cover request ${id} for ${chosen} sent to the insurer`,
                "/miner/insurance",
              ),
              insurerNotice(s, v.insurer, "finance", `New cover request ${id} from ${s.org.name} for ${chosen}`, `/insurer/requests`),
              ...s.notices,
            ],
          }));
          toast(`Request ${id} sent. The insurer will reply with a quote.`);
          onClose();
        }}
      >
        <Field label="Lot" className="col-span-2">
          <Select
            required
            value={chosen}
            onChange={(e) => setChosen(e.target.value)}
            className={sel}
          >
            <option value="" disabled>
              Select a lot
            </option>
            {eligible.map((l) => (
              <option key={l.id} value={l.id}>
                {l.id} · {l.mineral} · {fmtKg(l.quantityKg)}
              </option>
            ))}
          </Select>
        </Field>
        <Field label="Cover" className="col-span-2">
          <div className="grid grid-cols-3 gap-2">
            {(Object.keys(RATES) as Policy["cover"][]).map((c) => (
              <button
                key={c}
                type="button"
                onClick={() => setCover(c)}
                className={`rounded-xl border px-3 py-2.5 text-sm ${cover === c ? "border-[#1F5B3A] bg-primary-soft font-medium" : "border-gray-200"}`}
              >
                {c}
              </button>
            ))}
          </div>
        </Field>
        <Field label="Insurer">
          <Select name="insurer" required defaultValue="" className={sel}>
            <option value="" disabled>
              Select insurer
            </option>
            {state.parties
              .filter((p) => p.kind === "Insurer")
              .map((p) => (
                <option key={p.id} value={p.id}>
                  {p.name}
                </option>
              ))}
          </Select>
        </Field>
        <Field label="Duration">
          <Select name="months" defaultValue="1" className={sel}>
            <option value="1">1 month</option>
            <option value="3">3 months</option>
            <option value="6">6 months</option>
          </Select>
        </Field>
        {lot && (
          <div className="col-span-2 grid grid-cols-2 gap-4 rounded-2xl bg-page px-4 py-3 text-sm">
            <div>
              <p className="text-ink/60">Sum insured (estimated value)</p>
              <p className="font-medium">USD {fmtNum(sum)}</p>
            </div>
            <div>
              <p className="text-ink/60">Estimated premium per month</p>
              <p className="font-medium">
                USD {fmtNum(premium)} ({(RATES[cover] * 100).toFixed(1)}%)
              </p>
            </div>
          </div>
        )}
      </form>
    </Modal>
  );
}

export function acceptPolicy(policyId: string) {
  update((s) => {
    const p = s.policies.find((x) => x.id === policyId)!;
    const ins = s.parties.find((x) => x.id === p.insurerId)!;
    return {
      policies: s.policies.map((x) =>
        x.id === policyId
          ? { ...x, status: "Active" as const, from: today() }
          : x,
      ),
      events: [
        ...s.events,
        makeEvent(
          s,
          p.lotId,
          "Insured",
          ins.name,
          "Insurer",
          `${p.cover} cover ${p.id} · USD ${fmtNum(p.sumInsured)}`,
        ),
      ],
      txns: [
        {
          id: nextId(
            s.txns.filter((t) => t.direction === "out").map((t) => t.id),
            "TXN-OUT-2511-",
            3,
          ),
          direction: "out" as const,
          party: ins.name,
          ref: `Premium ${p.id} · ${p.lotId}`,
          amount: p.premium,
          currency: p.currency,
          method: "Bank Transfer",
          date: today(),
          status: "Paid" as const,
        },
        ...s.txns,
      ],
      notices: [
        makeNotice(
          s,
          "finance",
          `Policy ${p.id} is active for ${p.lotId}`,
          "/miner/insurance",
        ),
        ...s.notices,
      ],
    };
  });
}

/* ---------------------------------------------------------------- offers */

/** Deal agreed: the buyer's payment is locked in escrow and the lot is marked sold. */
export function acceptOffer(offerId: string, by: "You" | "Buyer") {
  update((s) => {
    const o = s.offers.find((x) => x.id === offerId)!;
    const req = s.requests.find((r) => r.id === o.requestId);
    const last = o.history?.[o.history.length - 1];
    const price = last?.pricePerKg ?? o.pricePerKg;
    const qty = last?.quantityKg ?? o.quantityKg;
    const amount = Math.round(price * qty);
    const buyer = req?.buyer ?? "Buyer";
    const escId = nextId(
      s.escrows.map((e) => e.id),
      "ESC-",
      4,
    );
    const events = [...s.events];
    events.push(
      makeEvent(
        { ...s, events },
        o.lotId,
        "Sold",
        buyer,
        "Buyer",
        `Offer ${o.id} accepted · ${fmtKg(qty)} at $${price}/kg`,
      ),
    );
    events.push(
      makeEvent(
        { ...s, events },
        o.lotId,
        "Escrow locked",
        buyer,
        "Buyer",
        `${o.currency} ${fmtNum(amount)} locked in escrow ${escId}`,
      ),
    );
    return {
      offers: s.offers.map((x) =>
        x.id === o.id
          ? {
              ...x,
              status: "Accepted" as const,
              pricePerKg: price,
              quantityKg: qty,
              history: [
                ...(x.history ?? []),
                {
                  by,
                  pricePerKg: price,
                  quantityKg: qty,
                  note: "Accepted",
                  date: today(),
                },
              ],
            }
          : x,
      ),
      escrows: [
        {
          id: escId,
          lotId: o.lotId,
          offerId: o.id,
          buyer,
          amount,
          currency: o.currency,
          status: "Locked" as const,
          locked: today(),
        },
        ...s.escrows,
      ],
      listings: s.listings.map((l) =>
        l.lotId === o.lotId && l.status === "Active"
          ? { ...l, status: "Sold" as const }
          : l,
      ),
      requests: s.requests.map((r) =>
        r.id === o.requestId
          ? {
              ...r,
              remainingT: Math.max(0, +(r.remainingT - qty / 1000).toFixed(2)),
            }
          : r,
      ),
      events,
      notices: [
        makeNotice(
          s,
          "payment",
          `${buyer} locked ${o.currency} ${fmtNum(amount)} in escrow for ${o.lotId}: dispatch the lot`,
          `/miner/mineral-lots/${o.lotId}`,
        ),
        ...s.notices,
      ],
    };
  });
}
