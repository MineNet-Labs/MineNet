"use client";

import { openForm } from "@/components/FormHost";

import { can } from "@/lib/roles";

import Link from "next/link";
import { withConfirm } from "@/components/ui/Confirm";
import { useParams } from "next/navigation";
import { useMemo, useState } from "react";
import {
  IconAlertTriangle,
  IconArrowLeft,
  IconBuildingBank,
  IconBuildingStore,
  IconCircleCheck,
  IconCircleDashed,
  IconDownload,
  IconFileText,
  IconLock,
  IconPlus,
  IconRoute,
  IconShieldCheck,
  IconSparkles,
  IconTruck,
  IconUmbrella,
} from "@tabler/icons-react";
import {
  Card,
  CardTitle,
  Empty,
  MineralThumb,
  PrimaryButton,
  StatusBadge,
  statusTone,
  toast,
} from "@/components/ui";
import {
  DispatchModal,
  confirmTransfer,
  lotValue,
  releaseEscrow,
} from "@/components/chain-forms";
import { fmtKg, fmtNum, type EventKind } from "@/lib/data";
import {
  PASSPORT_CONTRACT,
  activeLien,
  activePolicies,
  anomalies,
  listingChecklist,
  lotCustody,
  lotTimeline,
  orgCanAct,
  priceGuidance,
  tokenId,
} from "@/lib/domain";
import { siteName, useStore, useMe } from "@/lib/store";
import { downloadFile } from "@/lib/csv";

const eventColor: Partial<Record<EventKind, string>> = {
  Registered: "bg-[#1F5B3A]",
  Inspected: "bg-[#2563eb]",
  Listed: "bg-accent",
  Sold: "bg-accent",
  "Escrow locked": "bg-violet",
  "Escrow released": "bg-[#1F5B3A]",
  Financed: "bg-violet",
  "Lien released": "bg-violet",
  Insured: "bg-[#0e7490]",
};

const STAGES = [
  "Registered",
  "Inspected",
  "Sold",
  "In custody",
  "Delivered",
] as const;

