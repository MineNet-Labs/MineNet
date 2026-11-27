// HR and site operations: attendance, payroll, leave, safety incidents and
// shift reports. Types and sample data (Aug 2025, like the rest of the seed).

export type AttendanceStatus = "Present" | "Absent" | "Leave" | "Half day";
export type Attendance = { id: string; workerId: string; date: string; status: AttendanceStatus };

export type PayLine = { workerId: string; days: number; rate: number; gross: number; deductions: number; net: number };
export type PayRun = { id: string; month: string; status: "Draft" | "Approved" | "Paid"; lines: PayLine[]; created: string; paid?: string };

export type LeaveType = "Annual" | "Sick" | "Family" | "Unpaid";
export type LeaveStatus = "Pending" | "Approved" | "Rejected";
export type Leave = { id: string; workerId: string; type: LeaveType; from: string; to: string; days: number; reason: string; status: LeaveStatus; requested: string };

export type Severity = "Low" | "Medium" | "High";
export type IncidentStatus = "Open" | "Investigating" | "Closed";
export type Incident = {
  id: string;
  siteId: string;
  shaftId?: string;
  date: string;
  kind: string;
  severity: Severity;
  injured: number;
  description: string;
  actions?: string;
  status: IncidentStatus;
  reportedBy: string;
};

export type ShiftReport = { id: string; siteId: string; date: string; shift: "Day" | "Night"; crew: number; outputKg: number; hours: number; notes: string; by: string };

/** Daily pay (RWF) by work category; HR can override per run. */
export const DAILY_RATE: Record<string, number> = {
  Miner: 6000,
  Loader: 5000,
  Sorter: 5000,
  "Mineral Sorter": 5500,
  "Site assistant": 5500,
  "Transport support": 5500,
  Supervisor: 9000,
};
export const rateFor = (category: string) => DAILY_RATE[category] ?? 5000;
/** RSSB pension (3% employee share) as the standard deduction. */
export const DEDUCTION_PCT = 0.03;

export const INCIDENT_KINDS = ["Rock fall", "Equipment injury", "Flooding", "Ventilation / gas", "Explosives", "Slip or fall", "Near miss", "Environmental spill"];

// Workdays 18–29 Aug 2025 for the sample attendance.
const DAYS = ["2025-08-18", "2025-08-19", "2025-08-20", "2025-08-21", "2025-08-22", "2025-08-25", "2025-08-26", "2025-08-27", "2025-08-28", "2025-08-29"];
const WORKERS = Array.from({ length: 18 }, (_, i) => `WRK-${String(21 + i).padStart(4, "0")}`);
const INACTIVE = new Set(["WRK-0025", "WRK-0032", "WRK-0036"]);

function sampleAttendance(): Attendance[] {
  const out: Attendance[] = [];
  let n = 1;
  for (const d of DAYS) {
    WORKERS.forEach((w, i) => {
      if (INACTIVE.has(w)) return;
      const k = (i * 7 + d.charCodeAt(9) * 3) % 23;
      const status: AttendanceStatus = k === 0 ? "Absent" : k === 1 ? "Half day" : w === "WRK-0029" && d >= "2025-08-27" ? "Leave" : "Present";
      out.push({ id: `ATT-${String(n++).padStart(5, "0")}`, workerId: w, date: d, status });
    });
  }
  return out;
}

export const peopleSeed = {
  attendance: sampleAttendance(),
  payruns: [
    {
      id: "PAY-2025-07",
      month: "2025-07",
      status: "Paid",
      created: "Jul 31, 2025",
      paid: "Aug 01, 2025",
      lines: [
        { workerId: "WRK-0021", days: 22, rate: 6000, gross: 132000, deductions: 3960, net: 128040 },
        { workerId: "WRK-0022", days: 21, rate: 5000, gross: 105000, deductions: 3150, net: 101850 },
        { workerId: "WRK-0026", days: 22, rate: 5500, gross: 121000, deductions: 3630, net: 117370 },
        { workerId: "WRK-0027", days: 22, rate: 9000, gross: 198000, deductions: 5940, net: 192060 },
      ],
    },
  ] as PayRun[],
  leaves: [
    { id: "LV-0004", workerId: "WRK-0029", type: "Family", from: "2025-08-27", to: "2025-08-29", days: 3, reason: "Family event in Huye", status: "Approved", requested: "Aug 20, 2025" },
    { id: "LV-0005", workerId: "WRK-0033", type: "Sick", from: "2025-09-01", to: "2025-09-02", days: 2, reason: "Medical appointment", status: "Pending", requested: "Aug 28, 2025" },
    { id: "LV-0006", workerId: "WRK-0038", type: "Annual", from: "2025-09-08", to: "2025-09-12", days: 5, reason: "Annual leave", status: "Pending", requested: "Aug 29, 2025" },
  ] as Leave[],
  incidents: [
    { id: "INC-0012", siteId: "nyabihu", shaftId: "N-03", date: "Aug 26, 2025", kind: "Rock fall", severity: "Medium", injured: 1, description: "Loose rock fell near the N-03 face; one miner with a bruised shoulder.", actions: "Area barred, roof bolting scheduled.", status: "Investigating", reportedBy: "Grace Mukeshimana" },
    { id: "INC-0011", siteId: "gatumba", shaftId: "G-01", date: "Aug 19, 2025", kind: "Ventilation / gas", severity: "High", injured: 0, description: "Low oxygen reading at 90 m; shaft evacuated for 3 hours.", actions: "Fan replaced, gas detector recalibrated.", status: "Closed", reportedBy: "Emmanuel Twagirayezu" },
    { id: "INC-0010", siteId: "kigali", date: "Aug 12, 2025", kind: "Near miss", severity: "Low", injured: 0, description: "Loader reversed without a spotter near the sorting area.", status: "Closed", reportedBy: "Jean Uwimana" },
  ] as Incident[],
  shiftReports: [
    { id: "SR-0042", siteId: "nyabihu", date: "Aug 28, 2025", shift: "Day", crew: 6, outputKg: 85, hours: 9, notes: "N-03 face cleared after the rock fall; output below plan.", by: "Grace Mukeshimana" },
    { id: "SR-0041", siteId: "gatumba", date: "Aug 28, 2025", shift: "Day", crew: 8, outputKg: 340, hours: 9, notes: "Good run on G-01.", by: "Emmanuel Twagirayezu" },
    { id: "SR-0040", siteId: "kigali", date: "Aug 27, 2025", shift: "Night", crew: 5, outputKg: 40, hours: 8, notes: "Pump maintenance took 2 hours.", by: "Jean Uwimana" },
  ] as ShiftReport[],
};
