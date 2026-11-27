import { Suspense } from "react";
import { detailFallback } from "@/components/DetailShell";
import { InspectionDetail } from "./InspectionDetail";

export default function InspectionPage() {
  return <Suspense fallback={detailFallback}><InspectionDetail /></Suspense>;
}
