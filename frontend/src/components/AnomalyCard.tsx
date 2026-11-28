"use client";

import Link from "next/link";
import { useMemo } from "react";
import { IconCircleCheck, IconSparkles } from "@tabler/icons-react";
import { Card, CardTitle } from "@/components/ui";
import { anomalies } from "@/lib/domain";
import { useStore } from "@/lib/store";

/** AI anomaly flags across all lots (rule-based until the model service exists). */
export function AnomalyCard({ limit = 5 }: { limit?: number }) {
  const state = useStore((s) => s);
  const flags = useMemo(() => anomalies(state), [state]);
  return (
    <Card className="p-5">
      <CardTitle icon={IconSparkles} iconClass="text-violet">Anomaly alerts</CardTitle>
      <p className="mt-1 text-xs text-ink/60">Grades, quantities and licences that don&apos;t fit your history. Review before an inspector or buyer does.</p>
      {flags.length === 0 ? (
        <p className="mt-4 flex items-center gap-2 text-sm text-[#1F5B3A]"><IconCircleCheck className="size-5" /> Nothing unusual found</p>
      ) : (
        <ul className="mt-4 space-y-2 text-sm">
          {flags.slice(0, limit).map((f) => (
            <li key={f.lotId + f.text}>
              <Link href={`/miner/mineral-lots/${f.lotId}`} className={`block rounded-xl px-3 py-2 hover:opacity-80 ${f.severity === "high" ? "bg-danger-soft" : "bg-accent-soft"}`}>
                <b className={`font-semibold ${f.severity === "high" ? "text-danger" : "text-[#9a4a12]"}`}>{f.lotId}</b> · {f.text}
              </Link>
            </li>
          ))}
          {flags.length > limit && <li className="text-xs text-ink/60">+{flags.length - limit} more on the lot pages</li>}
        </ul>
      )}
    </Card>
  );
}
