"use client";

import Link from "next/link";
import { useMemo, useState } from "react";
import { IconAlertTriangle, IconCertificate, IconDownload, IconFileText, IconRefresh, IconTrash, IconUpload, IconCalendarDue } from "@tabler/icons-react";
import {
  Card,
  CardTitle,
  Empty,
  FilterSelect,
  PageHeader,
  Pagination,
  PrimaryButton,
  RowMenu,
  StatCard,
  StatusBadge,
  toast,
  usePaged,
  type BadgeTone,
} from "@/components/ui";
import { UploadDocModal } from "@/components/forms";
import type { Doc } from "@/lib/data";
import { siteName, update, useStore } from "@/lib/store";
import { downloadFile } from "@/lib/csv";

// The sample data is "as of" late Aug 2025.
const NOW = Date.parse("Aug 29, 2025");
const DAY = 86_400_000;

function validity(d: Doc): { label: string; tone: BadgeTone; days?: number } {
  if (!d.expires) return { label: "No expiry", tone: "neutral" };
  const days = Math.round((Date.parse(d.expires) - NOW) / DAY);
  if (days < 0) return { label: "Expired", tone: "danger", days };
  if (days <= 60) return { label: `Expires in ${days} days`, tone: "pending", days };
  return { label: "Valid", tone: "success", days };
}

