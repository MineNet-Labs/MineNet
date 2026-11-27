// Lot passport, custody, escrow, financing and insurance: types and sample
// data. Mirrors the on-chain model in project.md (ERC-721 lot passport with
// signed events). Until the contracts are wired in, hashes are simulated.

export type OrgStatus = "Validated" | "Pending" | "Suspended";
export type Org = {
  name: string;
  kind: string;
  rdbNumber: string;
  tin: string;
  regulator: string;
  licence: string;
  licenceIssued: string;
  licenceExpiry: string;
  status: OrgStatus;
  validatedBy: string;
  validatedOn: string;
  validatedUntil: string;
  suspensionReason?: string;
  renewalRequested?: string;
  wallet: string;
  contact: string;
  email: string;
  phone: string;
  address: string;
};

export type EventKind =
  | "Registered"
  | "Inspection requested"
  | "Inspected"
  | "Listed"
  | "Sold"
  | "Escrow locked"
  | "Handover"
  | "In transit"
  | "Delivered"
  | "Stored"
  | "Escrow released"
  | "Financed"
  | "Lien released"
  | "Insured"
  | "Document added";

export type LotEvent = {
  id: string;
  lotId: string;
  kind: EventKind;
  actor: string;
  role: string;
  date: string;
  detail: string;
  hash: string;
};

export type PartyKind = "Transporter" | "Warehouse" | "Financier" | "Insurer";
export type Party = { id: string; name: string; kind: PartyKind; location: string; licence: string; regulator: string };

export type TransferStatus = "Awaiting handover" | "In transit" | "Delivered" | "Stored" | "Cancelled";
export type Transfer = {
  id: string;
  lotId: string;
  kind: "Transport" | "Warehouse";
  partyId: string;
  from: string;
  to: string;
  seal: string;
  vehicle?: string;
  status: TransferStatus;
  senderConfirmed: boolean;
  receiverConfirmed: boolean;
  created: string;
};

export type EscrowStatus = "Locked" | "Released" | "Refunded";
export type Escrow = {
  id: string;
  lotId: string;
  offerId?: string;
  buyer: string;
  amount: number;
  currency: "USD" | "RWF";
  status: EscrowStatus;
  locked: string;
  released?: string;
  lienRepaid?: number;
};

export type LoanStatus = "Requested" | "Active" | "Repaid" | "Declined";
export type Loan = {
  id: string;
  lotId: string;
  financierId: string;
  amount: number;
  currency: "USD" | "RWF";
  ratePct: number;
  termDays: number;
  status: LoanStatus;
  requested: string;
  due?: string;
  purpose: string;
};

export type PolicyStatus = "Requested" | "Quoted" | "Active" | "Expired" | "Declined";
export type Policy = {
  id: string;
  lotId: string;
  insurerId: string;
  cover: "Storage" | "Transit" | "Storage & transit";
  sumInsured: number;
  premium: number;
  currency: "USD" | "RWF";
  status: PolicyStatus;
  from: string;
  to: string;
};

export type ClaimStatus = "Filed" | "Approved" | "Rejected";
export type Claim = { id: string; policyId: string; lotId: string; reason: string; amount: number; currency: "USD" | "RWF"; status: ClaimStatus; filed: string; decided?: string; note?: string };

export type NoticeKind = "inspection" | "licence" | "offer" | "custody" | "payment" | "finance" | "alert";
/** `audience` is "miner" (default) or "insurer:<partyId>". */
export type Notice = { id: string; kind: NoticeKind; text: string; href: string; date: string; read: boolean; audience?: string };

export type OfferMsg = { by: "You" | "Buyer"; pricePerKg: number; quantityKg: number; note?: string; date: string };

/** Deterministic stand-in for an on-chain transaction hash. */
export function simHash(input: string) {
  let h1 = 0x811c9dc5;
  let out = "";
  for (let round = 0; round < 8; round++) {
    for (let i = 0; i < input.length; i++) h1 = Math.imul(h1 ^ (input.charCodeAt(i) + round), 16777619) >>> 0;
    out += h1.toString(16).padStart(8, "0");
  }
  return `0x${out}`;
}

const ev = (id: string, lotId: string, kind: EventKind, actor: string, role: string, date: string, detail: string): LotEvent => ({
  id,
  lotId,
  kind,
  actor,
  role,
  date,
  detail,
  hash: simHash(`${id}${lotId}${kind}${date}`),
});

