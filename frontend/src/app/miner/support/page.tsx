"use client";

import { useState } from "react";
import { Select } from "@/components/ui/Select";
import { IconChevronDown, IconHeadphones, IconMail, IconMessage, IconPhone, IconUser, IconSend } from "@tabler/icons-react";
import { Card, CardTitle, Field, PageHeader, inputClass, toast } from "@/components/ui";

const faqs = [
  { q: "How do I get a mineral lot verified?", a: "Register the lot under Mineral Lots, then request an inspection from Inspections. Once the inspector attests the grade, the lot becomes Verified and can be sold on the Marketplace." },
  { q: "Why can't I list a lot on the Marketplace?", a: "Only Verified lots can be listed. Pending lots need a completed inspection first, and rejected lots must be re-inspected." },
  { q: "How do workers sign in?", a: "Each worker gets a QR access code linked to their site. Use “Send QR access code” in the Workers page for anyone still in setup." },
  { q: "What happens when a licence is about to expire?", a: "You'll see a reminder on the Overview and in Documents & Licences 60 days before expiry. Use “Request renewal” to notify the regulator." },
  { q: "Where does my data go?", a: "Until the MineNet backend is connected, everything you add is saved in this browser. Use “Reset demo data” in the account menu to start over." },
];

export default function SupportPage() {
  const [open, setOpen] = useState<number | null>(0);
  const [sent, setSent] = useState(false);

  return (
    <>
      <PageHeader title="Support" subtitle="Answers to common questions, or reach the MineNet team directly." />

      <div className="grid items-start gap-5 xl:grid-cols-[1fr_400px]">
        <Card className="p-6">
          <CardTitle icon={IconMessage}>Frequently asked questions</CardTitle>
          <ul className="mt-4 divide-y divide-gray-100">
            {faqs.map((f, i) => (
              <li key={f.q}>
                <button onClick={() => setOpen(open === i ? null : i)} aria-expanded={open === i} className="flex w-full items-center justify-between gap-4 py-4 text-left text-[15px] font-medium">
                  {f.q}
                  <IconChevronDown className={`size-5 shrink-0 transition-transform ${open === i ? "rotate-180" : ""}`} />
                </button>
                {open === i && <p className="pb-4 text-sm leading-relaxed text-ink/75">{f.a}</p>}
              </li>
            ))}
          </ul>
        </Card>

        <div className="space-y-5">
          <Card className="p-6">
            <CardTitle icon={IconHeadphones}>Contact support</CardTitle>
            {sent ? (
              <p className="mt-4 rounded-xl bg-primary-soft px-4 py-3 text-sm text-[#1F5B3A]">
                Thanks — your message was sent. We usually reply within one working day.
              </p>
            ) : (
              <form
                className="mt-4 space-y-4"
                onSubmit={(e) => {
                  e.preventDefault();
                  setSent(true);
                  toast("Support request sent");
                }}
              >
                <Field label="Topic">
                  <Select required defaultValue="" className={inputClass}>
                    <option value="" disabled>Select a topic</option>
                    <option>Lots & inspections</option>
                    <option>Marketplace & offers</option>
                    <option>Payments</option>
                    <option>Workers & access</option>
                    <option>Something else</option>
                  </Select>
                </Field>
                <Field label="Message">
                  <textarea required rows={4} className="w-full resize-none rounded-xl border border-gray-200 px-4 py-3 text-sm outline-none focus:border-[#1F5B3A]" />
                </Field>
                <button type="submit" className="flex w-full items-center justify-center gap-2 rounded-full bg-[#1F5B3A] py-3 text-[15px] font-medium text-white hover:bg-primary">
                  <IconSend className="size-4" /> Send message
                </button>
              </form>
            )}
            <div className="mt-5 space-y-2 border-t border-gray-100 pt-4 text-sm">
              <a href="mailto:help@minenet.rw" className="flex items-center gap-2 hover:text-[#1F5B3A]"><IconMail className="size-4" /> help@minenet.rw</a>
              <a href="tel:+250788000000" className="flex items-center gap-2 hover:text-[#1F5B3A]"><IconPhone className="size-4" /> +250 788 000 000</a>
            </div>
          </Card>

          <Card id="account" className="p-6">
            <CardTitle icon={IconUser}>My account</CardTitle>
            <dl className="mt-4 space-y-3 text-sm">
              <div className="flex justify-between"><dt className="text-ink/60">Name</dt><dd className="font-medium">Jean Uwimana</dd></div>
              <div className="flex justify-between"><dt className="text-ink/60">Role</dt><dd className="font-medium">Miner</dd></div>
              <div className="flex justify-between"><dt className="text-ink/60">Organisation</dt><dd className="font-medium">Kigali Gold Mine</dd></div>
              <div className="flex justify-between"><dt className="text-ink/60">Mining licence</dt><dd className="font-medium">ML-2025-081</dd></div>
            </dl>
          </Card>
        </div>
      </div>
    </>
  );
}
