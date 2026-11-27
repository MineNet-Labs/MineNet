"use client";

import { useEffect, useRef } from "react";

/**
 * Reads ?name= from the URL once after mount (e.g. global search → /miner/workers?q=Aline)
 * and hands it to `onValue`. Avoids useSearchParams so pages don't need a Suspense boundary.
 */
export function useQueryParam(name: string, onValue: (v: string) => void) {
  const done = useRef(false);
  useEffect(() => {
    if (done.current) return;
    done.current = true;
    const v = new URLSearchParams(window.location.search).get(name);
    if (v) onValue(v);
  }, [name, onValue]);
}
