"use client";

// MapLibre implementation of the Rwanda map. Browser-only: loaded through
// next/dynamic with ssr:false from RwandaMap.tsx.
//
// Base map: OpenFreeMap "Positron" (light, free, no API key, OK for production).
// Districts: /public/maps/rwanda-districts.geojson, shaded by lot count.

import { useEffect, useRef } from "react";
import * as maplibregl from "maplibre-gl";
import type { GeoJSONSource, Map as MLMap, MapLayerMouseEvent, Marker } from "maplibre-gl";
import "maplibre-gl/dist/maplibre-gl.css";
import type { FeatureCollection } from "geojson";
import type { MapSite } from "./RwandaMap";

const STYLE = "https://tiles.openfreemap.org/styles/positron";
const RWANDA: [[number, number], [number, number]] = [
  [28.86, -2.84], // south-west [lng, lat]
  [30.9, -1.05], // north-east
];
const GREEN = "#1F5B3A";
const ORANGE = "#E8792B";

function markerEl(site: MapSite, selected: boolean) {
  const el = document.createElement("button");
  el.type = "button";
  el.setAttribute("aria-label", `${site.name}, ${site.value ?? 0} lots`);
  el.title = site.name;
  styleMarker(el, site, selected);
  return el;
}

function styleMarker(el: HTMLElement, site: MapSite, selected: boolean) {
  const size = selected ? 16 : 12;
  Object.assign(el.style, {
    width: `${size}px`,
    height: `${size}px`,
    borderRadius: "50%",
    background: site.status === "active" ? GREEN : ORANGE,
    border: "2px solid #ffffff",
    boxShadow: selected ? "0 0 0 4px rgba(31,91,58,0.25)" : "0 2px 6px rgba(0,0,0,0.2)",
    cursor: "pointer",
    padding: "0",
    transition: "width .2s, height .2s, box-shadow .2s",
  });
}

export default function RwandaMapLibre({
  sites,
  totals,
  height,
  shadeDistricts,
  selected,
  onSelect,
}: {
  sites: MapSite[];
  totals: Map<string, number>;
  height: number;
  shadeDistricts: boolean;
  selected: string | null;
  onSelect: (name: string) => void;
}) {
  const box = useRef<HTMLDivElement>(null);
  const map = useRef<MLMap | null>(null);
  const markers = useRef(new Map<string, { marker: Marker; el: HTMLElement }>());
  const districts = useRef<FeatureCollection | null>(null);
  const ready = useRef(false);
  const latest = useRef({ sites, totals, shadeDistricts, selected, onSelect });
  useEffect(() => {
    latest.current = { sites, totals, shadeDistricts, selected, onSelect };
  });

  /** District data with each feature's lot total as a `lots` property. */
  const withLots = (): FeatureCollection | null => {
    const fc = districts.current;
    if (!fc) return null;
    const { totals: t, shadeDistricts: on } = latest.current;
    return {
      ...fc,
      features: fc.features.map((f) => ({
        ...f,
        properties: { ...f.properties, lots: on ? (t.get(String(f.properties?.shapeName)) ?? 0) : 0 },
      })),
    };
  };

  /** Add pins for new sites and remove pins for sites that are gone. */
  const syncPins = () => {
    const m = map.current;
    if (!m || !ready.current) return;
    const { sites: current, selected: sel } = latest.current;
    const names = new Set(current.map((s) => s.name));
    for (const [name, pin] of markers.current) {
      if (!names.has(name)) {
        pin.marker.remove();
        markers.current.delete(name);
      }
    }
    for (const s of current) {
      if (markers.current.has(s.name)) continue;
      const el = markerEl(s, s.name === sel);
      el.addEventListener("click", (ev) => {
        ev.stopPropagation();
        latest.current.onSelect(s.name);
        m.flyTo({ center: [s.lng, s.lat], zoom: 9, speed: 0.8 });
      });
      const marker = new maplibregl.Marker({ element: el }).setLngLat([s.lng, s.lat]).addTo(m);
      markers.current.set(s.name, { marker, el });
    }
  };

  // Create the map once.
  useEffect(() => {
    if (!box.current || map.current) return;
    const m = new maplibregl.Map({
      container: box.current,
      style: STYLE,
      bounds: RWANDA,
      fitBoundsOptions: { padding: 12 },
      attributionControl: { compact: true },
      scrollZoom: false, // don't hijack page scrolling
      dragRotate: false,
      pitchWithRotate: false,
    });
    m.addControl(new maplibregl.NavigationControl({ showCompass: false }), "top-left");
    map.current = m;

    m.on("error", (e) => console.error("[RwandaMap]", e.error?.message ?? e));
    const hover = new maplibregl.Popup({ closeButton: false, closeOnClick: false, offset: 8 });

    m.on("load", async () => {
      const res = await fetch("/maps/rwanda-districts.geojson");
      districts.current = (await res.json()) as FeatureCollection;
      m.addSource("districts", { type: "geojson", data: withLots()! });

      // Mint → emerald by lot count, matching the dashboard palette.
      m.addLayer({
        id: "districts-fill",
        type: "fill",
        source: "districts",
        paint: {
          "fill-color": [
            "interpolate", ["linear"], ["get", "lots"],
            0, "#e6f2ef",
            10, "#c9e2d4",
            25, "#9cc7ad",
            60, "#5e9474",
          ],
          "fill-opacity": 0.85,
        },
      });
      m.addLayer({
        id: "districts-border",
        type: "line",
        source: "districts",
        paint: { "line-color": "#ffffff", "line-width": 1.5 },
      });

      m.on("mousemove", "districts-fill", (e: MapLayerMouseEvent) => {
        const f = e.features?.[0];
        if (!f) return;
        m.getCanvas().style.cursor = "default";
        const lots = Number(f.properties?.lots ?? 0);
        hover
          .setLngLat(e.lngLat)
          .setHTML(`<b>${f.properties?.shapeName}</b>${lots ? `<br/>${lots} lots` : ""}`)
          .addTo(m);
      });
      m.on("mouseleave", "districts-fill", () => hover.remove());

      ready.current = true;
      syncPins();
    });

    const pins = markers.current;
    return () => {
      hover.remove();
      m.remove();
      map.current = null;
      ready.current = false;
      pins.clear();
    };
  }, []);

  // Live updates: re-shade districts when totals change.
  useEffect(() => {
    if (!ready.current) return;
    const src = map.current?.getSource("districts") as GeoJSONSource | undefined;
    const data = withLots();
    if (src && data) src.setData(data);
  }, [totals, shadeDistricts]);

  // Keep pins in step with the site list.
  const siteKey = sites.map((s) => `${s.name}@${s.lat},${s.lng}`).join("|");
  useEffect(() => {
    syncPins();
  }, [siteKey]);

  // Highlight the selected pin.
  useEffect(() => {
    for (const s of sites) {
      const pin = markers.current.get(s.name);
      if (pin) styleMarker(pin.el, s, s.name === selected);
    }
  }, [selected, sites]);

  return <div ref={box} className="w-full overflow-hidden rounded-xl bg-[#f8fafc]" style={{ height }} />;
}
