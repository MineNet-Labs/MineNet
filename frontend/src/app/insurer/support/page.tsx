"use client";

import { useState } from "react";
import { IconChevronDown, IconMail, IconMessage, IconPhone } from "@tabler/icons-react";
import { Card, CardTitle, PageHeader } from "@/components/ui";

const faqs = [
  { q: "Where do cover requests come from?", a: "Validated mining companies request cover for a specific lot. You see its passport (inspection, custody and history) before you quote." },
  { q: "How is the suggested premium calculated?", a: "Declared value × your monthly rate for that cover type × months. Change your rates in Settings." },
  { q: "Who gets paid on a claim if the lot has a loan?", a: "If a financier holds a lien on the lot, they are shown as loss payee on the policy." },
  { q: "Can I see where an insured lot is?", a: "Yes. Custody changes only when both sides confirm a handover, so the policy page always shows who holds the lot." },
];

export default function InsurerSupportPage() {
  const [open, setOpen] = useState<number | null>(0);
  return (
    <>
      <PageHeader title="Support" subtitle="Answers for insurers, or reach the MineNet team." />
      <div className="grid items-start gap-5 xl:grid-cols-[1fr_380px]">
        <Card className="p-5">
          <CardTitle icon={IconMessage}>Frequently asked questions</CardTitle>
          <ul className="mt-4 divide-y divide-gray-100">
            {faqs.map((f, i) => (
              <li key={f.q}>
                <button onClick={() => setOpen(open === i ? null : i)} aria-expanded={open === i} className="flex w-full items-center justify-between gap-4 py-4 text-left font-medium">
                  {f.q}
                  <IconChevronDown className={`size-5 shrink-0 transition-transform ${open === i ? "rotate-180" : ""}`} />
                </button>
                {open === i && <p className="pb-4 text-sm text-ink/75">{f.a}</p>}
              </li>
            ))}
          </ul>
        </Card>
        <Card className="space-y-4 p-5 text-sm">
          <CardTitle>Contact</CardTitle>
          <p className="flex items-center gap-3"><IconMail className="size-5 text-accent" /> support@minenet.rw</p>
          <p className="flex items-center gap-3"><IconPhone className="size-5 text-accent" /> +250 788 000 000</p>
        </Card>
      </div>
    </>
  );
}
