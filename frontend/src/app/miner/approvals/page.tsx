"use client";

import { useState } from "react";
import { IconCheck, IconChecklist } from "@tabler/icons-react";
import { Card, Empty, PageHeader, StatusBadge, toast, type BadgeTone } from "@/components/ui";
import { withConfirm } from "@/components/ui/Confirm";
import { Tabs } from "@/components/ui/Tabs";
import { decide, type Approval } from "@/lib/approvals";
import { siteName, useMe, useStore } from "@/lib/store";

const tone: Record<Approval["status"], BadgeTone> = { Pending: "pending", Approved: "success", Rejected: "danger" };

/** Owner: requests from site managers waiting for a decision. Site manager: their own requests. */
export default function ApprovalsPage() {
  const state = useStore((s) => s);
  const me = useMe();
  const owner = me.role === "Owner";
  const [tab, setTab] = useState("Pending");
  const rows = state.approvals.filter((a) => tab === "All" || a.status === tab);

  return (
    <>
      <PageHeader
        title={owner ? "Approvals" : "My Requests"}
        subtitle={
          owner
            ? "Site managers run their sites day to day. Hiring, new shafts, site documents and mineral handovers wait here until you approve them."
            : "Hiring, new shafts, site documents and mineral handovers need the owner's approval. They take effect once approved."
        }
      />
      <Card className="pt-5">
        <div className="border-b border-gray-100 px-6">
          <Tabs value={tab} onChange={setTab} items={["Pending", "Approved", "Rejected", "All"].map((k) => ({ key: k, label: k }))} />
        </div>
        <div className="px-3 py-4">
          {rows.length === 0 ? (
            <Empty>{tab === "Pending" ? "Nothing waiting for approval." : "No requests here."}</Empty>
          ) : (
            <table className="w-full text-left text-sm">
              <thead className="bg-head">
                <tr>{["Request", "What", "Site", "Requested by", "Status", ""].map((h) => <th key={h} className="px-3 py-3 text-[13px] font-medium">{h}</th>)}</tr>
              </thead>
              <tbody>
                {rows.map((a) => (
                  <tr key={a.id} className="border-b border-gray-100 last:border-0">
                    <td className="px-3 py-3 font-medium">{a.id}<span className="block text-xs font-normal text-ink/60">{a.requested}</span></td>
                    <td className="px-3"><b className="font-medium">{a.kind}</b><span className="block text-ink/70">{a.summary}</span></td>
                    <td className="px-3">{a.siteId ? siteName(state, a.siteId) : "—"}</td>
                    <td className="px-3">{a.requestedBy}</td>
                    <td className="px-3"><StatusBadge tone={tone[a.status]}>{a.status}</StatusBadge>{a.decided && <span className="block text-xs text-ink/60">{a.decided}</span>}</td>
                    <td className="px-3 text-right">
                      {owner && a.status === "Pending" && (
                        <span className="flex justify-end gap-2">
                          <button
                            onClick={withConfirm({ title: "Approve request?", message: `${a.summary}. It is added straight away.`, confirmLabel: "Approve" }, () => (decide(a, true), toast(`${a.id} approved`)))}
                            className="inline-flex items-center gap-1 rounded-full bg-[#1F5B3A] px-3 py-1.5 text-xs font-medium text-white"
                          >
                            <IconCheck className="size-3.5" /> Approve
                          </button>
                          <button
                            onClick={withConfirm({ title: "Reject request?", message: `${a.requestedBy} is told the request was rejected.`, confirmLabel: "Reject", tone: "danger" }, () => (decide(a, false), toast(`${a.id} rejected`, "info")))}
                            className="text-xs text-ink/60 underline"
                          >
                            Reject
                          </button>
                        </span>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </div>
      </Card>
      {owner && (
        <p className="flex items-center gap-2 pl-2 text-xs text-ink/60"><IconChecklist className="size-4" /> New requests also show in your notifications.</p>
      )}
    </>
  );
}
