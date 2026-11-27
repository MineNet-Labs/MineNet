import { Suspense } from "react";
import { detailFallback } from "@/components/DetailShell";
import { RequestDetail } from "./RequestDetail";

export default function BuyerRequestPage() {
  return <Suspense fallback={detailFallback}><RequestDetail /></Suspense>;
}
