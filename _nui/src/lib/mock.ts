import type { MockHandlers } from './nui';
import { nowSeconds } from './format';
import type {
  BedOccupant,
  BedUse,
  DeathScreen,
  Call,
  HospitalBeds,
  Invoice,
  Medic,
  Messages,
  Patient,
  PatientSummary,
  Permissions,
  Prescription,
  Rank,
  Report,
  ReportDraft,
  ReportSummary,
  StaffMember,
  Template,
  Treatment,
} from './types';

const now = Math.floor(Date.now() / 1000);
const minute = 60;
const hour = 3600;
const day = 86400;

const ok = { ok: true } as const;

function allPermissions(value: boolean): Permissions {
  return {
    writeReports: value,
    editOtherReports: value,
    editPatients: value,
    writePrescriptions: value,
    prescribeControlled: value,
    useDefib: value,
    sendInvoices: value,
    voidInvoices: value,
    shareReports: value,
    manageTreatments: value,
    manageRoster: value,
    manageTemplates: value,
    manageSettings: value,
    administrator: value,
  };
}

const trainee = location.hash === '#trainee';

const medic: Medic = trainee
  ? {
      citizenid: 'PRN44120',
      name: 'Priya Nair',
      callsign: 'EMS 9',
      grade: 0,
      gradeName: 'Trainee',
      department: { label: 'EMS', subtitle: 'City Of Los Santos' },
      status: 'available',
      permissions: { ...allPermissions(false), writeReports: true, useDefib: true },
      pages: ['dashboard', 'dispatch', 'patients', 'reports', 'roster'],
      locked: [
        { page: 'prescriptions', rank: 'EMT' },
        { page: 'billing', rank: 'EMT' },
        { page: 'management', rank: 'EMT' },
      ],
      trainee: true,
    }
  : {
      citizenid: 'JHL30112',
      name: 'Jordan Hale',
      callsign: 'EMS 3',
      grade: 2,
      gradeName: 'Paramedic',
      department: { label: 'EMS', subtitle: 'City Of Los Santos' },
      status: 'available',
      permissions: allPermissions(true),
      pages: ['dashboard', 'dispatch', 'patients', 'reports', 'prescriptions', 'billing', 'roster', 'management'],
      locked: [],
      trainee: false,
    };

const empty = location.hash === '#empty';

const downCall: Call = {
        id: 812,
        code: 'P1',
        title: 'Patient down, gunshot wound',
        description: 'Requested EMS while bleeding out',
        location: 'Grove Street, Davis',
        coords: { x: 100, y: -1900, z: 25 },
        distance: 1400,
        priority: 1,
        status: 'open',
        createdAt: now - 2 * minute,
        caller: null,
        raisedBy: 'Patient, request EMS key',
        responders: [
          { citizenid: 'JHL30112', name: 'Jordan Hale', callsign: 'EMS 3' },
          { citizenid: 'LSPD1A12', name: 'Mark Daniels', callsign: 'LSPD 1-ADAM-12' },
        ],
        notes: [],
        patient: {
          citizenid: 'LMX20391',
          name: 'Marcus Webb',
          bloodType: 'O-',
          state: 'down',
          bleedsOutAt: now + 161,
          injuries: [
            { bodyPart: 'torso', kind: 'bleeding' },
            { bodyPart: 'left_leg', kind: 'fracture' },
          ],
        },
      };

const fallCall: Call = {
        id: 814,
        code: 'P3',
        title: 'Fall injury, possible fracture',
        description: 'Fell off the pier, conscious',
        location: 'Vespucci Beach',
        coords: { x: -1400, y: -1500, z: 4 },
        distance: 3100,
        priority: 3,
        status: 'open',
        createdAt: now - 9 * minute,
        caller: { name: 'Owen Price', number: '555-0131' },
        raisedBy: null,
        responders: [{ citizenid: 'AMO22871', name: 'Amara Osei', callsign: 'EMS 5' }],
        notes: [],
        patient: null,
      };

