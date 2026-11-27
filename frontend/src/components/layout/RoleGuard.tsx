"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { IconLock } from "@tabler/icons-react";
import { canSee, sectionOf } from "@/lib/roles";
import { useMe } from "@/lib/store";

/** Shows a "no access" card instead of pages the member's role doesn't include. */
export function RoleGuard({ children }: { children: React.ReactNode }) {
  const me = useMe();
  const pathname = usePathname();
  if (canSee(me.role, sectionOf(pathname))) return <>{children}</>;
  return (
    <div className="rounded-[22px] bg-white p-10 text-center">
      <IconLock className="mx-auto size-10 text-ink/40" />
      <h2 className="mt-3">No access</h2>
      <p className="mt-2 text-ink/70">As {me.role.toLowerCase()} you don&apos;t have access to this page. Ask the company owner if you need it.</p>
      <Link href="/miner" className="mt-5 inline-block rounded-full bg-[#1F5B3A] px-6 py-3 font-medium text-white hover:bg-primary">Back to Overview</Link>
    </div>
  );
}
