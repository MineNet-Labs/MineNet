"use client";

import { useSyncExternalStore } from "react";
import { RegisterSiteModal, UploadDocModal, ListLotModal } from "@/components/forms";
import { RequestInspectionModal } from "@/app/miner/inspections/RequestInspectionModal";
import { InsureModal, RequestLoanModal } from "@/components/chain-forms";

/** Forms that open as a pop-up over whatever page you are on. */
export type FormKind = "site" | "inspection" | "document" | "sell" | "financing" | "insurance";
type Open = { kind: FormKind; lot?: string; site?: string } | null;

let open: Open = null;
const subs = new Set<() => void>();
const emit = () => subs.forEach((f) => f());
export const openForm = (kind: FormKind, lot?: string, site?: string) => ((open = { kind, lot, site }), emit());
const close = () => ((open = null), emit());

export function FormHost() {
  const f = useSyncExternalStore(
    (cb) => (subs.add(cb), () => void subs.delete(cb)),
    () => open,
    () => null,
  );
  if (!f) return null;
  switch (f.kind) {
    case "site": return <RegisterSiteModal onClose={close} />;
    case "inspection": return <RequestInspectionModal initialLot={f.lot ?? ""} onClose={close} />;
    case "document": return <UploadDocModal lotId={f.lot} siteId={f.site} onClose={close} />;
    case "sell": return <ListLotModal lotId={f.lot} onClose={close} />;
    case "financing": return <RequestLoanModal lotId={f.lot} onClose={close} />;
    case "insurance": return <InsureModal lotId={f.lot} onClose={close} />;
  }
}
