import { Suspense } from "react";
import { Sidebar } from "@/components/layout/Sidebar";
import { SupplyTopbar, supplyNav } from "@/components/supply/common";
import { FormHost } from "@/components/FormHost";
import { Toaster } from "@/components/ui/Toast";
import { ConfirmHost } from "@/components/ui/Confirm";

// Supply chain operator portal: shipments, inventory, processing, refining,
// export and traceability. Shares the MineNet data store until the backend exists.
export default function SupplyLayout({ children }: LayoutProps<"/supply">) {
  return (
    <div className="flex min-h-screen gap-5 bg-page p-3 lg:p-4">
      <div className="hidden lg:flex">
        <Suspense fallback={<div className="w-[208px] shrink-0 rounded-[28px] bg-white" />}>
          <Sidebar items={supplyNav} home="/supply" />
        </Suspense>
      </div>
      <div className="min-w-0 flex-1 space-y-5 pb-24 lg:pr-2">
        <Suspense fallback={<div className="h-12" />}>
          <SupplyTopbar />
        </Suspense>
        <Suspense fallback={<div className="h-64 animate-pulse rounded-[22px] bg-white" />}>{children}</Suspense>
      </div>
      <FormHost />
      <ConfirmHost />
      <Toaster />
    </div>
  );
}
