"use client";

// MineNet charts, built on ApexCharts.
// Every chart takes `live` (on by default): it updates on a timer from a
// simulated feed (useLiveSeries). When the backend is ready, swap the hook for
// a WebSocket / SSE subscription and the charts stay the same.

import dynamic from "next/dynamic";
import { useEffect, useState } from "react";
import type { ApexOptions } from "apexcharts";

// ApexCharts touches `window`, so it only renders in the browser.
export const Chart = dynamic(() => import("react-apexcharts"), {
  ssr: false,
  loading: () => <div className="h-full w-full animate-pulse rounded-xl bg-gray-50" />,
});

/* ----------------------------------------------------------- live feed */

type LiveMode = "roll" | "last";

/**
 * Simulated real-time feed.
 * - "roll": drops the oldest point and appends a new one (sparklines).
 * - "last": keeps the x-axis fixed and moves the latest point (current period).
 */
export function useLiveSeries(
  initial: number[],
  { live = true, mode = "roll", interval = 3000, volatility = 0.08, min = 0, max = Infinity }: {
    live?: boolean;
    mode?: LiveMode;
    interval?: number;
    volatility?: number;
    min?: number;
    max?: number;
  } = {},
) {
  const [values, setValues] = useState(initial);

  useEffect(() => {
    if (!live) return;
    const id = setInterval(() => {
      setValues((prev) => {
        const last = prev[prev.length - 1];
        const span = Math.max(...initial) - Math.min(...initial) || last || 1;
        const next = +Math.min(max, Math.max(min, last + (Math.random() - 0.45) * span * volatility * 2)).toFixed(1);
        return mode === "roll" ? [...prev.slice(1), next] : [...prev.slice(0, -1), next];
      });
    }, interval + Math.random() * 800); // stagger so cards don't tick in sync
    return () => clearInterval(id);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [live, mode, interval]);

  return values;
}

/** Small pulsing "Live" pill for chart headers. */
export function LiveBadge() {
  return (
    <span className="inline-flex items-center gap-1.5 rounded-full bg-success-soft px-2.5 py-0.5 text-xs font-medium text-[#1F6B3A]">
      <span className="relative flex size-2">
        <span className="absolute inline-flex size-full animate-ping rounded-full bg-success opacity-60" />
        <span className="relative inline-flex size-2 rounded-full bg-success" />
      </span>
      Live
    </span>
  );
}

const base: ApexOptions = {
  chart: {
    toolbar: { show: false },
    zoom: { enabled: false },
    fontFamily: "Public Sans Variable, sans-serif",
    animations: { enabled: true, speed: 600, dynamicAnimation: { enabled: true, speed: 700 } },
  },
  dataLabels: { enabled: false },
  legend: { show: false },
};

/* ------------------------------------------------------------ sparkline */

/** Small trend line with soft fill, used in the bottom-right of stat cards. */
export function Sparkline({
  values,
  color,
  width = 96,
  height = 44,
  live = true,
}: {
  values: number[];
  color: string;
  width?: number;
  height?: number;
  live?: boolean;
}) {
  const data = useLiveSeries(values, { live, mode: "roll", volatility: 0.25 });
  // Fit the y-range to the data (Apex starts at 0 by default, which flattens the trend).
  const lo = Math.min(...data);
  const hi = Math.max(...data);
  const pad = (hi - lo || 1) * 0.15;
  const options: ApexOptions = {
    ...base,
    chart: { ...base.chart, sparkline: { enabled: true } },
    yaxis: { min: lo - pad, max: hi + pad },
    colors: [color],
    stroke: { curve: "straight", width: 1.6 },
    fill: { type: "gradient", gradient: { opacityFrom: 0.28, opacityTo: 0.03, stops: [0, 100] } },
    tooltip: { enabled: false },
  };
  return (
    <div style={{ width, height }}>
      <Chart type="area" width={width} height={height} options={options} series={[{ name: "trend", data }]} />
    </div>
  );
}

/* ---------------------------------------------------------------- donut */

/** Donut chart with free-form center content. */
export function Donut({
  segments,
  labels,
  size = 128,
  thickness = 14,
  gap = 0,
  children,
}: {
  segments: { value: number; color: string }[];
  labels?: string[];
  size?: number;
  thickness?: number;
  gap?: number;
  children?: React.ReactNode;
}) {
  const options: ApexOptions = {
    ...base,
    chart: { ...base.chart, sparkline: { enabled: true } },
    labels: labels ?? segments.map((_, i) => `Series ${i + 1}`),
    colors: segments.map((s) => s.color),
    stroke: { width: gap, colors: ["#fff"] },
    plotOptions: { pie: { expandOnClick: false, donut: { size: `${Math.round((1 - (2 * thickness) / size) * 100)}%` } } },
    tooltip: { enabled: !!labels, fillSeriesColor: false, theme: "light" },
    states: { hover: { filter: { type: "none" } }, active: { filter: { type: "none" } } },
  };
  return (
    <div className="relative shrink-0" style={{ width: size, height: size }}>
      <Chart type="donut" width={size} height={size} options={options} series={segments.map((s) => s.value)} />
      <div className="pointer-events-none absolute inset-0 grid place-items-center text-center">{children}</div>
    </div>
  );
}

/* --------------------------------------------------------- grouped bars */

/** Grouped vertical bars (e.g. Gold vs Coltan per month). The current month is live. */
export function GroupedBars({
  labels,
  series,
  names,
  max = 20,
  ticks = [0, 5, 10, 15, 20],
  height = 250,
  live = true,
}: {
  labels: string[];
  series: { color: string; values: number[] }[];
  names?: string[];
  max?: number;
  ticks?: number[];
  height?: number;
  live?: boolean;
}) {
  const a = useLiveSeries(series[0].values, { live, mode: "last", min: 1, max });
  const b = useLiveSeries(series[1]?.values ?? [], { live: live && !!series[1], mode: "last", min: 1, max });
  const data = [a, b].slice(0, series.length);

  const options: ApexOptions = {
    ...base,
    colors: series.map((s) => s.color),
    plotOptions: { bar: { columnWidth: "58%", borderRadius: 10, borderRadiusApplication: "end" } },
    stroke: { show: true, width: 6, colors: ["transparent"] },
    grid: { borderColor: "#F1F2F6", strokeDashArray: 0, yaxis: { lines: { show: false } } },
    xaxis: {
      categories: labels,
      axisBorder: { show: true, color: "#E5E7EB" },
      axisTicks: { show: false },
      labels: { style: { fontSize: "14px", colors: "#374151" } },
    },
    yaxis: {
      min: 0,
      max,
      tickAmount: ticks.length - 1,
      labels: { style: { fontSize: "14px", colors: "#374151" }, formatter: (v) => `${Math.round(v)}` },
    },
    tooltip: { shared: true, intersect: false, y: { formatter: (v) => `${v} t` } },
  };

  return (
    <Chart
      type="bar"
      height={height}
      options={options}
      series={data.map((d, i) => ({ name: names?.[i] ?? `Series ${i + 1}`, data: d }))}
    />
  );
}

/** Grouped bars with any number of series (one per mineral), driven by store data. */
export function MineralBars({
  labels,
  series,
  height = 250,
  unit = " t",
}: {
  labels: string[];
  series: { name: string; color: string; values: number[] }[];
  height?: number;
  unit?: string;
}) {
  const options: ApexOptions = {
    ...base,
    colors: series.map((s) => s.color),
    plotOptions: { bar: { columnWidth: series.length > 3 ? "75%" : "58%", borderRadius: 6, borderRadiusApplication: "end" } },
    stroke: { show: true, width: series.length > 3 ? 2 : 5, colors: ["transparent"] },
    grid: { borderColor: "#F1F2F6", strokeDashArray: 0, yaxis: { lines: { show: false } } },
    xaxis: {
      categories: labels,
      axisBorder: { show: true, color: "#E5E7EB" },
      axisTicks: { show: false },
      labels: { style: { fontSize: "14px", colors: "#374151" } },
    },
    yaxis: { min: 0, forceNiceScale: true, labels: { style: { fontSize: "14px", colors: "#374151" }, formatter: (v) => `${+v.toFixed(1)}` } },
    tooltip: { shared: true, intersect: false, y: { formatter: (v) => `${v}${unit}` } },
  };
  return <Chart type="bar" height={height} options={options} series={series.map((s) => ({ name: s.name, data: s.values }))} />;
}

/* ------------------------------------------------------------ area line */

/** Smooth area chart with optional second series and y-axis. The latest point is live. */
export function AreaChart({
  series,
  height = 190,
  yMax,
  yTicks,
  xLabels,
  dots = true,
  live = true,
  unit = "",
}: {
  series: { name?: string; color: string; values: number[]; fillOpacity?: number }[];
  width?: number;
  height?: number;
  yMax?: number;
  yTicks?: number[];
  xLabels?: string[];
  dots?: boolean;
  live?: boolean;
  unit?: string;
}) {
  const max = yMax ?? Math.max(...series.flatMap((s) => s.values)) * 1.2;
  const a = useLiveSeries(series[0].values, { live, mode: "last", min: 0, max });
  const b = useLiveSeries(series[1]?.values ?? [], { live: live && !!series[1], mode: "last", min: 0, max });
  const data = [a, b].slice(0, series.length);
  const categories = xLabels ?? series[0].values.map((_, i) => `${i + 1}`);

  const options: ApexOptions = {
    ...base,
    colors: series.map((s) => s.color),
    stroke: { curve: "smooth", width: 2.4 },
    markers: { size: dots ? 4 : 0, strokeColors: "#fff", strokeWidth: 1.5, hover: { size: 6 } },
    fill: {
      type: "gradient",
      gradient: { shadeIntensity: 0, opacityFrom: series[0].fillOpacity ?? 0.2, opacityTo: 0.02, stops: [0, 100] },
    },
    grid: {
      show: !!yTicks,
      borderColor: "#E5E7EB",
      strokeDashArray: 4,
      padding: { left: yTicks ? 8 : 0, right: 8 },
    },
    xaxis: {
      categories,
      axisBorder: { show: false },
      axisTicks: { show: false },
      crosshairs: { show: true, stroke: { color: "#CBD5E1", width: 1, dashArray: 0 } },
      labels: { show: !!xLabels, style: { fontSize: "15px", colors: "#4B5563" } },
      tooltip: { enabled: false },
    },
    yaxis: {
      show: !!yTicks,
      min: 0,
      max,
      tickAmount: yTicks ? yTicks.length - 1 : undefined,
      labels: { style: { fontSize: "15px", colors: "#4B5563" }, formatter: (v) => `${Math.round(v)}` },
    },
    tooltip: { shared: true, intersect: false, y: { formatter: (v) => `${v}${unit}` } },
  };

  return (
    <Chart
      type="area"
      height={height}
      options={options}
      series={data.map((d, i) => ({ name: series[i].name ?? `Series ${i + 1}`, data: d }))}
    />
  );
}
