"use client";

import {
  IconBuildingWarehouse,
  IconMapPin,
  IconTruck,
} from "@tabler/icons-react";
import { Bar, Card, CardTitle, PageHeader, ViewAll } from "@/components/ui";
import { RwandaMap, type MapSite } from "@/components/ui/RwandaMap";
import { useInsurer } from "@/components/insurer/common";
import { fmtNum } from "@/lib/data";
import { lotCustody } from "@/lib/domain";
import { mineralColor } from "@/lib/series";

function List({
  rows,
  color,
  total,
}: {
  rows: [string, number][];
  color: (k: string) => string;
  total: number;
}) {
  return (
    <ul className="mt-5 space-y-4">
      {rows.map(([k, v]) => (
        <li key={k} className="space-y-1.5 text-sm">
          <p className="flex justify-between">
            <span>{k}</span>
            <span>
              USD {fmtNum(v)} · {Math.round((v / total) * 100)}%
            </span>
          </p>
          <Bar value={(v / total) * 100} color={color(k)} />
        </li>
      ))}
      {rows.length === 0 && (
        <li className="text-sm text-ink/60">No active cover.</li>
      )}
    </ul>
  );
}

/** Where your active exposure sits: by mineral, custody state and origin site. */
export default function RiskPage() {
  const { state, policies } = useInsurer();
  const active = policies.filter((p) => p.status === "Active");
  const total = active.reduce((n, p) => n + p.sumInsured, 0) || 1;

  const group = (key: (lotId: string) => string) => {
    const m = new Map<string, number>();
    active.forEach((p) =>
      m.set(key(p.lotId), (m.get(key(p.lotId)) ?? 0) + p.sumInsured),
    );
    return [...m].sort((a, b) => b[1] - a[1]);
  };
  const lot = (id: string) => state.lots.find((l) => l.id === id);
  const byMineral = group((id) => lot(id)?.mineral ?? "Unknown");
  const byCustody = group((id) =>
    lot(id) ? lotCustody(state, lot(id)!).state : "Unknown",
  );
  const bySite = group((id) => lot(id)?.siteId ?? "");

  const pins: MapSite[] = state.sites
    .filter((s) => bySite.some(([id]) => id === s.id))
    .map((s) => ({
      name: s.name,
      district: s.district,
      lat: s.lat,
      lng: s.lng,
      status: "active",
      value: Math.round((bySite.find(([id]) => id === s.id)?.[1] ?? 0) / 1000),
    }));

  return (
    <>
      <PageHeader
        title="Risk & Exposure"
        subtitle="How much you would pay if things go wrong, and where that money sits right now."
      />
      <div className="grid items-start gap-5 xl:grid-cols-3">
        <Card className="p-5">
          <CardTitle icon={IconMapPin} iconClass="text-[#B5551A]">
            By mineral
          </CardTitle>
          <List rows={byMineral} color={mineralColor} total={total} />
        </Card>
        <Card className="p-5">
          <CardTitle icon={IconTruck} iconClass="text-accent">
            By custody state
          </CardTitle>
          <List
            total={total}
            rows={byCustody}
            color={(k) =>
              k === "In transit"
                ? "#F0913F"
                : k === "In storage"
                  ? "#0e7490"
                  : "#1F5B3A"
            }
          />
          <p className="mt-4 text-xs text-ink/60">
            Lots in transit carry the most risk. Custody comes from
            both-sides-confirmed handovers.
          </p>
        </Card>
        <Card className="p-5">
          <CardTitle icon={IconBuildingWarehouse} action={<ViewAll href="/insurer/policies" />}>
            Largest single risks
          </CardTitle>
          <ul className="mt-5 space-y-2 text-sm">
            {[...active]
              .sort((a, b) => b.sumInsured - a.sumInsured)
              .slice(0, 5)
              .map((p) => (
                <li
                  key={p.id}
                  className="flex justify-between rounded-xl bg-page px-3 py-2"
                >
                  <span>
                    {p.id} · {p.lotId}
                  </span>
                  <b className="font-medium">USD {fmtNum(p.sumInsured)}</b>
                </li>
              ))}
          </ul>
        </Card>
      </div>
      <Card className="p-5">
        <CardTitle icon={IconMapPin} iconClass="text-[#1F5B3A]">
          Origin sites of insured lots (USD thousands)
        </CardTitle>
        <RwandaMap
          sites={pins}
          className="mt-4"
          height={360}
          valueLabel="USD k"
        />
      </Card>
    </>
  );
}
