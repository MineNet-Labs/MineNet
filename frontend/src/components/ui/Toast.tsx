"use client";

import { useSyncExternalStore } from "react";
import { IconCircleCheck, IconInfoCircle, IconAlertTriangle, IconX } from "@tabler/icons-react";

type Toast = { id: number; text: string; tone: "success" | "info" | "error" };
let toasts: Toast[] = [];
const listeners = new Set<() => void>();
const emit = () => listeners.forEach((l) => l());

/** Show a short confirmation, e.g. toast("Lot LOT-00125 created"). */
export function toast(text: string, tone: Toast["tone"] = "success") {
  const id = Date.now() + Math.random();
  toasts = [...toasts, { id, text, tone }];
  emit();
  setTimeout(() => dismiss(id), 3500);
}

function dismiss(id: number) {
  toasts = toasts.filter((t) => t.id !== id);
  emit();
}

const icons = { success: IconCircleCheck, info: IconInfoCircle, error: IconAlertTriangle };
const colors = { success: "text-[#1F5B3A]", info: "text-[#2563eb]", error: "text-danger" };
const empty: Toast[] = [];

export function Toaster() {
  const list = useSyncExternalStore(
    (fn) => {
      listeners.add(fn);
      return () => listeners.delete(fn);
    },
    () => toasts,
    () => empty,
  );
  return (
    <div aria-live="polite" className="pointer-events-none fixed top-6 left-1/2 z-[60] flex -translate-x-1/2 flex-col items-center gap-2">
      {list.map((t) => {
        const Icon = icons[t.tone];
        return (
          <div
            key={t.id}
            className="pointer-events-auto flex items-center gap-3 rounded-2xl bg-white px-4 py-3 text-sm font-medium shadow-[0_10px_30px_rgba(17,24,39,0.15)]"
          >
            <Icon className={`size-5 ${colors[t.tone]}`} />
            {t.text}
            <button onClick={() => dismiss(t.id)} aria-label="Dismiss" className="ml-2 text-ink/40 hover:text-ink">
              <IconX className="size-4" />
            </button>
          </div>
        );
      })}
    </div>
  );
}
