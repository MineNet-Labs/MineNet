"use client";

import { Children, isValidElement, useEffect, useId, useRef, useState } from "react";
import { IconCheck, IconChevronDown } from "@tabler/icons-react";

type Opt = { value: string; label: string; disabled?: boolean };

const text = (node: React.ReactNode): string =>
  Children.toArray(node)
    .map((c) => (typeof c === "string" || typeof c === "number" ? String(c) : isValidElement<{ children?: React.ReactNode }>(c) ? text(c.props.children) : ""))
    .join("");

/** Reads <option> children (as written for a native <select>). */
function readOptions(children: React.ReactNode): Opt[] {
  return Children.toArray(children).flatMap((c) => {
    if (!isValidElement<{ value?: string; children?: React.ReactNode; disabled?: boolean }>(c)) return [];
    const label = text(c.props.children);
    return [{ value: c.props.value !== undefined ? String(c.props.value) : label, label, disabled: c.props.disabled }];
  });
}

type ChangeEvent = { target: { value: string; name?: string } };

/**
 * Styled drop-in replacement for <select>: same props (name, value,
 * defaultValue, onChange, required, <option> children) so forms keep working
 * with FormData, but the menu matches the MineNet design.
 */
export function Select({
  name,
  value,
  defaultValue,
  onChange,
  required,
  disabled,
  className = "",
  children,
  "aria-label": ariaLabel,
}: {
  name?: string;
  value?: string;
  defaultValue?: string;
  onChange?: (e: ChangeEvent) => void;
  required?: boolean;
  disabled?: boolean;
  className?: string;
  children: React.ReactNode;
  "aria-label"?: string;
}) {
  const options = readOptions(children);
  const [inner, setInner] = useState(defaultValue ?? "");
  const current = value ?? inner;
  const selected = options.find((o) => o.value === current);
  const placeholder = options.find((o) => o.value === "" && o.disabled);
  const [open, setOpen] = useState(false);
  const [active, setActive] = useState(0);
  const ref = useRef<HTMLDivElement>(null);
  const listId = useId();

  useEffect(() => {
    if (!open) return;
    const onDown = (e: MouseEvent) => ref.current && !ref.current.contains(e.target as Node) && setOpen(false);
    document.addEventListener("mousedown", onDown);
    return () => document.removeEventListener("mousedown", onDown);
  }, [open]);

  const choices = options.filter((o) => !(o.value === "" && o.disabled));
  const pick = (o: Opt) => {
    if (o.disabled) return;
    if (value === undefined) setInner(o.value);
    onChange?.({ target: { value: o.value, name } });
    setOpen(false);
  };
  const openMenu = () => {
    setActive(Math.max(0, choices.findIndex((o) => o.value === current)));
    setOpen(true);
  };

  const onKey = (e: React.KeyboardEvent) => {
    if (e.key === "Escape") return setOpen(false);
    if (!open && ["ArrowDown", "ArrowUp", "Enter", " "].includes(e.key)) {
      e.preventDefault();
      return openMenu();
    }
    if (!open) return;
    if (e.key === "ArrowDown") {
      e.preventDefault();
      setActive((a) => Math.min(choices.length - 1, a + 1));
    }
    if (e.key === "ArrowUp") {
      e.preventDefault();
      setActive((a) => Math.max(0, a - 1));
    }
    if (e.key === "Enter" || e.key === " ") {
      e.preventDefault();
      if (choices[active]) pick(choices[active]);
    }
  };

  const shown = selected && !(selected.value === "" && selected.disabled) ? selected.label : placeholder?.label ?? "Select…";
  const isPlaceholder = !selected || (selected.value === "" && !!selected.disabled);

  return (
    <div ref={ref} className="relative">
      <button
        type="button"
        disabled={disabled}
        onClick={() => (open ? setOpen(false) : openMenu())}
        onKeyDown={onKey}
        aria-haspopup="listbox"
        aria-expanded={open}
        aria-controls={listId}
        aria-label={ariaLabel ?? placeholder?.label}
        className={`flex h-11 w-full items-center justify-between gap-2 rounded-xl border bg-white px-4 text-left text-[15px] outline-none disabled:opacity-50 ${
          open ? "border-[#1F5B3A] ring-2 ring-[#1F5B3A]/10" : "border-gray-200 hover:border-gray-300"
        } ${className.replace(/\b(h-\d+|w-full|rounded-\S+|border-gray-\d+|bg-white|px-\d+|pr-\d+|text-\[15px\])\b/g, "")}`}
      >
        <span className={`truncate ${isPlaceholder ? "text-gray-400" : ""}`}>{shown}</span>
        <IconChevronDown className={`size-4 shrink-0 text-ink/60 transition-transform ${open ? "rotate-180" : ""}`} />
      </button>
      {/* Carries the value into FormData and native "required" validation. */}
      <input
        tabIndex={-1}
        aria-hidden
        name={name}
        value={isPlaceholder ? "" : current}
        required={required}
        onChange={() => {}}
        className="pointer-events-none absolute bottom-0 left-4 h-px w-px opacity-0"
      />
      {open && (
        <ul
          id={listId}
          role="listbox"
          className="absolute top-full right-0 left-0 z-50 mt-1.5 rounded-2xl border border-gray-100 bg-white p-1.5 shadow-[0_12px_32px_rgba(17,24,39,0.14)]"
        >
          {choices.map((o, i) => {
            const sel = o.value === current;
            return (
              <li
                key={o.value + i}
                role="option"
                aria-selected={sel}
                aria-disabled={o.disabled}
                onMouseEnter={() => setActive(i)}
                onMouseDown={(e) => e.preventDefault()}
                onClick={() => pick(o)}
                className={`flex cursor-pointer items-center justify-between gap-3 rounded-xl px-3 py-2.5 text-sm ${
                  o.disabled ? "cursor-not-allowed text-ink/35" : i === active ? "bg-page" : ""
                } ${sel ? "font-medium text-[#1F5B3A]" : ""}`}
              >
                <span>{o.label}</span>
                {sel && <IconCheck className="size-4 shrink-0" />}
              </li>
            );
          })}
          {choices.length === 0 && <li className="px-3 py-2.5 text-sm text-ink/50">No options</li>}
        </ul>
      )}
    </div>
  );
}