const calls: Call[] = empty
  ? []
  : [
      downCall,
      {
        id: 813,
        code: 'P2',
        title: 'Vehicle crash, 2 injured',
        description: 'Two cars on the freeway, both drivers hurt',
        location: 'Del Perro Freeway, Pillbox Hill',
        coords: { x: 200, y: -800, z: 30 },
        distance: 2300,
        priority: 2,
        status: 'open',
        createdAt: now - 5 * minute,
        caller: { name: 'Lena Ruiz', number: '555-0188' },
        raisedBy: null,
        responders: [],
        notes: [],
        patient: null,
      },
      fallCall,
      {
        id: 806,
        code: 'P2',
        title: 'Overdose at a house party',
        description: 'Naloxone given',
        location: 'Mirror Park',
        coords: null,
        distance: null,
        priority: 2,
        status: 'closed',
        createdAt: now - 2 * hour,
        caller: null,
        raisedBy: null,
        responders: [{ citizenid: 'NBR41901', name: 'Noah Brandt', callsign: 'EMS 7' }],
        notes: [],
        patient: null,
      },
    ];

const patients: PatientSummary[] = [
  {
    citizenid: 'LMX20391',
    name: 'Marcus Webb',
    sex: 'male',
    dob: '1990-07-09',
    age: 36,
    bloodType: 'O-',
    state: 'down',
    online: true,
    balance: 0,
    conditions: ['Asthma', 'Old left knee injury'],
    lastTreated: { at: now - 22 * day, summary: 'broken arm' },
  },
  {
    citizenid: 'RKD55120',
    name: 'Tasha Webb',
    sex: 'female',
    dob: '1994-02-22',
    age: 32,
    bloodType: 'A+',
    state: 'alive',
    online: true,
    balance: 1080,
    conditions: [],
    lastTreated: { at: now - day, summary: 'broken ribs' },
  },
  {
    citizenid: 'PQA80217',
    name: 'Dennis Webber',
    sex: 'male',
    dob: '1971-12-03',
    age: 54,
    state: 'alive',
    online: false,
    balance: 650,
    conditions: [],
    lastTreated: { at: now - 13 * day, summary: 'fractured ribs' },
  },
];

const treatments: Treatment[] = [
  { id: 1, name: 'Bleeding control', category: 'injury', treats: ['bleeding'], item: 'bandage', price: 120, seconds: 6 },
  { id: 2, name: 'Gunshot wound care', category: 'injury', treats: ['bleeding', 'severed'], item: 'tourniquet', price: 600, seconds: 5 },
  { id: 3, name: 'Splint a fracture', category: 'injury', treats: ['fracture'], item: 'splint', price: 150, seconds: 8 },
  { id: 4, name: 'Burn dressing', category: 'injury', treats: ['burn'], item: 'burn_dressing', price: 180, seconds: 6 },
  { id: 5, name: 'Defibrillator revive', category: 'procedure', treats: ['down'], item: 'defibrillator', price: 300, seconds: 8 },
  { id: 6, name: 'Gauze', category: 'procedure', treats: ['bleeding'], item: null, price: 0, seconds: 4 },
  { id: 7, name: 'Morphine 10 mg, IV', category: 'medication', treats: [], item: null, price: 50, seconds: 0 },
  { id: 8, name: 'Saline 500 ml', category: 'medication', treats: [], item: null, price: 30, seconds: 0 },
  { id: 9, name: 'Clindamycin 600 mg', category: 'medication', treats: [], item: null, price: 40, seconds: 0 },
  { id: 10, name: 'Ambulance transport', category: 'fee', treats: [], item: null, price: 250, seconds: 0 },
  { id: 11, name: 'Hospital respawn', category: 'fee', treats: [], item: null, price: 200, seconds: 0 },
];

const keisha: ReportSummary = { id: 430, citizenid: 'KMN11823', patientName: 'Keisha Monroe', summary: 'Burns to both arms, kitchen fire', detail: 'Burn dressing x2, saline', medic: 'Amara Osei', medicCitizenid: 'AMO22871', outcome: 'transported', status: 'filed', billing: 'billed', billed: 540, createdAt: now - 2 * hour };

const armReport: ReportSummary = { id: 418, citizenid: 'LMX20391', patientName: 'Marcus Webb', summary: 'Fractured right arm', detail: 'Splint, 2 doses of morphine', medic: 'Amara Osei', medicCitizenid: 'AMO22871', outcome: 'scene', status: 'filed', billing: 'billed', billed: 300, createdAt: now - 22 * day };

