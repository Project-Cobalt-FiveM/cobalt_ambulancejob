export type Page =
  | 'dashboard'
  | 'dispatch'
  | 'patients'
  | 'reports'
  | 'prescriptions'
  | 'billing'
  | 'beds'
  | 'roster'
  | 'management';

export type Permission =
  | 'writeReports'
  | 'editOtherReports'
  | 'editPatients'
  | 'writePrescriptions'
  | 'prescribeControlled'
  | 'admitDischarge'
  | 'useDefib'
  | 'sendInvoices'
  | 'voidInvoices'
  | 'shareReports'
  | 'manageTreatments'
  | 'manageRoster'
  | 'manageTemplates'
  | 'manageSettings'
  | 'administrator';

export type Permissions = Record<Permission, boolean>;

export type MedicStatus = 'available' | 'busy' | 'enroute' | 'onscene' | 'break';

export type StaffStatus = MedicStatus | 'offduty';

export type BodyPart = 'head' | 'torso' | 'left_arm' | 'right_arm' | 'left_leg' | 'right_leg';

export type InjuryKind = 'bleeding' | 'fracture' | 'burn' | 'severed';

export type TreatKind = InjuryKind | 'down';

export type ReviveState = 'alive' | 'knocked_out' | 'down' | 'dead' | 'reviving';

export type Injury = { bodyPart: BodyPart; kind: InjuryKind };

export type Vec3 = { x: number; y: number; z: number };

export type Result = { ok: true } | { ok: false; error: string };

export type Created = { ok: true; id: number } | { ok: false; error: string };

export type LockedPage = { page: Page; rank: string };

export type Medic = {
  citizenid: string;
  name: string;
  callsign: string;
  grade: number;
  gradeName: string;
  department: { label: string; subtitle: string };
  status: MedicStatus;
  permissions: Permissions;
  pages: Page[];
  locked: LockedPage[];
  trainee: boolean;
};

export type Keybinds = { respond: string; waypoint: string };

export type Settings = { medicShare: number; shareWithPolice: boolean };

export type Responder = { citizenid: string; name: string; callsign: string };

export type CallNote = { author: string; text: string; time: number };

export type CallPatient = {
  citizenid: string;
  name: string;
  bloodType: string | null;
  state: ReviveState;
  bleedsOutAt: number | null;
  injuries: Injury[];
};

export type Call = {
  id: number;
  code: string;
  title: string;
  description: string;
  location: string;
  coords: Vec3 | null;
  distance: number | null;
  priority: 1 | 2 | 3;
  status: 'open' | 'closed';
  createdAt: number;
  caller: { name: string; number: string } | null;
  raisedBy: string | null;
  responders: Responder[];
  notes: CallNote[];
  patient: CallPatient | null;
};

export type OnDutyMedic = {
  citizenid: string;
  name: string;
  callsign: string;
  detail: string;
  status: MedicStatus;
};

export type HospitalCapacity = { id: string; label: string; free: number; total: number; admitted: number };

export type DashboardStats = {
  openCalls: number;
  patientsDown: number;
  medicsOnDuty: number;
  medicsAvailable: number;
  medicsOnCalls: number;
  bedsFree: number;
  bedsTotal: number;
  hospitals: number;
  unpaidTotal: number;
  unpaidCount: number;
  overdueCount: number;
  training: { done: number; total: number } | null;
};

export type Dashboard = { stats: DashboardStats; onDuty: OnDutyMedic[]; capacity: HospitalCapacity[] };

export type DispatchSummary = { available: number; onBreak: number; lastClosedAt: number | null };

export type Sex = 'male' | 'female' | 'other';

export type PatientSummary = {
  citizenid: string;
  name: string;
  sex: Sex;
  dob: string;
  age: number | null;
  bloodType: string | null;
  state: ReviveState;
  online: boolean;
  admission: string | null;
  balance: number;
  conditions: string[];
  lastTreated: { at: number; summary: string } | null;
};

export type ReportOutcome = 'scene' | 'transported' | 'admitted' | 'deceased' | 'respawned';

export type ReportStatus = 'draft' | 'filed';

export type ReportBilling = 'pending' | 'billed' | 'waived';

