"use client";

import Image from "next/image";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { useEffect, useState } from "react";
import {
  IconChartBar,
  IconBox,
  IconBuildingStore,
  IconClipboardList,
  IconFileText,
  IconHeadphones,
  IconHome,
  IconLayoutSidebarLeftCollapse,
  IconLayoutSidebarLeftExpand,
  IconMapPin,
  IconPick,
  IconShieldCheck,
  IconUsers,
  IconWallet,
  type Icon as TablerIcon,
} from "@tabler/icons-react";

type NavItem = { label: string; href: string; icon: TablerIcon };

export const minerNav: NavItem[] = [
  { label: "Overview", href: "/miner", icon: IconHome },
  { label: "Mining Sites", href: "/miner/mining-sites", icon: IconMapPin },
  { label: "Mine Shafts", href: "/miner/mine-shafts", icon: IconPick },
  { label: "Extraction Records", href: "/miner/extraction-records", icon: IconClipboardList },
  { label: "Mineral Lots", href: "/miner/mineral-lots", icon: IconBox },
  { label: "Marketplace", href: "/miner/marketplace", icon: IconBuildingStore },
  { label: "Inspections", href: "/miner/inspections", icon: IconShieldCheck },
  { label: "Workers", href: "/miner/workers", icon: IconUsers },
  { label: "Documents & Licences", href: "/miner/documents", icon: IconFileText },
  { label: "Payments & Finance", href: "/miner/payments", icon: IconWallet },
  { label: "Reports", href: "/miner/reports", icon: IconChartBar },
];

const STORAGE_KEY = "minenet.sidebar.collapsed";

export function Sidebar() {
  const pathname = usePathname();
  const [collapsed, setCollapsed] = useState(false);
  // Width animation only after the saved state is applied, so a reload
  // doesn't visibly slide the sidebar closed.
  const [animate, setAnimate] = useState(false);

  // Remember the choice between visits.
  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect -- read once after hydration
    setCollapsed(localStorage.getItem(STORAGE_KEY) === "1");
    const id = requestAnimationFrame(() => requestAnimationFrame(() => setAnimate(true)));
    return () => cancelAnimationFrame(id);
  }, []);

  const toggle = () =>
    setCollapsed((c) => {
      localStorage.setItem(STORAGE_KEY, c ? "0" : "1");
      return !c;
    });

  const ToggleIcon = collapsed ? IconLayoutSidebarLeftExpand : IconLayoutSidebarLeftCollapse;
  const toggleLabel = collapsed ? "Open sidebar" : "Close sidebar";

  return (
    <aside
      className={`sticky top-4 flex h-[calc(100dvh/var(--app-zoom,1)-2rem)] shrink-0 flex-col rounded-[28px] bg-white pt-6 pb-6 shadow-[0_4px_24px_rgba(17,24,39,0.04)] ${animate ? "transition-[width] duration-300 ease-out" : ""} ${
        collapsed ? "w-[84px] px-3" : "w-[208px] px-3"
      }`}
    >
      {/* Header: full logo + close button when open; when closed, the mark
          turns into the open button on hover (like Claude / ChatGPT). */}
      {collapsed ? (
        <button
          onClick={toggle}
          aria-label={toggleLabel}
          title={toggleLabel}
          className="group relative mx-auto mb-8 grid size-14 place-items-center rounded-2xl hover:bg-page"
        >
          <Image
            src="/brand/minenet-mark.png"
            alt="MineNet"
            width={48}
            height={48}
            className="transition-opacity group-hover:opacity-0"
            priority
          />
          <ToggleIcon
            className="absolute size-6 text-ink/70 opacity-0 transition-opacity group-hover:opacity-100"
            stroke={1.8}
          />
        </button>
      ) : (
        <div className="mb-8 flex h-14 items-center justify-between pl-3">
          {/* Open: the name only (wordmark colours from the MineNet logo) */}
          <Link href="/miner" aria-label="MineNet home" className="font-brand text-[28px] leading-none font-bold tracking-tight">
            <span className="text-[#05581A]">Mine</span>
            <span className="text-[#F57C00]">Net</span>
          </Link>
          <button
            onClick={toggle}
            aria-label={toggleLabel}
            title={toggleLabel}
            className="grid size-9 place-items-center rounded-lg text-ink/50 hover:bg-page hover:text-ink"
          >
            <ToggleIcon className="size-5" stroke={1.8} />
          </button>
        </div>
      )}

      <nav className="flex min-h-0 flex-1 flex-col gap-1 overflow-y-auto">
        {minerNav.map(({ label, href, icon: Icon }) => {
          const active = href === "/miner" ? pathname === href : pathname.startsWith(href);
          return (
            <Link
              key={href}
              href={href}
              title={collapsed ? label : undefined}
              aria-label={collapsed ? label : undefined}
              className={`flex items-center gap-3 rounded-xl py-2.5 text-sm leading-tight transition-colors ${
                collapsed ? "justify-center px-0" : "px-3"
              } ${active ? "bg-accent-soft text-accent" : "text-ink/80 hover:bg-page hover:text-ink"}`}
            >
              <Icon className={collapsed ? "size-[22px] shrink-0" : "size-[18px] shrink-0"} stroke={1.8} />
              {!collapsed && <span>{label}</span>}
            </Link>
          );
        })}
      </nav>

      <div className="border-t border-gray-200 pt-5">
        <Link
          href="/miner/support"
          title={collapsed ? "Support" : undefined}
          aria-label={collapsed ? "Support" : undefined}
          className={`flex items-center gap-3 text-sm text-ink/80 hover:text-ink ${collapsed ? "justify-center" : "px-2"}`}
        >
          <IconHeadphones className={collapsed ? "size-[22px]" : "size-[18px]"} stroke={1.8} />
          {!collapsed && "Support"}
        </Link>
      </div>
    </aside>
  );
}
