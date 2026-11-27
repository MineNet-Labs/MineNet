import { Suspense } from "react";
import { Sidebar } from "@/components/layout/Sidebar";
import { InsurerTopbar, insurerNav } from "@/components/insurer/common";
import { Toaster } from "@/components/ui/Toast";
import { ConfirmHost } from "@/components/ui/Confirm";

// Insurer portal. Shares the MineNet data store with the miner portal until
// the backend exists.
export default function InsurerLayout({ children }: LayoutProps<"/insurer">) {
  return (
    <div className="flex min-h-screen gap-6 bg-page p-3 lg:p-4">
      <div className="hidden lg:flex">
        <Suspense fallback={<div className="w-[208px] shrink-0 rounded-[28px] bg-white" />}>
          <Sidebar items={insurerNav} home="/insurer" />
        </Suspense>
      </div>
      <div className="min-w-0 flex-1 space-y-6 pb-24 lg:pr-2">
        <Suspense fallback={<div className="h-12" />}>
          <InsurerTopbar />
        </Suspense>
        <Suspense fallback={<div className="h-64 animate-pulse rounded-[22px] bg-white" />}>{children}</Suspense>
      </div>
      <ConfirmHost />
      <Toaster />
    </div>
  );
}
