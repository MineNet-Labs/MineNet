"use client";

import { openForm } from "@/components/FormHost";

import { can } from "@/lib/roles";

import { mineralColor } from "@/lib/series";

import { AnomalyCard } from "@/components/AnomalyCard";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useCallback, useMemo, useState } from "react";
import {
  IconArrowRight,
  IconBox,
  IconBuildingStore,
  IconChartBar,
  IconChevronRight,
  IconClock,
  IconDownload,
  IconEye,
  IconHistory,
  IconListCheck,
  IconMapPin,
  IconShieldCheck,
  IconUpload,
  IconX,
} from "@tabler/icons-react";
import {
  Bar,
  Card,
  CardTitle,
  DateRange,
  Empty,
  FilterSelect,
  MineralThumb,
  Modal,
  PageHeader,
  Pagination,
  PrimaryButton,
  RowMenu,
  StatCard,
  StatusBadge,
  statusTone,
  toast,
  usePaged,
} from "@/components/ui";
import { Donut } from "@/components/ui/charts";
import { RwandaMap, type MapSite } from "@/components/ui/RwandaMap";
import { CreateLotModal } from "@/components/forms";
import { fmtKg, type Lot } from "@/lib/data";
import { siteName, useStore, useMe } from "@/lib/store";
import { downloadCSV } from "@/lib/csv";
import { useQueryParam } from "@/lib/useQueryParam";

const mineralChip: Record<string, string> = {
  Gold: "bg-accent-soft text-[#B5551A]",
  Coltan: "bg-[#e3f3fb] text-[#1d4e6b]",
  Tantalum: "bg-gray-100 text-ink",
  Tin: "bg-success-soft text-[#1F5B3A]",
  Cassiterite: "bg-[#fdf0e6] text-[#9a4a12]",
  Wolframite: "bg-[#e8f1fd] text-[#1e40af]",
};

