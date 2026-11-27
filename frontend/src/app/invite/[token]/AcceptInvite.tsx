"use client";

import Link from "next/link";
import { useParams, useRouter } from "next/navigation";
import { IconCircleCheck, IconMailOpened } from "@tabler/icons-react";
import { ROLE_INFO } from "@/lib/roles";
import { update, useStore } from "@/lib/store";

/** Landing page of the email invitation a site manager or HR receives. */
export function AcceptInvite() {
  const { token } = useParams<{ token: string }>();
  const router = useRouter();
  const org = useStore((s) => s.org);
  const sites = useStore((s) => s.sites);
  const member = useStore((s) => s.members.find((m) => m.token === token));

  const card = "w-full max-w-md rounded-[22px] bg-white p-8 shadow-[0_4px_24px_rgba(17,24,39,0.06)]";
  const brand = (
    <p className="font-brand text-[26px] font-bold"><span className="text-[#05581A]">Mine</span><span className="text-[#F57C00]">Net</span></p>
  );

  if (!member || member.status === "Disabled") {
    return (
      <div className={`${card} text-center`}>
        {brand}
        <h2 className="mt-5">Invitation not valid</h2>
        <p className="mt-2 text-ink/70">This invite link has expired or was revoked. Ask your company owner to send a new one.</p>
      </div>
    );
  }

  const accept = () => {
    update((s) => ({ members: s.members.map((m) => (m.id === member.id ? { ...m, status: "Active" as const } : m)), sessionMemberId: member.id }));
    router.push("/miner");
  };

  return (
    <div className={card}>
      {brand}
      <IconMailOpened className="mt-6 size-10 text-[#1F5B3A]" />
      <h2 className="mt-3">You&apos;re invited</h2>
      <p className="mt-2 text-ink/75">
        {org.contact} invited <b>{member.name}</b> ({member.email}) to join <b>{org.name}</b> as <b>{member.role.toLowerCase()}</b>.
      </p>
      <p className="mt-4 rounded-xl bg-page px-4 py-3 text-sm text-ink/75">{ROLE_INFO[member.role]}</p>
      {member.role === "Site manager" && (
        <p className="mt-3 text-sm text-ink/75">Sites: {member.siteIds.map((id) => sites.find((s) => s.id === id)?.name ?? id).join(", ")}</p>
      )}
      {member.status === "Active" ? (
        <>
          <p className="mt-6 flex items-center gap-2 text-sm text-[#1F5B3A]"><IconCircleCheck className="size-5" /> Already accepted</p>
          <Link href="/miner" className="mt-4 block rounded-full bg-[#1F5B3A] py-3 text-center font-medium text-white hover:bg-primary">Open MineNet</Link>
        </>
      ) : (
        <button onClick={accept} className="mt-6 w-full rounded-full bg-[#1F5B3A] py-3 font-medium text-white hover:bg-primary">
          Accept invitation
        </button>
      )}
      <p className="mt-4 text-xs text-ink/55">Password or wallet sign-in is added with the authentication service.</p>
    </div>
  );
}
