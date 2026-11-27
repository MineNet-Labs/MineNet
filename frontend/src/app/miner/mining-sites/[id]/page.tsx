import { Suspense } from "react";
import { SiteDetail } from "./SiteDetail";

// The site id comes from the URL and sites can be created in the browser,
// so the detail view renders client-side inside a Suspense boundary.
export default function SiteDetailPage() {
  return (
    <Suspense fallback={<div className="h-64 animate-pulse rounded-[22px] bg-white" />}>
      <SiteDetail />
    </Suspense>
  );
}
