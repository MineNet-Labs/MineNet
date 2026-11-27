"use client";

import { isMinerNotice } from "@/lib/insurer";

import Link from "next/link";
import { useMemo, useState } from "react";
import { IconBell, IconChecks } from "@tabler/icons-react";
import { noticeIcon } from "@/components/noticeIcon";
import { Card, Empty, PageHeader, PrimaryButton, toast } from "@/components/ui";
import { Tabs } from "@/components/ui/Tabs";
import { update, useStore } from "@/lib/store";


export default function NotificationsPage() {
  const allNotices = useStore((s) => s.notices);
  const notices = useMemo(() => allNotices.filter(isMinerNotice), [allNotices]);
  const [tab, setTab] = useState("all");
  const rows = useMemo(() => notices.filter((n) => tab === "all" || (tab === "unread" ? !n.read : n.kind === tab)), [notices, tab]);
  const unread = notices.filter((n) => !n.read).length;
  const markAll = () => {
    update((s) => ({ notices: s.notices.map((n) => ({ ...n, read: true })) }));
    toast("All notifications marked as read", "info");
  };

  return (
    <>
      <PageHeader
        title="Notifications"
        subtitle="Updates on your lots, offers, custody, payments and licences."
        actions={<PrimaryButton icon={IconChecks} disabled={!unread} onClick={markAll} className="disabled:opacity-50">Mark all as read</PrimaryButton>}
      />
      <Card className="pt-5">
        <div className="overflow-x-auto border-b border-gray-100 px-6">
          <Tabs
            value={tab}
            onChange={setTab}
            items={[
              { key: "all", label: "All", count: notices.length },
              { key: "unread", label: "Unread", count: unread },
              { key: "offer", label: "Offers" },
              { key: "custody", label: "Custody" },
              { key: "inspection", label: "Inspections" },
              { key: "payment", label: "Payments" },
              { key: "finance", label: "Finance" },
              { key: "licence", label: "Licences" },
            ]}
          />
        </div>
        {rows.length === 0 ? (
          <div className="p-6"><Empty>Nothing here.</Empty></div>
        ) : (
          <ul className="divide-y divide-gray-100 px-3 py-2">
            {rows.map((n) => {
              const Icon = noticeIcon[n.kind] ?? IconBell;
              return (
                <li key={n.id}>
                  <Link
                    href={n.href}
                    onClick={() => update((s) => ({ notices: s.notices.map((x) => (x.id === n.id ? { ...x, read: true } : x)) }))}
                    className="flex items-center gap-4 rounded-xl px-3 py-3.5 hover:bg-page"
                  >
                    <span className="grid size-10 shrink-0 place-items-center rounded-full bg-accent-soft"><Icon className="size-5 text-accent" /></span>
                    <span className="flex-1">
                      <span className={`block text-[15px] ${n.read ? "text-ink/75" : "font-medium"}`}>{n.text}</span>
                      <span className="block text-xs text-ink/50">{n.date}</span>
                    </span>
                    {!n.read && <span className="size-2.5 rounded-full bg-accent" aria-label="Unread" />}
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
