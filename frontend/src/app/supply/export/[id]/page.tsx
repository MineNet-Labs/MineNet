import { Suspense } from "react";
import { DeclarationDetail } from "./DeclarationDetail";

export default function DeclarationPage() {
  return (
    <Suspense fallback={<div className="h-64 animate-pulse rounded-[22px] bg-white" />}>
      <DeclarationDetail />
    </Suspense>
  );
}
