"use client";

import { isMinerNotice } from "@/lib/insurer";

import Link from "next/link";
import { confirmAction } from "@/components/ui/Confirm";
import { usePathname, useRouter } from "next/navigation";
import { useMemo, useState } from "react";
import {
  IconBell,
  IconBox,
  IconClipboardList,
  IconFileText,
  IconPick,
  IconShieldCheck,
  IconWallet,
  IconBuildingStore,
  IconChevronDown,
  IconHeadphones,
  IconLogout,
  IconMapPin,
  IconRefresh,
  IconSearch,
  IconUmbrella,
  IconUser,
  IconUsers,
} from "@tabler/icons-react";
import { MenuItem, Popover, toast } from "@/components/ui";
import { resetData, update, useMe, useStore } from "@/lib/store";
import { noticeIcon } from "@/components/noticeIcon";
import { MobileNav } from "./MobileNav";

const placeholders: Record<string, string> = {
  "/miner/inspections": "Search requests, lots, or inspectors...",
  "/miner/marketplace": "Search minerals, buyers or locations...",
  "/miner/payments": "Search transactions, buyers, or workers...",
};


export function Topbar() {
  const pathname = usePathname();
  const router = useRouter();
  const placeholder = placeholders[pathname] ?? "Search (e.g. Lot ID, Site...)";
  const [q, setQ] = useState("");
  const allNotices = useStore((s) => s.notices);
  const notices = useMemo(() => allNotices.filter(isMinerNotice), [allNotices]);
  const orgName = useStore((s) => s.org.name);
  const members = useStore((s) => s.members);
  const me = useMe();
  const unread = notices.filter((n) => !n.read).length;
  const markRead = (id: string) => update((s) => ({ notices: s.notices.map((n) => (n.id === id ? { ...n, read: true } : n)) }));

  const data = useStore((s) => s);

  // Searches everything in the portal, so the box works on every page.
  const results = useMemo(() => {
    const t = q.trim().toLowerCase();
    if (t.length < 2) return [];
    const has = (...v: (string | undefined)[]) => v.some((x) => x?.toLowerCase().includes(t));
    const site = (id: string) => data.sites.find((x) => x.id === id)?.name ?? id;
    return [
      ...data.lots.filter((l) => has(l.id, l.mineral)).map((l) => ({ icon: IconBox, label: l.id, sub: `Lot · ${l.mineral} · ${l.status}`, href: `/miner/mineral-lots/${l.id}` })),
      ...data.sites.filter((s) => has(s.name, s.district, s.licence, s.manager)).map((s) => ({ icon: IconMapPin, label: s.name, sub: `Site · ${s.district}`, href: `/miner/mining-sites/${s.id}` })),
      ...data.shafts.filter((s) => has(s.id, s.name)).map((s) => ({ icon: IconPick, label: s.name, sub: `Shaft · ${site(s.siteId)}`, href: `/miner/mine-shafts/${s.id}` })),
      ...data.workers.filter((w) => has(w.name, w.id, w.category)).map((w) => ({ icon: IconUsers, label: w.name, sub: `Worker · ${w.id} · ${site(w.siteId)}`, href: `/miner/workers/${w.id}` })),
      ...data.inspections.filter((i) => has(i.id, i.lotId, i.inspector, i.type)).map((i) => ({ icon: IconShieldCheck, label: i.id, sub: `Inspection · ${i.type} · ${i.status}`, href: `/miner/inspections/${i.id}` })),
      ...data.requests.filter((r) => has(r.id, r.buyer, r.mineral, r.city)).map((r) => ({ icon: IconBuildingStore, label: r.buyer, sub: `Buyer request · ${r.mineral}`, href: `/miner/marketplace/requests/${r.id}` })),
      ...data.offers.filter((o) => has(o.id, o.lotId)).map((o) => ({ icon: IconBuildingStore, label: o.id, sub: `Offer · ${o.lotId} · ${o.status}`, href: `/miner/marketplace/offers/${o.id}` })),
      ...data.records.filter((r) => has(r.id)).map((r) => ({ icon: IconClipboardList, label: r.id, sub: `Extraction record · ${r.mineral} · ${site(r.siteId)}`, href: `/miner/extraction-records?q=${r.id}` })),
      ...data.txns.filter((x) => has(x.id, x.party, x.ref)).map((x) => ({ icon: IconWallet, label: x.party, sub: `Payment · ${x.id} · ${x.status}`, href: `/miner/payments?q=${encodeURIComponent(x.id)}` })),
      ...data.docs.filter((d) => has(d.name, d.number)).map((d) => ({ icon: IconFileText, label: d.name, sub: `Document · ${d.number}`, href: `/miner/documents?q=${encodeURIComponent(d.number)}` })),
    ].slice(0, 10);
  }, [q, data]);

  const go = (href: string) => {
    setQ("");
    router.push(href);
  };

  return (
    <header className="relative z-30 flex items-center justify-between gap-3 lg:gap-6">
      <MobileNav />
      <div className="relative w-full max-w-[660px]">
        <label className="flex h-12 items-center gap-3 rounded-2xl bg-white px-5 shadow-[0_2px_12px_rgba(17,24,39,0.03)]">
          <IconSearch className="size-5 text-ink/70" stroke={2} />
          <input
            type="search"
            value={q}
            onChange={(e) => setQ(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === "Enter" && results[0]) go(results[0].href);
              if (e.key === "Escape") setQ("");
            }}
            placeholder={placeholder}
            aria-label="Search MineNet"
            className="w-full bg-transparent text-sm outline-none placeholder:text-gray-400"
          />
        </label>
        {q.trim().length >= 2 && (
          <div className="absolute top-full right-0 left-0 z-40 mt-2 rounded-2xl border border-gray-100 bg-white p-1.5 shadow-[0_12px_32px_rgba(17,24,39,0.12)]">
            {results.length === 0 ? (
              <p className="px-3 py-3 text-sm text-ink/60">Nothing in MineNet matches “{q}”.</p>
            ) : (
              results.map((r) => (
                <button key={r.href + r.label} onClick={() => go(r.href)} className="flex w-full items-center gap-3 rounded-xl px-3 py-2 text-left hover:bg-page">
                  <r.icon className="size-4 text-accent" />
                  <span className="flex-1">
                    <span className="block text-sm font-medium">{r.label}</span>
                    <span className="block text-xs text-ink/60">{r.sub}</span>
                  </span>
                </button>
              ))
            )}
          </div>
        )}
      </div>

      <div className="flex shrink-0 items-center gap-2 lg:gap-4">
        <Popover
          align="right"
          panelClass="w-80"
          trigger={(_, toggle) => (
            <button
              onClick={toggle}
              aria-label={`Notifications${unread ? `, ${unread} unread` : ""}`}
              className="relative grid size-12 place-items-center rounded-full bg-white shadow-[0_2px_12px_rgba(17,24,39,0.05)]"
            >
              <IconBell className="size-5 text-ink" stroke={2} />
              {unread > 0 && (
                <span className="absolute top-2 right-2 grid size-4 place-items-center rounded-full bg-danger text-[10px] font-semibold text-white">
                  {unread}
                </span>
              )}
            </button>
          )}
        >
          {(close) => (
            <>
              <p className="flex items-center justify-between px-3 pt-2 pb-1 text-sm font-semibold">
                Notifications
                {unread > 0 && <span className="text-xs font-normal text-ink/60">{unread} unread</span>}
              </p>
              {notices.slice(0, 5).map((n) => {
                const Icon = noticeIcon[n.kind];
                return (
                  <Link key={n.id} href={n.href} onClick={() => (markRead(n.id), close())} className="flex gap-3 rounded-xl px-3 py-2.5 hover:bg-page">
                    <span className="grid size-8 shrink-0 place-items-center rounded-full bg-accent-soft">
                      <Icon className="size-4 text-accent" />
                    </span>
                    <span className="flex-1">
                      <span className={`block text-sm ${n.read ? "text-ink/70" : "font-medium"}`}>{n.text}</span>
                      <span className="block text-xs text-ink/50">{n.date}</span>
                    </span>
                    {!n.read && <span className="mt-1.5 size-2 shrink-0 rounded-full bg-accent" />}
                  </Link>
                );
              })}
              <Link href="/miner/notifications" onClick={close} className="mt-1 block border-t border-gray-100 px-3 pt-2.5 pb-1.5 text-center text-sm font-medium text-accent hover:underline">
                See all notifications
              </Link>
            </>
          )}
        </Popover>

        <Popover
          align="right"
          panelClass="w-72"
          trigger={(_, toggle) => (
            <button onClick={toggle} aria-label="Account menu" className="flex items-center gap-2 rounded-full bg-white py-1.5 pr-3 pl-1.5 shadow-[0_2px_12px_rgba(17,24,39,0.05)]">
              <span className="grid size-10 place-items-center rounded-full bg-[#F08A2C] text-sm font-medium text-white">{me.name.split(" ").map((w) => w[0]).slice(0, 2).join("")}</span>
              <IconChevronDown className="size-5 text-ink" />
            </button>
          )}
        >
          {(close) => (
            <>
              <div className="px-3 pt-2 pb-2">
                <p className="text-sm font-semibold">{me.name}</p>
                <p className="text-xs text-ink/60">{me.role} · {orgName}</p>
              </div>
              <div className="border-t border-gray-100 px-3 pt-2 pb-1">
                <p className="text-[11px] font-medium tracking-wide text-ink/50 uppercase">Demo: view as</p>
              </div>
              {members.filter((m) => m.status === "Active").map((m) => (
                <MenuItem
                  key={m.id}
                  active={m.id === me.id}
                  onClick={() => {
                    close();
                    update(() => ({ sessionMemberId: m.id }));
                    toast(`Now viewing as ${m.name} (${m.role})`, "info");
                    router.push("/miner");
                  }}
                >
                  {m.name} · {m.role}
                </MenuItem>
              ))}
              <MenuItem icon={IconUmbrella} onClick={() => (close(), router.push("/insurer"))}>Insurer portal (demo)</MenuItem>
              <div className="border-t border-gray-100 pt-1">
                <MenuItem icon={IconUser} onClick={() => (close(), router.push("/miner/settings"))}>Settings</MenuItem>
                <MenuItem icon={IconHeadphones} onClick={() => (close(), router.push("/miner/support"))}>Help & support</MenuItem>
                <MenuItem
                  icon={IconRefresh}
                  onClick={async () => {
                    close();
                    if (await confirmAction({ title: "Reset demo data?", message: "All your changes will be replaced by the original sample data.", confirmLabel: "Reset", tone: "danger" })) {
                      resetData();
                      toast("Demo data reset", "info");
                    }
                  }}
                >
                  Reset demo data
                </MenuItem>
                <MenuItem icon={IconLogout} danger onClick={() => (close(), toast("Signed out (sign-in pages come next)", "info"))}>
                  Sign out
                </MenuItem>
              </div>
            </>
          )}
        </Popover>
      </div>
    </header>
  );
}
