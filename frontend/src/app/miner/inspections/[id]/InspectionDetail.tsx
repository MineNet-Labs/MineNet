"use client";

import Link from "next/link";
import { useParams } from "next/navigation";
import { IconCircleCheck, IconCircleDashed, IconDownload, IconFlask, IconShieldCheck } from "@tabler/icons-react";
import { Card, CardTitle, StatusBadge, statusTone, toast } from "@/components/ui";
import { DetailHeader, Facts, NotFound } from "@/components/DetailShell";
import { simHash, type InspectionStatus } from "@/lib/data";
import { makeEvent, makeNotice } from "@/lib/domain";
import { siteName, update, useStore } from "@/lib/store";
import { downloadFile } from "@/lib/csv";

const STEPS: InspectionStatus[] = ["Pending", "Scheduled", "In Progress", "Completed"];

export function InspectionDetail() {
  const { id } = useParams<{ id: string }>();
  const state = useStore((s) => s);
  const ins = state.inspections.find((i) => i.id === id);
  if (!ins) return <NotFound what="Inspection" id={id} back="/miner/inspections" backLabel="Inspections" />;

  const lot = state.lots.find((l) => l.id === ins.lotId);
  const r = ins.result;
  const stepIdx = ins.status === "Rejected" ? 3 : STEPS.indexOf(ins.status);

  const report = () => {
    downloadFile(
      `${ins.id}-report.txt`,
      [
        "MINENET INSPECTION REPORT",
        "",
        `Inspection: ${ins.id}`,
        `Type: ${ins.type}`,
        `Lot: ${ins.lotId} (${ins.mineral})`,
        `Site: ${siteName(state, ins.siteId)} · ${ins.shaft}`,
        `Inspector: ${ins.inspector ?? "Not assigned"}`,
        `Status: ${ins.status}`,
        r ? `Sample: ${r.sampleId}\nMethod: ${r.method}\nMeasured grade: ${r.grade}%\nDeclared grade: ${lot?.grade ?? "?"}%\nFindings: ${r.findings}\nDate: ${r.date}` : "Results: not available yet",
        "",
        `Attestation hash: ${simHash(ins.id)} (simulated)`,
      ].join("\n"),
    );
    toast(`Report ${ins.id} downloaded`);
  };

  // Demo: stands in for the inspector's portal moving the inspection forward.
  const advance = () => {
    update((s) => {
      const next: InspectionStatus = ins.status === "Pending" ? "Scheduled" : ins.status === "Scheduled" ? "In Progress" : "Completed";
      const l = s.lots.find((x) => x.id === ins.lotId);
      const done = next === "Completed";
      const result = done ? { grade: l?.grade ?? 0, sampleId: `SMP-${ins.id.slice(-4)}`, method: "XRF + wet assay", findings: "Grade matches declaration.", date: new Date().toLocaleDateString("en-US", { month: "short", day: "2-digit", year: "numeric" }) } : undefined;
      return {
        inspections: s.inspections.map((x) => (x.id === ins.id ? { ...x, status: next, inspector: x.inspector ?? "Diane Uwamahoro", result: result ?? x.result } : x)),
        lots: done ? s.lots.map((x) => (x.id === ins.lotId ? { ...x, status: "Verified" as const } : x)) : s.lots,
        events: done ? [...s.events, makeEvent(s, ins.lotId, "Inspected", "Diane Uwamahoro", "Inspector", `${ins.type} · grade ${result!.grade}% attested`)] : s.events,
        notices: [makeNotice(s, "inspection", `Inspection ${ins.id} is now ${next.toLowerCase()}${done ? `: ${ins.lotId} verified` : ""}`, `/miner/inspections/${ins.id}`), ...s.notices],
      };
    });
    toast("Inspection moved forward (demo)", "info");
  };

  return (
    <>
      <DetailHeader
        back="/miner/inspections"
        backLabel="Inspections"
        title={ins.id}
        badge={<StatusBadge tone={statusTone(ins.status)}>{ins.status}</StatusBadge>}
        subtitle={`${ins.type} · submitted ${ins.submitted}`}
        actions={
          <button onClick={report} className="inline-flex items-center gap-2 rounded-2xl border border-gray-200 bg-white px-4 py-3 text-[15px] hover:bg-page">
            <IconDownload className="size-5" /> Report
          </button>
        }
      />

      <Card className="p-5">
        <ol className="grid grid-cols-4 gap-2">
          {STEPS.map((s, i) => {
            const label = i === 3 && ins.status === "Rejected" ? "Rejected" : s;
            const on = i <= stepIdx;
            return (
              <li key={s} className="flex flex-col items-center gap-2 text-sm">
                <span className={`grid size-9 place-items-center rounded-full ${on ? (label === "Rejected" ? "bg-danger text-white" : "bg-[#1F5B3A] text-white") : "bg-page text-ink/40"}`}>
                  {on ? <IconCircleCheck className="size-5" /> : <IconCircleDashed className="size-5" />}
                </span>
                <span className={on ? "font-medium" : "text-ink/50"}>{label}</span>
              </li>
            );
          })}
        </ol>
        {!["Completed", "Rejected"].includes(ins.status) && (
          <p className="mt-4 text-center text-xs text-ink/60">
            The inspector updates this from their portal.{" "}
            <button onClick={advance} className="text-accent underline">Demo: move to next step</button>
          </p>
        )}
      </Card>

      <div className="grid items-start gap-5 xl:grid-cols-2">
        <Card className="p-5">
          <CardTitle icon={IconShieldCheck} iconClass="text-[#1F5B3A]">Request</CardTitle>
          <div className="mt-5">
            <Facts
              cols={2}
              items={[
                ["Lot", <Link key="l" href={`/miner/mineral-lots/${ins.lotId}`} className="text-accent hover:underline">{ins.lotId}</Link>],
                ["Mineral", ins.mineral],
                ["Site", <Link key="s" href={`/miner/mining-sites/${ins.siteId}`} className="hover:underline">{siteName(state, ins.siteId)}</Link>],
                ["Shaft", ins.shaft],
                ["Type", ins.type],
                ["Inspector", ins.inspector ?? "Not assigned yet"],
                ["Declared grade", lot ? `${lot.grade}%` : "—"],
                ["Submitted", ins.submitted],
              ]}
            />
          </div>
        </Card>

        <Card className="p-5">
          <CardTitle icon={IconFlask} iconClass="text-[#2563eb]">Results</CardTitle>
          {r ? (
            <>
              <div className="mt-5">
                <Facts
                  cols={2}
                  items={[
                    ["Measured grade", `${r.grade}%`],
                    ["Difference", lot ? `${(r.grade - lot.grade).toFixed(1)} pts` : "—"],
                    ["Sample", r.sampleId],
                    ["Method", r.method],
                    ["Date", r.date],
                    ["Attestation", <code key="h" className="text-xs">{simHash(ins.id).slice(0, 14)}…</code>],
                  ]}
                />
              </div>
              <p className={`mt-5 rounded-xl px-4 py-3 text-sm ${ins.status === "Rejected" ? "bg-danger-soft text-danger" : "bg-success-soft text-[#1F5B3A]"}`}>{r.findings}</p>
            </>
          ) : (
            <p className="mt-5 text-sm text-ink/70">Results appear here once the inspector completes the inspection.</p>
          )}
        </Card>
      </div>
    </>
  );
}
