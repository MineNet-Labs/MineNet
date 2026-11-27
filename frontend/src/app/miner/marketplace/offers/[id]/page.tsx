import { Suspense } from "react";
import { detailFallback } from "@/components/DetailShell";
import { OfferDetail } from "./OfferDetail";

export default function OfferPage() {
  return <Suspense fallback={detailFallback}><OfferDetail /></Suspense>;
}
