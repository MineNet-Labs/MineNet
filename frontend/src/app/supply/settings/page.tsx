"use client";

import { useState, useSyncExternalStore } from "react";
import { IconBell, IconDeviceFloppy, IconUser } from "@tabler/icons-react";
import { Card, CardTitle, Field, PageHeader, PrimaryButton, inputClass, toast } from "@/components/ui";
import { Select } from "@/components/ui/Select";
import { WAREHOUSES } from "@/lib/supply";

const KEY = "minenet.supply.settings.v1";
type Prefs = { name: string; email: string; phone: string; warehouse: string; delays: boolean; customs: boolean; digest: boolean };
const DEFAULTS: Prefs = { name: "Jean Uwimana", email: "jean@minenet-logistics.rw", phone: "+250 788 300 110", warehouse: WAREHOUSES[0], delays: true, customs: true, digest: false };
let cached: Prefs | null = null;
const read = (): Prefs => {
  if (cached) return cached;
  try {
    cached = { ...DEFAULTS, ...JSON.parse(localStorage.getItem(KEY) ?? "{}") };
  } catch {
    cached = DEFAULTS;
  }
  return cached!;
};
const noop = () => () => {};

export default function SupplySettingsPage() {
  const saved = useSyncExternalStore(noop, read, () => DEFAULTS);
  const [draft, setP] = useState<Prefs | null>(null);
  const p = draft ?? saved;
  const set = <K extends keyof Prefs>(k: K, v: Prefs[K]) => setP({ ...p, [k]: v });
  const toggles: [keyof Prefs, string][] = [["delays", "Shipment delays and discrepancies"], ["customs", "Customs decisions on export declarations"], ["digest", "Daily email summary"]];

  return (
    <>
      <PageHeader title="Settings" subtitle="Your profile, default warehouse and which alerts you receive." />
      <form
        className="grid items-start gap-5 xl:grid-cols-2"
        onSubmit={(e) => {
          e.preventDefault();
          localStorage.setItem(KEY, JSON.stringify(p));
          cached = p;
          toast("Settings saved");
        }}
      >
        <Card className="space-y-4 p-5">
          <CardTitle icon={IconUser}>Profile</CardTitle>
          <Field label="Full name"><input value={p.name} onChange={(e) => set("name", e.target.value)} required className={inputClass} /></Field>
          <Field label="Email"><input type="email" value={p.email} onChange={(e) => set("email", e.target.value)} required className={inputClass} /></Field>
          <Field label="Phone"><input value={p.phone} onChange={(e) => set("phone", e.target.value)} className={inputClass} /></Field>
          <Field label="Default receiving warehouse">
            <Select value={p.warehouse} onChange={(e) => set("warehouse", e.target.value)}>
              {WAREHOUSES.map((w) => <option key={w}>{w}</option>)}
            </Select>
          </Field>
        </Card>
        <Card className="space-y-4 p-5">
          <CardTitle icon={IconBell}>Alerts</CardTitle>
          {toggles.map(([k, label]) => (
            <label key={k} className="flex items-center justify-between rounded-xl bg-page px-4 py-3 text-[15px]">
              {label}
              <input type="checkbox" checked={p[k] as boolean} onChange={(e) => set(k, e.target.checked as never)} className="size-5 accent-[#1F5B3A]" />
            </label>
          ))}
          <PrimaryButton icon={IconDeviceFloppy} type="submit">Save settings</PrimaryButton>
        </Card>
      </form>
    </>
  );
}
