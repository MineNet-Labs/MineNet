"use client";

import Link from "next/link";
import { IconChecks } from "@tabler/icons-react";
import { Card, Empty, PageHeader, PrimaryButton, toast } from "@/components/ui";
import { noticeIcon } from "@/components/noticeIcon";
import { useInsurer } from "@/components/insurer/common";
import { insurerAudience } from "@/lib/insurer";
import { update } from "@/lib/store";

export default function InsurerNotificationsPage() {
  const { me, notices } = useInsurer();
  const unread = notices.filter((n) => !n.read).length;
  return (
    <>
      <PageHeader
        title="Notifications"
        subtitle="New cover requests and claims from your clients."
        actions={
          <PrimaryButton
            icon={IconChecks}
            disabled={!unread}
            onClick={() => {
              update((s) => ({ notices: s.notices.map((n) => (n.audience === insurerAudience(me.id) ? { ...n, read: true } : n)) }));
              toast("All marked as read", "info");
            }}
            className="disabled:opacity-50"
          >
            Mark all as read
          </PrimaryButton>
        }
      />
      <Card className="px-3 py-2">
        {notices.length === 0 ? (
          <div className="p-4"><Empty>No notifications yet.</Empty></div>
        ) : (
          <ul className="divide-y divide-gray-100">
            {notices.map((n) => {
              const Icon = noticeIcon[n.kind];
              return (
                <li key={n.id}>
                  <Link href={n.href} onClick={() => update((s) => ({ notices: s.notices.map((x) => (x.id === n.id ? { ...x, read: true } : x)) }))} className="flex items-center gap-4 rounded-xl px-3 py-3.5 hover:bg-page">
                    <span className="grid size-10 place-items-center rounded-full bg-accent-soft"><Icon className="size-5 text-accent" /></span>
                    <span className="flex-1"><span className={`block ${n.read ? "text-ink/75" : "font-medium"}`}>{n.text}</span><span className="block text-xs text-ink/50">{n.date}</span></span>
                    {!n.read && <span className="size-2.5 rounded-full bg-accent" />}
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
