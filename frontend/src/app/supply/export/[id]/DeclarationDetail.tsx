"use client";

import Link from "next/link";
import { useParams } from "next/navigation";
import { IconArrowRight, IconCash, IconCircleCheck, IconDownload, IconFileText, IconPaperclip, IconRoute, IconSearch, IconShip } from "@tabler/icons-react";
import { Card, CardTitle, PrimaryButton, StatusBadge, toast } from "@/components/ui";
import { withConfirm } from "@/components/ui/Confirm";
import { DetailHeader, Facts, NotFound } from "@/components/DetailShell";
import { declTone, kg } from "@/components/supply/common";
import { downloadFile } from "@/lib/csv";
import { useStore } from "@/lib/store";
import { EXPORT_DOCS, NEXT_DECL, ROYALTY, attachExportDoc, missingDocs, payRoyalty, royaltyUsd, setDeclStatus, type ExportDecl } from "@/lib/supply";

const usd = (n: number) => `USD ${n.toLocaleString()}`;

export function DeclarationDetail() {
  const { id } = useParams<{ id: string }>();
  const d = useStore((s) => s.declarations.find((v) => v.id === id));
  if (!d) return <NotFound what="Declaration" id={id} back="/supply/export" backLabel="Export" />;
  const missing = missingDocs(d);
  const next = NEXT_DECL[d.status];
  const editable = d.status === "Draft" || d.status === "Requires Action";
  // Customs needs every paper; the lot can only leave once the royalty is paid.
  const blocked = (next === "Submitted" || next === "Under Review") && missing.length ? `Attach ${missing.length} more document${missing.length > 1 ? "s" : ""} first` : next === "Exported" && !d.royaltyPaid ? "Pay the royalty first" : null;
  const label = d.status === "Requires Action" ? "Resubmit to customs" : d.status === "Draft" ? "Submit to customs" : d.status === "Submitted" ? "Customs started review" : d.status === "Under Review" ? "Record customs clearance" : "Mark exported";

  const summary = (x: ExportDecl) =>
    downloadFile(`${x.id}-declaration.txt`, [`EXPORT DECLARATION ${x.id}`, "", `Lot: ${x.lotId}`, `Mineral: ${x.mineral} · ${x.qtyKg} kg`, `Destination: ${x.destination}`, `Buyer: ${x.buyer}`, `Declared value: ${usd(x.valueUsd)}`, `Royalty (${Math.round((ROYALTY[x.mineral] ?? 0.04) * 100)}%): ${usd(royaltyUsd(x))} · ${x.royaltyPaid ? "paid" : "not paid"}`, `Status: ${x.status} · submitted ${x.submitted}`, "", "DOCUMENTS", ...EXPORT_DOCS.map((k) => `  ${k}: ${x.docs[k] ?? "missing"}`)].join("\n"));

  return (
    <>
      <DetailHeader
        back="/supply/export"
        backLabel="Export"
        title={d.id}
        badge={<StatusBadge tone={declTone[d.status]}>{d.status}</StatusBadge>}
        subtitle={`${d.mineral} · ${kg(d.qtyKg)} to ${d.destination} · ${d.buyer}`}
        actions={
          <>
            <button onClick={() => (summary(d), toast("Declaration downloaded"))} className="inline-flex items-center gap-2 rounded-2xl border border-gray-200 bg-white px-5 py-3 text-[15px] hover:bg-page"><IconDownload className="size-5" /> Download PDF</button>
            {next && (
              <PrimaryButton
                icon={IconArrowRight}
                disabled={!!blocked}
                title={blocked ?? undefined}
                className="disabled:opacity-50"
                onClick={withConfirm({ title: `${label}?`, message: next === "Exported" ? `${d.lotId} has left the country. This closes the export.` : `${d.id} moves to ${next}.`, confirmLabel: "Confirm" }, () => (setDeclStatus(d, next), toast(`${d.id}: ${next}`)))}
              >
                {label}
              </PrimaryButton>
            )}
            {d.status === "Under Review" && (
              <button onClick={withConfirm({ title: "Customs requested changes?", message: `${d.id} comes back to you to fix and resubmit.`, confirmLabel: "Mark requires action", tone: "danger" }, () => (setDeclStatus(d, "Requires Action"), toast(`${d.id} needs action`, "info")))} className="inline-flex items-center gap-2 rounded-2xl border border-gray-200 bg-white px-5 py-3 text-[15px] hover:bg-page">
                <IconSearch className="size-5" /> Customs asked for changes
              </button>
            )}
          </>
        }
      />
      {blocked && <p className="pl-2 text-sm text-accent">{blocked}.</p>}

      <div className="grid items-start gap-5 xl:grid-cols-[1fr_400px]">
        <Card className="p-5">
          <CardTitle icon={IconFileText} iconClass="text-accent">Required documents</CardTitle>
          <p className="mt-1 text-sm text-ink/60">{EXPORT_DOCS.length - missing.length} of {EXPORT_DOCS.length} attached. Customs won&apos;t accept the declaration until all are attached.</p>
          <ul className="mt-4 divide-y divide-gray-100">
            {EXPORT_DOCS.map((name) => {
              const file = d.docs[name];
              return (
                <li key={name} className="flex flex-wrap items-center justify-between gap-3 py-3">
                  <span className="flex items-center gap-3">
                    {file ? <IconCircleCheck className="size-5 text-[#1F5B3A]" /> : <IconPaperclip className="size-5 text-ink/40" />}
                    <span><b className="block font-medium">{name}</b><span className="text-xs text-ink/60">{file ?? "Not attached"}</span></span>
                  </span>
                  {editable && (
                    <label className="cursor-pointer rounded-full border border-gray-200 px-4 py-1.5 text-sm hover:bg-page">
                      {file ? "Replace" : "Attach"}
                      <input type="file" accept=".pdf,.jpg,.jpeg,.png" className="hidden" onChange={(e) => { const f = e.target.files?.[0]; if (f) { attachExportDoc(d, name, f.name); toast(`${name} attached`); } }} />
                    </label>
                  )}
                </li>
              );
            })}
          </ul>
        </Card>

        <div className="space-y-5">
          <Card className="p-5">
            <CardTitle icon={IconShip} iconClass="text-accent">Declaration</CardTitle>
            <div className="mt-4">
              <Facts cols={2} items={[["Lot", <Link key="l" href={`/supply/traceability?lot=${d.lotId}`} className="text-accent hover:underline">{d.lotId}</Link>], ["Quantity", kg(d.qtyKg)], ["Destination", d.destination], ["Buyer", d.buyer], ["Declared value", usd(d.valueUsd)], ["Submitted", d.submitted]]} />
            </div>
            <Link href={`/supply/traceability?lot=${d.lotId}`} className="mt-4 inline-flex items-center gap-1.5 text-sm font-medium text-accent hover:underline"><IconRoute className="size-4" /> Trace this lot</Link>
          </Card>
          <Card className="p-5">
            <CardTitle icon={IconCash} iconClass="text-accent">Royalty to RMB</CardTitle>
            <p className="mt-3 text-3xl font-semibold">{usd(royaltyUsd(d))}</p>
            <p className="text-sm text-ink/60">{Math.round((ROYALTY[d.mineral] ?? 0.04) * 100)}% of the declared value · due before the lot leaves</p>
            {d.royaltyPaid ? (
              <StatusBadge tone="success" icon={IconCircleCheck}>Paid</StatusBadge>
            ) : (
              <PrimaryButton
                icon={IconCash}
                className="mt-4"
                onClick={withConfirm({ title: "Pay royalty?", message: `${usd(royaltyUsd(d))} is paid to the Rwanda Mines, Petroleum and Gas Board for ${d.id}. This can't be undone.`, confirmLabel: "Pay royalty" }, () => (payRoyalty(d), toast("Royalty paid")))}
              >
                Pay royalty
              </PrimaryButton>
            )}
          </Card>
        </div>
      </div>
    </>
  );
}