export default function MineralLotsPage() {
  const me = useMe();
  const router = useRouter();
  const state = useStore((s) => s);
  const { lots, sites } = state;
  const [status, setStatus] = useState("");
  const [search, setSearch] = useState("");
  const [modal, setModal] = useState<"create" | "history" | null>(null);
  useQueryParam("q", useCallback((v: string) => setSearch(v), []));

  const rows = useMemo(
    () => lots.filter((l) => (!status || l.status === status) && (!search || `${l.id} ${l.mineral}`.toLowerCase().includes(search.toLowerCase()))),
    [lots, status, search],
  );
  const { rows: page, pager } = usePaged(rows, 6);

  const verified = lots.filter((l) => l.status === "Verified").length;
  const pending = lots.filter((l) => l.status === "Pending").length;
  const rejected = lots.filter((l) => l.status === "Rejected").length;
  const pct = (n: number) => Math.round((n / Math.max(1, lots.length)) * 100);

  const byMineral = useMemo(() => {
    const m = new Map<string, number>();
    lots.forEach((l) => m.set(l.mineral, (m.get(l.mineral) ?? 0) + l.quantityKg));
    const total = [...m.values()].reduce((a, b) => a + b, 0) || 1;
    return [...m].sort((a, b) => b[1] - a[1]).map(([name, kg]) => ({ name, pct: Math.round((kg / total) * 100) }));
  }, [lots]);

  const mapSites: MapSite[] = useMemo(
    () => sites.map((s) => ({ name: s.name, district: s.district, lat: s.lat, lng: s.lng, status: s.status === "Active" ? "active" : "inactive", value: lots.filter((l) => l.siteId === s.id).length })),
    [sites, lots],
  );

  const exportLots = (list: Lot[], name = "mineral-lots") => {
    downloadCSV(name, list, [
      ["Lot ID", (l) => l.id],
      ["Mineral", (l) => l.mineral],
      ["Quantity (kg)", (l) => l.quantityKg],
      ["Grade (%)", (l) => l.grade],
      ["Origin site", (l) => siteName(state, l.siteId)],
      ["Status", (l) => l.status],
      ["Created", (l) => l.created],
    ]);
    toast(`${list.length === 1 ? `Lot ${list[0].id}` : `${list.length} lots`} exported`);
  };

  return (
    <>
      <PageHeader
        title="Mineral Lots"
        subtitle="Create, track and manage mineral lots across your mining operations."
        actions={
          <div className="flex flex-col items-end gap-4">
            <DateRange />
            <PrimaryButton onClick={() => setModal("create")}>
              + Create Lot <IconArrowRight className="size-4" />
            </PrimaryButton>
          </div>
        }
      />

      <div className="grid grid-cols-1 gap-5 sm:grid-cols-2 xl:grid-cols-4">
        <StatCard icon={IconBox} tone="green" label="Total Lots" value={lots.length} delta="+10%" note="from last period" spark={[3, 4, 3.5, 5, 3, 6, 8]} />
        <StatCard icon={IconShieldCheck} tone="green" label="Verified Lots" value={verified} delta="+7%" note="from last period" spark={[3, 4, 3.5, 5, 3, 6, 8]} />
        <StatCard icon={IconClock} tone="orange" label="Pending Verifications" value={pending} delta="-13" deltaDir="down" note="from last period" spark={[3, 3.5, 3.2, 4, 3.8, 5, 8]} />
        <StatCard icon={IconMapPin} tone="green" label="Active Sites" value={sites.filter((s) => s.status === "Active").length} delta="+1" note="from last period" spark={[3, 4, 3.5, 5, 3, 6, 8]} />
      </div>

      <div className="grid items-start gap-5 xl:grid-cols-[1fr_394px]">
        <div className="min-w-0 space-y-5">
          <Card className="grid gap-6 p-5 lg:grid-cols-[1fr_280px]">
            <div>
              <CardTitle icon={IconMapPin} iconClass="text-[#B5551A]">Lots by Site</CardTitle>
              <RwandaMap sites={mapSites} className="mt-4" height={320} valueLabel="Lots" />
            </div>
            <div className="border-gray-100 lg:border-l lg:pl-6">
              <h3 className="font-sans text-lg font-semibold">Top Mineral Types</h3>
              <ul className="mt-8 space-y-6">
                {byMineral.map(({ name, pct: p }) => (
                  <li key={name} className="flex items-center gap-4">
                    <MineralThumb size={44} />
                    <div className="flex-1 space-y-2">
                      <p className="flex justify-between text-[15px]"><span>{name}</span><span>{p}%</span></p>
                      <Bar value={p} color={mineralColor(name)} />
                    </div>
                  </li>
                ))}
              </ul>
            </div>
          </Card>
          <Card className="pt-5">
            <div className="flex flex-wrap items-center justify-between gap-3 px-5">
              <CardTitle icon={IconBox} iconClass="text-[#1F5B3A]">Mineral Lots</CardTitle>
              <div className="flex items-center gap-3">
                {search && (
                  <button onClick={() => setSearch("")} className="inline-flex items-center gap-1 rounded-full bg-page px-3 py-1.5 text-sm">
                    “{search}” <IconX className="size-3.5" />
                  </button>
                )}
                <FilterSelect label="All statuses" options={["Verified", "Pending", "Rejected"]} value={status} onChange={setStatus} />
              </div>
            </div>
            <div className="mt-5 overflow-x-auto px-2">
              {page.length === 0 ? (
                <Empty>No lots match these filters.</Empty>
              ) : (
                <table className="w-full text-left text-sm">
                  <thead className="bg-head">
                    <tr>{["Lot ID", "Mineral Type", "Quantity", "Grade", "Origin Site", "Status", "Date Created", "Actions"].map((h) => <th key={h} className="px-3 py-3 text-[13px] font-medium">{h}</th>)}</tr>
                  </thead>
                  <tbody>
                    {page.map((l) => (
                      <tr key={l.id} className="border-b border-gray-100 last:border-0">
                        <td className="px-3 py-3"><Link href={`/miner/mineral-lots/${l.id}`} className="flex items-center gap-3 text-[15px] hover:text-[#1F5B3A] hover:underline"><MineralThumb />{l.id}</Link></td>
                        <td className="px-3"><span className={`rounded-full px-3 py-1 ${mineralChip[l.mineral] ?? "bg-gray-100"}`}>{l.mineral}</span></td>
                        <td className="px-3">{fmtKg(l.quantityKg)}</td>
                        <td className="px-3">{l.grade}%</td>
                        <td className="px-3"><Link href={`/miner/mining-sites/${l.siteId}`} className="hover:text-[#1F5B3A] hover:underline">{siteName(state, l.siteId)}</Link></td>
                        <td className="px-3"><StatusBadge tone={statusTone(l.status)}>{l.status}</StatusBadge></td>
                        <td className="px-3 text-ink/70">{l.created}</td>
                        <td className="px-3">
                          <span className="flex items-center gap-1">
                            <button aria-label={`Download ${l.id}`} onClick={() => exportLots([l], l.id)} className="grid size-8 place-items-center rounded-full border border-gray-200 hover:bg-page">
                              <IconDownload className="size-4" />
                            </button>
                            <RowMenu
                              items={[
                                { label: "Open passport", icon: IconEye, onClick: () => router.push(`/miner/mineral-lots/${l.id}`) },
                                ...(l.status === "Verified" && can.sell(me.role) ? [{ label: "Sell on marketplace", icon: IconBuildingStore, onClick: () => openForm("sell", l.id) }] : []),
                                ...(l.status === "Pending" ? [{ label: "Request inspection", icon: IconShieldCheck, onClick: () => openForm("inspection", l.id) }] : []),
                              ]}
                            />
                          </span>
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              )}
            </div>
            <Pagination {...pager} noun="lots" />
          </Card>
        </div>
        <div className="min-w-0 space-y-5">
          <Card className="p-5">
            <CardTitle icon={IconChartBar} iconClass="text-[#1F5B3A]">Lots Overview</CardTitle>
            <div className="mt-12 flex items-center gap-6">
              <Donut
                size={128}
                thickness={13}
                labels={["Verified", "Pending", "Rejected"]}
                segments={[{ value: verified, color: "#1F5B3A" }, { value: pending, color: "#E8792B" }, { value: rejected, color: "#9CA3AF" }]}
              >
                <div>
                  <p className="font-heading text-3xl font-bold">{lots.length}</p>
                  <p className="text-[13px] text-ink/80">Total Lots</p>
                </div>
              </Donut>
              <ul className="flex-1 space-y-4 text-sm">
                {[["Verified", verified, "#1F5B3A"], ["Pending", pending, "#E8792B"], ["Rejected", rejected, "#9CA3AF"]].map(([l, n, c]) => (
                  <li key={l as string}>
                    <button onClick={() => setStatus(status === l ? "" : (l as string))} className={`flex w-full justify-between rounded-lg px-1 hover:bg-page ${status === l ? "font-semibold" : ""}`}>
                      <span className="flex items-center gap-2"><i className="size-2 rounded-full" style={{ background: c as string }} />{l}</span>
                      <span>{n} ({pct(n as number)}%)</span>
                    </button>
                  </li>
                ))}
              </ul>
            </div>
          </Card>
          <div className="space-y-5 self-start">
          <section className="rounded-[22px] bg-primary-soft/70 p-5">
            <CardTitle icon={IconShieldCheck} iconClass="text-[#1F5B3A]">Quick Actions</CardTitle>
            <div className="mt-5 space-y-3">
              {[
                { icon: IconListCheck, t: "Verify Pending Lots", s: `${pending} lots awaiting verification`, on: () => setStatus("Pending") },
                { icon: IconHistory, t: "View Lot History", s: "Track changes and updates", on: () => setModal("history") },
                { icon: IconUpload, t: "Export Lots Report", s: "Download lot data", on: () => exportLots(rows) },
              ].map(({ icon: I, t, s, on }) => (
                <button key={t} onClick={on} className="flex w-full items-center gap-4 rounded-2xl bg-white px-5 py-4 text-left hover:shadow-sm">
                  <I className="size-5 text-[#1F5B3A]" />
                  <span className="flex-1">
                    <span className="block text-[15px] font-medium">{t}</span>
                    <span className="block text-[13px] text-ink/70">{s}</span>
                  </span>
                  <IconChevronRight className="size-4" />
                </button>
              ))}
            </div>
          </section>
          <AnomalyCard limit={4} />
          </div>
        </div>
      </div>

      {modal === "create" && <CreateLotModal onClose={() => setModal(null)} />}
      {modal === "history" && (
        <Modal title="Lot History" subtitle="Every lot event, newest first" onClose={() => setModal(null)}>
          <ol className="space-y-4">
            {lots.slice(0, 10).map((l) => (
              <li key={l.id} className="flex gap-3 text-sm">
                <i className={`mt-1.5 size-2 shrink-0 rounded-full ${l.status === "Verified" ? "bg-[#1F5B3A]" : l.status === "Pending" ? "bg-accent" : "bg-danger"}`} />
                <div className="flex-1">
                  <p><Link href={`/miner/mineral-lots/${l.id}`} className="font-semibold hover:underline">{l.id}</Link> · {l.mineral} · {fmtKg(l.quantityKg)} registered at {siteName(state, l.siteId)}</p>
                  <p className="text-xs text-ink/60">{l.created} · now {l.status.toLowerCase()}</p>
                </div>
              </li>
            ))}
          </ol>
        </Modal>
      )}
    </>
  );
}