export default function DocumentsPage() {
  const state = useStore((s) => s);
  const { docs } = state;
  const [kind, setKind] = useState("");
  const [valid, setValid] = useState("");
  const [open, setOpen] = useState(false);

  const rows = useMemo(
    () =>
      docs.filter((d) => {
        const v = validity(d).label;
        return (!kind || d.kind === kind) && (!valid || (valid === "Expiring soon" ? v.startsWith("Expires") : v === valid));
      }),
    [docs, kind, valid],
  );
  const { rows: page, pager } = usePaged(rows, 8);

  const expiring = docs.filter((d) => validity(d).label.startsWith("Expires")).sort((a, b) => (validity(a).days ?? 0) - (validity(b).days ?? 0));
  const licences = docs.filter((d) => d.kind === "Mining Licence");

  const download = (d: Doc) => {
    downloadFile(
      d.fileName.replace(/\.(pdf|png|jpe?g)$/i, ".txt"),
      `MINENET DOCUMENT RECORD\n\n${d.name}\nType: ${d.kind}\nReference: ${d.number}\nIssued: ${d.issued}\nExpires: ${d.expires ?? "—"}\nSite: ${d.siteId ? siteName(state, d.siteId) : "—"}\nOriginal file: ${d.fileName}\n\n(The original file is served by the document store once the backend is connected.)`,
    );
    toast(`${d.name} downloaded`);
  };

  return (
    <>
      <PageHeader
        title="Documents & Licences"
        subtitle="Keep mining licences, permits and certificates valid and in one place."
        actions={<PrimaryButton icon={IconUpload} onClick={() => setOpen(true)}>Upload Document</PrimaryButton>}
      />

      <div className="grid grid-cols-2 gap-5 xl:grid-cols-4">
        <StatCard icon={IconFileText} tone="orange" label="Total Documents" value={docs.length} delta="+2" spark={[3, 3.5, 4, 4.2, 5, 5.5, 7]} />
        <StatCard icon={IconCertificate} tone="green" label="Mining Licences" value={licences.length} delta="+1" spark={[3, 3, 3.5, 3.5, 4, 4, 5]} />
        <StatCard icon={IconCalendarDue} tone="orange" label="Expiring Soon" value={expiring.length} delta="next 60 days" deltaDir="none" deltaClass="text-accent" note="" spark={[3, 4, 3, 5, 4, 6, 7]} />
        <StatCard icon={IconAlertTriangle} tone="violet" label="Expired" value={docs.filter((d) => validity(d).label === "Expired").length} delta="needs renewal" deltaDir="none" deltaClass="text-danger" note="" spark={[3, 3, 3, 3.5, 3, 3.2, 3]} />
      </div>

      {expiring.length > 0 && (
        <Card className="flex flex-wrap items-center gap-4 border border-[#f6d6bd] bg-accent-soft/60 px-6 py-4">
          <IconAlertTriangle className="size-6 text-accent" />
          <p className="flex-1 text-[15px]">
            <b className="font-semibold">{expiring[0].name}</b> expires on {expiring[0].expires}
            {expiring.length > 1 && ` · ${expiring.length - 1} more document${expiring.length > 2 ? "s" : ""} expire soon`}.
          </p>
          <button onClick={() => setValid("Expiring soon")} className="rounded-full bg-white px-4 py-2 text-sm font-medium text-accent hover:shadow-sm">
            Review expiring
          </button>
        </Card>
      )}

      <Card className="pt-6">
        <div className="flex flex-wrap items-center justify-between gap-3 px-6">
          <CardTitle icon={IconFileText}>All Documents</CardTitle>
          <div className="flex gap-2">
            <FilterSelect label="All types" options={[...new Set(docs.map((d) => d.kind))]} value={kind} onChange={setKind} />
            <FilterSelect label="Any validity" options={["Valid", "Expiring soon", "Expired", "No expiry"]} value={valid} onChange={setValid} />
          </div>
        </div>
        <div className="mt-5 overflow-x-auto px-3">
          {page.length === 0 ? (
            <Empty>No documents match these filters.</Empty>
          ) : (
            <table className="w-full text-left text-[15px] [&_td]:whitespace-nowrap">
              <thead className="bg-head">
                <tr>{["Document", "Type", "Reference", "Site", "Issued", "Expires", "Validity", ""].map((h, i) => <th key={i} className="px-4 py-3.5 text-[13px] font-medium">{h}</th>)}</tr>
              </thead>
              <tbody>
                {page.map((d) => {
                  const v = validity(d);
                  return (
                    <tr key={d.id} className="border-b border-gray-100">
                      <td className="px-4 py-3.5">
                        <span className="flex items-center gap-3">
                          <IconFileText className="size-5 shrink-0 text-danger" />
                          <span><span className="block font-medium">{d.name}</span><span className="block text-xs text-ink/60">{d.fileName}</span></span>
                        </span>
                      </td>
                      <td className="px-4">{d.kind}</td>
                      <td className="px-4">{d.number}</td>
                      <td className="px-4">{d.siteId ? <Link href={`/miner/mining-sites/${d.siteId}`} className="hover:text-[#1F5B3A] hover:underline">{siteName(state, d.siteId)}</Link> : "—"}</td>
                      <td className="px-4 text-ink/70">{d.issued}</td>
                      <td className="px-4 text-ink/70">{d.expires ?? "—"}</td>
                      <td className="px-4"><StatusBadge tone={v.tone}>{v.label}</StatusBadge></td>
                      <td className="px-4 text-right">
                        <span className="flex items-center justify-end gap-1">
                          <button aria-label={`Download ${d.name}`} onClick={() => download(d)} className="grid size-8 place-items-center rounded-full border border-gray-200 hover:bg-page">
                            <IconDownload className="size-4" />
                          </button>
                          <RowMenu
                            items={[
                              ...(d.expires
                                ? [{
                                    label: "Request renewal",
                                    icon: IconRefresh,
                                    onClick: () => toast(`Renewal request for ${d.number} sent to the regulator`),
                                  }]
                                : []),
                              {
                                label: "Delete",
                                icon: IconTrash,
                                danger: true,
                                onClick: () => {
                                  if (!confirm(`Delete "${d.name}"? This cannot be undone.`)) return;
                                  update((s) => ({ docs: s.docs.filter((x) => x.id !== d.id) }));
                                  toast(`${d.name} deleted`, "info");
                                },
                              },
                            ]}
                          />
                        </span>
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          )}
        </div>
        <Pagination {...pager} noun="documents" />
      </Card>

      {open && <UploadDocModal onClose={() => setOpen(false)} />}
    </>
  );
}
