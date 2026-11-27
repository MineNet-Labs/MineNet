"use client";

import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { useMemo, useState } from "react";
import {
  IconBell,
  IconBox,
  IconBuildingStore,
  IconChevronDown,
  IconFileText,
  IconHeadphones,
  IconLogout,
  IconMapPin,
  IconRefresh,
  IconSearch,
  IconShieldCheck,
  IconUser,
  IconUsers,
} from "@tabler/icons-react";
import { MenuItem, Popover, toast } from "@/components/ui";
import { resetData, useStore } from "@/lib/store";

const placeholders: Record<string, string> = {
  "/miner/inspections": "Search requests, lots, or inspectors...",
  "/miner/marketplace": "Search minerals, buyers or locations...",
  "/miner/payments": "Search transactions, buyers, or workers...",
};

const notifications = [
  { icon: IconShieldCheck, text: "Inspection for ML-2025-1047 at Kigali Site is due today", time: "1h ago", href: "/miner/inspections" },
  { icon: IconFileText, text: "Musanze Site licence ML-2025-087 expires in 7 days", time: "3h ago", href: "/miner/documents" },
  { icon: IconBuildingStore, text: "Great Lakes Minerals Co. countered your Coltan offer", time: "5h ago", href: "/miner/marketplace" },
];

export function Topbar() {
  const pathname = usePathname();
  const router = useRouter();
  const placeholder = placeholders[pathname] ?? "Search (e.g. Lot ID, Site...)";
  const [q, setQ] = useState("");
  const [unread, setUnread] = useState(notifications.length);

  const sites = useStore((s) => s.sites);
  const lots = useStore((s) => s.lots);
  const workers = useStore((s) => s.workers);
  const requests = useStore((s) => s.requests);

  const results = useMemo(() => {
    const t = q.trim().toLowerCase();
    if (t.length < 2) return [];
    const has = (...v: string[]) => v.some((x) => x.toLowerCase().includes(t));
    return [
      ...sites.filter((s) => has(s.name, s.district, s.licence)).map((s) => ({ icon: IconMapPin, label: s.name, sub: `Site · ${s.district}`, href: `/miner/mining-sites/${s.id}` })),
      ...lots.filter((l) => has(l.id, l.mineral)).map((l) => ({ icon: IconBox, label: l.id, sub: `Lot · ${l.mineral} · ${l.status}`, href: `/miner/mineral-lots?q=${l.id}` })),
      ...workers.filter((w) => has(w.name, w.id)).map((w) => ({ icon: IconUsers, label: w.name, sub: `Worker · ${w.id}`, href: `/miner/workers?q=${encodeURIComponent(w.name)}` })),
      ...requests.filter((r) => has(r.buyer, r.mineral, r.city)).map((r) => ({ icon: IconBuildingStore, label: r.buyer, sub: `Buyer request · ${r.mineral}`, href: `/miner/marketplace?q=${encodeURIComponent(r.buyer)}` })),
    ].slice(0, 8);
  }, [q, sites, lots, workers, requests]);

  const go = (href: string) => {
    setQ("");
    router.push(href);
  };

  return (
    <header className="relative z-30 flex items-center justify-between gap-6">
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
              <p className="px-3 py-3 text-sm text-ink/60">No sites, lots, workers or buyers match “{q}”.</p>
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

      <div className="flex items-center gap-4">
        <Popover
          align="right"
          panelClass="w-80"
          trigger={(_, toggle) => (
            <button
              onClick={() => {
                toggle();
                setUnread(0);
              }}
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
              <p className="px-3 pt-2 pb-1 text-sm font-semibold">Notifications</p>
              {notifications.map((n) => (
                <Link key={n.text} href={n.href} onClick={close} className="flex gap-3 rounded-xl px-3 py-2.5 hover:bg-page">
                  <span className="grid size-8 shrink-0 place-items-center rounded-full bg-accent-soft">
                    <n.icon className="size-4 text-accent" />
                  </span>
                  <span>
                    <span className="block text-sm">{n.text}</span>
                    <span className="block text-xs text-ink/50">{n.time}</span>
                  </span>
                </Link>
              ))}
            </>
          )}
        </Popover>

        <Popover
          align="right"
          panelClass="w-60"
          trigger={(_, toggle) => (
            <button onClick={toggle} aria-label="Account menu" className="flex items-center gap-2 rounded-full bg-white py-1.5 pr-3 pl-1.5 shadow-[0_2px_12px_rgba(17,24,39,0.05)]">
              <span className="grid size-10 place-items-center rounded-full bg-[#F08A2C] text-sm font-medium text-white">JU</span>
              <IconChevronDown className="size-5 text-ink" />
            </button>
          )}
        >
          {(close) => (
            <>
              <div className="px-3 pt-2 pb-2">
                <p className="text-sm font-semibold">Jean Uwimana</p>
                <p className="text-xs text-ink/60">Miner · Kigali Gold Mine</p>
              </div>
              <div className="border-t border-gray-100 pt-1">
                <MenuItem icon={IconUser} onClick={() => (close(), router.push("/miner/support#account"))}>My account</MenuItem>
                <MenuItem icon={IconHeadphones} onClick={() => (close(), router.push("/miner/support"))}>Help & support</MenuItem>
                <MenuItem
                  icon={IconRefresh}
                  onClick={() => {
                    close();
                    if (confirm("Reset all demo data to the original sample data? Your changes will be lost.")) {
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