export const chainSeed = {
  org: {
    name: "Uwimana Mining Cooperative",
    kind: "Mining cooperative",
    rdbNumber: "RDB-108452317",
    tin: "TIN 102 445 781",
    regulator: "Rwanda Mines, Petroleum and Gas Board (RMB)",
    licence: "ML-2025-081",
    licenceIssued: "Mar 14, 2025",
    licenceExpiry: "Mar 14, 2027",
    status: "Validated",
    validatedBy: "RMB officer · M. Habineza",
    validatedOn: "Mar 20, 2025",
    validatedUntil: "Mar 14, 2027",
    wallet: "0x7A3f9c21B4e8D05a6C1d2E9f0B3a4C5d6E7f8091",
    contact: "Jean Uwimana",
    email: "jean@uwimana-coop.rw",
    phone: "+250 788 000 184",
    address: "KG 9 Ave, Gasabo, Kigali",
  } as Org,

  parties: [
    { id: "volcano", name: "Volcano Freight Ltd", kind: "Transporter", location: "Musanze", licence: "RURA-TG-2025-114", regulator: "RURA" },
    { id: "nyungwe", name: "Nyungwe Logistics", kind: "Transporter", location: "Kigali", licence: "RURA-TG-2025-087", regulator: "RURA" },
    { id: "kbw", name: "Kigali Bonded Warehouse", kind: "Warehouse", location: "Kigali", licence: "RRA-BW-2025-012", regulator: "RRA" },
    { id: "rms", name: "Rubavu Mineral Store", kind: "Warehouse", location: "Rubavu", licence: "RMB-WS-2025-031", regulator: "RMB" },
    { id: "umurenge", name: "Umurenge Trade Finance", kind: "Financier", location: "Kigali", licence: "BNR-LF-2024-022", regulator: "BNR" },
    { id: "kivu-capital", name: "Kivu Capital Partners", kind: "Financier", location: "Rubavu", licence: "BNR-LF-2025-009", regulator: "BNR" },
    { id: "isange", name: "Isange Assurance", kind: "Insurer", location: "Kigali", licence: "BNR-IN-2023-004", regulator: "BNR" },
    { id: "akagera", name: "Akagera Insurance Co.", kind: "Insurer", location: "Kigali", licence: "BNR-IN-2024-011", regulator: "BNR" },
  ] as Party[],

  events: [
    ev("EV-0001", "LOT-00117", "Inspection requested", "Jean Uwimana", "Miner", "Aug 11, 2025", "Pre-export certification requested"),
    ev("EV-0002", "LOT-00117", "Inspected", "Eric Nshimiyimana", "Inspector", "Aug 13, 2025", "Grade 62.0% WO₃ attested · conflict-free"),
    ev("EV-0003", "LOT-00117", "Listed", "Jean Uwimana", "Miner", "Aug 12, 2025", "Listed as LST-0005 at $14.50/kg"),
    ev("EV-0004", "LOT-00117", "Sold", "Rwanda Minerals Export SA", "Buyer", "Aug 15, 2025", "Offer OFF-0024 accepted · 900 kg"),
    ev("EV-0005", "LOT-00117", "Escrow locked", "Rwanda Minerals Export SA", "Buyer", "Aug 15, 2025", "USD 13,050 locked in escrow ESC-0002"),
    ev("EV-0006", "LOT-00117", "Insured", "Akagera Insurance Co.", "Insurer", "Aug 16, 2025", "Transit cover POL-0003 · USD 13,050"),
    ev("EV-0007", "LOT-00117", "Handover", "Volcano Freight Ltd", "Transporter", "Aug 17, 2025", "Custody to transporter · seal SL-48812"),
    ev("EV-0008", "LOT-00120", "Inspected", "Diane Uwamahoro", "Inspector", "Aug 22, 2025", "Grade 68.4% Sn attested"),
    ev("EV-0009", "LOT-00120", "Listed", "Jean Uwimana", "Miner", "Aug 22, 2025", "Listed as LST-0007 at $18.20/kg"),
    ev("EV-0010", "LOT-00120", "Handover", "Nyungwe Logistics", "Transporter", "Aug 23, 2025", "Custody to transporter · seal SL-48790"),
    ev("EV-0011", "LOT-00120", "Stored", "Kigali Bonded Warehouse", "Warehouse", "Aug 24, 2025", "Received 1,800 kg · bay C-14"),
    ev("EV-0012", "LOT-00120", "Insured", "Isange Assurance", "Insurer", "Aug 24, 2025", "Storage cover POL-0002 · USD 32,760"),
    ev("EV-0013", "LOT-00120", "Financed", "Umurenge Trade Finance", "Financier", "Aug 25, 2025", "Loan LN-0002 · USD 12,000 · lien recorded"),
    ev("EV-0014", "LOT-00115", "Inspected", "Diane Uwamahoro", "Inspector", "Aug 03, 2025", "Grade 98.1% Au attested"),
    ev("EV-0015", "LOT-00115", "Sold", "Great Lakes Minerals Co.", "Buyer", "Aug 05, 2025", "530 kg sold"),
    ev("EV-0016", "LOT-00115", "Delivered", "Great Lakes Minerals Co.", "Buyer", "Aug 09, 2025", "Delivery accepted"),
    ev("EV-0017", "LOT-00115", "Escrow released", "Escrow contract", "System", "Aug 09, 2025", "USD 42,300 released · lien LN-0001 repaid first"),
    ev("EV-0018", "LOT-00122", "Inspected", "Aline Mukamana", "Inspector", "Aug 27, 2025", "Grade 93.7% Ta attested"),
    ev("EV-0019", "LOT-00124", "Inspection requested", "Jean Uwimana", "Miner", "Aug 28, 2025", "Pre-export certification requested"),
  ] as LotEvent[],

  transfers: [
    { id: "TRF-0003", lotId: "LOT-00117", kind: "Transport", partyId: "volcano", from: "Gatumba Mine", to: "Rwanda Minerals Export SA, Kigali", seal: "SL-48812", vehicle: "RAD 412 K", status: "In transit", senderConfirmed: true, receiverConfirmed: true, created: "Aug 17, 2025" },
    { id: "TRF-0002", lotId: "LOT-00120", kind: "Warehouse", partyId: "kbw", from: "Nyungwe Logistics", to: "Kigali Bonded Warehouse", seal: "SL-48790", status: "Stored", senderConfirmed: true, receiverConfirmed: true, created: "Aug 24, 2025" },
    { id: "TRF-0001", lotId: "LOT-00120", kind: "Transport", partyId: "nyungwe", from: "Gatumba Mine", to: "Kigali Bonded Warehouse", seal: "SL-48790", vehicle: "RAC 908 B", status: "Delivered", senderConfirmed: true, receiverConfirmed: true, created: "Aug 23, 2025" },
  ] as Transfer[],

  escrows: [
    { id: "ESC-0002", lotId: "LOT-00117", offerId: "OFF-0024", buyer: "Rwanda Minerals Export SA", amount: 13050, currency: "USD", status: "Locked", locked: "Aug 15, 2025" },
    { id: "ESC-0001", lotId: "LOT-00115", buyer: "Great Lakes Minerals Co.", amount: 42300, currency: "USD", status: "Released", locked: "Aug 05, 2025", released: "Aug 09, 2025", lienRepaid: 8240 },
  ] as Escrow[],

  loans: [
    { id: "LN-0002", lotId: "LOT-00120", financierId: "umurenge", amount: 12000, currency: "USD", ratePct: 11, termDays: 90, status: "Active", requested: "Aug 24, 2025", due: "Nov 23, 2025", purpose: "Working capital" },
    { id: "LN-0001", lotId: "LOT-00115", financierId: "kivu-capital", amount: 8000, currency: "USD", ratePct: 12, termDays: 30, status: "Repaid", requested: "Jul 20, 2025", due: "Aug 19, 2025", purpose: "Equipment hire" },
  ] as Loan[],

  policies: [
    { id: "POL-0003", lotId: "LOT-00117", insurerId: "akagera", cover: "Transit", sumInsured: 13050, premium: 78, currency: "USD", status: "Active", from: "Aug 16, 2025", to: "Sep 16, 2025" },
    { id: "POL-0002", lotId: "LOT-00120", insurerId: "isange", cover: "Storage", sumInsured: 32760, premium: 131, currency: "USD", status: "Active", from: "Aug 24, 2025", to: "Nov 24, 2025" },
  ] as Policy[],

  claims: [
    { id: "CLM-0001", policyId: "POL-0002", lotId: "LOT-00120", reason: "Water damage to 40 kg in bay C-14 after roof leak", amount: 720, currency: "USD", status: "Filed", filed: "Aug 27, 2025" },
  ] as Claim[],

  /** Which insurer is using the insurer portal (demo; set by sign-in later). */
  insurerSessionId: "isange",
  /** Premium rates (share of value per month) each insurer quotes with. */
  insurerRates: {
    isange: { Storage: 0.004, Transit: 0.006, "Storage & transit": 0.009 },
    akagera: { Storage: 0.0045, Transit: 0.0055, "Storage & transit": 0.0095 },
  } as Record<string, Record<Policy["cover"], number>>,

  notices: [
    { id: "N-0007", kind: "alert", text: "New claim CLM-0001 from Uwimana Mining Cooperative on LOT-00120: USD 720", href: "/insurer/claims/CLM-0001", date: "Aug 27, 2025", read: false, audience: "insurer:isange" },
    { id: "N-0006", kind: "offer", text: "Great Lakes Minerals Co. countered your Coltan offer OFF-0029", href: "/miner/marketplace/offers/OFF-0029", date: "Aug 29, 2025", read: false },
    { id: "N-0005", kind: "custody", text: "LOT-00117 is in transit with Volcano Freight Ltd (seal SL-48812)", href: "/miner/mineral-lots/LOT-00117", date: "Aug 28, 2025", read: false },
    { id: "N-0004", kind: "inspection", text: "Inspection INS-2025-0092 for LOT-00121 is waiting for an inspector", href: "/miner/inspections/INS-2025-0092", date: "Aug 28, 2025", read: false },
    { id: "N-0003", kind: "licence", text: "Musanze Mine licence ML-2025-087 has expired: lots can't be registered there", href: "/miner/licence", date: "Aug 27, 2025", read: true },
    { id: "N-0002", kind: "finance", text: "Loan LN-0002 on LOT-00120 is active · USD 12,000", href: "/miner/financing", date: "Aug 25, 2025", read: true },
    { id: "N-0001", kind: "payment", text: "USD 42,300 released from escrow for LOT-00115", href: "/miner/payments", date: "Aug 09, 2025", read: true },
  ] as Notice[],
};
