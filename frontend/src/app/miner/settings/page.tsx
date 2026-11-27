"use client";

import Link from "next/link";
import { Select } from "@/components/ui/Select";
import { useState, useSyncExternalStore } from "react";
import { IconBell, IconBuildingBank, IconDeviceFloppy, IconLanguage, IconUser } from "@tabler/icons-react";
import { Card, CardTitle, Field, PageHeader, PrimaryButton, inputClass, toast } from "@/components/ui";
import type { NoticeKind } from "@/lib/data";
import { update, useStore } from "@/lib/store";

const PREFS_KEY = "minenet.settings.v1";
type Prefs = { language: string; email: boolean; sms: boolean; kinds: Record<NoticeKind, boolean> };
const DEFAULT_PREFS: Prefs = {
  language: "English",
  email: true,
  sms: true,
  kinds: { offer: true, custody: true, inspection: true, payment: true, finance: true, licence: true, alert: true },
};

let cached: Prefs | null = null;
const readPrefs = (): Prefs => {
  if (cached) return cached;
  try {
    cached = { ...DEFAULT_PREFS, ...JSON.parse(localStorage.getItem(PREFS_KEY) ?? "{}") };
  } catch {
    cached = DEFAULT_PREFS;
  }
  return cached!;
};
const noop = () => () => {};

const kindLabels: Record<NoticeKind, string> = {
  offer: "Offers and counter-offers",
  custody: "Custody handovers and deliveries",
  inspection: "Inspection updates",
  payment: "Payments and escrow",
  finance: "Loans and insurance",
  licence: "Licence and validation",
  alert: "Anomaly alerts",
};

export default function SettingsPage() {
  const org = useStore((s) => s.org);
  const saved = useSyncExternalStore(noop, readPrefs, () => DEFAULT_PREFS);
  const [prefs, setPrefs] = useState<Prefs | null>(null);
  const p = prefs ?? saved;
  const edit = (patch: Partial<Prefs>) => setPrefs({ ...p, ...patch });

  return (
    <>
      <PageHeader title="Settings" subtitle="Your profile, organisation details and how MineNet contacts you." />

      <form
        className="grid items-start gap-5 xl:grid-cols-2"
        onSubmit={(e) => {
          e.preventDefault();
          const v = Object.fromEntries(new FormData(e.currentTarget).entries()) as Record<string, string>;
          update((s) => ({ org: { ...s.org, contact: v.contact, email: v.email, phone: v.phone, address: v.address } }));
          localStorage.setItem(PREFS_KEY, JSON.stringify(p));
          cached = p;
          toast("Settings saved");
        }}
      >
        <Card className="p-6">
          <CardTitle icon={IconUser} iconClass="text-[#1F5B3A]">Profile</CardTitle>
          <div className="mt-5 grid gap-4 sm:grid-cols-2">
            <Field label="Full name"><input name="contact" required defaultValue={org.contact} className={inputClass} /></Field>
            <Field label="Role"><input value="Miner · organisation admin" readOnly className={`${inputClass} bg-page`} /></Field>
            <Field label="Email"><input name="email" type="email" required defaultValue={org.email} className={inputClass} /></Field>
            <Field label="Phone"><input name="phone" required defaultValue={org.phone} className={inputClass} /></Field>
            <Field label="Address" className="sm:col-span-2"><input name="address" required defaultValue={org.address} className={inputClass} /></Field>
          </div>
        </Card>

        <Card className="p-6">
          <CardTitle icon={IconBuildingBank} iconClass="text-[#B5551A]">Organisation</CardTitle>
          <p className="mt-1 text-xs text-ink/60">These details come from your RMB validation and can only be changed by a regulator.</p>
          <dl className="mt-5 grid grid-cols-2 gap-4 text-sm">
            {[
              ["Name", org.name],
              ["Type", org.kind],
              ["RDB registration", org.rdbNumber],
              ["Tax ID", org.tin],
              ["Mining licence", org.licence],
              ["Status", `${org.status} until ${org.validatedUntil}`],
            ].map(([k, v]) => (
              <div key={k}><dt className="text-ink/60">{k}</dt><dd className="font-medium">{v}</dd></div>
            ))}
          </dl>
          <Link href="/miner/licence" className="mt-4 inline-block text-sm font-medium text-accent hover:underline">Licence & Validation</Link>
        </Card>

        <Card className="p-6">
          <CardTitle icon={IconBell} iconClass="text-accent">Notifications</CardTitle>
          <div className="mt-5 flex gap-6 text-sm">
            <label className="flex items-center gap-2"><input type="checkbox" checked={p.email} onChange={(e) => edit({ email: e.target.checked })} className="size-4 accent-[#1F5B3A]" /> Email</label>
            <label className="flex items-center gap-2"><input type="checkbox" checked={p.sms} onChange={(e) => edit({ sms: e.target.checked })} className="size-4 accent-[#1F5B3A]" /> SMS</label>
          </div>
          <ul className="mt-4 divide-y divide-gray-100 text-sm">
            {(Object.keys(kindLabels) as NoticeKind[]).map((k) => (
              <li key={k} className="flex items-center justify-between py-2.5">
                {kindLabels[k]}
                <input type="checkbox" checked={p.kinds[k]} onChange={(e) => edit({ kinds: { ...p.kinds, [k]: e.target.checked } })} className="size-4 accent-[#1F5B3A]" aria-label={kindLabels[k]} />
              </li>
            ))}
          </ul>
        </Card>

        <Card className="p-6">
          <CardTitle icon={IconLanguage}>Language</CardTitle>
          <Field label="Interface language" className="mt-5">
            <Select value={p.language} onChange={(e) => edit({ language: e.target.value })} className={inputClass}>
              <option>English</option>
              <option>Kinyarwanda</option>
              <option>Français</option>
            </Select>
          </Field>
          <p className="mt-2 text-xs text-ink/60">Translations are added once the copy is final; the choice is saved now.</p>
        </Card>

        <div className="flex justify-end xl:col-span-2">
          <PrimaryButton icon={IconDeviceFloppy} type="submit">Save settings</PrimaryButton>
        </div>
      </form>
    </>
  );
}
