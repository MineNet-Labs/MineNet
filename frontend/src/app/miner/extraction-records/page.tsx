"use client";

import { useQueryParam } from "@/lib/useQueryParam";

import { mineralColor, monthlyByMineral } from "@/lib/series";

import Link from "next/link";
import { useCallback, useMemo, useState } from "react";
import { IconArrowUp, IconBolt, IconChartBar, IconDownload, IconFileText, IconPick, IconPlus, IconSearch } from "@tabler/icons-react";
import {
  Card,
  CardTitle,
  DateRange,
  Empty,
  FilterSelect,
  MineralThumb,
  MiniSelect,
  PageHeader,
  Pagination,
  PrimaryButton,
  StatusBadge,
  statusTone,
  toast,
  usePaged,
} from "@/components/ui";
import { AreaChart, Donut, LiveBadge } from "@/components/ui/charts";
import { Tabs } from "@/components/ui/Tabs";
import { NewRecordModal } from "@/components/forms";
import { fmtNum } from "@/lib/data";
import { siteName, useStore } from "@/lib/store";
import { downloadCSV } from "@/lib/csv";


export default function ExtractionRecordsPage() {
  const state = useStore((s) => s);
  const { records } = state;
  const [tab, setTab] = useState("all");
  const [mineral, setMineral] = useState("");
  const [search, setSearch] = useState("");
  useQueryParam("q", useCallback((v: string) => setSearch(v), []));
  const [sortDesc, setSortDesc] = useState(true);
  const [open, setOpen] = useState(false);

  const rows = useMemo(() => {
    const r = records.filter(
      (x) =>
        (tab === "all" || x.status.toLowerCase() === tab) &&
        (!mineral || x.mineral === mineral) &&
        (!search || `${x.id} ${siteName(state, x.siteId)} ${x.mineral}`.toLowerCase().includes(search.toLowerCase())),
    );
    return [...r].sort((a, b) => (sortDesc ? b.quantityKg - a.quantityKg : a.quantityKg - b.quantityKg));
  }, [records, tab, mineral, search, sortDesc, state]);
  const { rows: page, pager } = usePaged(rows, 6);

  const approvedKg = records.filter((r) => r.status === "Approved").reduce((t, r) => t + r.quantityKg, 0);
  const monthly = useMemo(() => monthlyByMineral(records), [records]);
  const breakdown = useMemo(() => {
    const m = new Map<string, number>();
    records.forEach((r) => m.set(r.mineral, (m.get(r.mineral) ?? 0) + r.quantityKg));
    const total = [...m.values()].reduce((a, b) => a + b, 0) || 1;
    return [...m].sort((a, b) => b[1] - a[1]).map(([name, kg]) => ({ name, pct: Math.round((kg / total) * 100), color: mineralColor(name) }));
  }, [records]);

  const exportRecords = () => {
    downloadCSV("extraction-records", rows, [
      ["Record ID", (r) => r.id],
      ["Site", (r) => siteName(state, r.siteId)],
      ["Shaft", (r) => r.shaftId ?? ""],
      ["Mineral", (r) => r.mineral],
      ["Quantity (kg)", (r) => r.quantityKg],
      ["Date", (r) => r.date],
      ["Status", (r) => r.status],
    ]);
    toast(`${rows.length} records exported`);
  };

  return (
    <>
      <PageHeader
        title="Extraction Records"
        subtitle="Track and manage all mineral extraction activities."
        crumb={{ icon: IconPick, label: "Extraction Records" }}
        actions={
          <>
            <DateRange />
            <PrimaryButton icon={IconPlus} onClick={() => setOpen(true)}>New Record</PrimaryButton>
          </>
        }
      />

      <div className="grid items-start gap-5 xl:grid-cols-[1fr_410px]">
        <Card className="self-start px-5 pt-5">
          <div className="flex items-center justify-between border-b border-gray-100 px-2">
            <Tabs
              items={[
                { key: "all", label: "All Records" },
                { key: "approved", label: "Approved" },
                { key: "pending", label: "Pending" },
                { key: "rejected", label: "Rejected" },
              ]}
              value={tab}
              onChange={setTab}
            />
            <div className="mb-3">
              <FilterSelect label="All minerals" options={[...new Set(records.map((r) => r.mineral))]} value={mineral} onChange={setMineral} />
            </div>
          </div>
          <label className="mt-4 ml-2 flex w-56 items-center gap-2 rounded-full border border-gray-200 px-4 py-2.5 text-sm">
            <IconSearch className="size-4 text-ink/70" />
            <input value={search} onChange={(e) => setSearch(e.target.value)} placeholder="Search records..." className="w-full outline-none placeholder:text-gray-400" />
          </label>

          <div className="overflow-x-auto">
            {page.length === 0 ? (
              <Empty>No records match these filters.</Empty>
            ) : (
              <table className="mt-4 w-full text-left text-[15px]">
                <thead className="bg-head">
                  <tr>
                    <th className="py-3 pr-3 pl-7 font-medium">Record ID</th>
                    <th className="px-3 font-medium">Site</th>
                    <th className="px-3 font-medium">Mineral</th>
                    <th className="px-3 font-medium">
                      <button onClick={() => setSortDesc((d) => !d)} className="flex items-center gap-1" aria-label="Sort by quantity">
                        Quantity (kg) <IconArrowUp className={`size-3.5 transition-transform ${sortDesc ? "rotate-180" : ""}`} />
                      </button>
                    </th>
                    <th className="px-3 font-medium">Date</th>
                    <th className="px-3 font-medium">Status</th>
                  </tr>
                </thead>
                <tbody>
                  {page.map((r) => (
                    <tr key={r.id} className="border-b border-gray-100">
                      <td className="py-3 pl-3"><span className="flex items-center gap-2"><MineralThumb size={36} />{r.id}</span></td>
                      <td className="px-3"><Link href={`/miner/mining-sites/${r.siteId}`} className="hover:text-[#1F5B3A] hover:underline">{siteName(state, r.siteId)}</Link></td>
                      <td className="px-3">{r.mineral}</td>
                      <td className="px-4">{fmtNum(r.quantityKg)}</td>
                      <td className="px-3">{r.date}</td>
                      <td className="px-3"><StatusBadge tone={statusTone(r.status)}>{r.status}</StatusBadge></td>
                    </tr>
                  ))}
                </tbody>
              </table>
            )}
          </div>
          <Pagination {...pager} noun="records" />
        </Card>

        <div className="space-y-5">
          <Card className="p-5">
            <CardTitle icon={IconChartBar} iconClass="text-[#B5551A]" action={<MiniSelect options={["Last 6 Months", "Last 3 Months", "This year"]} />}>
              <span className="whitespace-nowrap">Extraction Overview</span>
            </CardTitle>
            <p className="mt-5 flex items-center gap-3 font-heading text-[34px] font-bold">{fmtNum(approvedKg)} kg <LiveBadge /></p>
            <p className="text-[15px] text-ink/70">Approved, last {monthly.labels.length} months</p>
            <div className="mt-2 px-5">
              <AreaChart height={150} unit=" t" xLabels={monthly.labels} series={[{ name: "Extracted", color: "#B5551A", values: monthly.totals, fillOpacity: 0.12 }]} />
            </div>
          </Card>

          <Card className="p-5">
            <CardTitle icon={IconChartBar} iconClass="text-[#B5551A]">Mineral Breakdown</CardTitle>
            <div className="mt-3 flex items-center gap-6">
              <Donut size={130} thickness={18} gap={3} labels={breakdown.map((b) => b.name)} segments={breakdown.map((b) => ({ value: b.pct, color: b.color }))}>
                <div>
                  <p className="text-xs text-ink/70">Records</p>
                  <p className="font-heading text-3xl font-bold">{records.length}</p>
                </div>
              </Donut>
              <ul className="flex-1 space-y-4 text-[15px]">
                {breakdown.map((b) => (
                  <li key={b.name}>
                    <button onClick={() => setMineral(mineral === b.name ? "" : b.name)} className="flex w-full justify-between rounded-lg hover:bg-page">
                      <span className="flex items-center gap-3"><i className="size-2.5 rounded-full" style={{ background: b.color }} />{b.name}</span>
                      <b className="font-semibold">{b.pct}%</b>
                    </button>
                  </li>
                ))}
              </ul>
            </div>
          </Card>

          <Card className="p-5">
            <CardTitle icon={IconBolt}>Quick Actions</CardTitle>
            <div className="mt-5 grid grid-cols-2 gap-3">
              <Link href="/miner/reports" className="flex items-center justify-center gap-2 rounded-2xl border border-[#f6d6bd] bg-accent-soft py-3 text-[15px] text-[#B5551A] hover:brightness-95">
                <IconFileText className="size-5" /> View Report
              </Link>
              <button onClick={exportRecords} className="flex items-center justify-center gap-2 rounded-2xl border border-[#cfe2d6] bg-primary-soft py-3 text-[15px] text-[#1F5B3A] hover:brightness-95">
                <IconDownload className="size-5" /> Export Records
              </button>
            </div>
          </Card>
        </div>
      </div>

      {open && <NewRecordModal onClose={() => setOpen(false)} />}
    </>
  );
}
