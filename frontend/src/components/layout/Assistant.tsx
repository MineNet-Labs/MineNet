"use client";

import { useEffect, useRef, useState } from "react";
import { usePathname } from "next/navigation";
import { IconSend2, IconSparkles, IconX } from "@tabler/icons-react";
import { getState, siteName } from "@/lib/store";
import { fmtKg } from "@/lib/data";

type Msg = { from: "user" | "assistant"; text: string };

// Suggested questions per section of the miner portal.
const suggestionsByPage: Record<string, string[]> = {
  marketplace: ["Which offers need my response?", "Where can I sell my lots?", "Which requests close soon?"],
  "mining-sites": ["How many sites are active?", "Which licences expire soon?", "How many workers per site?"],
  "mine-shafts": ["Which shafts are in maintenance?", "What is the deepest shaft?", "How many sites are active?"],
  "extraction-records": ["How much did I extract?", "Which records are pending?", "Where can I sell my lots?"],
  "mineral-lots": ["Which lots are verified?", "Where can I sell my lots?", "Which inspections are pending?"],
  inspections: ["Which inspections are pending?", "Which lots are verified?", "Which shafts are in maintenance?"],
  workers: ["How many workers per site?", "Which workers need access setup?", "How many sites are active?"],
  payments: ["What payments are pending?", "How much have I received?", "Which offers need my response?"],
};
const defaultSuggestions = ["What needs my attention?", "Where can I sell my lots?", "What payments are pending?"];

const list = (xs: string[]) => (xs.length ? xs.join(", ") : "none");

// Answers computed from the live portal data, until the AI service is connected.
function answer(q: string): string {
  const s = getState();
  const t = q.toLowerCase();

  if (t.includes("attention")) {
    const countered = s.offers.filter((o) => o.status === "Countered").length;
    const pendingInsp = s.inspections.filter((i) => i.status === "Pending").length;
    const pendingPay = s.txns.filter((x) => x.status === "Pending" || x.status === "Processing").length;
    const maint = s.shafts.filter((x) => x.status === "Maintenance").length;
    return `You have ${countered} countered offer(s) to answer, ${pendingInsp} pending inspection(s), ${pendingPay} payment(s) in progress and ${maint} shaft(s) in maintenance.`;
  }
  if (t.includes("offer")) {
    const c = s.offers.filter((o) => o.status === "Countered");
    const sent = s.offers.filter((o) => o.status === "Sent");
    return `${c.length} offer(s) need your response${c.length ? ` (${list(c.map((o) => o.id))})` : ""}. ${sent.length} sent offer(s) are awaiting buyer replies.`;
  }
  if (t.includes("sell")) {
    const listed = new Set(s.listings.filter((l) => l.status === "Active").map((l) => l.lotId));
    const ready = s.lots.filter((l) => l.status === "Verified" && !listed.has(l.id));
    const minerals = new Set(ready.map((l) => l.mineral));
    const reqs = s.requests.filter((r) => minerals.has(r.mineral));
    return ready.length
      ? `${ready.length} verified lot(s) can be listed: ${list(ready.map((l) => `${l.id} (${l.mineral}, ${fmtKg(l.quantityKg)})`))}. Matching buyer requests: ${list(reqs.map((r) => r.buyer))}. Use "Sell a lot" on the Marketplace page.`
      : "You have no verified, unlisted lots right now. Get a lot inspected and verified first.";
  }
  if (t.includes("close") || t.includes("deadline")) {
    const r = [...s.requests].sort((a, b) => a.inDays - b.inDays).slice(0, 3);
    return `Closing soonest: ${list(r.map((x) => `${x.buyer} (${x.deadline}, in ${x.inDays} days)`))}.`;
  }
  if (t.includes("licence") || t.includes("license")) {
    const soon = [...s.sites].sort((a, b) => Date.parse(a.licenceExpiry) - Date.parse(b.licenceExpiry)).slice(0, 3);
    return `Earliest licence expiries: ${list(soon.map((x) => `${x.name} (${x.licenceExpiry})`))}.`;
  }
  if (t.includes("worker") && (t.includes("access") || t.includes("setup"))) {
    const w = s.workers.filter((x) => x.access === "Setup pending");
    return `${w.length} worker(s) still need access setup: ${list(w.map((x) => x.name))}.`;
  }
  if (t.includes("worker")) {
    const per = s.sites.map((x) => `${x.name}: ${s.workers.filter((w) => w.siteId === x.id).length}`);
    return `You have ${s.workers.length} workers. ${per.join("; ")}. Open a site to see its own workers.`;
  }
  if (t.includes("site")) {
    const a = s.sites.filter((x) => x.status === "Active");
    return `${a.length} of ${s.sites.length} sites are active. Inactive: ${list(s.sites.filter((x) => x.status !== "Active").map((x) => x.name))}.`;
  }
  if (t.includes("maintenance")) {
    const m = s.shafts.filter((x) => x.status === "Maintenance");
    return `${m.length} shaft(s) in maintenance: ${list(m.map((x) => `${x.name} at ${siteName(s, x.siteId)}`))}.`;
  }
  if (t.includes("deep")) {
    const d = [...s.shafts].sort((a, b) => b.depthM - a.depthM)[0];
    return d ? `The deepest shaft is ${d.name} at ${siteName(s, d.siteId)}, ${d.depthM} m.` : "No shafts recorded yet.";
  }
  if (t.includes("extract")) {
    const total = s.records.reduce((n, r) => n + r.quantityKg, 0);
    return `You have ${s.records.length} extraction records totalling ${fmtKg(total)}.`;
  }
  if (t.includes("record") && t.includes("pending")) {
    const p = s.records.filter((r) => r.status === "Pending");
    return `${p.length} record(s) are pending approval: ${list(p.map((r) => r.id))}.`;
  }
  if (t.includes("verified") || t.includes("lot")) {
    const v = s.lots.filter((l) => l.status === "Verified");
    return `${v.length} of ${s.lots.length} lots are verified: ${list(v.map((l) => l.id))}.`;
  }
  if (t.includes("inspection")) {
    const p = s.inspections.filter((i) => i.status === "Pending" || i.status === "Scheduled");
    return `${p.length} inspection(s) are pending or scheduled: ${list(p.map((i) => `${i.id} (${i.mineral})`))}.`;
  }
  if (t.includes("received")) {
    const r = s.txns.filter((x) => x.direction === "in" && x.status === "Received");
    const sum = (c: string) => r.filter((x) => x.currency === c).reduce((n, x) => n + x.amount, 0).toLocaleString();
    return `Received so far: RWF ${sum("RWF")} and USD ${sum("USD")} across ${r.length} payment(s).`;
  }
  if (t.includes("payment") || t.includes("pay")) {
    const p = s.txns.filter((x) => x.status === "Pending" || x.status === "Processing");
    return `${p.length} payment(s) are pending or processing: ${list(p.map((x) => `${x.party} (${x.currency} ${x.amount.toLocaleString()})`))}.`;
  }
  return "I can answer questions about your sites, shafts, workers, lots, inspections, marketplace offers and payments. Try one of the suggestions.";
}

