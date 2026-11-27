import { Suspense } from "react";
import { detailFallback } from "@/components/DetailShell";
import { ShaftDetail } from "./ShaftDetail";

export default function ShaftPage() {
  return <Suspense fallback={detailFallback}><ShaftDetail /></Suspense>;
}
