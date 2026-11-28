"use client";

import { useEffect, useLayoutEffect, useRef, useState } from "react";
import { IconX } from "@tabler/icons-react";

/** Stops the page behind from scrolling while a dialog is open. */
let locks = 0;
function useScrollLock(active: boolean) {
  useEffect(() => {
    if (!active) return;
    const html = document.documentElement;
    if (locks++ === 0) {
      const gap = window.innerWidth - html.clientWidth;
      html.style.overflow = "hidden";
      html.style.paddingRight = gap ? `${gap}px` : "";
    }
    return () => {
      if (--locks === 0) {
        html.style.overflow = "";
        html.style.paddingRight = "";
      }
    };
  }, [active]);
}

/**
 * Pop-up dialog over the current page. Esc / backdrop closes. Nothing
 * scrolls: the page behind is locked, the dialog has no scrollbar, and a
 * form taller than the screen is scaled down to fit.
 */
export function Modal({
  title,
  subtitle,
  onClose,
  children,
  footer,
  width = 620,
}: {
  title: string;
  subtitle?: string;
  onClose: () => void;
  children: React.ReactNode;
  footer?: React.ReactNode;
  width?: number;
}) {
  useScrollLock(true);
  const box = useRef<HTMLDivElement>(null);
  const [scale, setScale] = useState(1);
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => e.key === "Escape" && onClose();
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [onClose]);
  useLayoutEffect(() => {
    const el = box.current;
    if (!el) return;
    const fit = () => setScale(Math.min(1, (window.innerHeight - 32) / el.offsetHeight));
    fit();
    const ro = new ResizeObserver(fit);
    ro.observe(el);
    window.addEventListener("resize", fit);
    return () => (ro.disconnect(), window.removeEventListener("resize", fit));
  }, []);

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center overflow-hidden bg-ink/10 p-4" onClick={onClose} role="presentation">
      <div
        ref={box}
        role="dialog"
        aria-modal="true"
        aria-label={title}
        onClick={(e) => e.stopPropagation()}
        className="flex w-full shrink-0 flex-col rounded-[22px] bg-white shadow-[0_20px_60px_rgba(17,24,39,0.18)]"
        style={{ maxWidth: width, transform: scale < 1 ? `scale(${scale})` : undefined }}
      >
        <div className="flex items-start justify-between gap-4 border-b border-gray-100 px-5 pt-6 pb-5">
          <div>
            <h2 className="font-sans text-xl font-semibold">{title}</h2>
            {subtitle && <p className="mt-1.5 text-sm text-ink/70">{subtitle}</p>}
          </div>
          <button onClick={onClose} aria-label="Close" className="grid size-9 shrink-0 place-items-center rounded-full bg-page">
            <IconX className="size-5" stroke={2.4} />
          </button>
        </div>
        <div className="px-5 py-5">{children}</div>
        {footer && <div className="flex items-center justify-end gap-4 border-t border-gray-100 px-5 py-4">{footer}</div>}
      </div>
    </div>
  );
}

export const inputClass =
  "h-11 w-full rounded-xl border border-gray-200 bg-white px-4 text-[15px] outline-none placeholder:text-gray-400 focus:border-[#1F5B3A]";

export function Field({
  label,
  hint,
  children,
  className = "",
}: {
  label: string;
  hint?: string;
  children: React.ReactNode;
  className?: string;
}) {
  return (
    <label className={`block space-y-2 ${className}`}>
      <span className="text-label">{label}</span>
      {children}
      {hint && <span className="block text-xs text-ink/60">{hint}</span>}
    </label>
  );
}

export function SubmitButton({ children, form }: { children: React.ReactNode; form: string }) {
  return (
    <button
      type="submit"
      form={form}
      className="rounded-full bg-[#1F5B3A] px-6 py-3 text-[15px] font-medium text-white shadow-[0_6px_16px_rgba(31,91,58,0.25)] hover:bg-primary"
    >
      {children}
    </button>
  );
}

export function CancelButton({ onClick }: { onClick: () => void }) {
  return (
    <button type="button" onClick={onClick} className="px-3 text-[15px]">
      Cancel
    </button>
  );
}

/** Read a <form>'s fields as strings. */
export function formValues(e: React.FormEvent<HTMLFormElement>) {
  e.preventDefault();
  return Object.fromEntries(new FormData(e.currentTarget).entries()) as Record<string, string>;
}