const reports: ReportSummary[] = [
  { id: 431, citizenid: 'LMX20391', patientName: 'Marcus Webb', summary: 'Gunshot to torso, fractured left leg', detail: '', medic: 'Jordan Hale', medicCitizenid: 'JHL30112', outcome: 'transported', status: 'draft', billing: 'pending', billed: null, createdAt: now - 6 * minute },
  keisha,
  { id: 429, citizenid: null, patientName: 'Unknown male', summary: 'Overdose, naloxone given', detail: 'Naloxone', medic: 'Noah Brandt', medicCitizenid: 'NBR41901', outcome: 'scene', status: 'filed', billing: 'waived', billed: null, createdAt: now - 3 * hour },
  { id: 428, citizenid: 'RDG77310', patientName: 'Rosa Delgado', summary: 'Fractured right leg, motorbike crash', detail: 'Splint, ibuprofen', medic: 'Sam Kowalski', medicCitizenid: 'SKW90012', outcome: 'transported', status: 'filed', billing: 'billed', billed: 980, createdAt: now - 4 * hour },
  { id: 427, citizenid: 'TKL31008', patientName: 'Trevor Kline', summary: 'Self respawn after bleed-out, no medic', detail: '', medic: 'Front desk', medicCitizenid: null, outcome: 'respawned', status: 'filed', billing: 'billed', billed: 200, createdAt: now - 5 * hour },
  armReport,
];

const reportDetail: Report = {
  ...keisha,
  callId: null,
  occurredAt: keisha.createdAt,
  injuries: [
    { bodyPart: 'left_arm', kind: 'burn', label: 'Burn', treatments: [4], treated: true },
    { bodyPart: 'right_arm', kind: 'burn', label: 'Burn', treatments: [4], treated: true },
  ],
  medications: [8],
  extras: [10],
  narrative: 'Second-degree burns to both forearms from a pan fire. Cooled, dressed and given pain relief on scene, then driven to Pillbox for review.',
  invoice: { id: 2207, status: 'paid' },
  sharedWithPolice: false,
  bloodType: 'B+',
};

const invoices: Invoice[] = [
  { id: 2214, citizenid: 'PQA80217', patientName: 'Dennis Webber', reportId: 402, summary: 'Report T-402, fractured ribs', lines: [{ label: 'Fracture care, ribs', amount: 400 }, { label: 'Ambulance transport', amount: 250 }], amount: 650, status: 'overdue', dueAt: now - 5 * day, createdAt: now - 12 * day, declinedAt: now - 5 * day },
  { id: 2219, citizenid: 'SVG10292', patientName: 'Sofia Varga', reportId: 409, summary: 'Report T-409, overdose', lines: [{ label: 'Overdose care', amount: 540 }], amount: 540, status: 'overdue', dueAt: now - 2 * day, createdAt: now - 9 * day, declinedAt: now - 2 * day },
  { id: 2224, citizenid: 'RDG77310', patientName: 'Rosa Delgado', reportId: 428, summary: 'Report T-428, fractured leg', lines: [{ label: 'Splint a fracture', amount: 150 }, { label: 'X-ray and cast', amount: 580 }, { label: 'Ambulance transport', amount: 250 }], amount: 980, status: 'unpaid', dueAt: now + 6 * day, createdAt: now - 4 * hour },
  { id: 2226, citizenid: 'TKL31008', patientName: 'Trevor Kline', reportId: 426, summary: 'Report T-426, stitches', lines: [{ label: 'Stitches', amount: 200 }], amount: 200, status: 'unpaid', dueAt: now + 7 * day, createdAt: now - day },
  { id: 2227, citizenid: 'RKD55120', patientName: 'Tasha Webb', summary: 'Medical care', lines: [{ label: 'Rib fracture care', amount: 680 }, { label: 'Pain relief', amount: 400 }], amount: 1080, status: 'unpaid', dueAt: now + 7 * day, createdAt: now - day },
  { id: 2207, citizenid: 'KMN11823', patientName: 'Keisha Monroe', reportId: 430, summary: 'Report T-430, burns', lines: [{ label: 'Burn dressing x2', amount: 360 }, { label: 'Ambulance transport', amount: 180 }], amount: 540, status: 'paid', dueAt: now + 5 * day, createdAt: now - 2 * hour, paidAt: now - 2 * hour },
  { id: 2190, citizenid: 'LMX20391', patientName: 'Marcus Webb', reportId: 418, summary: 'Report T-418, fractured arm', lines: [{ label: 'Splint a fracture', amount: 150 }, { label: 'Medications, 2', amount: 150 }], amount: 300, status: 'paid', dueAt: now - 15 * day, createdAt: now - 22 * day, paidAt: now - 22 * day },
  { id: 2185, citizenid: 'TKL31008', patientName: 'Trevor Kline', reportId: 401, summary: 'Report T-401, cut hand', lines: [{ label: 'Stitches', amount: 200 }], amount: 200, status: 'void', dueAt: now - 20 * day, createdAt: now - 27 * day, voidReason: 'Treated during a training drill' },
];

