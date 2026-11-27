import Link from "next/link";
import {
  IconArrowDown as ArrowDown,
  IconArrowRight as ArrowRight,
  IconArrowUp as ArrowUp,
  type Icon as TablerIcon,
} from "@tabler/icons-react";
import { Sparkline } from "./charts";

// Interactive pieces live in client files; re-exported here for one import path.
export { DateRange, FilterSelect, MiniSelect, RowMenu, Popover, MenuItem } from "./Dropdown";
export { Pagination, usePaged } from "./Pagination";
export { Modal, Field, inputClass, SubmitButton, CancelButton, formValues } from "./Modal";
export { toast } from "./Toast";

/* ------------------------------------------------------------------ tones */

export type Tone = "orange" | "green" | "violet" | "gray";

export const toneStyles: Record<Tone, { chip: string; icon: string; line: string }> = {
  orange: { chip: "bg-accent-soft", icon: "text-accent", line: "#F0913F" },
  green: { chip: "bg-primary-soft", icon: "text-[#1F5B3A]", line: "#1F5B3A" },
  violet: { chip: "bg-violet-soft", icon: "text-violet", line: "#8B7CF6" },
  gray: { chip: "bg-gray-100", icon: "text-gray-500", line: "#8B8FB8" },
};

/* ------------------------------------------------------------------- card */

export function Card({
  children,
  className = "",
  id,
}: {
  children: React.ReactNode;
  className?: string;
  id?: string;
}) {
  return (
    <section id={id} className={`min-w-0 scroll-mt-6 rounded-[22px] bg-white shadow-[0_4px_24px_rgba(17,24,39,0.04)] ${className}`}>
      {children}
    </section>
  );
}

export function CardTitle({
  icon: Icon,
  iconClass = "text-accent",
  children,
  action,
}: {
  icon?: TablerIcon;
  iconClass?: string;
  children: React.ReactNode;
  action?: React.ReactNode;
}) {
  return (
    <div className="flex items-center justify-between gap-4">
      <h3 className="flex items-center gap-2.5 font-sans text-lg font-semibold">
        {Icon && <Icon className={`size-5 ${iconClass}`} strokeWidth={2.2} />}
        {children}
      </h3>
      {action}
    </div>
  );
}

export function ViewAll({ href, label = "View All" }: { href: string; label?: string }) {
  return (
    <Link href={href} className="flex items-center gap-1 text-[15px] text-accent hover:underline">
      {label} <ArrowRight className="size-4" />
    </Link>
  );
}

/* ------------------------------------------------------------- stat card */

export function StatCard({
  icon: Icon,
  tone,
  label,
  value,
  delta,
  deltaDir = "up",
  deltaClass,
  note = "this month",
  spark,
  sparkTone,
}: {
  icon: TablerIcon;
  tone: Tone;
  label: string;
  value: React.ReactNode;
  delta?: React.ReactNode;
  deltaDir?: "up" | "down" | "none";
  deltaClass?: string;
  note?: string;
  spark: number[];
  sparkTone?: Tone;
}) {
  const t = toneStyles[tone];
  const Arrow = deltaDir === "down" ? ArrowDown : ArrowUp;
  const dClass = deltaClass ?? (deltaDir === "down" ? "text-accent" : "text-[#1F5B3A]");
  return (
    <Card className="flex items-center gap-4 overflow-hidden px-5 py-5">
      <span className={`grid size-14 shrink-0 place-items-center rounded-full ${t.chip}`}>
        <Icon className={`size-6 ${t.icon}`} strokeWidth={1.9} />
      </span>
      <div className="min-w-0 flex-1">
        <p className="text-[15px] leading-snug font-medium text-ink">{label}</p>
        <p className="font-heading text-[28px] leading-tight font-bold text-ink">{value}</p>
        {delta !== undefined && (
          <p className={`flex flex-wrap items-center gap-x-1 text-[13px] ${dClass}`}>
            {deltaDir !== "none" && <Arrow className="size-3.5" strokeWidth={2.5} />}
            <span>{delta}</span>
            <span className="text-ink/70">{note}</span>
          </p>
        )}
      </div>
      {/* In the flow (not on top of the text), so it never covers the numbers. */}
      <div className="-mr-5 -mb-5 shrink-0 self-end">
        <Sparkline values={spark} color={toneStyles[sparkTone ?? tone].line} width={72} />
      </div>
    </Card>
  );
}

/* --------------------------------------------------------------- badges */

const badgeStyles = {
  success: "bg-success-soft text-[#1F6B3A]",
  pending: "bg-accent-soft text-accent",
  danger: "bg-danger-soft text-danger",
  neutral: "bg-gray-100 text-gray-500",
  info: "bg-violet-soft text-violet",
  blue: "bg-[#e8f1fd] text-[#2563eb]",
} as const;

export type BadgeTone = keyof typeof badgeStyles;