export function LotPassport() {
  const me = useMe();
  const { id } = useParams<{ id: string }>();
  const state = useStore((s) => s);
  const lot = state.lots.find((l) => l.id === id);
  const [modal, setModal] = useState<"dispatch" | null>(null);

  const timeline = useMemo(
    () => (lot ? lotTimeline(state, lot) : []),
    [state, lot],
  );
  if (!lot) {
    return (
      <Card className="p-10 text-center">
        <h2>Lot not found</h2>
        <p className="mt-2 text-ink/70">No lot with id “{id}”.</p>
        <Link
          href="/miner/mineral-lots"
          className="mt-4 inline-block font-medium text-accent hover:underline"
        >
          Back to Mineral Lots
        </Link>
      </Card>
    );
  }

  const site = state.sites.find((s) => s.id === lot.siteId);
  const custody = lotCustody(state, lot);
  const transfers = state.transfers.filter((t) => t.lotId === lot.id);
  const escrows = state.escrows.filter((e) => e.lotId === lot.id);
  const loans = state.loans.filter((l) => l.lotId === lot.id);
  const policies = state.policies.filter((p) => p.lotId === lot.id);
  const lien = activeLien(state, lot.id);
  const cover = activePolicies(state, lot.id);
  const docs = state.docs.filter((d) => d.name.includes(lot.id));
  const inspections = state.inspections.filter((i) => i.lotId === lot.id);
  const checklist = listingChecklist(state, lot);
  const ready = checklist.every((c) => c.ok);
  const price = priceGuidance(state, lot.mineral, lot.grade);
  const flags = anomalies(state).filter((a) => a.lotId === lot.id);
  const canAct = orgCanAct(state);
  const kinds = new Set(timeline.map((e) => e.kind));
  const reached = [
    true,
    kinds.has("Inspected") || lot.status === "Verified",
    kinds.has("Sold") || escrows.length > 0,
    transfers.some(
      (t) => t.status !== "Awaiting handover" && t.status !== "Cancelled",
    ),
    kinds.has("Delivered") || escrows.some((e) => e.status === "Released"),
  ];

  const downloadPassport = () => {
    const passport = {
      lot: { ...lot, site: site?.name },
      token: {
        id: tokenId(lot.id),
        contract: PASSPORT_CONTRACT,
        owner: state.org.wallet,
      },
      custody,
      events: timeline,
      transfers,
      escrows,
      loans,
      policies,
      documents: docs.map((d) => ({
        name: d.name,
        number: d.number,
        file: d.fileName,
      })),
    };
    downloadFile(
      `passport-${lot.id}.json`,
      JSON.stringify(passport, null, 2),
      "application/json",
    );
    toast(`Passport for ${lot.id} downloaded`);
  };

  return (
    <>
      <div className="flex flex-wrap items-start justify-between gap-4 pl-2">
        <div>
          <Link
            href="/miner/mineral-lots"
            className="mb-4 inline-flex items-center gap-2 rounded-full border border-gray-200 bg-white px-5 py-2.5 text-[15px] font-medium text-ink shadow-sm hover:bg-page"
          >
            <IconArrowLeft className="size-5" /> Mineral Lots
          </Link>
          <div className="flex items-center gap-3">
            <MineralThumb size={48} />
            <div>
              <h1 className="flex items-center gap-3">
                {lot.id}{" "}
                <StatusBadge tone={statusTone(lot.status)}>
                  {lot.status}
                </StatusBadge>
              </h1>
              <p className="mt-1 text-[17px] text-ink/80">
                {lot.mineral} · {fmtKg(lot.quantityKg)} · {lot.grade}% ·{" "}
                <Link
                  href={`/miner/mining-sites/${lot.siteId}`}
                  className="hover:underline"
                >
                  {site?.name}
                </Link>
              </p>
            </div>
          </div>
        </div>
        <div className="flex flex-wrap gap-2">
          <button
            onClick={downloadPassport}
            className="inline-flex items-center gap-2 rounded-2xl border border-gray-200 bg-white px-4 py-3 text-[15px] hover:bg-page"
          >
            <IconDownload className="size-5" /> Passport
          </button>
          {lot.status === "Pending" &&
            !inspections.some((i) =>
              ["Pending", "Scheduled", "In Progress"].includes(i.status),
            ) && (
              <PrimaryButton
                icon={IconShieldCheck}
                onClick={() =>
                  openForm("inspection", lot.id)
                }
              >
                Request inspection
              </PrimaryButton>
            )}
          {lot.status === "Verified" && (
            <>
              <button
                disabled={!canAct}
                onClick={() => setModal("dispatch")}
                className="inline-flex items-center gap-2 rounded-2xl border border-gray-200 bg-white px-4 py-3 text-[15px] hover:bg-page disabled:opacity-50"
              >
                <IconTruck className="size-5" /> Dispatch
              </button>
              {can.finance(me.role) && (
                <>
                  <button
                    disabled={!canAct}
                    onClick={() =>
                      openForm("financing", lot.id)
                    }
                    className="inline-flex items-center gap-2 rounded-2xl border border-gray-200 bg-white px-4 py-3 text-[15px] hover:bg-page disabled:opacity-50"
                  >
                    <IconBuildingBank className="size-5" /> Finance
                  </button>
                  <button
                    disabled={!canAct}
                    onClick={() =>
                      openForm("insurance", lot.id)
                    }
                    className="inline-flex items-center gap-2 rounded-2xl border border-gray-200 bg-white px-4 py-3 text-[15px] hover:bg-page disabled:opacity-50"
                  >
                    <IconUmbrella className="size-5" /> Insure
                  </button>
                  {ready && (
                    <PrimaryButton
                      icon={IconBuildingStore}
                      onClick={() =>
                        openForm("sell", lot.id)
                      }
                    >
                      Sell
                    </PrimaryButton>
                  )}
                </>
              )}
            </>
          )}
        </div>
      </div>

      {/* Journey */}
      <Card className="p-6">
        <ol className="grid grid-cols-5 gap-2">
          {STAGES.map((s, i) => (
            <li
              key={s}
              className="flex flex-col items-center gap-2 text-center text-sm"
            >
              <span
                className={`grid size-9 place-items-center rounded-full ${reached[i] ? "bg-[#1F5B3A] text-white" : "bg-page text-ink/40"}`}
              >
                {reached[i] ? (
                  <IconCircleCheck className="size-5" />
                ) : (
                  <IconCircleDashed className="size-5" />
                )}
              </span>
              <span className={reached[i] ? "font-medium" : "text-ink/50"}>
                {s}
              </span>
            </li>
          ))}
        </ol>
      </Card>

      <div className="grid items-start gap-5 xl:grid-cols-[1fr_380px]">
        <div className="space-y-5">
          {/* Passport summary */}
          <Card className="p-6">
            <CardTitle icon={IconFileText} iconClass="text-[#1F5B3A]">
              Digital passport
            </CardTitle>
            <dl className="mt-5 grid grid-cols-2 gap-x-6 gap-y-4 text-sm md:grid-cols-3">
              {[
                ["Token", `#${tokenId(lot.id)} (ERC-721)`],
                ["Contract", PASSPORT_CONTRACT],
                ["Owner", state.org.name],
                ["Custody", custody.holder],
                ["Location", custody.place],
                ["Custody state", custody.state],
                [
                  "Lien",
                  lien ? `${lien.id} · USD ${fmtNum(lien.amount)}` : "None",
                ],
                [
                  "Insurance",
                  cover.length
                    ? cover.map((p) => `${p.cover} (${p.id})`).join(", ")
                    : "None",
                ],
                ["Registered", lot.created],
              ].map(([k, v]) => (
                <div key={k} className="min-w-0">
                  <dt className="text-ink/60">{k}</dt>
                  <dd className="truncate font-medium" title={v}>
                    {v}
                  </dd>
                </div>
              ))}
            </dl>
          </Card>

          {/* Timeline */}
          <Card className="p-6">
            <CardTitle icon={IconRoute} iconClass="text-[#B5551A]">
              Signed event history
            </CardTitle>
            <p className="mt-1 text-xs text-ink/60">
              Append-only. Each event is signed by the party that performed it.
              Hashes are simulated until the contracts are connected.
            </p>
            <ol className="relative mt-5 space-y-5 border-l-2 border-gray-100 pl-6">
              {[...timeline].reverse().map((e) => (
                <li key={e.id} className="relative">
                  <span
                    className={`absolute top-1 -left-[31px] size-3 rounded-full ring-4 ring-white ${eventColor[e.kind] ?? "bg-gray-400"}`}
                  />
                  <p className="text-[15px] font-medium">{e.kind}</p>
                  <p className="text-sm text-ink/80">{e.detail}</p>
                  <p className="mt-0.5 text-xs text-ink/55">
                    {e.date} · {e.actor} ({e.role}) ·{" "}
                    <code title={e.hash}>
                      {e.hash.slice(0, 10)}…{e.hash.slice(-6)}
                    </code>
                  </p>
                </li>
              ))}
            </ol>
          </Card>

          {/* Custody */}
          <Card className="pt-6">
            <div className="flex items-center justify-between px-6">
              <CardTitle icon={IconTruck} iconClass="text-[#1F5B3A]">
                Custody handovers
              </CardTitle>
              {lot.status === "Verified" && (
                <button
                  disabled={!canAct}
                  onClick={() => setModal("dispatch")}
                  className="inline-flex items-center gap-1 text-sm font-medium text-accent hover:underline disabled:opacity-50"
                >
                  <IconPlus className="size-4" /> New handover
                </button>
              )}
            </div>
            <div className="mt-4 overflow-x-auto px-3 pb-4">
              {transfers.length === 0 ? (
                <Empty>
                  The lot is still at the mine site. Dispatch it when it leaves.
                </Empty>
              ) : (
                <table className="w-full text-left text-sm">
                  <thead className="bg-head">
                    <tr>
                      {[
                        "ID",
                        "To",
                        "Party",
                        "Seal",
                        "Status",
                        "Confirmations",
                      ].map((h) => (
                        <th
                          key={h}
                          className="px-3 py-3 text-[13px] font-medium"
                        >
                          {h}
                        </th>
                      ))}
                    </tr>
                  </thead>
                  <tbody>
                    {transfers.map((t) => {
                      const party = state.parties.find(
                        (p) => p.id === t.partyId,
                      );
                      return (
                        <tr
                          key={t.id}
                          className="border-b border-gray-100 last:border-0 align-top"
                        >
                          <td className="px-3 py-3">
                            {t.id}
                            <p className="text-xs text-ink/55">{t.created}</p>
                          </td>
                          <td className="px-3 py-3">
                            {t.to}
                            <p className="text-xs text-ink/55">from {t.from}</p>
                          </td>
                          <td className="px-3 py-3">
                            {party?.name}
                            <p className="text-xs text-ink/55">
                              {t.kind === "Transport"
                                ? "Transporter"
                                : "Warehouse"}
                            </p>
                          </td>
                          <td className="px-3 py-3">
                            {t.seal}
                            {t.vehicle && (
                              <p className="text-xs text-ink/55">{t.vehicle}</p>
                            )}
                          </td>
                          <td className="px-3 py-3">
                            <StatusBadge
                              tone={
                                t.status === "Awaiting handover"
                                  ? "pending"
                                  : t.status === "In transit"
                                    ? "blue"
                                    : "success"
                              }
                            >
                              {t.status}
                            </StatusBadge>
                          </td>
                          <td className="px-3 py-3">
                            {t.status === "Awaiting handover" ? (
                              <div className="space-y-1.5">
                                {t.senderConfirmed ? (
                                  <p className="flex items-center gap-1.5 text-[#1F5B3A]">
                                    <IconCircleCheck className="size-4" /> You
                                    confirmed
                                  </p>
                                ) : (
                                  <button
                                    disabled={!canAct}
                                    onClick={withConfirm(
                                      {
                                        title: "Confirm handover?",
                                        message: `Confirm that ${party?.name} has collected ${lot.id} with seal ${t.seal}. Custody moves once both sides confirm, and it can\'t be undone.`,
                                        confirmLabel: "Confirm handover",
                                      },
                                      () => (
                                        confirmTransfer(t.id, "sender"),
                                        toast("Handover confirmed on your side")
                                      ),
                                    )}
                                    className="rounded-full bg-[#1F5B3A] px-3 py-1.5 text-xs font-medium text-white disabled:opacity-50"
                                  >
                                    Confirm handover
                                  </button>
                                )}
                                {t.receiverConfirmed ? (
                                  <p className="flex items-center gap-1.5 text-[#1F5B3A]">
                                    <IconCircleCheck className="size-4" />{" "}
                                    {party?.name} confirmed
                                  </p>
                                ) : (
                                  <p className="text-xs text-ink/60">
                                    Waiting for {party?.name}.{" "}
                                    <button
                                      onClick={() => (
                                        confirmTransfer(t.id, "receiver"),
                                        toast(
                                          `${party?.name} confirmed (demo)`,
                                          "info",
                                        )
                                      )}
                                      className="text-accent underline"
                                    >
                                      Demo: confirm as them
                                    </button>
                                  </p>
                                )}
                              </div>
                            ) : t.status === "In transit" &&
                              !escrows.some((e) => e.status === "Locked") ? (
                              <button
                                onClick={() => (
                                  confirmTransfer(t.id, "delivered"),
                                  toast("Delivery confirmed (demo)", "info")
                                )}
                                className="text-xs text-accent underline"
                              >
                                Demo: confirm delivery
                              </button>
                            ) : (
                              <span className="text-ink/60">
                                Both sides confirmed
                              </span>
                            )}
                          </td>
                        </tr>
                      );
                    })}
                  </tbody>
                </table>
              )}
            </div>
          </Card>
        </div>

        <div className="space-y-5">
          {/* AI: listing readiness */}
          <Card className="p-6">
            <CardTitle icon={IconSparkles} iconClass="text-violet">
              Ready to list?
            </CardTitle>
            <ul className="mt-4 space-y-3 text-sm">
              {checklist.map((c) => (
                <li key={c.label} className="flex gap-3">
                  {c.ok ? (
                    <IconCircleCheck className="size-5 shrink-0 text-[#1F5B3A]" />
                  ) : (
                    <IconCircleDashed className="size-5 shrink-0 text-accent" />
                  )}
                  <div>
                    <p className={c.ok ? "" : "font-medium"}>{c.label}</p>
                    <p className="text-xs text-ink/60">
                      {c.hint}
                      {!c.ok && c.href && (
                        <>
                          {" "}
                          ·{" "}
                          <Link
                            href={c.href}
                            className="text-accent hover:underline"
                          >
                            Fix
                          </Link>
                        </>
                      )}
                    </p>
                  </div>
                </li>
              ))}
            </ul>
            <p
              className={`mt-4 rounded-xl px-3 py-2 text-sm ${ready ? "bg-success-soft text-[#1F5B3A]" : "bg-accent-soft text-accent"}`}
            >
              {ready
                ? "Everything is in place. You can list this lot."
                : `${checklist.filter((c) => !c.ok).length} item(s) left before listing.`}
            </p>
          </Card>

          {/* AI: price guidance */}
          <Card className="p-6">
            <CardTitle icon={IconSparkles} iconClass="text-violet">
              Price guidance
            </CardTitle>
            <p className="mt-4 font-heading text-2xl font-bold">
              ${fmtNum(price.low, price.low < 1000 ? 2 : 0)} – $
              {fmtNum(price.high, price.high < 1000 ? 2 : 0)}{" "}
              <span className="text-base font-medium text-ink/60">/ kg</span>
            </p>
            <p className="mt-1 text-sm">
              Lot value about <b>USD {fmtNum(lotValue(lot))}</b>
            </p>
            <p className="mt-2 text-xs text-ink/60">
              {price.basis} Indicative only.
            </p>
          </Card>

          {/* AI: anomalies */}
          <Card className="p-6">
            <CardTitle icon={IconAlertTriangle} iconClass="text-danger">
              Anomaly checks
            </CardTitle>
            {flags.length === 0 ? (
              <p className="mt-4 flex items-center gap-2 text-sm text-[#1F5B3A]">
                <IconCircleCheck className="size-5" /> No issues found
              </p>
            ) : (
              <ul className="mt-4 space-y-2 text-sm">
                {flags.map((f) => (
                  <li
                    key={f.text}
                    className={`rounded-xl px-3 py-2 ${f.severity === "high" ? "bg-danger-soft text-danger" : "bg-accent-soft text-[#9a4a12]"}`}
                  >
                    {f.text}
                  </li>
                ))}
              </ul>
            )}
          </Card>

          {/* Money */}
          <Card className="p-6">
            <CardTitle icon={IconLock} iconClass="text-violet">
              Escrow, loans & cover
            </CardTitle>
            <ul className="mt-4 space-y-3 text-sm">
              {escrows.map((e) => (
                <li key={e.id} className="rounded-xl bg-page px-3 py-2.5">
                  <p className="flex justify-between">
                    <b className="font-medium">
                      {e.id} · {e.buyer}
                    </b>
                    <StatusBadge
                      tone={e.status === "Locked" ? "info" : "success"}
                    >
                      {e.status}
                    </StatusBadge>
                  </p>
                  <p className="text-ink/70">
                    {e.currency} {fmtNum(e.amount)} · locked {e.locked}
                    {e.released ? ` · released ${e.released}` : ""}
                  </p>
                  {e.status === "Locked" && (
                    <button
                      onClick={withConfirm(
                        {
                          title: "Release escrow? (demo)",
                          message:
                            "This stands in for the buyer accepting delivery: escrow repays any loan, then pays you.",
                          confirmLabel: "Release",
                        },
                        () => (
                          releaseEscrow(e.id),
                          toast(
                            "Delivery accepted, escrow released (demo)",
                            "info",
                          )
                        ),
                      )}
                      className="mt-1 text-xs text-accent underline"
                    >
                      Demo: buyer accepts delivery
                    </button>
                  )}
                </li>
              ))}
              {loans.map((l) => (
                <li key={l.id} className="rounded-xl bg-page px-3 py-2.5">
                  <p className="flex justify-between">
                    <b className="font-medium">{l.id} · loan</b>
                    <StatusBadge
                      tone={statusTone(
                        l.status === "Active"
                          ? "processing"
                          : l.status === "Repaid"
                            ? "paid"
                            : l.status,
                      )}
                    >
                      {l.status}
                    </StatusBadge>
                  </p>
                  <p className="text-ink/70">
                    USD {fmtNum(l.amount)} · {l.ratePct}% ·{" "}
                    {state.parties.find((p) => p.id === l.financierId)?.name}
                  </p>
                </li>
              ))}
              {policies.map((p) => (
                <li key={p.id} className="rounded-xl bg-page px-3 py-2.5">
                  <p className="flex justify-between">
                    <b className="font-medium">
                      {p.id} · {p.cover}
                    </b>
                    <StatusBadge
                      tone={p.status === "Active" ? "success" : "pending"}
                    >
                      {p.status}
                    </StatusBadge>
                  </p>
                  <p className="text-ink/70">
                    USD {fmtNum(p.sumInsured)} · until {p.to}
                  </p>
                </li>
              ))}
              {escrows.length + loans.length + policies.length === 0 && (
                <li className="text-ink/60">
                  No escrow, loan or insurance on this lot yet.
                </li>
              )}
            </ul>
          </Card>

          {/* Documents & inspections */}
          <Card className="p-6">
            <CardTitle icon={IconShieldCheck}>
              Inspections & documents
            </CardTitle>
            <ul className="mt-4 space-y-2 text-sm">
              {inspections.map((i) => (
                <li key={i.id}>
                  <Link
                    href={`/miner/inspections/${i.id}`}
                    className="flex justify-between rounded-xl px-2 py-1.5 hover:bg-page"
                  >
                    <span>
                      {i.id} · {i.type}
                    </span>
                    <StatusBadge tone={statusTone(i.status)}>
                      {i.status}
                    </StatusBadge>
                  </Link>
                </li>
              ))}
              {docs.map((d) => (
                <li key={d.id}>
                  <Link
                    href="/miner/documents"
                    className="flex items-center gap-2 rounded-xl px-2 py-1.5 hover:bg-page"
                  >
                    <IconFileText className="size-4 text-accent" /> {d.name}
                  </Link>
                </li>
              ))}
              {inspections.length + docs.length === 0 && (
                <li className="text-ink/60">None yet.</li>
              )}
            </ul>
            <button type="button" onClick={() => openForm("document", lot.id)} className="mt-3 inline-flex items-center gap-1 text-sm font-medium text-accent hover:underline">
              <IconPlus className="size-4" /> Upload document
            </button>
          </Card>
        </div>
      </div>

      {modal === "dispatch" && (
        <DispatchModal lot={lot} onClose={() => setModal(null)} />
      )}
      <p className="pl-2 text-xs text-ink/50">
        Origin: {siteName(state, lot.siteId)} · licence {site?.licence}
      </p>
    </>
  );
}
