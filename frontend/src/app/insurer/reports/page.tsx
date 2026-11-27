"use client";

import { IconDownload, IconFileSpreadsheet } from "@tabler/icons-react";
import { Card, CardTitle, PageHeader, toast } from "@/components/ui";
import { useInsurer } from "@/components/insurer/common";
import { fmtNum } from "@/lib/data";
import { downloadCSV } from "@/lib/csv";

export default function InsurerReportsPage() {
  const { me, policies, claims } = useInsurer();
  const written = policies.filter((p) => p.status === "Active" || p.status === "Expired");
  const premiums = written.reduce((n, p) => n + p.premium, 0);
  const paid = claims.filter((c) => c.status === "Approved").reduce((n, c) => n + c.amount, 0);
  const quoted = policies.filter((p) => p.status !== "Requested").length;
  const won = written.length;

  const reports = [
    {
      title: "Policy register",
      desc: "Every policy with cover, value, premium and period.",
      run: () => downloadCSV(`${me.id}-policy-register`, policies, [["Policy", (p) => p.id], ["Lot", (p) => p.lotId], ["Cover", (p) => p.cover], ["Sum insured", (p) => p.sumInsured], ["Premium", (p) => p.premium], ["Currency", (p) => p.currency], ["From", (p) => p.from], ["To", (p) => p.to], ["Status", (p) => p.status]]),
    },
    {
      title: "Claims register",
      desc: "All claims with amounts, decisions and notes.",
      run: () => downloadCSV(`${me.id}-claims-register`, claims, [["Claim", (c) => c.id], ["Policy", (c) => c.policyId], ["Lot", (c) => c.lotId], ["Reason", (c) => c.reason], ["Amount", (c) => c.amount], ["Filed", (c) => c.filed], ["Status", (c) => c.status], ["Decided", (c) => c.decided ?? ""], ["Note", (c) => c.note ?? ""]]),
    },
    {
      title: "Premium bordereau",
      desc: "Premiums written per policy, for your finance team or reinsurer.",
      run: () => downloadCSV(`${me.id}-bordereau`, written, [["Policy", (p) => p.id], ["Insured value", (p) => p.sumInsured], ["Premium", (p) => p.premium], ["Rate %", (p) => ((p.premium / Math.max(1, p.sumInsured)) * 100).toFixed(3)], ["Period", (p) => `${p.from} – ${p.to}`]]),
    },
  ];

  return (
    <>
      <PageHeader title="Reports" subtitle="Your book of business at a glance, and registers to download." />
      <div className="grid grid-cols-1 gap-5 sm:grid-cols-2 xl:grid-cols-4">
        {[
          ["Premiums written", `USD ${fmtNum(premiums)}`],
          ["Claims paid", `USD ${fmtNum(paid)}`],
          ["Loss ratio", `${premiums ? Math.round((paid / premiums) * 100) : 0}%`],
          ["Quote acceptance", `${quoted ? Math.round((won / quoted) * 100) : 0}%`],
        ].map(([k, v]) => (
          <Card key={k} className="p-5"><p className="text-sm text-ink/70">{k}</p><p className="mt-1 font-heading text-2xl font-bold">{v}</p></Card>
        ))}
      </div>
      <Card className="p-6">
        <CardTitle icon={IconFileSpreadsheet} iconClass="text-[#1F5B3A]">Downloads</CardTitle>
        <ul className="mt-4 divide-y divide-gray-100">
          {reports.map((r) => (
            <li key={r.title} className="flex items-center justify-between gap-4 py-4">
              <span><b className="font-medium">{r.title}</b><span className="block text-sm text-ink/65">{r.desc}</span></span>
              <button onClick={() => (r.run(), toast(`${r.title} downloaded`))} className="inline-flex items-center gap-1.5 rounded-full border border-gray-200 px-4 py-2 text-sm hover:bg-page">
                <IconDownload className="size-4" /> CSV
              </button>
            </li>
          ))}
        </ul>
      </Card>
    </>
  );
}
