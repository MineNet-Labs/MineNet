"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useState } from "react";
import { IconArrowBackUp, IconBell, IconChevronDown, IconRefresh, IconSearch, IconUmbrella } from "@tabler/icons-react";
import { MenuItem, Popover, toast } from "@/components/ui";
import { confirmAction } from "@/components/ui/Confirm";
import type { NavItem } from "@/components/layout/Sidebar";
import { MobileNav } from "@/components/layout/MobileNav";
import { noticeIcon } from "@/components/noticeIcon";
import { resetData, update, useStore } from "@/lib/store";

/**
 * Top bar for the partner portals (supply chain, and later the other roles):
 * search, notifications for that portal's audience, and the account menu.
 */
export function PortalTopbar({
  nav,
  home,
  name,
  role,
  audience,
  searchHint = "Search (e.g. Lot ID, Site…)",
  onSearch,
}: {
  nav: NavItem[];
  home: string;
  name: string;
  role: string;
  audience: string;
  searchHint?: string;
  onSearch: (q: string) => string;
}) {
  const router = useRouter();
  const [q, setQ] = useState("");
  const all = useStore((s) => s.notices);
  const notices = all.filter((n) => n.audience === audience);
  const unread = notices.filter((n) => !n.read).length;
  const markRead = (id: string) => update((s) => ({ notices: s.notices.map((n) => (n.id === id ? { ...n, read: true } : n)) }));
  const initials = name.split(" ").map((w) => w[0]).slice(0, 2).join("");

  return (
    <header className="relative z-30 flex items-center justify-between gap-3 lg:gap-6">
      <MobileNav items={nav} home={home} />
      <form
        className="flex h-12 min-w-0 flex-1 items-center gap-3 rounded-2xl bg-white px-4 shadow-[0_2px_12px_rgba(17,24,39,0.05)] lg:max-w-[660px]"
        onSubmit={(e) => {
          e.preventDefault();
          if (q.trim()) router.push(onSearch(q.trim()));
        }}
      >
        <IconSearch className="size-5 shrink-0" />
        <input value={q} onChange={(e) => setQ(e.target.value)} placeholder={searchHint} aria-label="Search" className="min-w-0 flex-1 bg-transparent text-[15px] outline-none placeholder:text-gray-400" />
      </form>
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
              <Link href={`${home}/notifications`} onClick={close} className="mt-1 block border-t border-gray-100 px-3 pt-2.5 pb-1.5 text-center text-sm font-medium text-accent hover:underline">See all notifications</Link>
            </>
          )}
        </Popover>
        <Popover
          align="right"
          panelClass="w-72"
          trigger={(_, toggle) => (
            <button onClick={toggle} aria-label="Account menu" className="flex items-center gap-2 rounded-full bg-white py-1.5 pr-3 pl-1.5 shadow-[0_2px_12px_rgba(17,24,39,0.05)]">
              <span className="grid size-10 place-items-center rounded-full bg-[#F08A2C] text-sm font-medium text-white">{initials}</span>
              <IconChevronDown className="size-5" />
            </button>
          )}
        >
          {(close) => (
            <>
              <div className="px-2 pt-2 pb-2">
                <p className="font-medium">{name}</p>
                <p className="text-xs text-ink/60">{role}</p>
              </div>
              <div className="border-t border-gray-100 pt-1">
                <p className="px-3 pt-1 pb-1 text-[11px] font-medium tracking-wide text-ink/50 uppercase">Demo: other portals</p>
                <MenuItem icon={IconArrowBackUp} onClick={() => (close(), router.push("/miner"))}>Miner portal</MenuItem>
                <MenuItem icon={IconUmbrella} onClick={() => (close(), router.push("/insurer"))}>Insurer portal</MenuItem>
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