const prescriptions: Prescription[] = [
  { id: 1182, citizenid: 'LMX20391', patientName: 'Marcus Webb', medication: 'Salbutamol inhaler', dose: '2 puffs when short of breath', reason: 'Asthma', refills: 3, refillsUsed: 2, controlled: false, prescriber: 'Dr. Ravi Menon', createdAt: now - 36 * day, endsAt: now + 24 * day, status: 'active', lastFill: { pharmacy: 'Pillbox pharmacy', at: now - 14 * day } },
  { id: 1190, citizenid: 'RDG77310', patientName: 'Rosa Delgado', medication: 'Ibuprofen 400 mg', dose: 'Every 8 hours with food', reason: 'Fractured right leg', refills: 1, refillsUsed: 0, controlled: false, prescriber: 'Dr. Elena Vasquez', createdAt: now - 3 * hour, endsAt: now + day, status: 'active' },
  { id: 1188, citizenid: 'KMN11823', patientName: 'Keisha Monroe', medication: 'Silver sulfadiazine cream', dose: 'On burns twice a day', reason: 'Burns', refills: 2, refillsUsed: 1, controlled: false, prescriber: 'Dr. Ravi Menon', createdAt: now - 2 * hour, endsAt: now + 13 * day, status: 'active', lastFill: { pharmacy: 'Pillbox pharmacy', at: now - hour } },
  { id: 1185, citizenid: 'RKD55120', patientName: 'Tasha Webb', medication: 'Oxycodone 5 mg', dose: 'Controlled, one tablet every 6 hours', reason: 'Broken ribs', refills: 0, refillsUsed: 0, controlled: true, prescriber: 'Dr. Elena Vasquez', createdAt: now - day, endsAt: now + 2 * day, status: 'active' },
  { id: 1101, citizenid: 'TKL31008', patientName: 'Trevor Kline', medication: 'Amoxicillin 500 mg', dose: 'Three times a day', reason: 'Infected cut', refills: 0, refillsUsed: 0, controlled: false, prescriber: 'Dr. Ravi Menon', createdAt: now - 40 * day, endsAt: now - 30 * day, status: 'expired' },
];

function occupant(citizenid: string, name: string, use: BedUse, state: BedOccupant['state'], minutes: number): BedOccupant {
  return { citizenid, name, use, state, since: now - minutes * minute };
}

function ward(id: string, label: string, short: string, size: number, occupants: Record<number, BedOccupant>): HospitalBeds {
  const beds = Array.from({ length: size }, (_, offset) => ({ index: offset + 1, label: `Bed ${offset + 1}`, occupant: occupants[offset + 1] }));

  return { id, label, short, total: size, occupied: beds.filter((bed) => bed.occupant).length, beds };
}

const rosaBed = occupant('RDG77310', 'Rosa Delgado', 'medic', 'alive', 3 * 60);
const tashaBed = occupant('RKD55120', 'Tasha Webb', 'rest', 'alive', 26);
const marcusBed = occupant('LMX20391', 'Marcus Webb', 'medic', 'down', 4);

function hospitalBeds(changed = false): HospitalBeds[] {
  const pillbox: Record<number, BedOccupant> = changed
    ? { 1: rosaBed, 2: tashaBed, 4: { ...marcusBed, state: 'alive' }, 9: occupant('PSH88120', 'Priya Shah', 'checkIn', 'alive', 0) }
    : { 1: rosaBed, 2: tashaBed, 4: marcusBed, 7: occupant('DVN44120', 'Devon Hale', 'checkIn', 'alive', 1) };

  return [
    ward('pillbox', 'Pillbox Hill Medical', 'Pillbox Hill', 12, pillbox),
    ward('sandy', 'Sandy Shores Medical', 'Sandy Shores', 4, { 3: occupant('LBR20019', 'Leon Brooks', 'medic', 'knocked_out', 9) }),
    ward('paleto', 'Paleto Bay Care Center', 'Paleto Bay', 0, {}),
  ];
}

