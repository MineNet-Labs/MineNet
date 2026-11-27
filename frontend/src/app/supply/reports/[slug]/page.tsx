import { Suspense } from "react";
import { ReportDetail } from "./ReportDetail";

export default function SupplyReportPage() {
  return (
    <Suspense fallback={<div className="h-64 animate-pulse rounded-[22px] bg-white" />}>
      <ReportDetail />
    </Suspense>
  );
}
