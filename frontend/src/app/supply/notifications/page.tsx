"use client";

import Link from "next/link";
import { IconBell, IconChecks } from "@tabler/icons-react";
import { Card, CardTitle, Empty, PageHeader, PrimaryButton, toast } from "@/components/ui";
import { noticeIcon } from "@/components/noticeIcon";
import { update, useStore } from "@/lib/store";
import { SUPPLY_AUDIENCE } from "@/lib/supply";

export default function SupplyNotificationsPage() {
  const all = useStore((s) => s.notices);
  const notices = all.filter((n) => n.audience === SUPPLY_AUDIENCE);
  const unread = notices.filter((n) => !n.read).length;
  const markAll = () => (update((s) => ({ notices: s.notices.map((n) => (n.audience === SUPPLY_AUDIENCE ? { ...n, read: true } : n)) })), toast("All marked as read", "info"));

  return (
    <>
      <PageHeader title="Notifications" subtitle="Delays, discrepancies and customs decisions that need you." actions={unread > 0 ? <PrimaryButton icon={IconChecks} onClick={markAll}>Mark all as read</PrimaryButton> : undefined} />
      <Card className="p-5">
        <CardTitle icon={IconBell} iconClass="text-accent">{unread ? `${unread} unread` : "All caught up"}</CardTitle>
        {notices.length === 0 ? (
          <div className="mt-4"><Empty>No notifications yet. Delays, discrepancies and customs requests will show here.</Empty></div>
        ) : (
          <ul className="mt-4 divide-y divide-gray-100">
            {notices.map((n) => {
              const Icon = noticeIcon[n.kind];
              return (
                <li key={n.id}>
                  <Link href={n.href} onClick={() => update((s) => ({ notices: s.notices.map((x) => (x.id === n.id ? { ...x, read: true } : x)) }))} className="flex items-center gap-3 py-3 hover:text-[#1F5B3A]">
                    <span className="grid size-9 shrink-0 place-items-center rounded-full bg-accent-soft"><Icon className="size-4 text-accent" /></span>
                    <span className={`flex-1 ${n.read ? "text-ink/70" : "font-medium"}`}>{n.text}</span>
                    <span className="text-xs text-ink/60">{n.date}</span>
                  </Link>
                </li>
              );
            })}
          </ul>
        )}
      </Card>
    </>
  );
}
