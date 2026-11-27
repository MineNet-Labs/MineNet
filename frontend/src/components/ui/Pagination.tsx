"use client";

import { useState } from "react";
import { IconChevronLeft, IconChevronRight } from "@tabler/icons-react";

/** Paginates a list: returns the current page's rows and pager props. */
export function usePaged<T>(rows: T[], perPage = 6) {
  const [page, setPage] = useState(1);
  const pages = Math.max(1, Math.ceil(rows.length / perPage));
  const current = Math.min(page, pages); // stays valid when filters shrink the list
  const start = (current - 1) * perPage;
  return {
    rows: rows.slice(start, start + perPage),
    pager: {
      page: current,
      pages,
      onChange: setPage,
      from: rows.length ? start + 1 : 0,
      to: Math.min(start + perPage, rows.length),
      total: rows.length,
    },
  };
}

export function Pagination({
  page,
  pages,
  onChange,
  from,
  to,
  total,
  noun = "records",
}: {
  page: number;
  pages: number;
  onChange: (p: number) => void;
  from: number;
  to: number;
  total: number;
  noun?: string;
}) {
  const base = "grid size-9 place-items-center rounded-full border text-sm disabled:opacity-40";
  return (
    <div className="flex items-center justify-between px-6 py-5">
      <p className="text-[15px] text-ink/80">
        {total ? `Showing ${from}-${to} of ${total} ${noun}` : `No ${noun} match these filters`}
      </p>
      {pages > 1 && (
        <div className="flex items-center gap-2">
          <button className={`${base} border-gray-200`} aria-label="Previous page" disabled={page === 1} onClick={() => onChange(page - 1)}>
            <IconChevronLeft className="size-4" />
          </button>
          {Array.from({ length: pages }, (_, i) => i + 1).map((p) => (
            <button
              key={p}
              onClick={() => onChange(p)}
              aria-current={p === page ? "page" : undefined}
              className={p === page ? `${base} border-transparent bg-[#1F5B3A] text-white` : `${base} border-gray-200 text-ink hover:bg-page`}
            >
              {p}
            </button>
          ))}
          <button className={`${base} border-gray-200`} aria-label="Next page" disabled={page === pages} onClick={() => onChange(page + 1)}>
            <IconChevronRight className="size-4" />
          </button>
        </div>
      )}
    </div>
  );
}
