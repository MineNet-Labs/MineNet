"use client";

import { openForm } from "@/components/FormHost";

import { insurerNotice } from "@/lib/insurer";

import Link from "next/link";

import { useState } from "react";
import { IconAlertTriangle, IconBuildingWarehouse, IconPlus, IconTruck, IconUmbrella } from "@tabler/icons-react";
import { CancelButton, Card, CardTitle, Empty, Field, Modal, PageHeader, PrimaryButton, StatCard, StatusBadge, SubmitButton, formValues, inputClass, toast, type BadgeTone } from "@/components/ui";
import { withConfirm, confirmAction } from "@/components/ui/Confirm";
import { acceptPolicy } from "@/components/chain-forms";
import { fmtNum, today, type ClaimStatus, type Policy, type PolicyStatus } from "@/lib/data";
import { makeNotice, orgCanAct } from "@/lib/domain";
import { getState, nextId, update, useStore } from "@/lib/store";

const tone: Record<PolicyStatus, BadgeTone> = { Requested: "blue", Quoted: "pending", Active: "success", Expired: "neutral", Declined: "danger" };
const claimTone: Record<ClaimStatus, BadgeTone> = { Filed: "pending", Approved: "success", Rejected: "danger" };

export default function InsurancePage() {
  const state = useStore((s) => s);
  const { policies, parties, claims } = state;
  const [claimFor, setClaimFor] = useState<Policy | null>(null);
  const active = policies.filter((p) => p.status === "Active");
  const covered = active.reduce((n, p) => n + p.sumInsured, 0);
  const insurer = (id: string) => parties.find((x) => x.id === id)?.name ?? id;

  return (
    <>
      <PageHeader
        title="Insurance"
        subtitle="Cover your lots while they are stored or moving. You request cover, the insurer quotes, you accept, and claims go straight to them."
        actions={<PrimaryButton icon={IconPlus} disabled={!orgCanAct(state)} onClick={() => openForm("insurance")} className="disabled:opacity-50">Get cover</PrimaryButton>}
      />

      <div className="grid grid-cols-1 gap-5 sm:grid-cols-2 xl:grid-cols-4">
        <StatCard deltaDir="none" icon={IconUmbrella} tone="green" label="Value covered (USD)" value={fmtNum(covered)} delta={`${active.length}`} note="active policies" spark={[3, 4, 4, 5, 5, 6, 6]} />
        <StatCard deltaDir="none" icon={IconTruck} tone="orange" label="Transit cover" value={active.filter((p) => p.cover !== "Storage").length} delta="" note="policies" spark={[1, 2, 2, 1, 2, 2, 1]} />
        <StatCard deltaDir="none" icon={IconBuildingWarehouse} tone="violet" label="Storage cover" value={active.filter((p) => p.cover !== "Transit").length} delta="" note="policies" spark={[1, 1, 2, 1, 1, 2, 1]} />
        <StatCard deltaDir="none" icon={IconAlertTriangle} tone="gray" label="Open claims" value={claims.filter((c) => c.status === "Filed").length} delta="" note="with insurers" spark={[1, 1, 1, 2, 2, 2, 2]} />
      </div>

      <Card className="pt-5">
        <div className="px-5"><CardTitle icon={IconUmbrella} iconClass="text-[#0e7490]">Policies</CardTitle></div>
        <div className="mt-5 overflow-x-auto px-2 pb-4">
          {policies.length === 0 ? (
            <Empty>No policies yet.</Empty>
          ) : (
            <table className="w-full text-left text-sm">
              <thead className="bg-head">
                <tr>{["Policy", "Lot", "Insurer", "Cover", "Sum insured", "Premium", "Period", "Status", ""].map((h) => <th key={h} className="px-3 py-3 text-[13px] font-medium">{h}</th>)}</tr>
              </thead>
              <tbody>
                {policies.map((p) => (
                  <tr key={p.id} className="border-b border-gray-100 last:border-0">
                    <td className="px-3 py-3 font-medium">{p.id}</td>
                    <td className="px-3"><Link href={`/miner/mineral-lots/${p.lotId}`} className="hover:underline">{p.lotId}</Link></td>
                    <td className="px-3">{insurer(p.insurerId)}</td>
                    <td className="px-3">{p.cover}</td>
                    <td className="px-3">{p.currency} {fmtNum(p.sumInsured)}</td>
                    <td className="px-3">{p.status === "Requested" ? <span className="text-ink/50">Awaiting quote</span> : `${p.currency} ${fmtNum(p.premium)}`}</td>
                    <td className="px-3">{p.from} – {p.to}</td>
                    <td className="px-3"><StatusBadge tone={tone[p.status]}>{p.status === "Requested" ? "Waiting for insurer" : p.status}</StatusBadge></td>
                    <td className="px-3 text-right">
                      {p.status === "Quoted" && (
                        <span className="flex justify-end gap-3 text-xs">
                          <button
                            onClick={withConfirm({ title: "Accept and pay premium?", message: `You pay ${p.currency} ${fmtNum(p.premium)} to ${insurer(p.insurerId)} for ${p.cover.toLowerCase()} cover on ${p.lotId}.`, confirmLabel: "Accept and pay" }, () => (acceptPolicy(p.id), toast(`Policy ${p.id} accepted and premium paid`)))}
                            className="rounded-full bg-[#1F5B3A] px-3 py-1.5 font-medium text-white"
                          >
                            Accept & pay
                          </button>
                          <button
                            onClick={withConfirm({ title: "Decline quote?", message: `The quote ${p.id} from ${insurer(p.insurerId)} will be declined.`, confirmLabel: "Decline", tone: "danger" }, () => {
                              update((s) => ({ policies: s.policies.map((x) => (x.id === p.id ? { ...x, status: "Declined" as const } : x)) }));
                              toast(`Quote ${p.id} declined`, "info");
                            })}
                            className="text-ink/60 underline"
                          >
                            Decline
                          </button>
                        </span>
                      )}
                      {p.status === "Active" && (
                        <button onClick={() => setClaimFor(p)} className="text-xs font-medium text-accent hover:underline">File a claim</button>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </div>
      </Card>

      <Card className="pt-5">
        <div className="px-5"><CardTitle icon={IconAlertTriangle} iconClass="text-danger">Claims</CardTitle></div>
        <div className="mt-5 overflow-x-auto px-2 pb-4">
          {claims.length === 0 ? (
            <Empty>No claims filed.</Empty>
          ) : (
            <table className="w-full text-left text-sm">
              <thead className="bg-head">
                <tr>{["Claim", "Policy", "Lot", "Reason", "Amount", "Filed", "Status"].map((h) => <th key={h} className="px-3 py-3 text-[13px] font-medium">{h}</th>)}</tr>
              </thead>
              <tbody>
                {claims.map((c) => (
                  <tr key={c.id} className="border-b border-gray-100 last:border-0">
                    <td className="px-3 py-3 font-medium">{c.id}</td>
                    <td className="px-3">{c.policyId}</td>
                    <td className="px-3"><Link href={`/miner/mineral-lots/${c.lotId}`} className="hover:underline">{c.lotId}</Link></td>
                    <td className="max-w-[320px] truncate px-3" title={c.reason}>{c.reason}</td>
                    <td className="px-3">{c.currency} {fmtNum(c.amount)}</td>
                    <td className="px-3">{c.filed}</td>
                    <td className="px-3"><StatusBadge tone={claimTone[c.status]}>{c.status}</StatusBadge>{c.note && <span className="block text-xs text-ink/60">{c.note}</span>}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </div>
      </Card>

      {claimFor && (
        <Modal
          title={`File a claim · ${claimFor.id}`}
          subtitle={`${claimFor.cover} cover on ${claimFor.lotId} with ${insurer(claimFor.insurerId)} · up to ${claimFor.currency} ${fmtNum(claimFor.sumInsured)}`}
          onClose={() => setClaimFor(null)}
          footer={<><CancelButton onClick={() => setClaimFor(null)} /><SubmitButton form="claim-form">File claim</SubmitButton></>}
        >
          <form
            id="claim-form"
            className="grid gap-4"
            onSubmit={async (e) => {
              const v = formValues(e);
              const p = claimFor;
              if (!(await confirmAction({ title: "File this claim?", message: `${p.currency} ${fmtNum(Number(v.amount))} is claimed from ${insurer(p.insurerId)}. They review it and decide.`, confirmLabel: "File claim" }))) return;
              const id = nextId(getState().claims.map((c) => c.id), "CLM-", 4);
              update((s) => ({
                claims: [{ id, policyId: p.id, lotId: p.lotId, reason: v.reason, amount: Number(v.amount), currency: p.currency, status: "Filed" as const, filed: today() }, ...s.claims],
                notices: [makeNotice(s, "finance", `Claim ${id} filed with ${insurer(p.insurerId)}`, "/miner/insurance"), insurerNotice(s, p.insurerId, "alert", `New claim ${id} from ${s.org.name} on ${p.lotId}: ${p.currency} ${fmtNum(Number(v.amount))}`, `/insurer/claims/${id}`), ...s.notices],
              }));
              toast(`Claim ${id} filed`);
              setClaimFor(null);
            }}
          >
            <Field label="What happened"><textarea name="reason" required rows={3} className={`${inputClass} h-auto py-3`} placeholder="e.g. 40 kg damaged by water in storage" /></Field>
            <Field label={`Amount claimed (${claimFor.currency})`}><input name="amount" type="number" min={1} max={claimFor.sumInsured} required className={inputClass} /></Field>
          </form>
        </Modal>
      )}
    </>
  );
}