export type ReportSummary = {
  id: number;
  citizenid: string | null;
  patientName: string;
  summary: string;
  detail: string;
  medic: string;
  medicCitizenid: string | null;
  outcome: ReportOutcome;
  status: ReportStatus;
  billing: ReportBilling;
  billed: number | null;
  createdAt: number;
};

export type ReportInjury = { bodyPart: BodyPart; kind: InjuryKind; label: string; treatments: number[]; treated: boolean };

export type InvoiceStatus = 'unpaid' | 'overdue' | 'paid' | 'void';

export type Report = ReportSummary & {
  callId: number | null;
  occurredAt: number;
  injuries: ReportInjury[];
  medications: number[];
  extras: number[];
  narrative: string;
  invoice: { id: number; status: InvoiceStatus } | null;
  sharedWithPolice: boolean;
  bloodType: string | null;
};

export type ReportDraft = {
  id: number | null;
  citizenid: string | null;
  patientName: string;
  callId: number | null;
  occurredAt: number;
  injuries: ReportInjury[];
  medications: number[];
  extras: number[];
  narrative: string;
  outcome: ReportOutcome;
};

export type InvoiceLine = { label: string; amount: number };

export type Invoice = {
  id: number;
  citizenid: string;
  patientName: string;
  reportId: number | null;
  summary: string;
  lines: InvoiceLine[];
  amount: number;
  status: InvoiceStatus;
  dueAt: number;
  createdAt: number;
  declinedAt: number | null;
  paidAt: number | null;
  voidReason: string | null;
};

export type Billing = { stats: { billedWeek: number; paidWeek: number; overdue: number }; invoices: Invoice[] };

export type PrescriptionStatus = 'active' | 'expired' | 'cancelled';

export type PrescriptionFill = { pharmacy: string; at: number };

export type Prescription = {
  id: number;
  citizenid: string;
  patientName: string;
  medication: string;
  dose: string;
  reason: string;
  refills: number;
  refillsUsed: number;
  controlled: boolean;
  prescriber: string;
  createdAt: number;
  endsAt: number;
  status: PrescriptionStatus;
  fills: PrescriptionFill[];
};

export type PrescriptionInput = {
  citizenid: string;
  medication: string;
  dose: string;
  reason: string;
  refills: number;
  days: number;
  controlled: boolean;
};

export type Admission = {
  id: number;
  citizenid: string;
  patientName: string;
  hospital: string;
  bed: number;
  reason: string;
  attending: string;
  admittedAt: number;
  plannedDischargeAt: number | null;
  reportId: number | null;
  notes: string;
  dischargedAt: number | null;
};

export type FrontDeskPatient = { citizenid: string; patientName: string; endsAt: number };

export type Bed = { index: number; label: string; admission: Admission | null; frontDesk?: FrontDeskPatient | null };

export type Hospital = { id: string; label: string; short: string; beds: Bed[] };

export type WaitingPatient = { id: number; citizenid: string; name: string; reason: string; since: number };

export type Beds = { hospitals: Hospital[]; waiting: WaitingPatient[] };

export type AdmitInput = {
  citizenid: string;
  hospital: string;
  bed: number;
  reason: string;
  dischargeHours: number | null;
  reportId: number | null;
};

export type Patient = PatientSummary & {
  phone: string;
  emergencyContact: string;
  notes: string;
  injuries: Injury[];
  reports: ReportSummary[];
  prescriptions: Prescription[];
  admissions: Admission[];
  invoices: Invoice[];
};

export type PatientInput = {
  citizenid: string;
  bloodType: string | null;
  conditions: string[];
  emergencyContact: string;
  notes: string;
};

export type Certification = { id: string; label: string };

export type RankOption = { grade: number; name: string };

export type StaffMember = {
  citizenid: string;
  name: string;
  callsign: string;
  grade: number;
  rank: string;
  certifications: string[];
  status: StaffStatus;
  online: boolean;
  doctor: boolean;
  trainee: boolean;
  joinedAt: number | null;
  hoursOnDuty: number;
  reportsFiled: number;
  revivesMonth: number;
};

export type Roster = { staff: StaffMember[]; ranks: RankOption[]; certifications: Certification[] };

export type StaffInput = { citizenid: string; callsign: string; grade: number; certifications: string[] };

export type Rank = { grade: number; name: string; holders: number; isBoss: boolean; permissions: Permissions };

export type TreatmentCategory = 'injury' | 'procedure' | 'medication' | 'fee';

