// MineNet domain types and seed (sample) data.
// Everything the miner portal shows starts from here; the store (store.ts)
// keeps changes in the browser until the backend API exists.

export type SiteStatus = "Active" | "Inactive";
export type Site = {
  id: string;
  name: string;
  district: string;
  location: string;
  lat: number;
  lng: number;
  status: SiteStatus;
  areaHa: number;
  lastActivity: string;
  minerals: string[];
  licence: string;
  licenceExpiry: string;
  manager: string;
};

export type ShaftStatus = "Operational" | "Maintenance" | "Closed";
export type Shaft = {
  id: string;
  siteId: string;
  name: string;
  depthM: number;
  mineral: string;
  status: ShaftStatus;
  lastInspection: string;
};

export type Access = "QR ready" | "Verified" | "Setup pending";
export type Worker = {
  id: string;
  name: string;
  siteId: string;
  category: string;
  access: Access;
  status: "Active" | "Inactive";
  phone: string;
  joined: string;
};

export type LotStatus = "Verified" | "Pending" | "Rejected";
export type Lot = {
  id: string;
  mineral: string;
  quantityKg: number;
  grade: number; // %
  siteId: string;
  status: LotStatus;
  created: string;
};

export type RecordStatus = "Approved" | "Pending" | "Rejected";
export type ExtractionRecord = {
  id: string;
  siteId: string;
  shaftId?: string;
  mineral: string;
  quantityKg: number;
  date: string;
  status: RecordStatus;
};

export type InspectionStatus = "Pending" | "Scheduled" | "In Progress" | "Completed" | "Rejected";
export type Inspection = {
  id: string;
  lotId: string;
  mineral: string;
  siteId: string;
  shaft: string;
  submitted: string;
  type: string;
  inspector?: string;
  status: InspectionStatus;
};

export type BuyerRequest = {
  id: string;
  buyer: string;
  verified: boolean;
  offers: number;
  mineral: string;
  remainingT: number;
  requiredT: number;
  grade: string;
  city: string;
  country: string;
  deadline: string;
  inDays: number;
  pricePerKg: number; // indicative, USD
  notes: string;
};

export type Listing = {
  id: string;
  lotId: string;
  mineral: string;
  quantityKg: number;
  pricePerKg: number;
  currency: "USD" | "RWF";
  location: string;
  status: "Active" | "Sold" | "Withdrawn";
  offers: number;
  posted: string;
  notes?: string;
};

export type OfferStatus = "Sent" | "Countered" | "Accepted" | "Declined";
export type Offer = {
  id: string;
  requestId: string;
  lotId: string;
  quantityKg: number;
  pricePerKg: number;
  currency: "USD" | "RWF";
  status: OfferStatus;
  sent: string;
};

export type TxnStatus = "Received" | "Paid" | "Pending" | "Processing" | "Failed";
export type Txn = {
  id: string;
  direction: "in" | "out";
  party: string;
  ref: string;
  amount: number;
  currency: "RWF" | "USD";
  method: string;
  date: string;
  status: TxnStatus;
};

export type Doc = {
  id: string;
  name: string;
  kind: "Mining Licence" | "Export Permit" | "Transport Permit" | "Environmental" | "Certificate" | "Other";
  siteId?: string;
  number: string;
  issued: string;
  expires?: string;
  fileName: string;
};

/* --------------------------------------------------------------- helpers */

export const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];

/** Today as "Mon DD, YYYY" (the format used across the app). */
export function today() {
  const d = new Date();
  return `${MONTHS[d.getMonth()]} ${String(d.getDate()).padStart(2, "0")}, ${d.getFullYear()}`;
}

/** Parses "Aug 28, 2025" → timestamp (for sorting). */
export function parseDate(s: string) {
  const t = Date.parse(s);
  return Number.isNaN(t) ? 0 : t;
}

export const fmtKg = (kg: number) => (kg >= 1000 ? `${+(kg / 1000).toFixed(2)} t` : `${kg} kg`);
export const fmtNum = (n: number, decimals = 0) =>
  n.toLocaleString("en-US", { minimumFractionDigits: decimals, maximumFractionDigits: decimals });

export const MINERALS = ["Gold", "Coltan", "Cassiterite", "Wolframite", "Tantalum", "Tin"];
export const WORK_CATEGORIES = ["Miner", "Loader", "Sorter", "Mineral Sorter", "Site assistant", "Transport support", "Supervisor"];

