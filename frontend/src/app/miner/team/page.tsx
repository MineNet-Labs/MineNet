"use client";

import Link from "next/link";
import { useState } from "react";
import { IconCopy, IconMailForward, IconPlayerPause, IconPlayerPlay, IconSend, IconTrash, IconUserPlus, IconUsersGroup } from "@tabler/icons-react";
import { Card, CardTitle, Field, Initials, PageHeader, RowMenu, StatusBadge, inputClass, toast, type BadgeTone } from "@/components/ui";
import { Select } from "@/components/ui/Select";
import { withConfirm, confirmAction } from "@/components/ui/Confirm";
import { today } from "@/lib/data";
import { ROLE_INFO, ACCESS, type Member, type MemberStatus, type Role } from "@/lib/roles";
import { getState, nextId, update, useStore } from "@/lib/store";

const statusTone: Record<MemberStatus, BadgeTone> = { Active: "success", Invited: "pending", Disabled: "neutral" };
const inviteLink = (m: Member) => (typeof window === "undefined" ? "" : `${window.location.origin}/invite/${m.token}`);

export default function TeamPage() {
  const members = useStore((s) => s.members);
  const sites = useStore((s) => s.sites);
  const org = useStore((s) => s.org);
  const [role, setRole] = useState<Role>("Site manager");
  const [picked, setPicked] = useState<string[]>([]);
  const taken = new Set(members.filter((m) => m.role === "Site manager" && m.status !== "Disabled").flatMap((m) => m.siteIds));
  const freeSites = sites.filter((s) => !taken.has(s.id));

  const setMember = (id: string, patch: Partial<Member>, msg: string) => {
    update((s) => ({ members: s.members.map((m) => (m.id === id ? { ...m, ...patch } : m)) }));
    toast(msg, "info");
  };
  const copy = (m: Member) => {
    navigator.clipboard?.writeText(inviteLink(m));
    toast("Invite link copied", "info");
  };

  return (
    <>
      <PageHeader title="Team" subtitle="Give each site its own manager and invite HR by email. Managers run their site and send hiring, new shafts, site documents and handovers to you for approval." />

      <div className="grid items-start gap-5 xl:grid-cols-[1fr_400px]">
        <Card className="pt-6">
          <div className="px-6"><CardTitle icon={IconUsersGroup} iconClass="text-[#1F5B3A]">Members</CardTitle></div>
          <div className="mt-4 overflow-x-auto px-3 pb-4">
            <table className="w-full text-left text-sm">
              <thead className="bg-head">
                <tr>{["Member", "Role", "Sites", "Status", "Invited", ""].map((h) => <th key={h} className="px-3 py-3 text-[13px] font-medium">{h}</th>)}</tr>
              </thead>
              <tbody>
                {members.map((m) => (
                  <tr key={m.id} className="border-b border-gray-100 last:border-0">
                    <td className="px-3 py-3">
                      <span className="flex items-center gap-3"><Initials name={m.name} className="size-9 text-xs" /><span><b className="font-medium">{m.name}</b><span className="block text-xs text-ink/60">{m.email}</span></span></span>
                    </td>
                    <td className="px-3">{m.role}</td>
                    <td className="px-3">{m.role === "Site manager" ? m.siteIds.map((id) => sites.find((s) => s.id === id)?.name ?? id).join(", ") || "None" : m.role === "HR" ? "People, all sites" : "All"}</td>
                    <td className="px-3"><StatusBadge tone={statusTone[m.status]}>{m.status}</StatusBadge></td>
                    <td className="px-3 text-ink/70">{m.invited}</td>
                    <td className="px-3 text-right">
                      {m.role !== "Owner" && (
                        <RowMenu
                          items={[
                            ...(m.status === "Invited"
                              ? [
                                  { label: "Copy invite link", icon: IconCopy, onClick: () => copy(m) },
                                  { label: "Resend invite", icon: IconMailForward, onClick: () => setMember(m.id, { invited: today() }, `Invite resent to ${m.email}`) },
                                ]
                              : []),
                            m.status === "Disabled"
                              ? { label: "Re-enable", icon: IconPlayerPlay, onClick: () => setMember(m.id, { status: "Active" }, `${m.name} can sign in again`) }
                              : {
                                  label: "Disable access",
                                  icon: IconPlayerPause,
                                  danger: true,
                                  onClick: withConfirm({ title: "Disable access?", message: `${m.name} won't be able to sign in until you re-enable them.`, confirmLabel: "Disable", tone: "danger" }, () =>
                                    setMember(m.id, { status: "Disabled" }, `${m.name} disabled`),
                                  ),
                                },
                            {
                              label: "Remove",
                              icon: IconTrash,
                              danger: true,
                              onClick: withConfirm({ title: "Remove member?", message: `${m.name} is removed from ${org.name}.`, confirmLabel: "Remove", tone: "danger" }, () => {
                                update((s) => ({ members: s.members.filter((x) => x.id !== m.id) }));
                                toast(`${m.name} removed`, "info");
                              }),
                            },
                          ]}
                        />
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </Card>

        <Card className="p-6">
          <CardTitle icon={IconUserPlus} iconClass="text-[#B5551A]">Invite a member</CardTitle>
          <form
            className="mt-5 space-y-4"
            onSubmit={async (e) => {
              e.preventDefault();
              const form = e.currentTarget;
              const v = Object.fromEntries(new FormData(form).entries()) as Record<string, string>;
              if (role === "Site manager" && picked.length === 0) return toast("Pick the site this manager runs", "error");
              if (getState().members.some((m) => m.email.toLowerCase() === v.email.toLowerCase())) return toast("That email is already on the team", "error");
              const ok = await confirmAction({ title: "Send invitation?", message: `${v.name} (${v.email}) is invited as ${role.toLowerCase()} of ${org.name}.`, confirmLabel: "Send invite" });
              if (!ok) return;
              const id = nextId(getState().members.map((m) => m.id), "M-", 3);
              const member: Member = { id, name: v.name, email: v.email, role, siteIds: role === "Site manager" ? picked : [], status: "Invited", invited: today(), token: `t-${Math.random().toString(36).slice(2, 10)}` };
              update((s) => ({ members: [...s.members, member], sites: role === "Site manager" ? s.sites.map((x) => (x.id === picked[0] ? { ...x, manager: v.name } : x)) : s.sites }));
              toast(`Invitation for ${v.email} created`);
              form.reset();
              setPicked([]);
            }}
          >
            <Field label="Full name"><input name="name" required className={inputClass} /></Field>
            <Field label="Email"><input name="email" type="email" required className={inputClass} placeholder="name@company.rw" /></Field>
            <Field label="Role">
              <Select value={role} onChange={(e) => setRole(e.target.value as Role)}>
                <option value="Site manager">Site manager</option>
                <option value="HR">HR</option>
              </Select>
            </Field>
            <p className="rounded-xl bg-page px-3 py-2 text-xs text-ink/70">{ROLE_INFO[role]}</p>
            {role === "Site manager" && (
              <Field label="Site they manage" hint="Each site has one manager, who reports to you.">
                <Select value={picked[0] ?? ""} onChange={(e) => setPicked([e.target.value])}>
                  <option value="" disabled>{freeSites.length ? "Select site" : "Every site already has a manager"}</option>
                  {freeSites.map((s) => <option key={s.id} value={s.id}>{s.name}</option>)}
                </Select>
              </Field>
            )}
            <button type="submit" className="flex w-full items-center justify-center gap-2 rounded-full bg-[#1F5B3A] py-3 font-medium text-white hover:bg-primary">
              <IconSend className="size-5" /> Send invitation
            </button>
            <p className="text-xs text-ink/60">
              The invite email is sent by the MineNet backend once it&apos;s connected. Until then, copy the invite link from the member&apos;s menu and share it.
            </p>
          </form>
        </Card>
      </div>

      <Card className="p-6">
        <CardTitle>What each role can open</CardTitle>
        <div className="mt-4 grid gap-4 md:grid-cols-3">
          {(Object.keys(ACCESS) as Role[]).map((r) => (
            <div key={r} className="rounded-2xl bg-page p-4 text-sm">
              <p className="font-medium">{r}</p>
              <p className="mt-1 text-ink/70">{ROLE_INFO[r]}</p>
            </div>
          ))}
        </div>
        <p className="mt-3 text-xs text-ink/60">Want to try a role? Use “Demo: view as” in your account menu. <Link href="/miner/settings" className="text-accent hover:underline">Settings</Link></p>
      </Card>
    </>
  );
}