export type Treatment = {
  id: number;
  name: string;
  category: TreatmentCategory;
  treats: TreatKind[];
  item: string | null;
  price: number;
  seconds: number;
};

export type TreatmentInput = Omit<Treatment, 'id'> & { id: number | null };

export type ItemOption = { name: string; label: string };

export type Template = { id: number; name: string; narrative: string; uses: number };

export type TemplateInput = { id: number | null; name: string; narrative: string };

export type SearchHit =
  | { kind: 'patient'; citizenid: string; title: string; detail: string }
  | { kind: 'call'; id: number; title: string; detail: string }
  | { kind: 'report'; id: number; title: string; detail: string };

export type Session = {
  medic: Medic;
  settings: Settings;
  keybinds: Keybinds;
  page: Page | null;
  citizenid: string | null;
};

export type AlertData = { call: Call; distance: number; seconds: number };

export type DeathScreen =
  | { kind: 'knockedout'; endsAt: number; now: number }
  | { kind: 'laststand'; endsAt: number; total: number; now: number; callKey: string; emsCalled: boolean }
  | { kind: 'dead'; respawnAt: number; now: number; fee: number; hospital: string; respawnKey: string; killKey?: string };

export type Messages =
  | { action: 'open'; data: Session }
  | { action: 'close' }
  | { action: 'callAdded'; data: Call }
  | { action: 'callUpdated'; data: Call }
  | { action: 'alert'; data: AlertData }
  | { action: 'alertClear'; data: { id: number } }
  | { action: 'death'; data: DeathScreen | false }
  | { action: 'deathHold'; data: number | false }
  | { action: 'bedsChanged' };

export type Boot = { locales: Record<string, string>; bleedoutSeconds: number };

export type Requests = {
  boot: [void, Boot];
  close: [void, Result];
  respawn: [void, Result];
  setStatus: [{ status: MedicStatus }, Result];
  search: [{ query: string }, SearchHit[]];
  getDashboard: [void, Dashboard];
  getCalls: [void, Call[]];
  getDispatchSummary: [void, DispatchSummary];
  respondCall: [{ id: number }, Result];
  leaveCall: [{ id: number }, Result];
  waypointCall: [{ id: number }, Result];
  assignCall: [{ id: number; citizenid: string }, Result];
  closeCall: [{ id: number }, Result];
  markTransported: [{ id: number }, Result];
  searchPatients: [{ query: string }, PatientSummary[]];
  getPatient: [{ citizenid: string }, Patient | null];
  savePatient: [PatientInput, Result];
  getReports: [void, ReportSummary[]];
  getReport: [{ id: number }, Report | null];
  newReport: [{ citizenid: string | null; callId: number | null; templateId: number | null }, ReportDraft];
  saveReport: [ReportDraft, Created];
  fileReport: [ReportDraft & { sendInvoice: boolean }, Created];
  shareReport: [{ id: number; shared: boolean }, Result];
  getPrescriptions: [void, Prescription[]];
  createPrescription: [PrescriptionInput, Created];
  renewPrescription: [{ id: number }, Result];
  cancelPrescription: [{ id: number }, Result];
  getBilling: [void, Billing];
  createInvoice: [{ citizenid: string; lines: InvoiceLine[] }, Created];
  chargeInvoice: [{ id: number }, Result];
  markInvoicePaid: [{ id: number }, Result];
  voidInvoice: [{ id: number; reason: string }, Result];
  getBeds: [void, Beds];
  admit: [AdmitInput, Created];
  discharge: [{ id: number }, Result];
  moveBed: [{ id: number; hospital: string; bed: number }, Result];
  saveWardNotes: [{ id: number; notes: string }, Result];
  seePatient: [{ id: number }, Result];
  getRoster: [void, Roster];
  saveStaff: [StaffInput, Result];
  getRanks: [void, Rank[]];
  saveRank: [{ grade: number; permissions: Permissions }, Result];
  getTreatments: [void, Treatment[]];
  getItems: [void, ItemOption[]];
  saveTreatment: [TreatmentInput, Created];
  deleteTreatment: [{ id: number }, Result];
  getTemplates: [void, Template[]];
  saveTemplate: [TemplateInput, Created];
  deleteTemplate: [{ id: number }, Result];
  getSettings: [void, Settings];
  saveSettings: [Settings, Result];
};
