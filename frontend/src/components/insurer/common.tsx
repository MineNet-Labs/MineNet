"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useMemo } from "react";
import {
  IconAlertTriangle,
  IconArrowBackUp,
  IconBell,
  IconBuildingCommunity,
  IconChartBar,
  IconChevronDown,
  IconFileCertificate,
  IconHome,
  IconInbox,
  IconMapPin,
  IconRefresh,
} from "@tabler/icons-react";
import { MenuItem, Popover, StatusBadge, toast, type BadgeTone } from "@/components/ui";
import { confirmAction } from "@/components/ui/Confirm";
import type { NavItem } from "@/components/layout/Sidebar";
import { MobileNav } from "@/components/layout/MobileNav";
import { noticeIcon } from "@/components/noticeIcon";
import type { ClaimStatus, PolicyStatus } from "@/lib/data";
import { insurerAudience } from "@/lib/insurer";
import { resetData, update, useStore } from "@/lib/store";

export const insurerNav: NavItem[] = [
  { label: "Overview", href: "/insurer", icon: IconHome },
  { label: "Cover Requests", href: "/insurer/requests", icon: IconInbox },
  { label: "Policies", href: "/insurer/policies", icon: IconFileCertificate },
  { label: "Claims", href: "/insurer/claims", icon: IconAlertTriangle },
  { label: "Clients", href: "/insurer/clients", icon: IconBuildingCommunity },
  { label: "Risk & Exposure", href: "/insurer/risk", icon: IconMapPin },
  { label: "Reports", href: "/insurer/reports", icon: IconChartBar },
  { label: "Notifications", href: "/insurer/notifications", icon: IconBell },
];

export const policyTone: Record<PolicyStatus, BadgeTone> = { Requested: "blue", Quoted: "pending", Active: "success", Expired: "neutral", Declined: "danger" };
export const claimTone: Record<ClaimStatus, BadgeTone> = { Filed: "pending", Approved: "success", Rejected: "danger" };
export const PolicyBadge = ({ status }: { status: PolicyStatus }) => (
  <StatusBadge tone={policyTone[status]}>{status === "Requested" ? "To quote" : status === "Quoted" ? "Quote sent" : status}</StatusBadge>
);

/** The insurer using the portal, and everything that belongs to it. */
export function useInsurer() {
  const state = useStore((s) => s);
  return useMemo(() => {
    const me = state.parties.find((p) => p.id === state.insurerSessionId) ?? state.parties.find((p) => p.kind === "Insurer")!;
    const policies = state.policies.filter((p) => p.insurerId === me.id);
    const ids = new Set(policies.map((p) => p.id));
    const claims = state.claims.filter((c) => ids.has(c.policyId));
    const notices = state.notices.filter((n) => n.audience === insurerAudience(me.id));
    return { state, me, policies, claims, notices };
  }, [state]);
}

export function InsurerTopbar() {
  const router = useRouter();
  const { state, me, notices } = useInsurer();
  const unread = notices.filter((n) => !n.read).length;
  const markRead = (id: string) => update((s) => ({ notices: s.notices.map((n) => (n.id === id ? { ...n, read: true } : n)) }));

  return (
    <header className="relative z-30 flex items-center justify-between gap-3 lg:gap-6">
      <MobileNav items={insurerNav} home="/insurer" />
      <div className="min-w-0 pl-2">
        <p className="truncate font-heading text-lg font-semibold">{me.name}</p>
        <p className="truncate text-xs text-ink/60">Insurer · {me.regulator} licence {me.licence}</p>
      </div>
      <div className="flex shrink-0 items-center gap-2 lg:gap-4">
        <Popover
          align="right"
          panelClass="w-80"
          trigger={(_, toggle) => (
            <button onClick={toggle} aria-label={`Notifications${unread ? `, ${unread} unread` : ""}`} className="relative grid size-12 place-items-center rounded-full bg-white shadow-[0_2px_12px_rgba(17,24,39,0.05)]">
              <IconBell className="size-5" stroke={2} />
              {unread > 0 && <span className="absolute top-2 right-2 grid size-4 place-items-center rounded-full bg-danger text-[10px] font-semibold text-white">{unread}</span>}
            </button>
          )}
        >
          {(close) => (
            <>
              <p className="px-3 pt-2 pb-1 text-sm font-semibold">Notifications</p>
              {notices.slice(0, 5).map((n) => {
                const Icon = noticeIcon[n.kind];
                return (
                  <Link key={n.id} href={n.href} onClick={() => (markRead(n.id), close())} className="flex gap-3 rounded-xl px-3 py-2.5 hover:bg-page">
                    <span className="grid size-8 shrink-0 place-items-center rounded-full bg-accent-soft"><Icon className="size-4 text-accent" /></span>
                    <span className="flex-1"><span className={`block text-sm ${n.read ? "text-ink/70" : "font-medium"}`}>{n.text}</span><span className="block text-xs text-ink/50">{n.date}</span></span>
                  </Link>
                );
              })}
              {notices.length === 0 && <p className="px-3 py-3 text-sm text-ink/60">No notifications.</p>}
              <Link href="/insurer/notifications" onClick={close} className="mt-1 block border-t border-gray-100 px-3 pt-2.5 pb-1.5 text-center text-sm font-medium text-accent hover:underline">See all notifications</Link>
            </>
          )}
        </Popover>
        <Popover
          align="right"
          panelClass="w-72"
          trigger={(_, toggle) => (
            <button onClick={toggle} aria-label="Account menu" className="flex items-center gap-2 rounded-full bg-white py-1.5 pr-3 pl-1.5 shadow-[0_2px_12px_rgba(17,24,39,0.05)]">
              <span className="grid size-10 place-items-center rounded-full bg-[#0e7490] text-sm font-medium text-white">{me.name.split(" ").map((w) => w[0]).slice(0, 2).join("")}</span>
              <IconChevronDown className="size-5" />
            </button>
          )}
        >
          {(close) => (
            <>
              <p className="px-3 pt-2 pb-1 text-[11px] font-medium tracking-wide text-ink/50 uppercase">Demo: signed in as</p>
              {state.parties.filter((p) => p.kind === "Insurer").map((p) => (
                <MenuItem key={p.id} active={p.id === me.id} onClick={() => (close(), update(() => ({ insurerSessionId: p.id })), toast(`Now viewing as ${p.name}`, "info"))}>{p.name}</MenuItem>
              ))}
              <div className="mt-1 border-t border-gray-100 pt-1">
                <MenuItem icon={IconArrowBackUp} onClick={() => (close(), router.push("/miner"))}>Miner portal (demo)</MenuItem>
                <MenuItem
                  icon={IconRefresh}
                  onClick={async () => {
                    close();
                    if (await confirmAction({ title: "Reset demo data?", message: "All changes are replaced by the original sample data.", confirmLabel: "Reset", tone: "danger" })) {
                      resetData();
                      toast("Demo data reset", "info");
                    }
                  }}
                >
                  Reset demo data
                </MenuItem>
              </div>
            </>
          )}
        </Popover>
      </div>
    </header>
  );
}
