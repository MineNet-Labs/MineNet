"use client";

import { openForm } from "@/components/FormHost";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useMemo, useState } from "react";
import {
  IconChartBar,
  IconCheck,
  IconEye,
  IconMap,
  IconMapPin,
  IconPick,
  IconPlayerPause,
  IconPlayerPlay,
  IconPlus,
  IconBolt,
} from "@tabler/icons-react";
import {
  Card,
  CardTitle,
  DateRange,
  FilterSelect,
  Modal,
  PageHeader,
  Pagination,
  PrimaryButton,
  RowMenu,
  SiteThumb,
  StatCard,
  StatusBadge,
  toast,
  usePaged,
} from "@/components/ui";
import { RwandaMap, type MapSite } from "@/components/ui/RwandaMap";
import { fmtNum, parseDate } from "@/lib/data";
import { update, useMe, useStore } from "@/lib/store";
import { can } from "@/lib/roles";

type Sort = "Name" | "Area" | "Last activity";

export default function MiningSitesPage() {
  const router = useRouter();
  const me = useMe();
  const sites = useStore((s) => s.sites);
  const lots = useStore((s) => s.lots);
  const [status, setStatus] = useState("");
  const [sort, setSort] = useState<Sort>("Name");
  const [modal, setModal] = useState<"register" | "map" | null>(null);

  const rows = useMemo(() => {
    const r = sites.filter((s) => !status || s.status === status);
    return [...r].sort((a, b) =>
      sort === "Area" ? b.areaHa - a.areaHa : sort === "Last activity" ? parseDate(b.lastActivity) - parseDate(a.lastActivity) : a.name.localeCompare(b.name),
    );
  }, [sites, status, sort]);
  const { rows: page, pager } = usePaged(rows, 6);

  const active = sites.filter((s) => s.status === "Active").length;
  const area = sites.reduce((t, s) => t + s.areaHa, 0);
  const mapSites: MapSite[] = useMemo(
    () =>
      sites.map((s) => ({
        name: s.name,
        district: s.district,
        lat: s.lat,
        lng: s.lng,
        status: s.status === "Active" ? "active" : "inactive",
        value: lots.filter((l) => l.siteId === s.id).length,
      })),
    [sites, lots],
  );

  const toggleStatus = (id: string) => {
    const s = sites.find((x) => x.id === id)!;
    const next = s.status === "Active" ? "Inactive" : "Active";
    update((st) => ({ sites: st.sites.map((x) => (x.id === id ? { ...x, status: next } : x)) }));
    toast(`${s.name} marked ${next.toLowerCase()}`, "info");
  };

  return (
    <>
      <PageHeader
        title="Mining Sites"
        subtitle="Manage and monitor your mining sites across Rwanda."
        actions={
          <div className="flex flex-col items-end gap-4">
            <DateRange />
            {can.registerSites(me.role) && <PrimaryButton icon={IconPlus} onClick={() => openForm("site")}>Register Mineral Site</PrimaryButton>}
          </div>
        }
      />

      <div className="grid grid-cols-1 gap-5 sm:grid-cols-2 xl:grid-cols-4">
        <StatCard icon={IconPick} tone="orange" label="Total Sites" value={sites.length} delta="+1" deltaClass="text-accent" spark={[3, 3.5, 3.2, 4, 3.8, 5, 8]} />
        <StatCard icon={IconCheck} tone="green" label="Active Sites" value={active} delta="+1" spark={[3, 4, 3.5, 5, 4.5, 6, 8]} />
        <StatCard icon={IconPlayerPause} tone="orange" label="Inactive sites" value={sites.length - active} delta="-1" deltaDir="down" spark={[3, 3.5, 3.2, 4, 3.8, 5, 8]} />
        <StatCard icon={IconMapPin} tone="green" label="Total Area" value={`${fmtNum(area, 1)} ha`} delta="+2%" spark={[3, 4, 3.5, 5, 4.5, 6, 8]} />
      </div>

      <div className="grid items-start gap-5 xl:grid-cols-[1fr_400px]">
        <Card className="pt-6 pb-1">
          <div className="px-6">
            <CardTitle
              icon={IconMapPin}
              action={
                <div className="flex gap-3">
                  <FilterSelect label="All statuses" options={["Active", "Inactive"]} value={status} onChange={setStatus} />
                  <FilterSelect label="Sort by: Name" options={["Area", "Last activity"]} value={sort === "Name" ? "" : sort} onChange={(v) => setSort((v || "Name") as Sort)} />
                </div>
              }
            >
              <span className="text-xl">Mining Sites</span>
            </CardTitle>
          </div>
          <div className="overflow-x-auto px-5">
            <table className="mt-5 w-full text-left text-[15px]">
              <thead className="bg-head">
                <tr>
                  {["Site Name", "Location", "Status", "Total Area", "Last Activity", "Actions"].map((h) => (
                    <th key={h} className="px-3 py-4 font-medium">{h}</th>
                  ))}
                </tr>
              </thead>
              <tbody>
                {page.map((s) => (
                  <tr
                    key={s.id}
                    onClick={() => router.push(`/miner/mining-sites/${s.id}`)}
                    className="cursor-pointer border-b border-gray-100 hover:bg-page/60"
                  >
                    <td className="px-3 py-3">
                      <Link href={`/miner/mining-sites/${s.id}`} onClick={(e) => e.stopPropagation()} className="flex items-center gap-5 text-base hover:text-[#1F5B3A] hover:underline">
                        <SiteThumb />
                        {s.name}
                      </Link>
                    </td>
                    <td className="px-3">{s.location}</td>
                    <td className="px-3"><StatusBadge tone={s.status === "Active" ? "success" : "pending"}>{s.status}</StatusBadge></td>
                    <td className="px-3">{s.areaHa} ha</td>
                    <td className="px-3">{s.lastActivity}</td>
                    <td className="px-3 text-center" onClick={(e) => e.stopPropagation()}>
                      <RowMenu
                        items={[
                          { label: "View details", icon: IconEye, onClick: () => router.push(`/miner/mining-sites/${s.id}`) },
                          s.status === "Active"
                            ? { label: "Mark inactive", icon: IconPlayerPause, onClick: () => toggleStatus(s.id) }
                            : { label: "Mark active", icon: IconPlayerPlay, onClick: () => toggleStatus(s.id) },
                        ]}
                      />
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <Pagination {...pager} noun="sites" />
        </Card>

        <div className="space-y-5">
          <Card className="p-6">
            <CardTitle icon={IconMapPin}>Sites Overview</CardTitle>
            <RwandaMap sites={mapSites} className="mt-4" height={340} valueLabel="Lots" />
            <ul className="mt-3 flex gap-6 text-sm">
              <li className="flex items-center gap-2"><i className="size-2.5 rounded-full bg-[#1F5B3A]" /> Active <span className="text-ink/60">({active})</span></li>
              <li className="flex items-center gap-2"><i className="size-2.5 rounded-full bg-accent" /> Inactive <span className="text-ink/60">({sites.length - active})</span></li>
            </ul>
            <div className="mt-6 flex items-center gap-4 rounded-2xl bg-primary-soft px-5 py-4">
              <span className="grid size-9 place-items-center rounded-full bg-[#1F5B3A]">
                <IconCheck className="size-5 text-white" stroke={3} />
              </span>
              <p className="text-sm">
                <b className="font-semibold text-[#1F5B3A]">{Math.round((active / Math.max(1, sites.length)) * 100)}%</b> of sites are<br />currently active
              </p>
            </div>
          </Card>

          <Card className="p-6">
            <CardTitle icon={IconBolt}>Quick Actions</CardTitle>
            <div className="mt-5 grid grid-cols-2 gap-3">
              <button onClick={() => setModal("map")} className="flex items-center justify-center gap-2 rounded-2xl border border-[#f6d6bd] bg-accent-soft py-3 text-[15px] text-accent hover:brightness-95">
                <IconMap className="size-5" /> View Map
              </button>
              <Link href="/miner/reports" className="flex items-center justify-center gap-2 rounded-2xl border border-[#cfe2d6] bg-primary-soft py-3 text-[15px] text-[#1F5B3A] hover:brightness-95">
                <IconChartBar className="size-5" /> View Reports
              </Link>
            </div>
          </Card>
        </div>
      </div>

      {modal === "map" && (
        <Modal title="All mining sites" subtitle="Click a pin to focus a site. Use + / − to zoom." onClose={() => setModal(null)} width={1100}>
          <RwandaMap sites={mapSites} height={560} valueLabel="Lots" />
        </Modal>
      )}
    </>
  );
}
