"use client";

import Link from "next/link";
import { withConfirm } from "@/components/ui/Confirm";
import { useRouter } from "next/navigation";
import { useCallback, useMemo, useState } from "react";
import {
  IconArrowRight,
  IconBolt,
  IconCheck,
  IconChevronRight,
  IconCircleCheck,
  IconClock,
  IconDownload,
  IconInfoCircle,
  IconMapPin,
  IconUser,
  IconPlayerPause,
  IconPlayerPlay,
  IconPlus,
  IconQrcode,
  IconSearch,
  IconShieldCheck,
  IconUsers,
} from "@tabler/icons-react";
import {
  Card,
  CardTitle,
  Empty,
  FilterSelect,
  Initials,
  PageHeader,
  Pagination,
  PrimaryButton,
  RowMenu,
  StatusBadge,
  toast,
  usePaged,
  ViewAll,
} from "@/components/ui";
import { Tabs } from "@/components/ui/Tabs";
import { AddWorkerModal } from "@/components/forms";
import type { Access } from "@/lib/data";
import { siteName, update, useStore } from "@/lib/store";
import { downloadCSV } from "@/lib/csv";
import { useQueryParam } from "@/lib/useQueryParam";

function AccessBadge({ value }: { value: Access }) {
  if (value === "Setup pending") return <StatusBadge tone="pending" icon={IconClock}>{value}</StatusBadge>;
  if (value === "QR ready") return <StatusBadge tone="success" icon={IconCircleCheck}>{value}</StatusBadge>;
  return <StatusBadge tone="success" icon={IconCheck}>{value}</StatusBadge>;
}

