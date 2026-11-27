import { Suspense } from "react";
import { detailFallback } from "@/components/DetailShell";
import { PolicyDetail } from "./PolicyDetail";

export default function InsurerPolicyPage() {
  return <Suspense fallback={detailFallback}><PolicyDetail /></Suspense>;
}