/* ------------------------------------------------------------------ seed */

export const seed = {
  sites: [
    { id: "kigali", name: "Kigali Gold Mine", district: "Gasabo", location: "Kigali City", lat: -1.89, lng: 30.11, status: "Active", areaHa: 32.5, lastActivity: "Jun 28, 2025", minerals: ["Gold"], licence: "ML-2025-081", licenceExpiry: "Mar 14, 2027", manager: "Jean Uwimana" },
    { id: "ruhango", name: "Ruhango Mine", district: "Ruhango", location: "Ruhango", lat: -2.23, lng: 29.78, status: "Active", areaHa: 28.0, lastActivity: "Jun 27, 2025", minerals: ["Gold", "Cassiterite"], licence: "ML-2025-082", licenceExpiry: "Jan 30, 2027", manager: "Claude Mugisha" },
    { id: "nyabihu", name: "Nyabihu Mine", district: "Nyabihu", location: "Nyabihu", lat: -1.65, lng: 29.51, status: "Active", areaHa: 24.7, lastActivity: "Jun 26, 2025", minerals: ["Tantalum", "Coltan"], licence: "ML-2025-083", licenceExpiry: "Nov 02, 2026", manager: "Grace Mukeshimana" },
    { id: "musanze", name: "Musanze Mine", district: "Musanze", location: "Musanze", lat: -1.5, lng: 29.63, status: "Active", areaHa: 26.1, lastActivity: "Jun 25, 2025", minerals: ["Coltan", "Cassiterite"], licence: "ML-2025-087", licenceExpiry: "Sep 05, 2025", manager: "Eric Nshimiyimana" },
    { id: "rubavu", name: "Coltan Site", district: "Rubavu", location: "Rubavu", lat: -1.68, lng: 29.36, status: "Inactive", areaHa: 18.3, lastActivity: "Jun 20, 2025", minerals: ["Coltan"], licence: "ML-2024-061", licenceExpiry: "Dec 18, 2025", manager: "Samuel Nkurunziza" },
    { id: "gatumba", name: "Gatumba Mine", district: "Ngororero", location: "Rusizi", lat: -1.86, lng: 29.6, status: "Active", areaHa: 20.0, lastActivity: "Jun 18, 2025", minerals: ["Cassiterite", "Wolframite"], licence: "ML-2025-090", licenceExpiry: "Jun 21, 2027", manager: "Diane Uwamahoro" },
    { id: "kamonyi", name: "Kamonyi Shaft", district: "Kamonyi", location: "Kamonyi", lat: -2.0, lng: 29.9, status: "Active", areaHa: 12.4, lastActivity: "Jun 16, 2025", minerals: ["Gold"], licence: "ML-2025-091", licenceExpiry: "Feb 11, 2027", manager: "Patrick Habimana" },
    { id: "rulindo", name: "Rutongo Mine", district: "Rulindo", location: "Rulindo", lat: -1.8, lng: 30.05, status: "Active", areaHa: 9.8, lastActivity: "Jun 12, 2025", minerals: ["Cassiterite"], licence: "ML-2025-093", licenceExpiry: "Aug 09, 2027", manager: "Aline Mukamana" },
    { id: "rusizi", name: "Rusizi Site", district: "Rusizi", location: "Rusizi", lat: -2.48, lng: 28.93, status: "Active", areaHa: 7.6, lastActivity: "Jun 10, 2025", minerals: ["Gold"], licence: "ML-2025-095", licenceExpiry: "Oct 30, 2027", manager: "Clarisse Ingabire" },
    { id: "nyamasheke", name: "Nyamasheke Site", district: "Nyamasheke", location: "Nyamasheke", lat: -2.32, lng: 29.13, status: "Inactive", areaHa: 5.1, lastActivity: "May 29, 2025", minerals: ["Wolframite"], licence: "ML-2024-058", licenceExpiry: "Jul 01, 2026", manager: "Samuel Nkurunziza" },
  ] as Site[],

  shafts: [
    { id: "K-01", siteId: "kigali", name: "Shaft K-01", depthM: 84, mineral: "Gold", status: "Operational", lastInspection: "Aug 14, 2025" },
    { id: "K-04", siteId: "kigali", name: "Shaft K-04", depthM: 112, mineral: "Gold", status: "Operational", lastInspection: "Aug 14, 2025" },
    { id: "R-01", siteId: "ruhango", name: "Shaft R-01", depthM: 66, mineral: "Gold", status: "Operational", lastInspection: "Aug 25, 2025" },
    { id: "R-02", siteId: "ruhango", name: "Shaft R-02", depthM: 48, mineral: "Cassiterite", status: "Maintenance", lastInspection: "Jul 30, 2025" },
    { id: "N-01", siteId: "nyabihu", name: "Shaft N-01", depthM: 57, mineral: "Coltan", status: "Operational", lastInspection: "Aug 09, 2025" },
    { id: "N-03", siteId: "nyabihu", name: "Shaft N-03", depthM: 73, mineral: "Tantalum", status: "Operational", lastInspection: "Aug 28, 2025" },
    { id: "M-02", siteId: "musanze", name: "Shaft M-02", depthM: 61, mineral: "Coltan", status: "Operational", lastInspection: "Aug 21, 2025" },
    { id: "C-01", siteId: "rubavu", name: "Shaft C-01", depthM: 39, mineral: "Coltan", status: "Closed", lastInspection: "May 18, 2025" },
    { id: "G-01", siteId: "gatumba", name: "Shaft G-01", depthM: 95, mineral: "Cassiterite", status: "Operational", lastInspection: "Aug 02, 2025" },
    { id: "KM-01", siteId: "kamonyi", name: "Shaft KM-01", depthM: 52, mineral: "Gold", status: "Operational", lastInspection: "Jul 22, 2025" },
    { id: "RT-01", siteId: "rulindo", name: "Shaft RT-01", depthM: 44, mineral: "Cassiterite", status: "Maintenance", lastInspection: "Jul 12, 2025" },
  ] as Shaft[],

  workers: [
    { id: "WRK-0021", name: "Aline Mukamana", siteId: "kigali", category: "Miner", access: "QR ready", status: "Active", phone: "078 ••• 1184", joined: "Mar 02, 2025" },
    { id: "WRK-0022", name: "Eric Ndayisaba", siteId: "ruhango", category: "Loader", access: "Verified", status: "Active", phone: "073 ••• 4402", joined: "Mar 09, 2025" },
    { id: "WRK-0023", name: "Diane Uwamahoro", siteId: "nyabihu", category: "Sorter", access: "Setup pending", status: "Active", phone: "079 ••• 5520", joined: "Apr 11, 2025" },
    { id: "WRK-0024", name: "Patrick Habimana", siteId: "kigali", category: "Site assistant", access: "Verified", status: "Active", phone: "078 ••• 7731", joined: "Apr 18, 2025" },
    { id: "WRK-0025", name: "Clarisse Ingabire", siteId: "musanze", category: "Miner", access: "QR ready", status: "Inactive", phone: "072 ••• 3310", joined: "May 05, 2025" },
    { id: "WRK-0026", name: "Samuel Nkurunziza", siteId: "ruhango", category: "Transport support", access: "Verified", status: "Active", phone: "078 ••• 9054", joined: "May 12, 2025" },
    { id: "WRK-0027", name: "Grace Mukeshimana", siteId: "nyabihu", category: "Supervisor", access: "Verified", status: "Active", phone: "079 ••• 2218", joined: "May 20, 2025" },
    { id: "WRK-0028", name: "Jean Bosco Hakizimana", siteId: "gatumba", category: "Miner", access: "Verified", status: "Active", phone: "078 ••• 6602", joined: "Jun 01, 2025" },
    { id: "WRK-0029", name: "Claudine Uwase", siteId: "kigali", category: "Sorter", access: "QR ready", status: "Active", phone: "073 ••• 1129", joined: "Jun 08, 2025" },
    { id: "WRK-0030", name: "Innocent Niyonzima", siteId: "musanze", category: "Loader", access: "Setup pending", status: "Active", phone: "072 ••• 8841", joined: "Jun 15, 2025" },
    { id: "WRK-0031", name: "Vestine Mukandayisenga", siteId: "kamonyi", category: "Miner", access: "Verified", status: "Active", phone: "078 ••• 4471", joined: "Jun 22, 2025" },
    { id: "WRK-0032", name: "Olivier Habyarimana", siteId: "rubavu", category: "Miner", access: "Verified", status: "Inactive", phone: "079 ••• 3307", joined: "Jul 01, 2025" },
    { id: "WRK-0033", name: "Josiane Mutoni", siteId: "rulindo", category: "Mineral Sorter", access: "Verified", status: "Active", phone: "073 ••• 9902", joined: "Jul 07, 2025" },
    { id: "WRK-0034", name: "Emmanuel Twagirayezu", siteId: "gatumba", category: "Supervisor", access: "Verified", status: "Active", phone: "078 ••• 2266", joined: "Jul 14, 2025" },
    { id: "WRK-0035", name: "Alice Umutoni", siteId: "ruhango", category: "Sorter", access: "QR ready", status: "Active", phone: "072 ••• 5579", joined: "Jul 21, 2025" },
    { id: "WRK-0036", name: "Fabrice Iradukunda", siteId: "rusizi", category: "Miner", access: "Verified", status: "Inactive", phone: "079 ••• 6118", joined: "Jul 28, 2025" },
    { id: "WRK-0037", name: "Sandrine Uwimbabazi", siteId: "kigali", category: "Transport support", access: "Verified", status: "Active", phone: "078 ••• 0435", joined: "Aug 04, 2025" },
    { id: "WRK-0038", name: "Thierry Mugabo", siteId: "nyabihu", category: "Miner", access: "Verified", status: "Active", phone: "073 ••• 7790", joined: "Aug 11, 2025" },
  ] as Worker[],

  lots: [
    { id: "LOT-00124", mineral: "Gold", quantityKg: 500, grade: 98.5, siteId: "kigali", status: "Verified", created: "Aug 28, 2025" },
    { id: "LOT-00123", mineral: "Coltan", quantityKg: 300, grade: 95.2, siteId: "musanze", status: "Pending", created: "Aug 27, 2025" },
    { id: "LOT-00122", mineral: "Tantalum", quantityKg: 200, grade: 93.7, siteId: "nyabihu", status: "Verified", created: "Aug 25, 2025" },
    { id: "LOT-00121", mineral: "Tin", quantityKg: 150, grade: 92.1, siteId: "rubavu", status: "Verified", created: "Aug 24, 2025" },
    { id: "LOT-00120", mineral: "Cassiterite", quantityKg: 1800, grade: 68.4, siteId: "gatumba", status: "Verified", created: "Aug 21, 2025" },
    { id: "LOT-00119", mineral: "Gold", quantityKg: 620, grade: 97.9, siteId: "kigali", status: "Verified", created: "Aug 18, 2025" },
    { id: "LOT-00118", mineral: "Coltan", quantityKg: 480, grade: 31.5, siteId: "ruhango", status: "Pending", created: "Aug 15, 2025" },
    { id: "LOT-00117", mineral: "Wolframite", quantityKg: 900, grade: 62.0, siteId: "gatumba", status: "Verified", created: "Aug 11, 2025" },
    { id: "LOT-00116", mineral: "Cassiterite", quantityKg: 1200, grade: 66.1, siteId: "rulindo", status: "Rejected", created: "Aug 07, 2025" },
    { id: "LOT-00115", mineral: "Gold", quantityKg: 530, grade: 98.1, siteId: "kamonyi", status: "Verified", created: "Aug 02, 2025" },
  ] as Lot[],

  records: [
    { id: "ER-2025-1047", siteId: "kamonyi", shaftId: "KM-01", mineral: "Gold", quantityKg: 120, date: "Aug 28, 2025", status: "Approved" },
    { id: "ER-2025-1046", siteId: "musanze", shaftId: "M-02", mineral: "Coltan", quantityKg: 85, date: "Aug 27, 2025", status: "Pending" },
    { id: "ER-2025-1045", siteId: "ruhango", shaftId: "R-01", mineral: "Gold", quantityKg: 200, date: "Aug 26, 2025", status: "Approved" },
    { id: "ER-2025-1044", siteId: "nyabihu", shaftId: "N-03", mineral: "Tantalum", quantityKg: 75, date: "Aug 24, 2025", status: "Rejected" },
    { id: "ER-2025-1043", siteId: "rubavu", shaftId: "C-01", mineral: "Gold", quantityKg: 110, date: "Aug 22, 2025", status: "Approved" },
    { id: "ER-2025-1042", siteId: "kigali", shaftId: "K-04", mineral: "Coltan", quantityKg: 90, date: "Aug 20, 2025", status: "Approved" },
    { id: "ER-2025-1041", siteId: "gatumba", shaftId: "G-01", mineral: "Cassiterite", quantityKg: 340, date: "Aug 18, 2025", status: "Approved" },
    { id: "ER-2025-1040", siteId: "kigali", shaftId: "K-01", mineral: "Gold", quantityKg: 95, date: "Aug 16, 2025", status: "Approved" },
    { id: "ER-2025-1039", siteId: "nyabihu", shaftId: "N-01", mineral: "Coltan", quantityKg: 130, date: "Aug 14, 2025", status: "Pending" },
    { id: "ER-2025-1038", siteId: "rulindo", shaftId: "RT-01", mineral: "Cassiterite", quantityKg: 210, date: "Aug 12, 2025", status: "Approved" },
    { id: "ER-2025-1037", siteId: "ruhango", shaftId: "R-02", mineral: "Cassiterite", quantityKg: 160, date: "Aug 09, 2025", status: "Approved" },
    { id: "ER-2025-1036", siteId: "musanze", shaftId: "M-02", mineral: "Coltan", quantityKg: 70, date: "Aug 06, 2025", status: "Rejected" },
    { id: "ER-2025-1035", siteId: "kamonyi", shaftId: "KM-01", mineral: "Gold", quantityKg: 105, date: "Aug 03, 2025", status: "Approved" },
  ] as ExtractionRecord[],

  inspections: [
    { id: "INS-2025-0091", lotId: "LOT-2025-0148", mineral: "Cassiterite", siteId: "nyabihu", shaft: "Shaft N-03", submitted: "Aug 28, 2025", type: "Grade Verification", status: "Pending" },
    { id: "INS-2025-0089", lotId: "LOT-2025-0146", mineral: "Coltan", siteId: "ruhango", shaft: "Shaft R-01", submitted: "Aug 25, 2025", type: "Purity Assay", inspector: "Aline Mukamana", status: "Scheduled" },
    { id: "INS-2025-0087", lotId: "LOT-2025-0143", mineral: "Wolframite", siteId: "musanze", shaft: "Shaft M-02", submitted: "Aug 21, 2025", type: "Pre-export Certification", inspector: "Eric Nshimiyimana", status: "In Progress" },
    { id: "INS-2025-0084", lotId: "LOT-2025-0139", mineral: "Cassiterite", siteId: "kigali", shaft: "Shaft K-04", submitted: "Aug 14, 2025", type: "Grade Verification", inspector: "Diane Uwamahoro", status: "Completed" },
    { id: "INS-2025-0081", lotId: "LOT-2025-0136", mineral: "Coltan", siteId: "nyabihu", shaft: "Shaft N-01", submitted: "Aug 09, 2025", type: "Site Compliance", inspector: "Patrick Habimana", status: "Rejected" },
    { id: "INS-2025-0078", lotId: "LOT-2025-0133", mineral: "Coltan", siteId: "ruhango", shaft: "Shaft R-02", submitted: "Aug 03, 2025", type: "Purity Assay", inspector: "Aline Mukamana", status: "Completed" },
    { id: "INS-2025-0074", lotId: "LOT-2025-0129", mineral: "Gold", siteId: "kigali", shaft: "Shaft K-01", submitted: "Jul 28, 2025", type: "Grade Verification", inspector: "Diane Uwamahoro", status: "Completed" },
    { id: "INS-2025-0070", lotId: "LOT-2025-0125", mineral: "Cassiterite", siteId: "gatumba", shaft: "Shaft G-01", submitted: "Jul 21, 2025", type: "Pre-export Certification", inspector: "Eric Nshimiyimana", status: "Completed" },
  ] as Inspection[],

  requests: [
    { id: "MKT-2025-0218", buyer: "Kigali Tin Traders Ltd", verified: true, offers: 6, mineral: "Cassiterite", remainingT: 3.2, requiredT: 5, grade: "≥ 65% Sn", city: "Kigali", country: "Rwanda", deadline: "Sep 20", inDays: 22, pricePerKg: 18.5, notes: "Delivery to Kigali bonded warehouse. ITSCI tags required." },
    { id: "MKT-2025-0216", buyer: "Great Lakes Minerals Co.", verified: true, offers: 3, mineral: "Coltan", remainingT: 2, requiredT: 2, grade: "≥ 30% Ta₂O₅", city: "Dar es Salaam", country: "Tanzania", deadline: "Oct 05", inDays: 37, pricePerKg: 42, notes: "FOB Dar es Salaam. Pre-export certificate needed." },
    { id: "MKT-2025-0215", buyer: "Rwanda Minerals Export SA", verified: true, offers: 2, mineral: "Wolframite", remainingT: 1.8, requiredT: 3, grade: "≥ 60% WO₃", city: "Kigali", country: "Rwanda", deadline: "Sep 30", inDays: 32, pricePerKg: 14.2, notes: "Partial deliveries accepted." },
    { id: "MKT-2025-0213", buyer: "Musanze Smelting Co-op", verified: true, offers: 4, mineral: "Cassiterite", remainingT: 1.5, requiredT: 1.5, grade: "≥ 60% Sn", city: "Musanze", country: "Rwanda", deadline: "Sep 12", inDays: 14, pricePerKg: 17.8, notes: "Collection from site possible within Northern Province." },
    { id: "MKT-2025-0211", buyer: "East Africa Coltan Buyers", verified: false, offers: 1, mineral: "Coltan", remainingT: 0.9, requiredT: 1.2, grade: "≥ 25% Ta₂O₅", city: "Mombasa", country: "Kenya", deadline: "Sep 18", inDays: 20, pricePerKg: 39.5, notes: "Buyer verification in progress." },
    { id: "MKT-2025-0209", buyer: "Kivu Metals Trading", verified: true, offers: 2, mineral: "Cassiterite", remainingT: 2.6, requiredT: 4, grade: "≥ 55% Sn", city: "Rubavu", country: "Rwanda", deadline: "Oct 01", inDays: 33, pricePerKg: 17.2, notes: "Payment within 7 days of delivery." },
  ] as BuyerRequest[],

  listings: [
    { id: "LST-0007", lotId: "LOT-00120", mineral: "Cassiterite", quantityKg: 1800, pricePerKg: 18.2, currency: "USD", location: "Ngororero, Rwanda", status: "Active", offers: 2, posted: "Aug 22, 2025" },
    { id: "LST-0005", lotId: "LOT-00117", mineral: "Wolframite", quantityKg: 900, pricePerKg: 14.5, currency: "USD", location: "Ngororero, Rwanda", status: "Sold", offers: 3, posted: "Aug 12, 2025" },
  ] as Listing[],

  offers: [
    { id: "OFF-0031", requestId: "MKT-2025-0218", lotId: "LOT-00120", quantityKg: 1500, pricePerKg: 18.4, currency: "USD", status: "Sent", sent: "Aug 26, 2025" },
    { id: "OFF-0029", requestId: "MKT-2025-0216", lotId: "LOT-00123", quantityKg: 300, pricePerKg: 43, currency: "USD", status: "Countered", sent: "Aug 23, 2025" },
    { id: "OFF-0024", requestId: "MKT-2025-0215", lotId: "LOT-00117", quantityKg: 900, pricePerKg: 14.5, currency: "USD", status: "Accepted", sent: "Aug 14, 2025" },
    { id: "OFF-0021", requestId: "MKT-2025-0213", lotId: "LOT-00116", quantityKg: 1200, pricePerKg: 17.5, currency: "USD", status: "Accepted", sent: "Aug 08, 2025" },
  ] as Offer[],

  txns: [
    { id: "TXN-IN-2508-014", direction: "in", party: "Kigali Tin Traders Ltd", ref: "LOT-2025-0139 · Sale S-0412", amount: 18450000, currency: "RWF", method: "Bank Transfer", date: "Aug 28, 2025", status: "Received" },
    { id: "TXN-IN-2508-011", direction: "in", party: "Great Lakes Minerals Co.", ref: "LOT-2025-0133 · Sale S-0407", amount: 42300, currency: "USD", method: "Electronic Banking", date: "Aug 24, 2025", status: "Received" },
    { id: "TXN-IN-2508-009", direction: "in", party: "Rwanda Minerals Export SA", ref: "Invoice INV-2025-0218", amount: 9860000, currency: "RWF", method: "Bank Transfer", date: "Aug 20, 2025", status: "Pending" },
    { id: "TXN-IN-2508-007", direction: "in", party: "Musanze Smelting Co-op", ref: "LOT-2025-0131 · Sale S-0398", amount: 6120000, currency: "RWF", method: "MTN Mobile Money", date: "Aug 15, 2025", status: "Processing" },
    { id: "TXN-IN-2508-005", direction: "in", party: "East Africa Coltan Buyers", ref: "Invoice INV-2025-0204", amount: 12800, currency: "USD", method: "Bank Transfer", date: "Aug 09, 2025", status: "Failed" },
    { id: "TXN-IN-2508-003", direction: "in", party: "Kivu Metals Trading", ref: "LOT-2025-0127 · Sale S-0390", amount: 7340000, currency: "RWF", method: "Bank Transfer", date: "Aug 05, 2025", status: "Received" },
    { id: "TXN-IN-2508-001", direction: "in", party: "Kigali Tin Traders Ltd", ref: "LOT-2025-0124 · Sale S-0386", amount: 11200000, currency: "RWF", method: "Electronic Banking", date: "Aug 02, 2025", status: "Received" },
    { id: "TXN-OUT-2508-104", direction: "out", party: "Diane Uwamahoro", ref: "Salary · Aug 2025", amount: 185000, currency: "RWF", method: "MTN Mobile Money", date: "Aug 30, 2025", status: "Pending" },
    { id: "TXN-OUT-2508-101", direction: "out", party: "Aline Mukamana", ref: "Salary · Aug 2025", amount: 210000, currency: "RWF", method: "MTN Mobile Money", date: "Aug 29, 2025", status: "Paid" },
    { id: "TXN-OUT-2508-097", direction: "out", party: "Rwanda Mining Board", ref: "Licence renewal ML-2025-087", amount: 1200000, currency: "RWF", method: "Bank Transfer", date: "Aug 26, 2025", status: "Paid" },
    { id: "TXN-OUT-2508-093", direction: "out", party: "Kigali Equipment Hire", ref: "Excavator rental · Aug", amount: 3450000, currency: "RWF", method: "Bank Transfer", date: "Aug 22, 2025", status: "Processing" },
    { id: "TXN-OUT-2508-088", direction: "out", party: "Eric Ndayisaba", ref: "Salary · Jul 2025", amount: 160000, currency: "RWF", method: "Airtel Money", date: "Aug 05, 2025", status: "Failed" },
    { id: "TXN-OUT-2508-085", direction: "out", party: "Samuel Nkurunziza", ref: "Salary · Jul 2025", amount: 175000, currency: "RWF", method: "MTN Mobile Money", date: "Aug 01, 2025", status: "Paid" },
  ] as Txn[],

  docs: [
    { id: "DOC-001", name: "Mining Licence – Kigali Gold Mine", kind: "Mining Licence", siteId: "kigali", number: "ML-2025-081", issued: "Mar 14, 2025", expires: "Mar 14, 2027", fileName: "Mining_Licence_ML-2025-081.pdf" },
    { id: "DOC-002", name: "Mining Licence – Musanze Mine", kind: "Mining Licence", siteId: "musanze", number: "ML-2025-087", issued: "Sep 05, 2023", expires: "Sep 05, 2025", fileName: "Mining_Licence_ML-2025-087.pdf" },
    { id: "DOC-003", name: "Mining Licence – Coltan Site", kind: "Mining Licence", siteId: "rubavu", number: "ML-2024-061", issued: "Dec 18, 2023", expires: "Dec 18, 2025", fileName: "Mining_Licence_ML-2024-061.pdf" },
    { id: "DOC-004", name: "Export Permit – Cassiterite", kind: "Export Permit", number: "EXP-2025-0412", issued: "Jul 02, 2025", expires: "Jan 02, 2026", fileName: "Export_Permit_EXP-2025-0412.pdf" },
    { id: "DOC-005", name: "Transport Permit – Northern Route", kind: "Transport Permit", number: "TRP-2025-0198", issued: "Jun 15, 2025", expires: "Dec 15, 2025", fileName: "Transport_Permit_TRP-2025-0198.pdf" },
    { id: "DOC-006", name: "Environmental Impact Assessment – Gatumba", kind: "Environmental", siteId: "gatumba", number: "EIA-2024-033", issued: "Nov 20, 2024", fileName: "EIA_Gatumba_2024.pdf" },
    { id: "DOC-007", name: "Conflict-Free Certificate – LOT-00117", kind: "Certificate", number: "CFC-2025-0087", issued: "Aug 14, 2025", fileName: "CFC_LOT-00117.pdf" },
  ] as Doc[],
};

export type AppData = typeof seed;
