"use client";

import Link from "next/link";
import { IconAlertTriangle } from "@tabler/icons-react";
import { useStore } from "@/lib/store";

/** Portal-wide warning while the organisation can't sign events. */
export function LicenceBanner() {
  const org = useStore((s) => s.org);
  if (org.status === "Validated") return null;
  const suspended = org.status === "Suspended";
  return (
    <div role="alert" className={`flex flex-wrap items-center gap-3 rounded-2xl px-5 py-3 text-sm ${suspended ? "bg-danger-soft text-danger" : "bg-accent-soft text-[#9a4a12]"}`}>
      <IconAlertTriangle className="size-5 shrink-0" />
      <span className="flex-1">
        {suspended
          ? `Your organisation is suspended by RMB${org.suspensionReason ? ` (${org.suspensionReason})` : ""}. You can't register, list or dispatch lots, and lots in progress are frozen.`
          : "Your RMB validation is pending. You can view your data, but lot registration, listing and dispatch are blocked until it is validated."}
      </span>
      <Link href="/miner/licence" className="font-medium underline">Licence & Validation</Link>
    </div>
  );
}
