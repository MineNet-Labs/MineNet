"use client";

import { useState } from "react";
import { Select } from "@/components/ui/Select";
import { IconChevronDown, IconHeadphones, IconMail, IconMessage, IconPhone, IconUser, IconSend } from "@tabler/icons-react";
import { Card, CardTitle, Field, PageHeader, inputClass, toast } from "@/components/ui";

export type Faq = { q: string; a: string };

/** Support page shared by every portal: FAQs plus a message form. */
export function SupportView({ faqs, subtitle = "Answers to common questions, or reach the MineNet team directly." }: { faqs: Faq[]; subtitle?: string }) {
  const [open, setOpen] = useState<number | null>(0);
  const [sent, setSent] = useState(false);

  return (
    <>
      <PageHeader title="Support" subtitle={subtitle} />

      <div className="grid items-start gap-5 xl:grid-cols-[1fr_400px]">
        <Card className="p-5">
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
          <Card className="p-5">
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