/** Floating MineNet assistant, available on every miner page (bottom-right). */
export function Assistant() {
  const path = usePathname();
  const section = path.split("/")[2] ?? "";
  const suggestions = suggestionsByPage[section] ?? defaultSuggestions;

  const [open, setOpen] = useState(false);
  const [msgs, setMsgs] = useState<Msg[]>([]);
  const [input, setInput] = useState("");
  const end = useRef<HTMLDivElement>(null);

  useEffect(() => end.current?.scrollIntoView({ behavior: "smooth" }), [msgs]);

  const ask = (q: string) => {
    if (!q.trim()) return;
    setMsgs((m) => [...m, { from: "user", text: q }, { from: "assistant", text: answer(q) }]);
    setInput("");
  };

  return (
    <>
      {open && (
        <section
          role="dialog"
          aria-label="MineNet assistant"
          className="fixed right-6 bottom-24 z-40 flex h-[460px] w-[360px] flex-col rounded-[22px] bg-white shadow-[0_20px_60px_rgba(17,24,39,0.18)]"
        >
          <header className="flex items-start justify-between border-b border-gray-100 px-5 pt-5 pb-4">
            <div>
              <h2 className="font-sans text-[15px] font-semibold">MineNet assistant</h2>
              <p className="text-xs text-ink/60">Answers from your sites, lots, offers and payments</p>
            </div>
            <button onClick={() => setOpen(false)} aria-label="Close assistant" className="grid size-8 place-items-center rounded-full bg-page">
              <IconX className="size-4" stroke={2.2} />
            </button>
          </header>

          <div className="flex-1 space-y-3 overflow-y-auto px-5 py-4 text-sm">
            {msgs.length === 0 && <p className="text-ink/80">Ask me anything about your operations. Try one of these:</p>}
            {msgs.map((m, i) => (
              <p
                key={i}
                className={`max-w-[88%] rounded-2xl px-3.5 py-2.5 ${m.from === "user" ? "ml-auto bg-[#1F5B3A] text-white" : "bg-page text-ink"}`}
              >
                {m.text}
              </p>
            ))}
            {msgs.length === 0 &&
              suggestions.map((q) => (
                <button
                  key={q}
                  onClick={() => ask(q)}
                  className="block w-full rounded-xl border border-gray-200 px-4 py-2.5 text-left hover:border-[#1F5B3A]/40 hover:bg-primary-soft/40"
                >
                  {q}
                </button>
              ))}
            <div ref={end} />
          </div>

          <form
            className="flex items-center gap-2 border-t border-gray-100 px-3 py-3"
            onSubmit={(e) => {
              e.preventDefault();
              ask(input);
            }}
          >
            <input
              value={input}
              onChange={(e) => setInput(e.target.value)}
              placeholder="Ask a question..."
              className="h-10 flex-1 rounded-full bg-page px-4 text-sm outline-none placeholder:text-gray-400"
            />
            <button
              type="submit"
              aria-label="Send"
              disabled={!input.trim()}
              className="grid size-10 place-items-center rounded-full bg-[#1F5B3A] text-white disabled:opacity-40"
            >
              <IconSend2 className="size-5" />
            </button>
          </form>
        </section>
      )}

      <button
        onClick={() => setOpen((o) => !o)}
        aria-label={open ? "Close assistant" : "Open MineNet assistant"}
        className={`fixed right-6 bottom-6 z-40 flex items-center gap-2 rounded-full bg-[#1F5B3A] text-white shadow-[0_8px_24px_rgba(31,91,58,0.35)] hover:bg-primary ${
          open ? "px-5 py-3 text-[15px] font-medium" : "size-14 justify-center"
        }`}
      >
        {open ? (
          <>
            <IconX className="size-5" stroke={2.2} /> Close
          </>
        ) : (
          <IconSparkles className="size-7" stroke={1.8} />
        )}
      </button>
    </>
  );
}
