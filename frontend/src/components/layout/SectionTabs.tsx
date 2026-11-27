"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { useMe } from "@/lib/store";

type Group = { tabs: { label: string; href: string }[] };

/** Owner pages that live inside a sidebar section. The first tab is the section itself. */
export const SECTION_GROUPS: Group[] = [
  { tabs: [{ label: "Sites", href: "/miner/mining-sites" }, { label: "Safety Incidents", href: "/miner/incidents" }, { label: "Shift Reports", href: "/miner/site-reports" }] },
  { tabs: [{ label: "Workers", href: "/miner/workers" }, { label: "Attendance", href: "/miner/attendance" }, { label: "Payroll", href: "/miner/payroll" }, { label: "Leave", href: "/miner/leave" }, { label: "Team", href: "/miner/team" }] },
  { tabs: [{ label: "Documents", href: "/miner/documents" }, { label: "Licence & Validation", href: "/miner/licence" }] },
  { tabs: [{ label: "Payments & Escrow", href: "/miner/payments" }, { label: "Financing", href: "/miner/financing" }, { label: "Insurance", href: "/miner/insurance" }] },
];

/** Tabs over a section's list page, owner only. Site managers and HR reach these pages from their own sidebar. */
export function SectionTabs() {
  const pathname = usePathname();
  const me = useMe();
  if (me.role !== "Owner") return null;
  const group = SECTION_GROUPS.find((g) => g.tabs.some((t) => t.href === pathname));
  if (!group) return null;
  return (
    <nav className="flex flex-wrap gap-2" aria-label="Section pages">
      {group.tabs.map((t) => (
        <Link
          key={t.href}
          href={t.href}
          className={`rounded-full px-4 py-2 text-sm ${t.href === pathname ? "bg-[#1F5B3A] font-medium text-white" : "bg-white text-ink/70 hover:text-ink"}`}
        >
          {t.label}
        </Link>
      ))}
    </nav>
  );
}
