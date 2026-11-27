import { Suspense } from "react";
import { AcceptInvite } from "./AcceptInvite";

export default function InvitePage() {
  return (
    <main className="grid min-h-screen place-items-center bg-page p-6">
      <Suspense fallback={<div className="h-80 w-full max-w-md animate-pulse rounded-[22px] bg-white" />}>
        <AcceptInvite />
      </Suspense>
    </main>
  );
}
