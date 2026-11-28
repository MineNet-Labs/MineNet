"use client";

// Rwanda map card content: light MapLibre base map (OpenFreeMap Positron),
// district shading by lot count, live site pins, and a floating info card for
// the selected site (click a pin to select it and fly to it).

import dynamic from "next/dynamic";
import { useEffect, useMemo, useState } from "react";

// MapLibre needs `window`, so it only loads in the browser.
const RwandaMapLibre = dynamic(() => import("./RwandaMapLibre"), {
  ssr: false,
  loading: () => <div className="h-full w-full animate-pulse rounded-xl bg-gray-100" />,
});

export type MapSite = {
  name: string;
  district: string;
  lat: number;
  lng: number;
  status: "active" | "inactive";
  /** e.g. lot count — shown in the info card and drives district shading */
  value?: number;
};

/** Known MineNet sample sites, at their real coordinates. */
export const sampleSites: MapSite[] = [
  { name: "Kigali Site", district: "Gasabo", lat: -1.89, lng: 30.11, status: "active", value: 72 },
  { name: "Ruhango Site", district: "Ruhango", lat: -2.23, lng: 29.78, status: "active", value: 31 },
  { name: "Nyabihu Site", district: "Nyabihu", lat: -1.65, lng: 29.51, status: "active", value: 28 },
  { name: "Musanze Site", district: "Musanze", lat: -1.5, lng: 29.63, status: "active", value: 26 },
  { name: "Rubavu Site", district: "Rubavu", lat: -1.68, lng: 29.36, status: "inactive", value: 9 },
  { name: "Gatumba Mine", district: "Ngororero", lat: -1.86, lng: 29.6, status: "active", value: 22 },
  { name: "Rusizi Site", district: "Rusizi", lat: -2.48, lng: 28.93, status: "active", value: 14 },
  { name: "Kamonyi Site", district: "Kamonyi", lat: -2.0, lng: 29.9, status: "active", value: 18 },
  { name: "Rulindo Site", district: "Rulindo", lat: -1.75, lng: 30.0, status: "active", value: 16 },
  { name: "Nyamasheke Site", district: "Nyamasheke", lat: -2.32, lng: 29.13, status: "inactive", value: 6 },
];

/**
 * Simulated live feed: active sites' values tick up every few seconds.
 * The ticks are kept separately and added on top of the `sites` prop, so the
 * map always reflects the current site list (e.g. a newly registered site).
 */
function useLiveSites(sites: MapSite[], live: boolean) {
  const [extra, setExtra] = useState<Record<string, number>>({});
  const names = sites.filter((s) => s.status === "active").map((s) => s.name).join("|");
  useEffect(() => {
    if (!live || !names) return;
    const active = names.split("|");
    const id = setInterval(() => {
      setExtra((prev) => {
        const next = { ...prev };
        for (const n of active) if (Math.random() < 0.4) next[n] = (next[n] ?? 0) + 1;
        return next;
      });
    }, 4000);
    return () => clearInterval(id);
  }, [live, names]);
  return useMemo(() => sites.map((s) => ({ ...s, value: (s.value ?? 0) + (extra[s.name] ?? 0) })), [sites, extra]);
}

export function RwandaMap({
  sites = sampleSites,
  valueLabel = "Lots",
  height = 320,
  shade = true,
  live = true,
  className = "",
}: {
  sites?: MapSite[];
  valueLabel?: string;
  height?: number;
  /** Shade districts by the total value of their sites. */
  shade?: boolean;
  live?: boolean;
  className?: string;
}) {
  const current = useLiveSites(sites, live);
  const [selected, setSelected] = useState<string | null>(sites[0]?.name ?? null);
  const site = current.find((s) => s.name === selected);

  const totals = useMemo(() => {
    const t = new Map<string, number>();
    for (const s of current) t.set(s.district, (t.get(s.district) ?? 0) + (s.value ?? 0));
    return t;
  }, [current]);

  return (
    <div className={`relative ${className}`} style={{ height }}>
      <RwandaMapLibre
        sites={current}
        totals={totals}
        height={height}
        shadeDistricts={shade}
        selected={selected}
        onSelect={setSelected}
      />

      {/* Floating info card (the design's "Kigali Site · 72 Lots") */}
      {site && (
        <div className="pointer-events-none absolute top-1/2 right-4 z-10 -translate-y-1/2 rounded-xl border border-gray-200 bg-white px-2.5 py-2.5 shadow-[0_4px_12px_rgba(0,0,0,0.08)]">
          <p className="flex items-center gap-1.5 text-[13px] font-semibold text-ink">
            <i className={`size-[7px] rounded-full ${site.status === "active" ? "bg-[#1F5B3A]" : "bg-accent"}`} />
            {site.name}
          </p>
          <p className="mt-0.5 pl-3.5 text-xs text-ink/60">
            {site.value ?? 0} {valueLabel}
          </p>
        </div>
      )}
    </div>
  );
}
