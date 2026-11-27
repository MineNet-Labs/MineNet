import { Suspense } from "react";
import { ShipmentDetail } from "./ShipmentDetail";

export default function ShipmentPage() {
  return (
    <Suspense fallback={<div className="h-64 animate-pulse rounded-[22px] bg-white" />}>
      <ShipmentDetail />
    </Suspense>
  );
}
