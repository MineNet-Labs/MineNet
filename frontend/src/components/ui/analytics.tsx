"use client";

// Advanced MineNet analytics: supply-chain Sankey (d3-sankey), radial gauges,
// heatmap and funnel (ApexCharts). All feed from simulated live data until the
// backend streams real events.

import { useEffect, useState } from "react";
import type { ApexOptions } from "apexcharts";
import { Chart } from "./charts";

const GREEN = "#1F5B3A";
const ORANGE = "#E8792B";
const FONT = "Public Sans Variable, sans-serif";

const base: ApexOptions = {
  chart: {
    toolbar: { show: false },
    fontFamily: FONT,
    animations: { enabled: true, speed: 600, dynamicAnimation: { enabled: true, speed: 700 } },
  },
  dataLabels: { enabled: false },
  legend: { show: false },
};

/** Calls `tick` on an interval while mounted (simulated live feed). */
function useTicker(tick: () => void, ms: number, live = true) {
  useEffect(() => {
    if (!live) return;
    const id = setInterval(tick, ms);
    return () => clearInterval(id);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [ms, live]);
}

export { SupplyChainSankey } from "./SupplyChainSankey";

/* ------------------------------------------------------ radial gauges */

/** Concentric radial gauges, e.g. verification / inspection pass / licence compliance. */
export function ComplianceGauges({
  items,
  height = 260,
  live = true,
}: {
  items: { label: string; value: number; color: string }[];
  height?: number;
  live?: boolean;
}) {
  const [values, setValues] = useState(items.map((i) => i.value));
  useTicker(
    () =>
      setValues((v) =>
        v.map((x) => Math.min(100, Math.max(60, +(x + (Math.random() - 0.45) * 1.6).toFixed(1)))),
      ),
    4000,
    live,
  );

  const options: ApexOptions = {
    ...base,
    labels: items.map((i) => i.label),
    colors: items.map((i) => i.color),
    plotOptions: {
      radialBar: {
        hollow: { size: "38%" },
        track: { background: "#F1F2F6", margin: 6 },
        dataLabels: {
          name: { fontSize: "13px", color: "#6B7280", offsetY: 18 },
          value: { fontSize: "24px", fontWeight: 700, color: "#111827", offsetY: -14, formatter: (v) => `${v}%` },
          total: {
            show: true,
            label: "Average",
            color: "#6B7280",
            formatter: (w) =>
              `${Math.round((w.globals.seriesTotals as number[]).reduce((a, b) => a + b, 0) / items.length)}%`,
          },
        },
      },
    },
    stroke: { lineCap: "round" },
  };

  return <Chart type="radialBar" height={height} options={options} series={values} />;
}

/* ------------------------------------------------------------ heatmap */

const DAYS = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];

/** Extraction activity per site and weekday (kg). Today's column is live. */
export function ExtractionHeatmap({
  sites,
  height = 280,
  live = true,
}: {
  sites: string[];
  height?: number;
  live?: boolean;
}) {
  const [grid, setGrid] = useState(() =>
    sites.map((_, s) => DAYS.map((_, d) => (d === 6 ? 8 : 20) + ((s * 37 + d * 53) % 110))),
  );
  useTicker(
    () =>
      setGrid((g) => {
        const today = (new Date().getDay() + 6) % 7;
        const row = Math.floor(Math.random() * g.length);
        return g.map((r, i) => (i === row ? r.map((v, d) => (d === today ? v + Math.round(Math.random() * 6) : v)) : r));
      }),
    3500,
    live,
  );

  const options: ApexOptions = {
    ...base,
    plotOptions: {
      heatmap: {
        radius: 6,
        enableShades: false,
        colorScale: {
          ranges: [
            { from: 0, to: 40, color: "#E6EFE8", name: "Low" },
            { from: 41, to: 80, color: "#93BEA2", name: "Medium" },
            { from: 81, to: 120, color: "#4F8A66", name: "High" },
            { from: 121, to: 9999, color: GREEN, name: "Peak" },
          ],
        },
      },
    },
    stroke: { width: 3, colors: ["#fff"] },
    legend: { show: true, position: "bottom", fontSize: "13px", markers: { shape: "square" } },
    xaxis: { categories: DAYS, axisBorder: { show: false }, axisTicks: { show: false }, labels: { style: { fontSize: "13px" } } },
    yaxis: { labels: { style: { fontSize: "13px" } } },
    tooltip: { y: { formatter: (v) => `${v} kg` } },
  };

  // Apex draws heatmap rows bottom-up; reverse so the first site is on top.
  const series = sites.map((name, i) => ({ name, data: grid[i] })).reverse();
  return <Chart type="heatmap" height={height} options={options} series={series} />;
}

/* ------------------------------------------------------------- funnel */

/** Inspection pipeline funnel: requested â†’ â€¦ â†’ certified. */
export function InspectionFunnel({
  stages,
  height = 280,
  live = true,
}: {
  stages: { label: string; value: number }[];
  height?: number;
  live?: boolean;
}) {
  const [values, setValues] = useState(stages.map((s) => s.value));
  useTicker(
    () =>
      setValues((v) => {
        // A new request arrives at the top; occasionally one moves down a stage.
        const next = [...v];
        next[0] += 1;
        const i = 1 + Math.floor(Math.random() * (next.length - 1));
        if (next[i] < next[i - 1]) next[i] += 1;
        return next;
      }),
    5000,
    live,
  );

  const options: ApexOptions = {
    ...base,
    colors: [GREEN, "#2F6E4A", "#4F8A66", ORANGE, "#D0630B"],
    plotOptions: {
      bar: { horizontal: true, isFunnel: true, distributed: true, borderRadius: 6, barHeight: "82%" },
    },
    dataLabels: {
      enabled: true,
      formatter: (v, opt) => `${stages[opt?.dataPointIndex ?? 0]?.label}: ${v}`,
      style: { fontSize: "13px", fontWeight: 500 },
      dropShadow: { enabled: false },
    },
    xaxis: { categories: stages.map((s) => s.label) },
    yaxis: { labels: { show: false } },
    grid: { show: false },
    tooltip: { y: { formatter: (v) => `${v} lots` } },
  };

  return <Chart type="bar" height={height} options={options} series={[{ name: "Lots", data: values }]} />;
}
