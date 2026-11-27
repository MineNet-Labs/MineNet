"use client";

// Tiny client store for the miner portal (no extra dependency).
// Changes are saved in localStorage so they survive reloads, until the
// backend API replaces this. Use selectors that return stored slices
// (e.g. `useStore((s) => s.lots)`) — derived arrays belong in useMemo.

import { useSyncExternalStore } from "react";
import { seed, type AppData } from "./data";

const KEY = "minenet.data.v1";
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

export function useStore<T>(select: (s: AppData) => T): T {
  return useSyncExternalStore(
    subscribe,
    () => {
      load();
      return select(state);
    },
    () => select(seed),
  );
}

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
