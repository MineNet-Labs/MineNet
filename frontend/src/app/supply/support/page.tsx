"use client";

import { SupportView } from "@/components/SupportView";

const faqs = [
  { q: "How does a lot get into my inventory?", a: "When a shipment is marked Delivered, its lot is added to the destination warehouse as Available. You can also register stock received outside MineNet from Inventory." },
  { q: "How do I trace a lot?", a: "Type its lot ID in the search bar or on Traceability. You see every stage from the mine to export, with the shipment, processing, refinery and export records." },
  { q: "When can I start refining?", a: "Once a processing batch passes its quality check, use Start refining on the Refinery page." },
  { q: "What moves an export declaration forward?", a: "Submit it, then customs reviews it. Once cleared, mark it exported when the lot leaves. A declaration that needs action goes back to review once you fix it." },
];

export default function SupplySupportPage() {
  return <SupportView faqs={faqs} subtitle="Answers for supply chain operators, or reach the MineNet team." />;
}