export default function WorkersPage() {
  const router = useRouter();
  const state = useStore((s) => s);
  const { workers, sites } = state;
  const [tab, setTab] = useState("all");
  const [search, setSearch] = useState("");
  const [site, setSite] = useState("");
  const [category, setCategory] = useState("");
  const [access, setAccess] = useState("");
  const [open, setOpen] = useState(false);
  useQueryParam("q", useCallback((v: string) => setSearch(v), []));

  const rows = useMemo(
    () =>
      workers.filter(
        (w) =>
          (tab === "all" || w.status.toLowerCase() === tab) &&
          (!site || siteName(state, w.siteId) === site) &&
          (!category || w.category === category) &&
          (!access || w.access === access) &&
          (!search || `${w.name} ${w.id}`.toLowerCase().includes(search.toLowerCase())),
      ),
    [workers, tab, site, category, access, search, state],
  );
  const { rows: page, pager } = usePaged(rows, 6);

  const active = workers.filter((w) => w.status === "Active").length;
  const pendingSetup = workers.filter((w) => w.access === "Setup pending").length;
  const siteCount = new Set(workers.map((w) => w.siteId)).size;

  const setWorker = (id: string, patch: Partial<(typeof workers)[number]>, msg: string) => {
    update((s) => ({ workers: s.workers.map((w) => (w.id === id ? { ...w, ...patch } : w)) }));
    toast(msg, "info");
  };

  return (
    <>
      <PageHeader
        title="Workers"
        subtitle="Manage your site workforce, access and work records"
        actions={
          <PrimaryButton icon={IconPlus} className="rounded-full text-[17px]" onClick={() => setOpen(true)}>
            Add Worker
          </PrimaryButton>
        }
      />

      <Card className="flex items-center gap-4 px-6 py-4 text-base">
        <IconUsers className="size-6" stroke={1.6} />
        <b className="font-medium">{workers.length} workers</b>
        <span className="h-5 border-l border-gray-200" />
        <span className="text-ink/70">Across {siteCount} sites</span>
        {pendingSetup > 0 && (
          <>
            <span className="mx-2 h-5 border-l border-gray-200" />
            <i className="size-2.5 rounded-full bg-accent" />
            <span>{pendingSetup} workers awaiting account setup</span>
            <button onClick={() => (setAccess("Setup pending"), setTab("all"))} className="flex items-center gap-1 text-accent hover:underline">
              Review <IconChevronRight className="size-4" />
            </button>
          </>
        )}
      </Card>

      <div className="grid items-start gap-5 xl:grid-cols-[1fr_300px]">
        <Card className="px-5 pt-5">
          <div className="flex items-center justify-between border-b border-gray-100 px-2">
            <Tabs
              size="lg"
              items={[
                { key: "all", label: "All Workers", count: workers.length },
                { key: "active", label: "Active", count: active },
                { key: "inactive", label: "Inactive", count: workers.length - active },
              ]}
              value={tab}
              onChange={setTab}
            />
            <label className="mb-3 flex w-64 items-center gap-3 rounded-full border border-gray-200 px-4 py-2.5 text-sm">
              <IconSearch className="size-5" />
              <input value={search} onChange={(e) => setSearch(e.target.value)} placeholder="Search workers..." className="w-full outline-none placeholder:text-gray-400" />
            </label>
          </div>

          <div className="flex justify-end gap-3 py-4">
            <FilterSelect label="Site" options={sites.map((s) => s.name)} value={site} onChange={setSite} />
            <FilterSelect label="Work category" options={[...new Set(workers.map((w) => w.category))]} value={category} onChange={setCategory} />
            <FilterSelect label="Access status" options={["QR ready", "Verified", "Setup pending"]} value={access} onChange={setAccess} />
            <button
              aria-label="Download worker list"
              onClick={() => {
                downloadCSV("workers", rows, [
                  ["Worker ID", (w) => w.id],
                  ["Name", (w) => w.name],
                  ["Site", (w) => siteName(state, w.siteId)],
                  ["Category", (w) => w.category],
                  ["Access", (w) => w.access],
                  ["Status", (w) => w.status],
                  ["Joined", (w) => w.joined],
                ]);
                toast(`${rows.length} workers exported`);
              }}
              className="grid size-11 place-items-center rounded-xl border border-gray-200 hover:bg-page"
            >
              <IconDownload className="size-5" />
            </button>
          </div>

          <div className="overflow-x-auto">
            {page.length === 0 ? (
              <Empty>No workers match these filters.</Empty>
            ) : (
              <table className="w-full text-left text-[15px]">
                <thead className="bg-head">
                  <tr>{["Worker", "Worker ID", "Site", "Work category", "Account access", "Assignment", "Actions"].map((h) => <th key={h} className="px-3 py-3.5 font-normal">{h}</th>)}</tr>
                </thead>
                <tbody>
                  {page.map((w) => (
                    <tr key={w.id} className="border-b border-gray-100">
                      <td className="px-3 py-2.5"><Link href={`/miner/workers/${w.id}`} className="flex items-center gap-4 font-medium hover:text-[#1F5B3A] hover:underline"><Initials name={w.name} className="size-10 text-sm" />{w.name}</Link></td>
                      <td className="px-3">{w.id}</td>
                      <td className="px-3"><Link href={`/miner/mining-sites/${w.siteId}`} className="hover:text-[#1F5B3A] hover:underline">{siteName(state, w.siteId)}</Link></td>
                      <td className="px-3">{w.category}</td>
                      <td className="px-3"><AccessBadge value={w.access} /></td>
                      <td className="px-3"><StatusBadge tone={w.status === "Active" ? "success" : "neutral"}>{w.status}</StatusBadge></td>
                      <td className="px-3 text-center">
                        <RowMenu
                          items={[
                            { label: "View profile", icon: IconUser, onClick: () => router.push(`/miner/workers/${w.id}`) },
                            { label: "View site", icon: IconMapPin, onClick: () => router.push(`/miner/mining-sites/${w.siteId}`) },
                            ...(w.access === "Setup pending"
                              ? [{ label: "Send QR access code", icon: IconQrcode, onClick: () => setWorker(w.id, { access: "QR ready" }, `QR access code sent to ${w.name} (${w.phone})`) }]
                              : []),
                            w.status === "Active"
                              ? { label: "Deactivate", icon: IconPlayerPause, danger: true, onClick: withConfirm({ title: "Deactivate worker?", message: `${w.name} will lose site access until reactivated.`, confirmLabel: "Deactivate", tone: "danger" }, () => setWorker(w.id, { status: "Inactive" }, `${w.name} deactivated`)) }
                              : { label: "Reactivate", icon: IconPlayerPlay, onClick: () => setWorker(w.id, { status: "Active" }, `${w.name} reactivated`) },
                          ]}
                        />
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            )}
          </div>
          <Pagination {...pager} noun="workers" />
        </Card>

        <div className="space-y-5">
          <Card className="p-5">
            <CardTitle icon={IconUsers} iconClass="text-accent">Worker onboarding</CardTitle>
            <ol className="mt-5 space-y-4">
              {[
                ["Create worker profile", "Completed", true],
                ["Assign site & work category", "Completed", true],
                ["QR access & first sign-in", `${pendingSetup} pending`, pendingSetup === 0],
              ].map(([t, s, done]) => (
                <li key={t as string} className="flex gap-4">
                  <span className={`grid size-6 shrink-0 place-items-center rounded-full ${done ? "bg-[#1F5B3A]" : "border-2 border-accent"}`}>
                    {done ? <IconCheck className="size-3.5 text-white" stroke={3} /> : <IconClock className="size-3.5 text-accent" stroke={2.5} />}
                  </span>
                  <div>
                    <p className="text-[15px]">{t as string}</p>
                    <p className={`text-sm ${done ? "text-ink/50" : "text-accent"}`}>{done && t === "QR access & first sign-in" ? "Completed" : (s as string)}</p>
                  </div>
                </li>
              ))}
            </ol>
            <button
              onClick={() => (setAccess("Setup pending"), setTab("all"))}
              className="mt-5 flex w-full items-center justify-center gap-2 rounded-full border border-gray-200 py-2.5 text-sm font-medium hover:bg-page"
            >
              Manage onboarding <IconArrowRight className="size-4" />
            </button>
            <p className="mt-3 flex gap-2 text-xs text-ink/60">
              <IconInfoCircle className="size-4 shrink-0" />
              QR access links a worker to their site; it is not a shared password.
            </p>
          </Card>

          <Card className="p-5">
            <CardTitle icon={IconBolt} action={<ViewAll href="/miner/attendance" />}>Recent workforce activity</CardTitle>
            <ul className="mt-5 space-y-3">
              {workers.slice(0, 3).map((w, i) => (
                <li key={w.id} className="flex gap-3">
                  <i className={`mt-1.5 size-2 shrink-0 rounded-full ${w.access === "Setup pending" ? "bg-accent" : "bg-[#1F5B3A]"}`} />
                  <div className="flex-1">
                    <p className="text-sm font-medium">{w.name}</p>
                    <p className="text-xs text-ink/60">{w.access === "Setup pending" ? "account setup pending" : i === 0 ? "profile added" : "site assignment updated"}</p>
                  </div>
                  <span className="text-xs text-ink/60">{i + 2}h ago</span>
                </li>
              ))}
            </ul>
            <p className="mt-4 flex items-center gap-3 rounded-xl bg-primary-soft px-4 py-3 text-xs text-[#1F5B3A]">
              <IconShieldCheck className="size-5 shrink-0" />
              Worker records are visible only within your authorized sites.
            </p>
          </Card>
        </div>
      </div>

      {open && <AddWorkerModal onClose={() => setOpen(false)} />}
    </>
  );
}
