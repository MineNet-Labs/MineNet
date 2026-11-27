"use client";

import { useEffect, useRef, useState } from "react";
import {
  IconCalendar,
  IconCheck,
  IconChevronDown,
  IconDotsVertical,
  type Icon as TablerIcon,
} from "@tabler/icons-react";

/** Closes when clicking outside or pressing Escape. */
function useDismiss(open: boolean, close: () => void) {
  const ref = useRef<HTMLDivElement>(null);
  useEffect(() => {
    if (!open) return;
    const onDown = (e: MouseEvent) => ref.current && !ref.current.contains(e.target as Node) && close();
    const onKey = (e: KeyboardEvent) => e.key === "Escape" && close();
    document.addEventListener("mousedown", onDown);
    document.addEventListener("keydown", onKey);
    return () => {
      document.removeEventListener("mousedown", onDown);
      document.removeEventListener("keydown", onKey);
    };
  }, [open, close]);
  return ref;
}

/** Generic popover: trigger + panel. */
export function Popover({
  trigger,
  children,
  align = "left",
  panelClass = "",
}: {
  trigger: (open: boolean, toggle: () => void) => React.ReactNode;
  children: (close: () => void) => React.ReactNode;
  align?: "left" | "right";
  panelClass?: string;
}) {
  const [open, setOpen] = useState(false);
  const close = () => setOpen(false);
  const ref = useDismiss(open, close);
  return (
    <div ref={ref} className="relative">
      {trigger(open, () => setOpen((o) => !o))}
      {open && (
        <div
          className={`absolute top-full z-40 mt-2 min-w-full rounded-2xl border border-gray-100 bg-white p-1.5 shadow-[0_12px_32px_rgba(17,24,39,0.12)] ${
            align === "right" ? "right-0" : "left-0"
          } ${panelClass}`}
        >
          {children(close)}
        </div>
      )}
    </div>
  );
}

export function MenuItem({
  icon: Icon,
  children,
  onClick,
  danger,
  active,
}: {
  icon?: TablerIcon;
  children: React.ReactNode;
  onClick: () => void;
  danger?: boolean;
  active?: boolean;
}) {
  return (
    <button
      onClick={onClick}
      className={`flex w-full items-center gap-2.5 rounded-xl px-3 py-2 text-left text-sm whitespace-nowrap hover:bg-page ${
        danger ? "text-danger" : "text-ink"
      }`}
    >
      {Icon && <Icon className="size-4 shrink-0" stroke={1.9} />}
      <span className="flex-1">{children}</span>
      {active && <IconCheck className="size-4 text-[#1F5B3A]" />}
    </button>
  );
}

/** Filter dropdown: shows the label for "all", or the selected value. */
export function FilterSelect({
  label,
  options,
  value,
  onChange,
  className = "",
}: {
  label: string;
  options: string[];
  value: string;
  onChange: (v: string) => void;
  className?: string;
}) {
  return (
    <Popover
      trigger={(open, toggle) => (
        <button
          onClick={toggle}
          aria-expanded={open}
          className={`inline-flex items-center justify-between gap-2 rounded-full border px-4 py-2 text-[15px] whitespace-nowrap ${
            value ? "border-[#1F5B3A]/40 bg-primary-soft/50 text-[#1F5B3A]" : "border-gray-200 bg-white text-ink"
          } ${className}`}
        >
          {value || label}
          <IconChevronDown className={`size-4 transition-transform ${open ? "rotate-180" : ""}`} />
        </button>
      )}
    >
      {(close) => (
        <>
          <MenuItem active={!value} onClick={() => (onChange(""), close())}>{label}</MenuItem>
          {options.map((o) => (
            <MenuItem key={o} active={value === o} onClick={() => (onChange(o), close())}>{o}</MenuItem>
          ))}
        </>
      )}
    </Popover>
  );
}

export const RANGES = ["Last 7 days", "Last 30 days", "Last 60 days", "Last 3 Months", "Last 6 Months", "This year"];

/** Date-range picker with presets (filters are applied by the page if it wants). */
export function DateRange({
  label = "29 Jun, 2025 – 29 Aug, 2025",
  onChange,
}: {
  label?: string;
  onChange?: (range: string) => void;
}) {
  const [value, setValue] = useState(label);
  return (
    <Popover
      align="right"
      trigger={(open, toggle) => (
        <button
          onClick={toggle}
          aria-expanded={open}
          className="inline-flex items-center gap-3 rounded-2xl bg-white px-5 py-3 text-[15px] whitespace-nowrap text-ink shadow-[0_2px_12px_rgba(17,24,39,0.04)]"
        >
          <IconCalendar className="size-5" stroke={1.8} />
          {value}
          <IconChevronDown className={`size-5 transition-transform ${open ? "rotate-180" : ""}`} />
        </button>
      )}
    >
      {(close) =>
        [label, ...RANGES].map((r) => (
          <MenuItem
            key={r}
            active={value === r}
            onClick={() => {
              setValue(r);
              onChange?.(r);
              close();
            }}
          >
            {r}
          </MenuItem>
        ))
      }
    </Popover>
  );
}

/** Compact select (e.g. "Last 6 Months" on chart cards). */
export function MiniSelect({ options, initial, className = "" }: { options: string[]; initial?: string; className?: string }) {
  const [value, setValue] = useState(initial ?? options[0]);
  return (
    <Popover
      align="right"
      trigger={(open, toggle) => (
        <button
          onClick={toggle}
          className={`inline-flex items-center gap-2 rounded-xl border border-gray-200 bg-white px-4 py-2 text-sm whitespace-nowrap ${className}`}
        >
          {value}
          <IconChevronDown className={`size-4 transition-transform ${open ? "rotate-180" : ""}`} />
        </button>
      )}
    >
      {(close) =>
        options.map((o) => (
          <MenuItem key={o} active={value === o} onClick={() => (setValue(o), close())}>{o}</MenuItem>
        ))
      }
    </Popover>
  );
}

/** "⋮" row actions menu. */
export function RowMenu({
  items,
}: {
  items: { label: string; icon?: TablerIcon; onClick: () => void; danger?: boolean }[];
}) {
  return (
    <Popover
      align="right"
      trigger={(_, toggle) => (
        <button onClick={toggle} aria-label="Row actions" className="grid size-8 place-items-center rounded-full hover:bg-page">
          <IconDotsVertical className="size-5" />
        </button>
      )}
    >
      {(close) =>
        items.map((it) => (
          <MenuItem key={it.label} icon={it.icon} danger={it.danger} onClick={() => (it.onClick(), close())}>
            {it.label}
          </MenuItem>
        ))
      }
    </Popover>
  );
}
