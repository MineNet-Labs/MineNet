// Team roles inside a mining company. The owner invites a site manager and
// HR by email so the daily work is shared; each role only sees what it needs.

export type Role = "Owner" | "Site manager" | "HR";
export type MemberStatus = "Invited" | "Active" | "Disabled";
export type Member = {
  id: string;
  name: string;
  email: string;
  role: Role;
  /** Site managers only see these sites (and their shafts, workers, lots…). */
  siteIds: string[];
  status: MemberStatus;
  invited: string;
  token: string;
};

/** Sections of the miner portal, by URL segment ("" = Overview). */
export type Section =
  | ""
  | "mining-sites"
  | "mine-shafts"
  | "extraction-records"
  | "mineral-lots"
  | "marketplace"
  | "inspections"
  | "workers"
  | "licence"
  | "documents"
  | "payments"
  | "financing"
  | "insurance"
  | "reports"
  | "team"
  | "approvals"
  | "attendance"
  | "payroll"
  | "leave"
  | "incidents"
  | "site-reports"
  | "notifications"
  | "settings"
  | "support";

const ALL: Section[] = ["", "mining-sites", "mine-shafts", "extraction-records", "mineral-lots", "marketplace", "inspections", "workers", "licence", "documents", "payments", "financing", "insurance", "reports", "team", "approvals", "attendance", "payroll", "leave", "incidents", "site-reports", "notifications", "settings", "support"];

export const ACCESS: Record<Role, Section[]> = {
  Owner: ALL,
  // Runs the sites day to day: production, lots, inspections, custody and crews.
  "Site manager": ["", "approvals", "mining-sites", "mine-shafts", "extraction-records", "mineral-lots", "inspections", "workers", "attendance", "incidents", "site-reports", "documents", "notifications", "settings", "support"],
  // People and pay: workers, salaries and their documents.
  HR: ["", "workers", "attendance", "payroll", "leave", "payments", "documents", "notifications", "settings", "support"],
};

export const ROLE_INFO: Record<Role, string> = {
  Owner: "Full access, including sales, finance, licence and team.",
  "Site manager": "Runs one site and reports to the owner: extraction records, lots, inspections, attendance, safety incidents and shift reports. Hiring, new shafts, site documents and mineral handovers go to the owner for approval. No sales or finance.",
  HR: "Manages workers, attendance, leave and payroll (salary payments). No sites, lots or sales.",
};

export const sectionOf = (pathname: string) => (pathname.split("/")[2] ?? "") as Section;
export const canSee = (role: Role, section: Section) => ACCESS[role].includes(section);

/** Actions that need more than page access. */
export const can = {
  sell: (r: Role) => r === "Owner",
  finance: (r: Role) => r === "Owner",
  manageTeam: (r: Role) => r === "Owner",
  registerSites: (r: Role) => r === "Owner",
  manageWorkers: (r: Role) => r === "Owner" || r === "HR" || r === "Site manager",
  recordProduction: (r: Role) => r === "Owner" || r === "Site manager",
};

/** One owner, one HR, and one manager per site; managers are peers and report to the owner. */
const mgr = (id: string, name: string, email: string, site: string, invited: string, status: MemberStatus = "Active"): Member => ({ id, name, email: `${email}@uwimana-coop.rw`, role: "Site manager", siteIds: [site], status, invited, token: `t-${email}-${id.slice(2)}` });
export const teamSeed: Member[] = [
  { id: "M-001", name: "Jean Uwimana", email: "jean@uwimana-coop.rw", role: "Owner", siteIds: [], status: "Active", invited: "Mar 14, 2025", token: "owner" },
  mgr("M-002", "Grace Mukeshimana", "grace", "nyabihu", "Apr 02, 2025"),
  { id: "M-003", name: "Alice Umutoni", email: "alice@uwimana-coop.rw", role: "HR", siteIds: [], status: "Active", invited: "Apr 10, 2025", token: "t-alice-29bd" },
  mgr("M-004", "Eric Nshimiyimana", "eric", "musanze", "Apr 05, 2025"),
  mgr("M-005", "Olivier Nsengiyumva", "olivier", "kigali", "Apr 03, 2025"),
  mgr("M-006", "Claude Mugisha", "claude", "ruhango", "Apr 04, 2025"),
  mgr("M-007", "Samuel Nkurunziza", "samuel", "rubavu", "Apr 08, 2025"),
  mgr("M-008", "Diane Uwamahoro", "diane", "gatumba", "Apr 12, 2025"),
  mgr("M-009", "Patrick Habimana", "patrick", "kamonyi", "May 02, 2025"),
  mgr("M-010", "Aline Mukamana", "aline", "rulindo", "May 06, 2025"),
  mgr("M-011", "Clarisse Ingabire", "clarisse", "rusizi", "Jun 01, 2025"),
  mgr("M-012", "Innocent Hakizimana", "innocent", "nyamasheke", "Aug 27, 2025", "Invited"),
];

export type Collection = "workers" | "shafts" | "docs" | "transfers";
export type Approval = {
  id: string;
  kind: string;
  summary: string;
  siteId?: string;
  requestedBy: string;
  memberId: string;
  requested: string;
  status: "Pending" | "Approved" | "Rejected";
  decided?: string;
  note?: string;
  adds: { to: Collection; item: unknown }[];
};

export const approvalSeed: Approval[] = [
  {
    id: "APR-0001",
    kind: "New worker",
    summary: "Hire Jean-Paul Habineza as Driller",
    siteId: "nyabihu",
    requestedBy: "Grace Mukeshimana",
    memberId: "M-002",
    requested: "Aug 28, 2025",
    status: "Pending",
    adds: [{ to: "workers", item: { id: "WRK-0099", name: "Jean-Paul Habineza", siteId: "nyabihu", category: "Driller", access: "Setup pending", status: "Active", phone: "+250 788 410 233", joined: "Aug 28, 2025" } }],
  },
];