const staff: StaffMember[] = [
  { citizenid: 'HCR10001', name: 'Dr. Helen Carter', callsign: 'Med 1', grade: 4, rank: 'Chief of medicine', certifications: ['fto', 'life'], status: 'offduty', online: false, doctor: true, trainee: false, joinedAt: now - 400 * day, hoursOnDuty: 640, reportsFiled: 190, revivesMonth: 4 },
  { citizenid: 'EVQ22010', name: 'Dr. Elena Vasquez', callsign: 'Med 4', grade: 3, rank: 'Doctor', certifications: ['life'], status: 'busy', online: true, doctor: true, trainee: false, joinedAt: now - 300 * day, hoursOnDuty: 410, reportsFiled: 121, revivesMonth: 9 },
  { citizenid: 'JHL30112', name: 'Jordan Hale', callsign: 'EMS 3', grade: 2, rank: 'Paramedic', certifications: ['life'], status: 'enroute', online: true, doctor: false, trainee: false, joinedAt: now - 246 * day, hoursOnDuty: 212, reportsFiled: 52, revivesMonth: 17 },
  { citizenid: 'SKW90012', name: 'Sam Kowalski', callsign: 'Air 1', grade: 2, rank: 'Paramedic', certifications: ['flight', 'life'], status: 'available', online: true, doctor: false, trainee: false, joinedAt: now - 150 * day, hoursOnDuty: 180, reportsFiled: 44, revivesMonth: 11 },
  { citizenid: 'MTR77001', name: 'Mia Torres', callsign: 'EMS 12', grade: 0, rank: 'Trainee', certifications: [], status: 'offduty', online: false, doctor: false, trainee: true, joinedAt: now - 9 * day, hoursOnDuty: 14, reportsFiled: 3, revivesMonth: 0 },
];

const rankNames = ['Trainee', 'EMT', 'Paramedic', 'Doctor', 'Chief of medicine'];

const ranks: Rank[] = rankNames.map((name, grade) => ({
  grade,
  name,
  holders: [1, 4, 9, 5, 1][grade] ?? 0,
  isBoss: grade === 4,
  permissions:
    grade === 4
      ? allPermissions(true)
      : {
          ...allPermissions(false),
          writeReports: true,
          useDefib: true,
          editPatients: grade >= 2,
          sendInvoices: grade >= 1,
          writePrescriptions: grade >= 3,
          prescribeControlled: grade >= 3,
          voidInvoices: grade >= 3,
          editOtherReports: grade >= 3,
          shareReports: grade >= 3,
        },
}));

const templates: Template[] = [
  { id: 1, name: 'Gunshot wound', narrative: 'Found [conscious or unresponsive] at [location], [time].\nWound: [entry site], [exit site or none].\nBlood loss: [none, moderate, severe].\n\nTreatment on scene: [tourniquet, gauze, splint].\nMedications: [drug, dose, route].\n\nHanded to: [hospital and doctor], or treated and released.', uses: 64 },
  { id: 2, name: 'Vehicle crash', narrative: 'Called to a [number]-vehicle crash at [location].\nPatient was the [driver or passenger], [belted or unbelted].\n\nInjuries: [details].\nTreatment: [details].', uses: 118 },
  { id: 3, name: 'Overdose', narrative: 'Found [conscious or unresponsive] at [location].\nSubstance: [drug, if known].\nNaloxone: [dose, response].', uses: 23 },
  { id: 4, name: 'Death on scene', narrative: 'Pronounced dead at [time] at [location].\nCause: [cause].\nNext of kin: [informed or not].', uses: 4 },
];

