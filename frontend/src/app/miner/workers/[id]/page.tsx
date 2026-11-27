import { Suspense } from "react";
import { detailFallback } from "@/components/DetailShell";
import { WorkerDetail } from "./WorkerDetail";

export default function WorkerPage() {
  return <Suspense fallback={detailFallback}><WorkerDetail /></Suspense>;
}
