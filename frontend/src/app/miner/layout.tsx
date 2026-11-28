import { Suspense } from "react";
import { Sidebar } from "@/components/layout/Sidebar";
import { Topbar } from "@/components/layout/Topbar";
import { Assistant } from "@/components/layout/Assistant";
import { LicenceBanner } from "@/components/layout/LicenceBanner";
import { Toaster } from "@/components/ui/Toast";
import { ConfirmHost } from "@/components/ui/Confirm";
import { RoleGuard } from "@/components/layout/RoleGuard";
import { FormHost } from "@/components/FormHost";
import { SectionTabs } from "@/components/layout/SectionTabs";

// Sidebar and Topbar read the current path, so on dynamic routes
// (e.g. /miner/mining-sites/[id]) they stream in inside Suspense.
// Below the lg breakpoint the sidebar is replaced by the Topbar's menu button.
export default function MinerLayout({ children }: LayoutProps<"/miner">) {
  return (
    <div className="flex min-h-screen gap-5 bg-page p-3 lg:p-4">
      <div className="hidden lg:flex">
        <Suspense fallback={<div className="w-[208px] shrink-0 rounded-[28px] bg-white" />}>
          <Sidebar />
        </Suspense>
      </div>
      <div className="min-w-0 flex-1 space-y-5 pb-24 lg:pr-2">
        <Suspense fallback={<div className="h-12" />}>
          <Topbar />
        </Suspense>
        <LicenceBanner />
        <Suspense>
          <SectionTabs />
        </Suspense>
        <Suspense>
          <RoleGuard>{children}</RoleGuard>
        </Suspense>
      </div>
      <Suspense>
        <Assistant />
      </Suspense>
      <FormHost />
      <ConfirmHost />
      <Toaster />
    </div>
  );
}
