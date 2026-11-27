import { Suspense } from "react";
import { Sidebar } from "@/components/layout/Sidebar";
import { Topbar } from "@/components/layout/Topbar";
import { Assistant } from "@/components/layout/Assistant";
import { Toaster } from "@/components/ui/Toast";

// Sidebar and Topbar read the current path, so on dynamic routes
// (e.g. /miner/mining-sites/[id]) they stream in inside Suspense.
export default function MinerLayout({ children }: LayoutProps<"/miner">) {
  return (
    <div className="flex min-h-screen gap-6 bg-page p-4">
      <Suspense fallback={<div className="w-[208px] shrink-0 rounded-[28px] bg-white" />}>
        <Sidebar />
      </Suspense>
      <div className="min-w-0 flex-1 space-y-6 pr-2 pb-10">
        <Suspense fallback={<div className="h-12" />}>
          <Topbar />
        </Suspense>
        {children}
      </div>
      <Suspense>
        <Assistant />
      </Suspense>
      <Toaster />
    </div>
  );
}