function profile(citizenid: string): Patient | null {
  const summary = patients.find((patient) => patient.citizenid === citizenid);
  if (!summary) return null;

  return {
    ...summary,
    phone: '555-0154',
    emergencyContact: 'Tasha Webb, sister',
    notes: '',
    injuries: summary.state === 'down' ? [{ bodyPart: 'torso', kind: 'bleeding' }, { bodyPart: 'left_leg', kind: 'fracture' }] : [],
    reports: [
      armReport,
      { ...armReport, id: 377, summary: 'Asthma attack', detail: 'Salbutamol nebuliser', medic: 'Jordan Hale', outcome: 'scene', createdAt: now - 36 * day },
      { ...armReport, id: 341, summary: 'Gunshot, left leg', detail: 'Tourniquet, driven to Pillbox', medic: 'Dr. Elena Vasquez', outcome: 'transported', createdAt: now - 62 * day },
    ],
    prescriptions: prescriptions.filter((entry) => entry.citizenid === citizenid),
    invoices: invoices.filter((entry) => entry.citizenid === citizenid),
  };
}

function draft(citizenid: string | null, callId: number | null): ReportDraft {
  const patient = patients.find((entry) => entry.citizenid === citizenid);

  return {
    id: 431,
    citizenid: patient?.citizenid ?? null,
    patientName: patient?.name ?? '',
    callId,
    occurredAt: now - 6 * minute,
    injuries: patient
      ? [
          { bodyPart: 'torso', kind: 'bleeding', label: 'Gunshot, bleeding', treatments: [2, 6], treated: true },
          { bodyPart: 'left_leg', kind: 'fracture', label: 'Fracture', treatments: [3], treated: true },
        ]
      : [],
    medications: patient ? [7, 8, 9] : [],
    extras: patient ? [5, 10] : [],
    narrative: patient
      ? 'Found unresponsive on Grove Street with a gunshot wound to the abdomen. Tourniquet and gauze applied, left leg splinted. Driven to Pillbox and laid on a bed.'
      : '',
    outcome: 'transported',
  };
}

export const handlers: MockHandlers = {
  boot: () => ({ locales: {}, bleedoutSeconds: 300 }),
  close: () => ok,
  respawn: () => ok,
  setStatus: () => ok,
  search: ({ query }) =>
    patients
      .filter((patient) => patient.name.toLowerCase().includes(query.toLowerCase()))
      .map((patient) => ({ kind: 'patient' as const, citizenid: patient.citizenid, title: patient.name, detail: patient.citizenid })),
  getDashboard: () => ({
    stats: {
      openCalls: calls.filter((call) => call.status === 'open').length,
      patientsDown: 1,
      medicsOnDuty: 6,
      medicsAvailable: 3,
      medicsOnCalls: 3,
      unpaidTotal: 3450,
      unpaidCount: 5,
      overdueCount: 2,
      training: trainee ? { done: 6, total: 10 } : undefined,
    },
    onDuty: [
      { citizenid: 'JHL30112', name: 'Jordan Hale', callsign: 'EMS 3', detail: 'Paramedic, ambulance', status: 'enroute' },
      { citizenid: 'AMO22871', name: 'Amara Osei', callsign: 'EMS 5', detail: 'EMT, ambulance', status: 'onscene' },
      { citizenid: 'EVQ22010', name: 'Dr. Elena Vasquez', callsign: '', detail: 'Doctor, Pillbox', status: 'busy' },
      { citizenid: 'NBR41901', name: 'Noah Brandt', callsign: 'EMS 7', detail: 'EMT, ambulance', status: 'available' },
      { citizenid: 'SKW90012', name: 'Sam Kowalski', callsign: 'Air 1', detail: 'Flight medic, helicopter', status: 'available' },
      { citizenid: 'RMN50110', name: 'Dr. Ravi Menon', callsign: '', detail: 'Doctor, Pillbox front desk', status: 'available' },
    ],
    hospitals: hospitalBeds(),
  }),
  getCalls: () => calls,
  getDispatchSummary: () => ({ available: 4, onBreak: 1, lastClosedAt: now - 18 * minute }),
  respondCall: () => ok,
  leaveCall: () => ok,
  waypointCall: () => ok,
  assignCall: () => ok,
  closeCall: () => ok,
  markTransported: () => ok,
  searchPatients: ({ query }) => patients.filter((patient) => patient.name.toLowerCase().includes(query.toLowerCase()) || patient.citizenid.includes(query.toUpperCase())),
  getPatient: ({ citizenid }) => profile(citizenid),
  savePatient: () => ok,
  getReports: () => reports,
  getReport: ({ id }) => (id === reportDetail.id ? reportDetail : { ...reportDetail, ...reports.find((entry) => entry.id === id) }),
  newReport: ({ citizenid, callId }) => draft(citizenid ?? 'LMX20391', callId ?? 812),
  saveReport: () => ({ ok: true, id: 431 }),
  fileReport: () => ({ ok: true, id: 431 }),
  shareReport: () => ok,
  getPrescriptions: () => prescriptions,
  createPrescription: () => ({ ok: true, id: 1200 }),
  renewPrescription: () => ok,
  cancelPrescription: () => ok,
  getBilling: () => ({ stats: { billedWeek: 12880, paidWeek: 9430, overdue: 1190 }, invoices }),
  createInvoice: () => ({ ok: true, id: 2230 }),
  chargeInvoice: () => ({ ok: false, error: 'Their bank declined the charge' }),
  markInvoicePaid: () => ok,
  voidInvoice: () => ok,
  getRoster: () => ({
    staff,
    ranks: rankNames.map((name, grade) => ({ grade, name })),
    certifications: [
      { id: 'life', label: 'Life support' },
      { id: 'flight', label: 'Flight medic' },
      { id: 'fto', label: 'Field training officer' },
    ],
  }),
  saveStaff: () => ok,
  getRanks: () => ranks,
  saveRank: () => ok,
  getTreatments: () => treatments,
  getItems: () => [
    { name: 'bandage', label: 'Bandage' },
    { name: 'tourniquet', label: 'Tourniquet' },
    { name: 'splint', label: 'Splint' },
    { name: 'burn_dressing', label: 'Burn dressing' },
    { name: 'defibrillator', label: 'Defibrillator charge' },
  ],
  saveTreatment: () => ({ ok: true, id: 12 }),
  deleteTreatment: () => ok,
  getTemplates: () => templates,
  saveTemplate: () => ({ ok: true, id: 5 }),
  deleteTemplate: () => ok,
  getSettings: () => ({ medicShare: 20, shareWithPolice: true }),
  saveSettings: () => ok,
};

