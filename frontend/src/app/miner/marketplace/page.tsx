"use client";

import { openForm } from "@/components/FormHost";

import Link from "next/link";
import { withConfirm } from "@/components/ui/Confirm";
import { useRouter } from "next/navigation";
import { acceptOffer } from "@/components/chain-forms";

import { useCallback, useMemo, useState } from "react";
import {
  IconBuildingStore,
  IconCirclePlus,
  IconEye,
  IconHeartHandshake,
  IconPencil,
  IconRosetteDiscountCheck,
  IconScale,
  IconSend,
  IconShieldExclamation,
  IconTrash,
  IconCheck,
  IconX,
  IconArrowBackUp,
} from "@tabler/icons-react";
import {
  Card,
  Empty,
  FilterSelect,
  Modal,
  PageHeader,
  PrimaryButton,
  RowMenu,
  StatCard,
  StatusBadge,
  statusTone,
  toast,
  inputClass,
  Field,
  SubmitButton,
  CancelButton,
  formValues,
} from "@/components/ui";
import { MakeOfferModal } from "@/components/forms";
import { fmtKg, type BuyerRequest, type Listing } from "@/lib/data";
import { update, useStore } from "@/lib/store";
import { useQueryParam } from "@/lib/useQueryParam";

const mineralDot: Record<string, string> = {
  Cassiterite: "bg-[#E8792B]",
  Coltan: "bg-[#8B7CF6]",
  Wolframite: "bg-[#3B82F6]",
  Gold: "bg-[#D4A017]",
  Tantalum: "bg-[#64748B]",
  Tin: "bg-[#1F5B3A]",
};

const QTY = { "Under 1 t": [0, 1], "1 – 3 t": [1, 3], "Over 3 t": [3, Infinity] } as const;
const GRADES = ["≥ 60%", "Below 60%"];

type Tab = "demand" | "listings" | "offers";

