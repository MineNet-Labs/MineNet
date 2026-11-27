"use client";

import { IconBuildingCommunity, IconCircleCheck } from "@tabler/icons-react";
import { Card, CardTitle, PageHeader, StatusBadge } from "@/components/ui";
import { useInsurer } from "@/components/insurer/common";
import { fmtNum } from "@/lib/data";

/** Companies you cover, with their validation status and loss history. */
export default function InsurerClientsPage() {
  const { state, policies, claims } = useInsurer();
  const org = state.org;
  const active = policies.filter((p) => p.status === "Active");
  const premiums = policies.filter((p) => p.status === "Active" || p.status === "Expired").reduce((n, p) => n + p.premium, 0);
  const paid = claims.filter((c) => c.status === "Approved").reduce((n, c) => n + c.amount, 0);
  const serious = state.incidents.filter((i) => i.severity !== "Low").length;

  return (
    <>
      <PageHeader title="Clients" subtitle="Companies that requested or hold cover with you. Only regulator-validated companies can request cover." />
      <Card className="p-6">
        <div className="flex flex-wrap items-start justify-between gap-4">
          <CardTitle icon={IconBuildingCommunity} iconClass="text-[#1F5B3A]">{org.name}</CardTitle>
          <StatusBadge tone={org.status === "Validated" ? "success" : org.status === "Pending" ? "pending" : "danger"} icon={org.status === "Validated" ? IconCircleCheck : undefined}>
            {org.status === "Validated" ? `RMB validated until ${org.validatedUntil}` : org.status}
          </StatusBadge>
        </div>
        <dl className="mt-5 grid grid-cols-2 gap-x-6 gap-y-4 text-sm md:grid-cols-4">
          {[
            ["Type", org.kind],
            ["Licence", org.licence],
            ["RDB registration", org.rdbNumber],
            ["Contact", `${org.contact} · ${org.phone}`],
            ["Policies", `${policies.length} (${active.length} active)`],
            ["Exposure", `USD ${fmtNum(active.reduce((n, p) => n + p.sumInsured, 0))}`],
            ["Premiums", `USD ${fmtNum(premiums)}`],
            ["Claims paid", `USD ${fmtNum(paid)} (${premiums ? Math.round((paid / premiums) * 100) : 0}% loss ratio)`],
            ["Sites", `${state.sites.length} (${state.sites.filter((s) => s.status === "Active").length} active)`],
            ["Serious incidents", `${serious} reported`],
            ["Lots verified", `${state.lots.filter((l) => l.status === "Verified").length} of ${state.lots.length}`],
            ["Address", org.address],
          ].map(([k, v]) => (
            <div key={k}><dt className="text-ink/60">{k}</dt><dd className="font-medium">{v}</dd></div>
          ))}
        </dl>
      </Card>
      <p className="pl-2 text-xs text-ink/55">More clients appear here as other validated companies request cover from you.</p>
    </>
  );
}
