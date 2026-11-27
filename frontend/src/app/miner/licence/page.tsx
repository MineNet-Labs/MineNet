"use client";

import Link from "next/link";
import { confirmAction } from "@/components/ui/Confirm";
import { useMemo } from "react";
import {
  IconAlertTriangle,
  IconBuildingBank,
  IconCertificate,
  IconCircleCheck,
  IconClock,
  IconCopy,
  IconMapPin,
  IconRefresh,
  IconShieldCheck,
  IconShieldX,
  IconWallet,
} from "@tabler/icons-react";
import { Card, CardTitle, PageHeader, PrimaryButton, StatusBadge, toast, type BadgeTone } from "@/components/ui";
import { today, type OrgStatus } from "@/lib/data";
import { daysUntil, licenceState, orgCanAct, makeNotice, type LicenceState } from "@/lib/domain";
import { update, useStore } from "@/lib/store";

const orgTone: Record<OrgStatus, BadgeTone> = { Validated: "success", Pending: "pending", Suspended: "danger" };
const licTone: Record<LicenceState, BadgeTone> = { Valid: "success", Expiring: "pending", Expired: "danger" };

export default function LicencePage() {
  const org = useStore((s) => s.org);
  const sites = useStore((s) => s.sites);
  const state = useStore((s) => s);
  const canAct = orgCanAct(state);
  const left = daysUntil(org.validatedUntil);

  const siteRows = useMemo(
    () => [...sites].sort((a, b) => daysUntil(a.licenceExpiry) - daysUntil(b.licenceExpiry)).map((s) => ({ ...s, state: licenceState(s.licenceExpiry), left: daysUntil(s.licenceExpiry) })),
    [sites],
  );
  const counts = { Valid: 0, Expiring: 0, Expired: 0 } as Record<LicenceState, number>;
  siteRows.forEach((r) => counts[r.state]++);

  const requestRenewal = (what: string, href = "/miner/licence") => {
    update((s) => ({
      org: what === "organisation" ? { ...s.org, renewalRequested: today() } : s.org,
      notices: [makeNotice(s, "licence", `Renewal request for ${what} sent to RMB`, href), ...s.notices],
    }));
    toast(`Renewal request for ${what} sent to RMB`);
  };

  const setStatus = async (status: OrgStatus) => {
    if (!(await confirmAction({ title: `Preview as ${status}?`, message: "Demo only: in production an RMB regulator sets this status.", confirmLabel: "Change status", tone: status === "Suspended" ? "danger" : "primary" }))) return;
    update((s) => ({
      org: { ...s.org, status, suspensionReason: status === "Suspended" ? "Licence under review by RMB" : undefined },
      notices: [makeNotice(s, "licence", `Your organisation status changed to ${status}`, "/miner/licence"), ...s.notices],
    }));
    toast(`Status set to ${status} (demo)`, "info");
  };

  const StatusIcon = org.status === "Validated" ? IconShieldCheck : org.status === "Pending" ? IconClock : IconShieldX;

  return (
    <>
      <PageHeader
        title="Licence & Validation"
        subtitle="Your RMB validation controls what you can do on MineNet. Lots can only be registered while it is valid."
        actions={
          <PrimaryButton icon={IconRefresh} onClick={() => requestRenewal("organisation")} disabled={!!org.renewalRequested} className="disabled:opacity-50">
            {org.renewalRequested ? `Renewal requested ${org.renewalRequested}` : "Request renewal"}
          </PrimaryButton>
        }
      />

      <div className="grid items-start gap-5 xl:grid-cols-[1.3fr_1fr]">
        <Card className="p-5">
          <div className="flex items-start justify-between gap-4">
            <CardTitle icon={IconBuildingBank} iconClass="text-[#1F5B3A]">Organisation validation</CardTitle>
            <StatusBadge tone={orgTone[org.status]}>{org.status}</StatusBadge>
          </div>

          <div
            className={`mt-5 flex items-center gap-4 rounded-2xl px-5 py-4 ${
              org.status === "Validated" ? "bg-success-soft" : org.status === "Pending" ? "bg-accent-soft" : "bg-danger-soft"
            }`}
          >
            <StatusIcon className={`size-10 shrink-0 ${org.status === "Validated" ? "text-[#1F5B3A]" : org.status === "Pending" ? "text-accent" : "text-danger"}`} />
            <div>
              {org.status === "Validated" && (
                <>
                  <p className="font-heading text-xl font-bold">Validated until {org.validatedUntil}</p>
                  <p className="text-sm text-ink/75">{left >= 0 ? `${left} days left` : "Expired"} · you can register, list and dispatch lots.</p>
                </>
              )}
              {org.status === "Pending" && (
                <>
                  <p className="font-heading text-xl font-bold">Validation pending</p>
                  <p className="text-sm text-ink/75">An RMB officer is reviewing your documents. Lot registration is blocked until then.</p>
                </>
              )}
              {org.status === "Suspended" && (
                <>
                  <p className="font-heading text-xl font-bold">Suspended</p>
                  <p className="text-sm text-ink/75">{org.suspensionReason ?? "Suspended by RMB"}. You can&apos;t sign new events and lots in progress are frozen.</p>
                </>
              )}
            </div>
          </div>

          <dl className="mt-6 grid grid-cols-2 gap-x-6 gap-y-4 text-sm">
            {[
              ["Organisation", org.name],
              ["Type", org.kind],
              ["Regulator", org.regulator],
              ["Mining licence", org.licence],
              ["Licence issued", org.licenceIssued],
              ["Licence expires", org.licenceExpiry],
              ["Validated by", org.validatedBy],
              ["Validated on", org.validatedOn],
              ["RDB registration", org.rdbNumber],
              ["Tax ID", org.tin],
            ].map(([k, v]) => (
              <div key={k}>
                <dt className="text-ink/60">{k}</dt>
                <dd className="font-medium">{v}</dd>
              </div>
            ))}
          </dl>
        </Card>

        <div className="space-y-5">
          <Card className="p-5">
            <CardTitle icon={IconWallet} iconClass="text-[#B5551A]">Signing wallet</CardTitle>
            <p className="mt-3 text-sm text-ink/70">Every event you sign on a lot passport comes from this wallet.</p>
            <div className="mt-4 flex items-center gap-2 rounded-xl bg-page px-4 py-3">
              <code className="flex-1 truncate text-[13px]">{org.wallet}</code>
              <button
                aria-label="Copy wallet address"
                onClick={() => {
                  navigator.clipboard?.writeText(org.wallet);
                  toast("Wallet address copied", "info");
                }}
                className="grid size-8 place-items-center rounded-full hover:bg-white"
              >
                <IconCopy className="size-4" />
              </button>
            </div>
            <p className="mt-3 flex items-center gap-2 text-sm">
              {canAct ? <IconCircleCheck className="size-4 text-[#1F5B3A]" /> : <IconAlertTriangle className="size-4 text-danger" />}
              {canAct ? "Allowed to sign events" : "Signing is blocked"}
            </p>
          </Card>

          <Card className="p-5">
            <CardTitle icon={IconCertificate}>What your status allows</CardTitle>
            <ul className="mt-4 space-y-3 text-sm">
              {[
                ["Register new lots", canAct],
                ["List lots on the marketplace", canAct],
                ["Dispatch lots and confirm handovers", canAct],
                ["Request financing and insurance", canAct],
                ["View your data and documents", true],
              ].map(([label, ok]) => (
                <li key={label as string} className="flex items-center gap-3">
                  {ok ? <IconCircleCheck className="size-5 text-[#1F5B3A]" /> : <IconShieldX className="size-5 text-danger" />}
                  {label}
                </li>
              ))}
            </ul>
            <div className="mt-5 border-t border-gray-100 pt-4">
              <p className="text-xs text-ink/60">Demo only: preview how the portal behaves in each status (an RMB regulator sets this in production).</p>
              <div className="mt-2 flex gap-2">
                {(["Validated", "Pending", "Suspended"] as OrgStatus[]).map((st) => (
                  <button
                    key={st}
                    onClick={() => setStatus(st)}
                    className={`rounded-full border px-3 py-1.5 text-xs ${org.status === st ? "border-[#1F5B3A] bg-primary-soft font-medium" : "border-gray-200 hover:bg-page"}`}
                  >
                    {st}
                  </button>
                ))}
              </div>
            </div>
          </Card>
        </div>
      </div>

      <Card className="pt-5">
        <div className="flex flex-wrap items-center justify-between gap-3 px-5">
          <CardTitle icon={IconMapPin} iconClass="text-[#1F5B3A]">Site licences</CardTitle>
          <div className="flex gap-2 text-sm">
            <StatusBadge tone="success">{counts.Valid} valid</StatusBadge>
            <StatusBadge tone="pending">{counts.Expiring} expiring</StatusBadge>
            <StatusBadge tone="danger">{counts.Expired} expired</StatusBadge>
          </div>
        </div>
        <div className="mt-5 overflow-x-auto px-2 pb-4">
          <table className="w-full text-left text-sm">
            <thead className="bg-head">
              <tr>{["Site", "District", "Licence", "Expires", "Status", "Lot registration", ""].map((h) => <th key={h} className="px-3 py-3 text-[13px] font-medium">{h}</th>)}</tr>
            </thead>
            <tbody>
              {siteRows.map((s) => (
                <tr key={s.id} className="border-b border-gray-100 last:border-0">
                  <td className="px-3 py-3"><Link href={`/miner/mining-sites/${s.id}`} className="font-medium hover:text-[#1F5B3A] hover:underline">{s.name}</Link></td>
                  <td className="px-3">{s.district}</td>
                  <td className="px-3">{s.licence}</td>
                  <td className="px-3">{s.licenceExpiry} <span className="text-ink/60">({s.left >= 0 ? `${s.left} days` : `${-s.left} days ago`})</span></td>
                  <td className="px-3"><StatusBadge tone={licTone[s.state]}>{s.state}</StatusBadge></td>
                  <td className="px-3">{s.state !== "Expired" && s.status === "Active" && canAct ? "Allowed" : <span className="text-danger">Blocked</span>}</td>
                  <td className="px-3 text-right">
                    {s.state !== "Valid" && (
                      <button onClick={() => requestRenewal(`${s.name} (${s.licence})`)} className="font-medium text-accent hover:underline">
                        Request renewal
                      </button>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </Card>
    </>
  );
}
