"use client";

import { useSyncExternalStore } from "react";
import { IconAlertTriangle, IconShieldCheck } from "@tabler/icons-react";
import { Modal } from "./Modal";

type Ask = {
  title: string;
  message: React.ReactNode;
  confirmLabel?: string;
  tone?: "danger" | "primary";
  resolve: (ok: boolean) => void;
};

let current: Ask | null = null;
const listeners = new Set<() => void>();
const emit = () => listeners.forEach((l) => l());

/**
 * Ask before doing something important or hard to undo.
 * `if (await confirmAction({ title, message })) doIt();`
 */
export function confirmAction(opts: Omit<Ask, "resolve">): Promise<boolean> {
  return new Promise((resolve) => {
    current?.resolve(false);
    current = { ...opts, resolve };
    emit();
  });
}

/** Runs `fn` only after the person confirms. */
export function withConfirm(opts: Omit<Ask, "resolve">, fn: () => void) {
  return () => {
    void confirmAction(opts).then((ok) => ok && fn());
  };
}

function close(ok: boolean) {
  current?.resolve(ok);
  current = null;
  emit();
}

/** Mounted once in the layout. */
export function ConfirmHost() {
  const ask = useSyncExternalStore(
    (fn) => (listeners.add(fn), () => listeners.delete(fn)),
    () => current,
    () => null,
  );
  if (!ask) return null;
  const danger = ask.tone === "danger";
  const Icon = danger ? IconAlertTriangle : IconShieldCheck;
  return (
    <Modal
      title={ask.title}
      onClose={() => close(false)}
      width={480}
      footer={
        <>
          <button type="button" onClick={() => close(false)} className="px-3 text-[15px]">Cancel</button>
          <button
            type="button"
            autoFocus
            onClick={() => close(true)}
            className={`rounded-full px-6 py-3 text-[15px] font-medium text-white ${danger ? "bg-danger hover:brightness-95" : "bg-[#1F5B3A] hover:bg-primary"}`}
          >
            {ask.confirmLabel ?? "Confirm"}
          </button>
        </>
      }
    >
      <div className="flex gap-4">
        <span className={`grid size-11 shrink-0 place-items-center rounded-full ${danger ? "bg-danger-soft text-danger" : "bg-primary-soft text-[#1F5B3A]"}`}>
          <Icon className="size-5" />
        </span>
        <div className="text-[15px] text-ink/80">{ask.message}</div>
      </div>
    </Modal>
  );
}
