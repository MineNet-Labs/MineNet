import { Suspense } from "react";
import { LotPassport } from "./LotPassport";

// Lots are created in the browser, so the passport renders client-side.
export default function LotPassportPage() {
  return (
    <Suspense fallback={<div className="h-64 animate-pulse rounded-[22px] bg-white" />}>
      <LotPassport />
    </Suspense>
  );
}
