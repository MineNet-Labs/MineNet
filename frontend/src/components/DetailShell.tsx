"use client";

import Link from "next/link";
import { IconArrowLeft } from "@tabler/icons-react";
import { Card } from "@/components/ui";

/** Back link + title row used by every detail page. */
export function DetailHeader({
  back,
  backLabel,
  title,
  subtitle,
  badge,
  actions,
}: {
  back: string;
  backLabel: string;
  title: React.ReactNode;
  subtitle?: React.ReactNode;
  badge?: React.ReactNode;
  actions?: React.ReactNode;
}) {
  return (
    <div className="flex flex-wrap items-start justify-between gap-4 pl-2">
      <div>
        <Link href={back} className="mb-4 inline-flex items-center gap-2 rounded-full border border-gray-200 bg-white px-5 py-2.5 text-[15px] font-medium text-ink shadow-sm hover:bg-page">
          <IconArrowLeft className="size-5" /> {backLabel}
        </Link>
        <h1 className="flex flex-wrap items-center gap-3">{title} {badge}</h1>
        {subtitle && <p className="mt-1 text-[17px] text-ink/80">{subtitle}</p>}
      </div>
      {actions && <div className="flex flex-wrap gap-2">{actions}</div>}
    </div>
  );
}

export function NotFound({ what, id, back, backLabel }: { what: string; id: string; back: string; backLabel: string }) {
  return (
    <Card className="p-10 text-center">
      <h2>{what} not found</h2>
      <p className="mt-2 text-ink/70">Nothing matches “{id}”.</p>
      <Link href={back} className="mt-4 inline-block font-medium text-accent hover:underline">Back to {backLabel}</Link>
    </Card>
  );
}

/** Key/value grid. */
export function Facts({ items, cols = 3 }: { items: [string, React.ReactNode][]; cols?: 2 | 3 | 4 }) {
  const c = { 2: "md:grid-cols-2", 3: "md:grid-cols-3", 4: "md:grid-cols-4" }[cols];
  return (
    <dl className={`grid grid-cols-2 gap-x-6 gap-y-4 text-sm ${c}`}>
      {items.map(([k, v]) => (
        <div key={k} className="min-w-0">
          <dt className="text-ink/60">{k}</dt>
          <dd className="font-medium break-words">{v}</dd>
        </div>
      ))}
    </dl>
  );
}

/** Suspense wrapper for client detail views that read the URL. */
export const detailFallback = <div className="h-64 animate-pulse rounded-[22px] bg-white" />;
