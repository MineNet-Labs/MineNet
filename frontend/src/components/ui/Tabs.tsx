"use client";

export type TabItem = { key: string; label: string; count?: number };

/** Underline tabs with optional counts, as used on table cards. */
export function Tabs({
  items,
  value,
  onChange,
  size = "md",
}: {
  items: TabItem[];
  value: string;
  onChange: (key: string) => void;
  size?: "md" | "lg";
}) {
  return (
    <div className="flex gap-7">
      {items.map((t) => {
        const active = t.key === value;
        return (
          <button
            key={t.key}
            onClick={() => onChange(t.key)}
            className={`-mb-px border-b-2 px-1 pb-3 whitespace-nowrap ${
              size === "lg" ? "text-[17px]" : "text-[15px]"
            } ${active ? "border-accent font-medium text-accent" : "border-transparent text-ink/80 hover:text-ink"}`}
          >
            {t.label}
            {t.count !== undefined && (
              <span className={`ml-1.5 ${size === "lg" ? "" : "align-super text-[11px]"}`}>{t.count}</span>
            )}
          </button>
        );
      })}
    </div>
  );
}
