"use client";

// Chain-of-custody Sankey, drawn as SVG with d3-sankey (BSD licence, free,
// no watermark). d3 only computes the layout; React renders everything.

import { useEffect, useMemo, useRef, useState } from "react";
import {
  sankey,
  sankeyLeft,
  sankeyLinkHorizontal,
  type SankeyLink,
  type SankeyNode,
} from "d3-sankey";

type NodeDatum = { id: string; title: string; color: string };
type LinkDatum = { source: string; target: string; value: number };
type N = SankeyNode<NodeDatum, LinkDatum>;
type L = SankeyLink<NodeDatum, LinkDatum>;

const GREEN = "#1F5B3A";
const ORANGE = "#E8792B";

/** Tonnes moving through the lot lifecycle (mirrors the whitepaper). */
const nodes: NodeDatum[] = [
  { id: "kigali", title: "Kigali Gold Mine", color: GREEN },
  { id: "musanze", title: "Musanze Mine", color: GREEN },
  { id: "nyabihu", title: "Nyabihu Mine", color: GREEN },
  { id: "ruhango", title: "Ruhango Mine", color: GREEN },
  { id: "inspected", title: "Inspected Lots", color: "#4F8A66" },
  { id: "rejected", title: "Rejected", color: "#DC2626" },
  { id: "warehouse", title: "Warehouse", color: "#904E22" },
  { id: "processor", title: "Processor", color: "#B5551A" },
  { id: "refinery", title: "Refinery", color: ORANGE },
  { id: "export", title: "Export Buyers", color: "#D0630B" },
  { id: "local", title: "Local Traders", color: "#C9A27A" },
];

const links: LinkDatum[] = [
  { source: "kigali", target: "inspected", value: 7.2 },
  { source: "musanze", target: "inspected", value: 5.1 },
  { source: "nyabihu", target: "inspected", value: 4.6 },
  { source: "ruhango", target: "inspected", value: 3.9 },
  { source: "nyabihu", target: "rejected", value: 0.6 },
  { source: "inspected", target: "warehouse", value: 8.4 },
  { source: "inspected", target: "processor", value: 12.4 },
  { source: "warehouse", target: "processor", value: 8.4 },
  { source: "processor", target: "refinery", value: 19.1 },
  { source: "refinery", target: "export", value: 13.2 },
  { source: "refinery", target: "local", value: 5.9 },
];

/** Is this link part of the hovered node's flow (upstream or downstream)? */
function connected(link: L, hovered: string | null) {
  if (!hovered) return true;
  const s = (link.source as N).id;
  const t = (link.target as N).id;
  return s === hovered || t === hovered;
}

export function SupplyChainSankey({ height = 340 }: { height?: number }) {
  const box = useRef<HTMLDivElement>(null);
  const [width, setWidth] = useState(0);
  const [hovered, setHovered] = useState<string | null>(null);
  const [tip, setTip] = useState<{ x: number; y: number; html: string } | null>(null);

  useEffect(() => {
    if (!box.current) return;
    const ro = new ResizeObserver(([e]) => setWidth(Math.floor(e.contentRect.width)));
    ro.observe(box.current);
    return () => ro.disconnect();
  }, []);

  const graph = useMemo(() => {
    if (!width) return null;
    const layout = sankey<NodeDatum, LinkDatum>()
      .nodeId((d) => d.id)
      // Place each stage by its step in the chain, so "Rejected" sits right
      // after inspection instead of being pushed to the far right.
      .nodeAlign(sankeyLeft)
      .nodeWidth(14)
      .nodePadding(18)
      .extent([
        [1, 8],
        [width - 1, height - 8],
      ]);
    // d3 mutates its input, so give it fresh copies each time.
    return layout({ nodes: nodes.map((n) => ({ ...n })), links: links.map((l) => ({ ...l })) });
  }, [width, height]);

  const path = sankeyLinkHorizontal();

  return (
    <div ref={box} className="relative w-full" style={{ height }}>
      {graph && (
        <svg width={width} height={height} role="img" aria-label="Chain of custody flow in tonnes">
          <defs>
            {graph.links.map((l, i) => (
              <linearGradient
                key={i}
                id={`sk-${i}`}
                gradientUnits="userSpaceOnUse"
                x1={(l.source as N).x1}
                x2={(l.target as N).x0}
              >
                <stop offset="0%" stopColor={(l.source as N).color} />
                <stop offset="100%" stopColor={(l.target as N).color} />
              </linearGradient>
            ))}
          </defs>

          {/* Flows */}
          <g fill="none">
            {graph.links.map((l, i) => {
              const s = l.source as N;
              const t = l.target as N;
              return (
                <path
                  key={i}
                  d={path(l) ?? undefined}
                  stroke={`url(#sk-${i})`}
                  strokeWidth={Math.max(1, l.width ?? 1)}
                  strokeOpacity={connected(l, hovered) ? 0.42 : 0.08}
                  style={{ transition: "stroke-opacity .2s" }}
                  onMouseMove={(e) =>
                    setTip({
                      x: e.nativeEvent.offsetX,
                      y: e.nativeEvent.offsetY,
                      html: `${s.title} → ${t.title}|${l.value} t`,
                    })
                  }
                  onMouseLeave={() => setTip(null)}
                />
              );
            })}
          </g>

          {/* Stages */}
          {graph.nodes.map((n) => {
            const left = (n.x0 ?? 0) < width / 2;
            return (
              <g
                key={n.id}
                onMouseEnter={() => setHovered(n.id)}
                onMouseLeave={() => setHovered(null)}
                className="cursor-default"
              >
                <rect
                  x={n.x0}
                  y={n.y0}
                  width={(n.x1 ?? 0) - (n.x0 ?? 0)}
                  height={Math.max(2, (n.y1 ?? 0) - (n.y0 ?? 0))}
                  rx={3}
                  fill={n.color}
                />
                <text
                  x={left ? (n.x1 ?? 0) + 8 : (n.x0 ?? 0) - 8}
                  y={((n.y0 ?? 0) + (n.y1 ?? 0)) / 2}
                  dy="0.35em"
                  textAnchor={left ? "start" : "end"}
                  className="fill-ink text-[13px] font-medium"
                >
                  {n.title}
                  <tspan className="fill-ink/50"> {(n.value ?? 0).toFixed(1)} t</tspan>
                </text>
              </g>
            );
          })}
        </svg>
      )}

      {tip && (
        <div
          className="pointer-events-none absolute z-10 rounded-lg border border-gray-200 bg-white px-3 py-1.5 text-[13px] shadow-md"
          style={{ left: tip.x + 12, top: tip.y + 12 }}
        >
          <b className="font-semibold">{tip.html.split("|")[0]}</b>
          <br />
          {tip.html.split("|")[1]}
        </div>
      )}

      {!graph && <div className="h-full animate-pulse rounded-xl bg-gray-50" />}
    </div>
  );
}
