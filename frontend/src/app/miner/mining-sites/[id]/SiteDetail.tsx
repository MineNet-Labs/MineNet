"use client";

import Link from "next/link";
import { useParams } from "next/navigation";
import { useMemo, useState } from "react";
import {
  IconArrowLeft,
  IconBox,
  IconCalendar,
  IconCertificate,
  IconClipboardList,
  IconDownload,
  IconMapPin,
  IconPick,
  IconPlus,
  IconRuler,
  IconUser,
  IconUsers,
} from "@tabler/icons-react";
import {
  Card,
  CardTitle,
  Empty,
  Initials,
  MineralThumb,
  PrimaryButton,
  SiteThumb,
  StatusBadge,
  statusTone,
  toast,
} from "@/components/ui";
import { RwandaMap } from "@/components/ui/RwandaMap";
import { AddShaftModal, AddWorkerModal, CreateLotModal, NewRecordModal } from "@/components/forms";
import { fmtKg, fmtNum } from "@/lib/data";
import { useStore } from "@/lib/store";
import { downloadCSV } from "@/lib/csv";

type Tab = "workers" | "shafts" | "lots" | "records";

/** One mining site: its own workers, shafts, lots and extraction records. */
export function SiteDetail() {
  const { id } = useParams<{ id: string }>();
  const sites = useStore((s) => s.sites);
  const allShafts = useStore((s) => s.shafts);
  const allWorkers = useStore((s) => s.workers);
  const allLots = useStore((s) => s.lots);
  const allRecords = useStore((s) => s.records);
  const [tab, setTab] = useState<Tab>("workers");
  const [modal, setModal] = useState<"worker" | "shaft" | "lot" | "record" | null>(null);

  const site = sites.find((s) => s.id === id);
  const shafts = useMemo(() => allShafts.filter((x) => x.siteId === id), [allShafts, id]);
  const workers = useMemo(() => allWorkers.filter((x) => x.siteId === id), [allWorkers, id]);
  const lots = useMemo(() => allLots.filter((x) => x.siteId === id), [allLots, id]);
  const records = useMemo(() => allRecords.filter((x) => x.siteId === id), [allRecords, id]);

  if (!site) {
    return (
      <Card className="p-10 text-center">
        <h2>Site not found</h2>
        <p className="mt-2 text-ink/70">This site may have been removed.</p>
        <Link href="/miner/mining-sites" className="mt-4 inline-block text-accent hover:underline">Back to Mining Sites</Link>
      </Card>
    );
  }

  const extracted = records.filter((r) => r.status === "Approved").reduce((t, r) => t + r.quantityKg, 0);
  const activeWorkers = workers.filter((w) => w.status === "Active").length;
  // Sample data is "as of" Aug 29, 2025: flag licences expiring within 60 days.
  const licenceSoon = Date.parse(site.licenceExpiry) - Date.parse("Aug 29, 2025") < 60 * 86_400_000;

  const tabs: { key: Tab; label: string; count: number }[] = [
    { key: "workers", label: "Workers", count: workers.length },
    { key: "shafts", label: "Mine Shafts", count: shafts.length },
    { key: "lots", label: "Mineral Lots", count: lots.length },
    { key: "records", label: "Extraction Records", count: records.length },
  ];
  const addLabel = { workers: "Add Worker", shafts: "Add Shaft", lots: "Register Lot", records: "New Record" }[tab];
  const addModal = ({ workers: "worker", shafts: "shaft", lots: "lot", records: "record" } as const)[tab];

  return (
    <>
      <div className="pl-2">
        <Link href="/miner/mining-sites" className="mb-3 inline-flex items-center gap-2 text-[15px] text-accent hover:underline">
          <IconArrowLeft className="size-4" /> Mining Sites
        </Link>
        <div className="flex items-start justify-between gap-6">
          <div className="flex items-center gap-5">
            <SiteThumb className="h-20 w-28 rounded-2xl" />
            <div>
              <div className="flex items-center gap-3">
                <h1>{site.name}</h1>
                <StatusBadge tone={site.status === "Active" ? "success" : "pending"}>{site.status}</StatusBadge>
              </div>
              <p className="mt-1 flex items-center gap-2 text-[17px] text-ink/80">
                <IconMapPin className="size-5" /> {site.district} District · {site.minerals.join(", ")}
              </p>
            </div>
          </div>
          <PrimaryButton
            icon={IconDownload}
            onClick={() => {
              downloadCSV(`${site.id}-workers`, workers, [
                ["Worker ID", (w) => w.id],
                ["Name", (w) => w.name],
                ["Category", (w) => w.category],
                ["Access", (w) => w.access],
                ["Status", (w) => w.status],
                ["Joined", (w) => w.joined],
              ]);
              toast("Site worker list downloaded");
            }}
          >
            Export Workers
          </PrimaryButton>
        </div>
      </div>

      <div className="grid grid-cols-2 gap-4 xl:grid-cols-5">
        {[
          { icon: IconRuler, label: "Total area", value: `${site.areaHa} ha` },
          { icon: IconUsers, label: "Workers", value: `${activeWorkers} active`, sub: `${workers.length} total` },
          { icon: IconPick, label: "Mine shafts", value: shafts.length, sub: `${shafts.filter((s) => s.status === "Operational").length} operational` },
          { icon: IconBox, label: "Mineral lots", value: lots.length, sub: `${lots.filter((l) => l.status === "Verified").length} verified` },
          { icon: IconClipboardList, label: "Extracted (approved)", value: fmtKg(extracted), sub: `${records.length} records` },
        ].map((k) => (
          <Card key={k.label} className="flex items-center gap-3 p-4">
            <span className="grid size-11 shrink-0 place-items-center rounded-full bg-primary-soft">
              <k.icon className="size-5 text-[#1F5B3A]" />
            </span>
            <div className="min-w-0">
              <p className="truncate text-sm text-ink/70">{k.label}</p>
              <p className="font-heading text-xl font-bold">{k.value}</p>
              {k.sub && <p className="text-xs text-ink/60">{k.sub}</p>}
            </div>
          </Card>
        ))}
      </div>

      <div className="grid gap-5 xl:grid-cols-[1fr_380px]">
        <Card className="pt-5">
          <div className="flex items-center justify-between border-b border-gray-100 px-6">
            <div className="flex gap-7">
              {tabs.map((t) => (
                <button
                  key={t.key}
                  onClick={() => setTab(t.key)}
                  className={`-mb-px border-b-2 pb-3 text-[15px] whitespace-nowrap ${
                    tab === t.key ? "border-accent font-medium text-accent" : "border-transparent text-ink/80 hover:text-ink"
                  }`}
                >
                  {t.label} <span className="align-super text-[11px]">{t.count}</span>
                </button>
              ))}
            </div>
            <button onClick={() => setModal(addModal)} className="mb-3 inline-flex items-center gap-1.5 rounded-full border border-gray-200 px-4 py-2 text-sm hover:bg-page">
              <IconPlus className="size-4" /> {addLabel}
            </button>
          </div>

          <div className="overflow-x-auto px-3 pb-3">
            {tab === "workers" &&
              (workers.length === 0 ? (
                <Empty>No workers assigned to this site yet.</Empty>
              ) : (
                <table className="w-full text-left text-sm [&_td]:whitespace-nowrap">
                  <thead className="bg-head">
                    <tr>{["Worker", "Worker ID", "Category", "Phone", "Account access", "Status", "Joined"].map((h) => <th key={h} className="px-3 py-3 text-[13px] font-medium">{h}</th>)}</tr>
                  </thead>
                  <tbody>
                    {workers.map((w) => (
                      <tr key={w.id} className="border-b border-gray-100">
                        <td className="px-3 py-3"><span className="flex items-center gap-3 font-medium"><Initials name={w.name} className="size-8" />{w.name}</span></td>
                        <td className="px-3">{w.id}</td>
                        <td className="px-3">{w.category}</td>
                        <td className="px-3 text-ink/70">{w.phone}</td>
                        <td className="px-3"><StatusBadge tone={w.access === "Setup pending" ? "pending" : "success"}>{w.access}</StatusBadge></td>
                        <td className="px-3"><StatusBadge tone={w.status === "Active" ? "success" : "neutral"}>{w.status}</StatusBadge></td>
                        <td className="px-3 text-ink/70">{w.joined}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              ))}

            {tab === "shafts" &&
              (shafts.length === 0 ? (
                <Empty>No shafts registered at this site.</Empty>
              ) : (
                <table className="w-full text-left text-sm [&_td]:whitespace-nowrap">
                  <thead className="bg-head">
                    <tr>{["Shaft", "Mineral", "Depth", "Status", "Last inspection"].map((h) => <th key={h} className="px-3 py-3 text-[13px] font-medium">{h}</th>)}</tr>
                  </thead>
                  <tbody>
                    {shafts.map((s) => (
                      <tr key={s.id} className="border-b border-gray-100">
                        <td className="px-3 py-3 font-medium">{s.name}</td>
                        <td className="px-3">{s.mineral}</td>
                        <td className="px-3">{s.depthM} m</td>
                        <td className="px-3"><StatusBadge tone={statusTone(s.status === "Maintenance" ? "pending" : s.status)}>{s.status}</StatusBadge></td>
                        <td className="px-3 text-ink/70">{s.lastInspection}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              ))}

            {tab === "lots" &&
              (lots.length === 0 ? (
                <Empty>No mineral lots from this site yet.</Empty>
              ) : (
                <table className="w-full text-left text-sm [&_td]:whitespace-nowrap">
                  <thead className="bg-head">
                    <tr>{["Lot ID", "Mineral", "Quantity", "Grade", "Status", "Created"].map((h) => <th key={h} className="px-3 py-3 text-[13px] font-medium">{h}</th>)}</tr>
                  </thead>
                  <tbody>
                    {lots.map((l) => (
                      <tr key={l.id} className="border-b border-gray-100">
                        <td className="px-3 py-3"><span className="flex items-center gap-3 font-medium"><MineralThumb />{l.id}</span></td>
                        <td className="px-3">{l.mineral}</td>
                        <td className="px-3">{fmtKg(l.quantityKg)}</td>
                        <td className="px-3">{l.grade}%</td>
                        <td className="px-3"><StatusBadge tone={statusTone(l.status)}>{l.status}</StatusBadge></td>
                        <td className="px-3 text-ink/70">{l.created}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              ))}

            {tab === "records" &&
              (records.length === 0 ? (
                <Empty>No extraction records for this site yet.</Empty>
              ) : (
                <table className="w-full text-left text-sm [&_td]:whitespace-nowrap">
                  <thead className="bg-head">
                    <tr>{["Record ID", "Shaft", "Mineral", "Quantity", "Date", "Status"].map((h) => <th key={h} className="px-3 py-3 text-[13px] font-medium">{h}</th>)}</tr>
                  </thead>
                  <tbody>
                    {records.map((r) => (
                      <tr key={r.id} className="border-b border-gray-100">
                        <td className="px-3 py-3 font-medium">{r.id}</td>
                        <td className="px-3">{r.shaftId ? `Shaft ${r.shaftId}` : "—"}</td>
                        <td className="px-3">{r.mineral}</td>
                        <td className="px-3">{fmtNum(r.quantityKg)} kg</td>
                        <td className="px-3 text-ink/70">{r.date}</td>
                        <td className="px-3"><StatusBadge tone={statusTone(r.status)}>{r.status}</StatusBadge></td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              ))}
          </div>
        </Card>

        <div className="space-y-5">
          <Card className="p-5">
            <CardTitle icon={IconMapPin}>Location</CardTitle>
            <RwandaMap
              className="mt-4"
              height={260}
              valueLabel="Lots"
              sites={[{ name: site.name, district: site.district, lat: site.lat, lng: site.lng, status: site.status === "Active" ? "active" : "inactive", value: lots.length }]}
            />
            <p className="mt-2 text-xs text-ink/60">{site.lat.toFixed(4)}, {site.lng.toFixed(4)}</p>
          </Card>

          <Card className="p-5">
            <CardTitle icon={IconCertificate}>Licence & Management</CardTitle>
            <dl className="mt-4 space-y-3 text-sm">
              <div className="flex justify-between"><dt className="text-ink/60">Mining licence</dt><dd className="font-medium">{site.licence}</dd></div>
              <div className="flex justify-between">
                <dt className="text-ink/60">Expires</dt>
                <dd className={`flex items-center gap-1.5 font-medium ${licenceSoon ? "text-accent" : ""}`}><IconCalendar className="size-4" /> {site.licenceExpiry}</dd>
              </div>
              <div className="flex justify-between"><dt className="text-ink/60">Site manager</dt><dd className="flex items-center gap-1.5 font-medium"><IconUser className="size-4" /> {site.manager}</dd></div>
              <div className="flex justify-between"><dt className="text-ink/60">Last activity</dt><dd className="font-medium">{site.lastActivity}</dd></div>
            </dl>
            {licenceSoon && (
              <p className="mt-4 rounded-xl bg-accent-soft px-3 py-2 text-xs text-accent">Licence expires soon — renew it under Documents & Licences.</p>
            )}
            <Link href="/miner/documents" className="mt-4 block text-center text-sm font-medium text-accent hover:underline">View documents →</Link>
          </Card>
        </div>
      </div>

      {modal === "worker" && <AddWorkerModal siteId={site.id} onClose={() => setModal(null)} />}
      {modal === "shaft" && <AddShaftModal siteId={site.id} onClose={() => setModal(null)} />}
      {modal === "lot" && <CreateLotModal siteId={site.id} onClose={() => setModal(null)} />}
      {modal === "record" && <NewRecordModal siteId={site.id} onClose={() => setModal(null)} />}
    </>
  );
}
