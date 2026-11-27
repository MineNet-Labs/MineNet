"use client";

import { IconBuilding, IconDeviceFloppy, IconPercentage } from "@tabler/icons-react";
import { Card, CardTitle, Field, PageHeader, PrimaryButton, inputClass, toast } from "@/components/ui";
import { confirmAction } from "@/components/ui/Confirm";
import { useInsurer } from "@/components/insurer/common";
import type { Policy } from "@/lib/data";
import { update } from "@/lib/store";

const COVERS: Policy["cover"][] = ["Storage", "Transit", "Storage & transit"];

export default function InsurerSettingsPage() {
  const { state, me } = useInsurer();
  const rates = state.insurerRates[me.id] ?? { Storage: 0.004, Transit: 0.006, "Storage & transit": 0.009 };

  return (
    <>
      <PageHeader title="Settings" subtitle="Your company details and the rates used to suggest quotes." />
      <form
        className="grid items-start gap-5 xl:grid-cols-2"
        onSubmit={async (e) => {
          e.preventDefault();
          const v = Object.fromEntries(new FormData(e.currentTarget).entries()) as Record<string, string>;
          if (!(await confirmAction({ title: "Save new rates?", message: "New quotes are suggested with these rates. Quotes already sent don't change.", confirmLabel: "Save" }))) return;
          update((s) => ({
            insurerRates: { ...s.insurerRates, [me.id]: Object.fromEntries(COVERS.map((c) => [c, Number(v[c]) / 100])) as Record<Policy["cover"], number> },
            parties: s.parties.map((p) => (p.id === me.id ? { ...p, location: v.location } : p)),
          }));
          toast("Settings saved");
        }}
      >
        <Card className="p-6">
          <CardTitle icon={IconBuilding} iconClass="text-[#1F5B3A]">Company</CardTitle>
          <div className="mt-5 grid gap-4 sm:grid-cols-2">
            <Field label="Name"><input value={me.name} readOnly className={`${inputClass} bg-page`} /></Field>
            <Field label="Licence"><input value={`${me.regulator} ${me.licence}`} readOnly className={`${inputClass} bg-page`} /></Field>
            <Field label="Office location" className="sm:col-span-2"><input name="location" required defaultValue={me.location} className={inputClass} /></Field>
          </div>
          <p className="mt-3 text-xs text-ink/60">Name and licence come from your BNR validation.</p>
        </Card>
        <Card className="p-6">
          <CardTitle icon={IconPercentage} iconClass="text-accent">Monthly premium rates</CardTitle>
          <div className="mt-5 grid gap-4 sm:grid-cols-3">
            {COVERS.map((c) => (
              <Field key={c} label={`${c} (%)`}>
                <input name={c} type="number" step="0.01" min={0.01} max={10} required defaultValue={+(rates[c] * 100).toFixed(2)} className={inputClass} />
              </Field>
            ))}
          </div>
          <p className="mt-3 text-xs text-ink/60">Share of the insured value per month. Used as the starting point when you quote.</p>
        </Card>
        <div className="flex justify-end xl:col-span-2"><PrimaryButton icon={IconDeviceFloppy} type="submit">Save settings</PrimaryButton></div>
      </form>
    </>
  );
}
