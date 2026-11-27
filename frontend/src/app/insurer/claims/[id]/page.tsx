import { Suspense } from "react";
import { detailFallback } from "@/components/DetailShell";
import { ClaimDetail } from "./ClaimDetail";

export default function InsurerClaimPage() {
  return <Suspense fallback={detailFallback}><ClaimDetail /></Suspense>;
}
