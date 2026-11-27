"use client";

// Tiny client store for the miner portal (no extra dependency).
// Changes are saved in localStorage so they survive reloads, until the
// backend API replaces this. Use selectors that return stored slices
// (e.g. `useStore((s) => s.lots)`) — derived arrays belong in useMemo.

import { useSyncExternalStore } from "react";
import { seed, type AppData } from "./data";

const KEY = "minenet.data.v7";
let state: AppData = seed;
let loaded = false;
const listeners = new Set<() => void>();

function load() {
  if (loaded || typeof window === "undefined") return;
  loaded = true;
  try {
    const raw = localStorage.getItem(KEY);
    if (raw) state = { ...seed, ...(JSON.parse(raw) as Partial<AppData>) };
  } catch {
    state = seed;
  }
}

function subscribe(fn: () => void) {
  listeners.add(fn);
  return () => listeners.delete(fn);
}

/**
 * What the signed-in member may see: site managers only get their assigned
 * sites and everything that belongs to them. Cached so selectors stay stable.
 */
let scopedFor: AppData | null = null;
let scopedState: AppData = seed;
export function scope(s: AppData): AppData {
  if (s === scopedFor) return scopedState;
  const me = s.members.find((m) => m.id === s.sessionMemberId);
  let out = s;
  if (me?.role === "Site manager") {
    const ids = new Set(me.siteIds);
    const workerIds = new Set(s.workers.filter((w) => ids.has(w.siteId)).map((w) => w.id));
    const lotIds = new Set(s.lots.filter((l) => ids.has(l.siteId)).map((l) => l.id));
    out = {
      ...s,
      sites: s.sites.filter((x) => ids.has(x.id)),
      shafts: s.shafts.filter((x) => ids.has(x.siteId)),
      workers: s.workers.filter((x) => ids.has(x.siteId)),
      lots: s.lots.filter((x) => ids.has(x.siteId)),
      records: s.records.filter((x) => ids.has(x.siteId)),
      inspections: s.inspections.filter((x) => ids.has(x.siteId)),
      docs: s.docs.filter((x) => !x.siteId || ids.has(x.siteId)),
      transfers: s.transfers.filter((x) => lotIds.has(x.lotId)),
      attendance: s.attendance.filter((a) => workerIds.has(a.workerId)),
      leaves: s.leaves.filter((a) => workerIds.has(a.workerId)),
      incidents: s.incidents.filter((x) => ids.has(x.siteId)),
      shiftReports: s.shiftReports.filter((x) => ids.has(x.siteId)),
      events: s.events.filter((x) => lotIds.has(x.lotId)),
      approvals: s.approvals.filter((x) => x.memberId === me.id),
    };
  }
  scopedFor = s;
  scopedState = out;
  return out;
}

export function useStore<T>(select: (s: AppData) => T): T {
  return useSyncExternalStore(
    subscribe,
    () => {
      load();
      return select(scope(state));
    },
    () => select(seed),
  );
}

/** The signed-in team member. */
export const useMe = () => useStore((s) => s.members.find((m) => m.id === s.sessionMemberId) ?? s.members[0]);

/** Read the current state outside React (event handlers). */
export function getState() {
  load();
  return state;
}

export function update(fn: (s: AppData) => Partial<AppData>) {
  load();
  state = { ...state, ...fn(state) };
  try {
    localStorage.setItem(KEY, JSON.stringify(state));
  } catch {
    /* storage full or blocked: keep in memory */
  }
  listeners.forEach((l) => l());
}

/** Restore the original sample data. */
export function resetData() {
  state = seed;
  localStorage.removeItem(KEY);
  listeners.forEach((l) => l());
}

/** Next sequential id like "LOT-00125" from the existing ids. */
export function nextId(ids: string[], prefix: string, width = 5) {
  const max = ids.reduce((m, id) => {
    const n = Number(id.replace(/\D+/g, "").slice(-width));
    return Number.isFinite(n) && n > m ? n : m;
  }, 0);
  return `${prefix}${String(max + 1).padStart(width, "0")}`;
}

/** Lookup helpers */
export const siteName = (s: AppData, id: string) => s.sites.find((x) => x.id === id)?.name ?? id;