export default function MarketplacePage() {
  const router = useRouter();
  const requests = useStore((s) => s.requests);
  const listings = useStore((s) => s.listings);
  const offers = useStore((s) => s.offers);

  const [tab, setTab] = useState<Tab>("demand");
  const [mineral, setMineral] = useState("");
  const [location, setLocation] = useState("");
  const [grade, setGrade] = useState("");
  const [qty, setQty] = useState("");
  const [search, setSearch] = useState("");
  const [offerFor, setOfferFor] = useState<BuyerRequest | null>(null);
  const [details, setDetails] = useState<BuyerRequest | null>(null);
  const [editing, setEditing] = useState<Listing | null>(null);
  useQueryParam("q", useCallback((v: string) => setSearch(v), []));

  const minerals = useMemo(() => [...new Set(requests.map((r) => r.mineral))], [requests]);
  const countries = useMemo(() => [...new Set(requests.map((r) => r.country))], [requests]);

  const demand = useMemo(
    () =>
      requests.filter((r) => {
        const pct = Number(r.grade.match(/[\d.]+/)?.[0] ?? 0);
        const [lo, hi] = qty ? QTY[qty as keyof typeof QTY] : [0, Infinity];
        return (
          (!mineral || r.mineral === mineral) &&
          (!location || r.country === location) &&
          (!grade || (grade === "≥ 60%" ? pct >= 60 : pct < 60)) &&
          r.remainingT >= lo &&
          r.remainingT < hi &&
          (!search || `${r.buyer} ${r.mineral} ${r.city}`.toLowerCase().includes(search.toLowerCase()))
        );
      }),
    [requests, mineral, location, grade, qty, search],
  );

  const totalDemand = requests.reduce((t, r) => t + r.remainingT, 0);
  const activeOffers = offers.filter((o) => o.status === "Sent" || o.status === "Countered");
  const countered = offers.filter((o) => o.status === "Countered").length;
  const accepted = offers.filter((o) => o.status === "Accepted").length;

  const tabs: { key: Tab; label: string; count: number }[] = [
    { key: "demand", label: "Buyer Demand", count: requests.length },
    { key: "listings", label: "My Listings", count: listings.filter((l) => l.status === "Active").length },
    { key: "offers", label: "My Offers", count: offers.length },
  ];

  const reqById = (id: string) => requests.find((r) => r.id === id);

  return (
    <>
      <PageHeader
        title="Marketplace"
        subtitle="Discover mineral demand and connect with verified buyers."
        actions={
          <PrimaryButton icon={IconCirclePlus} className="rounded-full" onClick={() => openForm("sell")}>
            Sell on Marketplace
          </PrimaryButton>
        }
      />

      <div className="grid grid-cols-2 gap-5 xl:grid-cols-4">
        <StatCard icon={IconBuildingStore} tone="orange" label="Open Buyer Requests" value={requests.length} delta="+10" spark={[3, 4, 3.5, 5, 4.5, 6, 9]} />
        <StatCard icon={IconScale} tone="violet" label="Total Mineral Demand" value={`${totalDemand.toFixed(1)} t`} delta="+9%" spark={[3, 4, 3.5, 5, 5.5, 6.5, 8]} />
        <StatCard icon={IconSend} tone="orange" label="Active Offers" value={activeOffers.length} delta={`${countered} countered`} spark={[3, 4, 3, 5, 4, 4.5, 4]} />
        <StatCard icon={IconHeartHandshake} tone="green" label="Accepted Offers" value={accepted} delta="+1" spark={[3, 3, 4, 4, 5, 5, 8]} />
      </div>

      <Card className="pt-5">
        <div className="flex items-center justify-between border-b border-gray-100 px-5">
          <div className="flex gap-7">
            {tabs.map((t) => (
              <button
                key={t.key}
                onClick={() => setTab(t.key)}
                className={`-mb-px flex items-center gap-2 border-b-2 pb-3 text-[17px] whitespace-nowrap ${
                  tab === t.key ? "border-accent font-semibold text-accent" : "border-transparent text-ink/80 hover:text-ink"
                }`}
              >
                {t.key === "demand" && <IconBuildingStore className="size-5" />}
                {t.label}
               
              </button>
            ))}
          </div>
          <p className="pb-3 text-sm text-ink/60">Updated Aug 29, 2025 · 09:12</p>
        </div>

        {tab === "demand" && (
          <>
            <div className="mt-4 flex flex-wrap items-center gap-3 px-5">
              <FilterSelect label="All minerals" options={minerals} value={mineral} onChange={setMineral} />
              <FilterSelect label="All locations" options={countries} value={location} onChange={setLocation} />
              <FilterSelect label="Any grade" options={GRADES} value={grade} onChange={setGrade} />
              <FilterSelect label="Any quantity" options={Object.keys(QTY)} value={qty} onChange={setQty} />
              {search && (
                <button onClick={() => setSearch("")} className="inline-flex items-center gap-1 rounded-full bg-page px-3 py-1.5 text-sm">
                  “{search}” <IconX className="size-3.5" />
                </button>
              )}
            </div>
            <div className="mt-5 overflow-x-auto px-2 pb-3">
              {demand.length === 0 ? (
                <Empty>No buyer requests match these filters.</Empty>
              ) : (
                <table className="w-full min-w-[1000px] text-left text-sm">
                  <thead className="bg-head">
                    <tr>
                      {["Buyer", "Mineral", "Remaining / Required", "Min. grade", "Destination", "Deadline"].map((h) => (
                        <th key={h} className="px-3 py-3.5 text-[13px] font-medium">{h}</th>
                      ))}
                      <th className="px-3 text-right text-[13px] font-medium">Actions</th>
                    </tr>
                  </thead>
                  <tbody>
                    {demand.map((r) => {
                      const pct = Math.round(((r.requiredT - r.remainingT) / r.requiredT) * 100);
                      return (
                        <tr key={r.id} className="border-b border-gray-100">
                          <td className="px-3 py-3.5">
                            <p className="flex items-center gap-1.5 font-semibold">
                              {r.buyer}
                              {r.verified ? (
                                <IconRosetteDiscountCheck className="size-[18px] text-[#1F5B3A]" aria-label="Verified buyer" />
                              ) : (
                                <IconShieldExclamation className="size-[18px] text-accent" aria-label="Verification pending" />
                              )}
                            </p>
                            <p className="text-xs text-ink/60">{r.id} · {r.offers} offers</p>
                          </td>
                          <td className="px-3">
                            <span className="flex items-center gap-2"><i className={`size-2 rounded-full ${mineralDot[r.mineral]}`} />{r.mineral}</span>
                          </td>
                          <td className="px-3">
                            <p><b className="font-semibold">{fmtKg(r.remainingT * 1000)}</b> <span className="text-ink/60">/ {fmtKg(r.requiredT * 1000)}</span></p>
                            <div className="mt-1 h-1 w-24 rounded-full bg-gray-100" title={`${pct}% filled`}>
                              <div className="h-full rounded-full bg-[#1F5B3A]" style={{ width: `${Math.max(pct, 0)}%` }} />
                            </div>
                          </td>
                          <td className="px-3 text-ink/80">{r.grade}</td>
                          <td className="px-3"><p>{r.city}</p><p className="text-xs text-ink/60">{r.country}</p></td>
                          <td className="px-3">
                            <p>{r.deadline}</p>
                            <p className={`text-xs ${r.inDays <= 14 ? "text-accent" : "text-ink/60"}`}>in {r.inDays} days</p>
                          </td>
                          <td className="px-3">
                            <span className="flex items-center justify-end gap-4">
                              <Link href={`/miner/marketplace/requests/${r.id}`} className="flex items-center gap-1.5 text-ink/80 hover:text-ink">
                                <IconEye className="size-[18px]" /> View Details
                              </Link>
                              <button onClick={() => setOfferFor(r)} className="rounded-full bg-[#1F5B3A] px-4 py-2 font-medium text-white hover:bg-primary">
                                Make Offer
                              </button>
                            </span>
                          </td>
                        </tr>
                      );
                    })}
                  </tbody>
                </table>
              )}
            </div>
          </>
        )}

        {tab === "listings" && (
          <div className="mt-4 overflow-x-auto px-2 pb-3">
            {listings.length === 0 ? (
              <Empty>
                You have no listings yet.{" "}
                <button onClick={() => openForm("sell")} className="font-medium text-accent hover:underline">Sell a verified lot</button>
              </Empty>
            ) : (
              <table className="w-full min-w-[900px] text-left text-sm">
                <thead className="bg-head">
                  <tr>
                    {["Listing", "Lot", "Mineral", "Quantity", "Asking price", "Location", "Offers", "Posted", "Status", ""].map((h, i) => (
                      <th key={i} className="px-3 py-3.5 text-[13px] font-medium">{h}</th>
                    ))}
                  </tr>
                </thead>
                <tbody>
                  {listings.map((l) => (
                    <tr key={l.id} className="border-b border-gray-100">
                      <td className="px-3 py-3.5 font-semibold">{l.id}</td>
                      <td className="px-3">{l.lotId}</td>
                      <td className="px-3"><span className="flex items-center gap-2"><i className={`size-2 rounded-full ${mineralDot[l.mineral] ?? "bg-gray-400"}`} />{l.mineral}</span></td>
                      <td className="px-3">{fmtKg(l.quantityKg)}</td>
                      <td className="px-3 font-medium">{l.currency === "USD" ? "$" : "RWF "}{l.pricePerKg}/kg</td>
                      <td className="px-3">{l.location}</td>
                      <td className="px-3">{l.offers}</td>
                      <td className="px-3 text-ink/70">{l.posted}</td>
                      <td className="px-3"><StatusBadge tone={statusTone(l.status)}>{l.status}</StatusBadge></td>
                      <td className="px-3 text-right">
                        {l.status === "Active" && (
                          <RowMenu
                            items={[
                              { label: "Edit price / quantity", icon: IconPencil, onClick: () => setEditing(l) },
                              {
                                label: "Withdraw listing",
                                icon: IconTrash,
                                danger: true,
                                onClick: withConfirm(
                                  { title: "Withdraw listing?", message: `Buyers will no longer see ${l.lotId} on the marketplace.`, confirmLabel: "Withdraw", tone: "danger" },
                                  () => {
                                    update((s) => ({ listings: s.listings.map((x) => (x.id === l.id ? { ...x, status: "Withdrawn" } : x)) }));
                                    toast(`Listing ${l.id} withdrawn`, "info");
                                  },
                                ),
                              },
                            ]}
                          />
                        )}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            )}
          </div>
        )}

        {tab === "offers" && (
          <div className="mt-4 overflow-x-auto px-2 pb-3">
            {offers.length === 0 ? (
              <Empty>You haven&apos;t sent any offers yet. Open Buyer Demand and choose “Make Offer”.</Empty>
            ) : (
              <table className="w-full min-w-[900px] text-left text-sm">
                <thead className="bg-head">
                  <tr>
                    {["Offer", "Buyer", "Mineral", "Your lot", "Quantity", "Price", "Sent", "Status", ""].map((h, i) => (
                      <th key={i} className="px-3 py-3.5 text-[13px] font-medium">{h}</th>
                    ))}
                  </tr>
                </thead>
                <tbody>
                  {offers.map((o) => {
                    const r = reqById(o.requestId);
                    return (
                      <tr key={o.id} className="border-b border-gray-100">
                        <td className="px-3 py-3.5 font-semibold"><Link href={`/miner/marketplace/offers/${o.id}`} className="hover:text-[#1F5B3A] hover:underline">{o.id}</Link></td>
                        <td className="px-3">{r?.buyer ?? o.requestId}</td>
                        <td className="px-3">{r?.mineral}</td>
                        <td className="px-3"><Link href={`/miner/mineral-lots/${o.lotId}`} className="hover:underline">{o.lotId}</Link></td>
                        <td className="px-3">{fmtKg(o.quantityKg)}</td>
                        <td className="px-3">${o.pricePerKg}/kg</td>
                        <td className="px-3 text-ink/70">{o.sent}</td>
                        <td className="px-3"><StatusBadge tone={statusTone(o.status)}>{o.status === "Countered" ? "Countered – reply needed" : o.status}</StatusBadge></td>
                        <td className="px-3 text-right">
                          {o.status === "Countered" && (
                            <RowMenu
                              items={[
                                {
                                  label: "Accept counter-offer",
                                  icon: IconCheck,
                                  onClick: withConfirm(
                                    { title: "Accept counter-offer?", message: `This agrees the sale of ${o.lotId} to ${r?.buyer}. Their payment is locked in escrow and the lot is marked sold.`, confirmLabel: "Accept and sell" },
                                    () => {
                                      acceptOffer(o.id, "You");
                                      toast(`Counter-offer from ${r?.buyer} accepted: payment locked in escrow`);
                                    },
                                  ),
                                },
                                { label: "Open negotiation", icon: IconEye, onClick: () => router.push(`/miner/marketplace/offers/${o.id}`) },
                                {
                                  label: "Decline",
                                  icon: IconArrowBackUp,
                                  danger: true,
                                  onClick: () => {
                                    update((s) => ({ offers: s.offers.map((x) => (x.id === o.id ? { ...x, status: "Declined" } : x)) }));
                                    toast("Counter-offer declined", "info");
                                  },
                                },
                              ]}
                            />
                          )}
                          {o.status === "Sent" && (
                            <RowMenu
                              items={[
                                {
                                  label: "Withdraw offer",
                                  icon: IconTrash,
                                  danger: true,
                                  onClick: () => {
                                    update((s) => ({ offers: s.offers.filter((x) => x.id !== o.id) }));
                                    toast(`Offer ${o.id} withdrawn`, "info");
                                  },
                                },
                              ]}
                            />
                          )}
                        </td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            )}
          </div>
        )}
      </Card>

      {offerFor && <MakeOfferModal request={offerFor} onClose={() => setOfferFor(null)} />}
      {details && (
        <Modal
          title={details.buyer}
          subtitle={`${details.id} · ${details.verified ? "Verified buyer" : "Verification pending"}`}
          onClose={() => setDetails(null)}
          footer={
            <>
              <CancelButton onClick={() => setDetails(null)} />
              <button
                onClick={() => (setOfferFor(details), setDetails(null))}
                className="rounded-full bg-[#1F5B3A] px-6 py-3 text-[15px] font-medium text-white hover:bg-primary"
              >
                Make Offer
              </button>
            </>
          }
        >
          <dl className="grid grid-cols-2 gap-4 text-sm">
            {[
              ["Mineral", details.mineral],
              ["Minimum grade", details.grade],
              ["Still needed", `${fmtKg(details.remainingT * 1000)} of ${fmtKg(details.requiredT * 1000)}`],
              ["Indicative price", `$${details.pricePerKg}/kg`],
              ["Destination", `${details.city}, ${details.country}`],
              ["Deadline", `${details.deadline} (in ${details.inDays} days)`],
              ["Offers received", String(details.offers)],
            ].map(([k, v]) => (
              <div key={k}><dt className="text-ink/60">{k}</dt><dd className="font-medium">{v}</dd></div>
            ))}
          </dl>
          <p className="mt-5 rounded-xl bg-page px-4 py-3 text-sm">{details.notes}</p>
        </Modal>
      )}
      {editing && (
        <Modal
          title={`Edit listing ${editing.id}`}
          onClose={() => setEditing(null)}
          footer={<><CancelButton onClick={() => setEditing(null)} /><SubmitButton form="edit-listing">Save</SubmitButton></>}
        >
          <form
            id="edit-listing"
            className="grid grid-cols-2 gap-4"
            onSubmit={(e) => {
              const v = formValues(e);
              update((s) => ({
                listings: s.listings.map((x) => (x.id === editing.id ? { ...x, quantityKg: Number(v.quantity), pricePerKg: Number(v.price) } : x)),
              }));
              toast(`Listing ${editing.id} updated`);
              setEditing(null);
            }}
          >
            <Field label="Quantity (kg)"><input name="quantity" type="number" min={1} required defaultValue={editing.quantityKg} className={inputClass} /></Field>
            <Field label={`Price per kg (${editing.currency})`}><input name="price" type="number" min={0.01} step="0.01" required defaultValue={editing.pricePerKg} className={inputClass} /></Field>
          </form>
        </Modal>
      )}

    </>
  );
}
