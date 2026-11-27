"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { useEffect, useState } from "react";
import { IconHeadphones, IconMenu2, IconSettings, IconX } from "@tabler/icons-react";
import { navFor, type NavItem } from "./Sidebar";
import { useMe } from "@/lib/store";

/** Hamburger + slide-in menu for screens narrower than the sidebar layout. */
export function MobileNav({ items, home = "/miner" }: { items?: NavItem[]; home?: string } = {}) {
  const pathname = usePathname();
  const [open, setOpen] = useState(false);

  useEffect(() => {
    if (!open) return;
    const onKey = (e: KeyboardEvent) => e.key === "Escape" && setOpen(false);
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [open]);

  const me = useMe();
  const links = [...(items ?? navFor(me.role)), { label: "Settings", href: `${home}/settings`, icon: IconSettings }, { label: "Support", href: `${home}/support`, icon: IconHeadphones }];

  return (
    <>
      <button onClick={() => setOpen(true)} aria-label="Open menu" className="grid size-12 shrink-0 place-items-center rounded-2xl bg-white shadow-[0_2px_12px_rgba(17,24,39,0.03)] lg:hidden">
        <IconMenu2 className="size-6" />
      </button>
      {open && (
        <div className="fixed inset-0 z-50 overflow-y-auto overscroll-contain bg-ink/20 lg:hidden" onClick={() => setOpen(false)} role="presentation">
          <nav
            aria-label="Main menu"
            onClick={(e) => e.stopPropagation()}
            className="flex min-h-full w-[280px] max-w-[85vw] flex-col rounded-r-[28px] bg-white px-3 py-5 shadow-xl"
          >
            <div className="mb-5 flex items-center justify-between pl-3">
              <span className="font-brand text-[26px] font-bold"><span className="text-[#05581A]">Mine</span><span className="text-[#F57C00]">Net</span></span>
              <button onClick={() => setOpen(false)} aria-label="Close menu" className="grid size-10 place-items-center rounded-full bg-page">
                <IconX className="size-5" />
              </button>
            </div>
            {links.map(({ label, href, icon: Icon }) => {
              const active = href === home ? pathname === href : pathname.startsWith(href);
              return (
                <Link
                  key={href}
                  href={href}
                  onClick={() => setOpen(false)}
                  className={`flex items-center gap-3 rounded-xl px-3 py-3 text-[15px] ${active ? "bg-accent-soft text-accent" : "text-ink/80 hover:bg-page"}`}
                >
                  <Icon className="size-5" stroke={1.8} /> {label}
                </Link>
              );
            })}
          </nav>
        </div>
      )}
    </>
  );
}