export function StatusBadge({
  tone,
  children,
  dot = true,
  icon: Icon,
}: {
  tone: BadgeTone;
  children: React.ReactNode;
  dot?: boolean;
  icon?: TablerIcon;
}) {
  return (
    <span
      className={`inline-flex items-center gap-1.5 rounded-full px-2.5 py-1 text-[13px] font-medium whitespace-nowrap ${badgeStyles[tone]}`}
    >
      {Icon ? <Icon className="size-4" strokeWidth={2.2} /> : dot && <span className="size-1.5 rounded-full bg-current" />}
      {children}
    </span>
  );
}

/** Maps common status words to badge tones. */
export function statusTone(status: string): BadgeTone {
  const s = status.toLowerCase();
  if (["verified", "approved", "active", "completed", "operational", "received", "paid", "accepted", "sold"].includes(s)) return "success";
  if (["rejected", "failed", "closed", "declined", "expired"].includes(s)) return "danger";
  if (["processing", "scheduled", "sent"].includes(s)) return "blue";
  if (["withdrawn"].includes(s)) return "neutral";
  return "pending";
}

/* -------------------------------------------------------------- buttons */

export function PrimaryButton({
  children,
  icon: Icon,
  tone = "green",
  className = "",
  ...props
}: React.ButtonHTMLAttributes<HTMLButtonElement> & {
  icon?: TablerIcon;
  tone?: "green" | "orange";
}) {
  // One approved green for every primary action (tone kept for old call sites).
  void tone;
  const bg = "bg-[#1F5B3A] hover:bg-primary shadow-[0_6px_16px_rgba(31,91,58,0.25)]";
  return (
    <button
      className={`inline-flex items-center gap-2 rounded-2xl px-6 py-3 text-[15px] font-medium whitespace-nowrap text-white transition-colors ${bg} ${className}`}
      {...props}
    >
      {Icon && <Icon className="size-5" strokeWidth={2.2} />}
      {children}
    </button>
  );
}

/* ---------------------------------------------------------- page header */

export function PageHeader({
  title,
  subtitle,
  crumb,
  actions,
}: {
  title: string;
  subtitle: string;
  crumb?: { icon: TablerIcon; label: string };
  actions?: React.ReactNode;
}) {
  return (
    <div className="flex flex-col gap-4 pl-2 sm:flex-row sm:items-start sm:justify-between sm:gap-6">
      <div>
        {crumb && (
          <p className="mb-1 flex items-center gap-2 text-[17px] font-medium text-accent">
            <crumb.icon className="size-5" strokeWidth={2} />
            {crumb.label}
          </p>
        )}
        <h1>{title}</h1>
        <p className="mt-2 text-[17px] text-ink/80">{subtitle}</p>
        <span className="mt-2 block h-[3px] w-16 rounded-full bg-accent" />
      </div>
      {actions && <div className="flex flex-wrap items-start gap-3 sm:flex-col sm:items-end sm:gap-4 md:flex-row md:items-center">{actions}</div>}
    </div>
  );
}

/* ---------------------------------------------------------- thumbnails */

/** Placeholder mineral image; replace with exported Figma assets. */
export function MineralThumb({ size = 32 }: { size?: number }) {
  return (
    <span className="inline-grid shrink-0 place-items-center rounded-full bg-[#efe9df]" style={{ width: size, height: size }}>
      <span
        className="rounded-[40%] bg-[radial-gradient(circle_at_35%_35%,#f4d27a,#b88a2c_60%,#6b5326)]"
        style={{ width: size * 0.62, height: size * 0.45 }}
      />
    </span>
  );
}

/** Placeholder site photo. */
export function SiteThumb({ className = "h-8 w-12" }: { className?: string }) {
  return (
    <span
      className={`block shrink-0 rounded-md bg-[linear-gradient(160deg,#7a9a6b_0%,#a8754a_45%,#c98a55_70%,#6d4a2f_100%)] ${className}`}
    />
  );
}

export function Initials({ name, className = "" }: { name: string; className?: string }) {
  const init = name
    .split(" ")
    .map((n) => n[0])
    .join("")
    .slice(0, 2)
    .toUpperCase();
  return (
    <span className={`grid size-7 shrink-0 place-items-center rounded-full bg-violet-soft text-[11px] font-medium text-violet ${className}`}>
      {init}
    </span>
  );
}

/** Progress bar used in "Top Mineral Types". */
export function Bar({ value, color }: { value: number; color: string }) {
  return (
    <div className="h-1.5 w-full rounded-full bg-gray-100">
      <div className="h-full rounded-full" style={{ width: `${Math.min(100, value)}%`, background: color }} />
    </div>
  );
}

/** Empty-state row/card text. */
export function Empty({ children }: { children: React.ReactNode }) {
  return <p className="px-6 py-10 text-center text-sm text-ink/60">{children}</p>;
}
