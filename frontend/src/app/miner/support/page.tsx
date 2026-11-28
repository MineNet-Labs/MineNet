"use client";

import { SupportView } from "@/components/SupportView";

const faqs = [
  { q: "How do I get a mineral lot verified?", a: "Register the lot under Mineral Lots, then request an inspection from Inspections. Once the inspector attests the grade, the lot becomes Verified and can be sold on the Marketplace." },
  { q: "Why can't I list a lot on the Marketplace?", a: "Only Verified lots can be listed. Pending lots need a completed inspection first, and rejected lots must be re-inspected." },
  { q: "How do workers sign in?", a: "Each worker gets a QR access code linked to their site. Use “Send QR access code” in the Workers page for anyone still in setup." },
  { q: "What happens when a licence is about to expire?", a: "You'll see a reminder on the Overview and in Documents & Licences 60 days before expiry. Use “Request renewal” to notify the regulator." },
  { q: "Where does my data go?", a: "Until the MineNet backend is connected, everything you add is saved in this browser. Use “Reset demo data” in the account menu to start over." },
];

export default function SupportPage() {
  return <SupportView faqs={faqs} />;
}