const routes: Record<string, { page: Medic['pages'][number]; citizenid?: string }> = {
  '#dispatch': { page: 'dispatch' },
  '#empty': { page: 'dispatch' },
  '#patients': { page: 'patients' },
  '#profile': { page: 'patients', citizenid: 'LMX20391' },
  '#reports': { page: 'reports' },
  '#prescriptions': { page: 'prescriptions' },
  '#billing': { page: 'billing' },
  '#beds': { page: 'dashboard' },
  '#roster': { page: 'roster' },
  '#management': { page: 'management' },
};

const route = routes[location.hash] ?? { page: 'dashboard' as const };

export const openMessage: Messages = {
  action: 'open',
  data: {
    medic,
    settings: { medicShare: 20, shareWithPolice: true },
    keybinds: { respond: 'E', waypoint: 'K' },
    page: route.page,
    citizenid: route.citizenid ?? null,
  },
};

export function startDeath(): void {
  document.body.style.background = '#3a4048';

  const at = nowSeconds();
  const screen: DeathScreen =
    location.hash === '#laststand'
      ? { kind: 'laststand', endsAt: at + 187, total: 300, now: at, callKey: 'G', emsCalled: false }
      : {
          kind: 'dead',
          respawnAt: location.hash === '#respawn' ? at : at + 42,
          now: at,
          fee: 200,
          hospital: 'Pillbox Hill',
          respawnKey: 'E',
          killKey: 'F',
        };

  window.postMessage({ action: 'death', data: screen } satisfies Messages, '*');
  if (location.hash === '#laststand') window.postMessage({ action: 'deathHold', data: 9000 } satisfies Messages, '*');
}

export function startBedUpdates(): void {
  if (location.hash !== '#beds') return;

  setTimeout(() => window.postMessage({ action: 'bedsChanged', data: hospitalBeds(true) } satisfies Messages, '*'), 3000);
}

export function startAlerts(): void {
  document.body.style.background = '#3a4048';

  if (location.hash !== '#popup') return;

  window.postMessage({ action: 'alert', data: { call: fallCall, distance: 3100, seconds: 600 } } satisfies Messages, '*');
  setTimeout(() => window.postMessage({ action: 'alert', data: { call: { ...downCall, createdAt: now }, distance: 1200, seconds: 600 } } satisfies Messages, '*'), 50);
}
