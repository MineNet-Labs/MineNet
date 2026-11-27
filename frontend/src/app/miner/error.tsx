"use client";

import { useEffect } from "react";
import { IconAlertTriangle, IconRefresh } from "@tabler/icons-react";
import { resetData } from "@/lib/store";

export default function MinerError({ error, reset }: { error: Error & { digest?: string }; reset: () => void }) {
  useEffect(() => {
    console.error(error);
  }, [error]);

  return (
    <div className="rounded-[22px] bg-white p-10 text-center">
      <IconAlertTriangle className="mx-auto size-10 text-danger" />
      <h2 className="mt-3">Something went wrong</h2>
      <p className="mt-2 text-ink/70">This page hit an error. Try again, or reset the demo data if it keeps happening.</p>
      <div className="mt-5 flex justify-center gap-3">
        <button onClick={reset} className="inline-flex items-center gap-2 rounded-full bg-[#1F5B3A] px-6 py-3 font-medium text-white hover:bg-primary">
          <IconRefresh className="size-5" /> Try again
        </button>
        <button
          onClick={() => {
            resetData();
            reset();
          }}
          className="rounded-full border border-gray-200 px-6 py-3 hover:bg-page"
        >
          Reset demo data
        </button>
      </div>
    </div>
  );
}
