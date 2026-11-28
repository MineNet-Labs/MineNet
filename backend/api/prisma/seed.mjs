import 'dotenv/config';
import { createHash } from 'node:crypto';
import { PrismaPg } from '@prisma/adapter-pg';
import { PrismaClient } from '@prisma/client';
import { Pool } from 'pg';

const pool = new Pool({ connectionString: process.env.DATABASE_URL });
const adapter = new PrismaPg(pool);
const prisma = new PrismaClient({ adapter });

const hash = (s) => `0x${createHash('sha256').update(s).digest('hex')}`;

async function main() {
  const org = await prisma.organization.upsert({
    where: { rdbNumber: 'RDB-108452317' },
    update: {},
    create: {
      name: 'Uwimana Mining Cooperative',
      kind: 'Mining cooperative',
      rdbNumber: 'RDB-108452317',
      tin: 'TIN 102 445 781',
      regulatorName: 'Rwanda Mines, Petroleum and Gas Board (RMB)',
      licenceNumber: 'ML-2025-081',
      licenceIssuedAt: new Date('2025-03-14T00:00:00.000Z'),
      licenceExpiryAt: new Date('2027-03-14T00:00:00.000Z'),
      status: 'VALIDATED',
      payoutWallet: '0x7A3f9c21B4e8D05a6C1d2E9f0B3a4C5d6E7f8091',
      contactName: 'Jean Uwimana',
      contactEmail: 'jean@uwimana-coop.rw',
      contactPhone: '+250 788 000 184',
      address: 'KG 9 Ave, Gasabo, Kigali',
    },
  });

  const gatumba = await prisma.mineSite.upsert({
    where: { code: 'SITE-001' },
    update: {},
    create: {
      code: 'SITE-001',
      name: 'Gatumba Mine',
      district: 'Ngororero',
      location: 'Gatumba Sector, Western Province',
      lat: -1.918,
      lng: 29.654,
      status: 'ACTIVE',
      areaHa: 145.5,
      minerals: ['Coltan', 'Cassiterite', 'Wolframite'],
      licence: 'ML-2025-081',
      licenceExpiry: new Date('2027-03-14T00:00:00.000Z'),
      manager: 'Jean Uwimana',
      lastActivity: new Date(),
      organizationId: org.id,
    },
  });

  await prisma.mineSite.upsert({
    where: { code: 'SITE-002' },
    update: {},
    create: {
      code: 'SITE-002',
      name: 'Rutongo North Concession',
      district: 'Rulindo',
      location: 'Rutongo Sector, Northern Province',
      lat: -1.812,
      lng: 30.058,
      status: 'ACTIVE',
      areaHa: 92.0,
      minerals: ['Cassiterite', 'Tin'],
      licence: 'ML-2025-094',
      licenceExpiry: new Date('2027-06-30T00:00:00.000Z'),
      manager: 'Claudine Mukamana',
      lastActivity: new Date(),
      organizationId: org.id,
    },
  });

  const shaftA = await prisma.mineShaft.upsert({
    where: { code: 'SHF-001' },
    update: {},
    create: {
      code: 'SHF-001',
      name: 'North Tunnel A',
      depthM: 85,
      mineral: 'Coltan',
      status: 'OPERATIONAL',
      lastInspection: new Date('2026-10-15T00:00:00.000Z'),
      siteId: gatumba.id,
    },
  });

  await prisma.mineShaft.upsert({
    where: { code: 'SHF-002' },
    update: {},
    create: {
      code: 'SHF-002',
      name: 'West Adit B',
      depthM: 62,
      mineral: 'Cassiterite',
      status: 'OPERATIONAL',
      lastInspection: new Date('2026-11-01T00:00:00.000Z'),
      siteId: gatumba.id,
    },
  });

  const wallet = org.payoutWallet ?? '0x7A3f9c21B4e8D05a6C1d2E9f0B3a4C5d6E7f8091';

  const lot117 = await prisma.mineralLot.upsert({
    where: { lotCode: 'LOT-00117' },
    update: {},
    create: {
      lotCode: 'LOT-00117',
      mineralType: 'Wolframite',
      quantityGrams: BigInt(900_000),
      gradePct: 62.0,
      status: 'INSPECTED',
      ownerWallet: wallet,
      custodianWallet: wallet,
      organizationId: org.id,
      siteId: gatumba.id,
      shaftId: shaftA.id,
      events: {
        create: [
          {
            eventType: 'REGISTERED',
            actorWallet: wallet,
            actorName: 'Jean Uwimana',
            actorRole: 'Miner',
            dataHash: hash('LOT-00117:REGISTERED'),
            detail: '900 kg Wolframite registered at Gatumba Mine · declared grade 62.0%',
          },
          {
            eventType: 'INSPECTED',
            actorWallet: '0x2B9e000000000000000000000000000000000102',
            actorName: 'Eric Nshimiyimana',
            actorRole: 'Inspector',
            dataHash: hash('LOT-00117:INSPECTED'),
            detail: 'Grade 62.0% WO3 attested · conflict-free verified',
          },
        ],
      },
    },
  });

  await prisma.inspection.upsert({
    where: { code: 'INS-2026-0001' },
    update: {},
    create: {
      code: 'INS-2026-0001',
      lotId: lot117.id,
      siteId: gatumba.id,
      shaft: 'North Tunnel A',
      type: 'Pre-export certification',
      inspectorName: 'Eric Nshimiyimana',
      inspectorWallet: '0x2B9e000000000000000000000000000000000102',
      status: 'COMPLETED',
      measuredGradePct: 62.0,
      sampleId: 'SMP-2026-0117',
      method: 'XRF Spectrometry',
      findings: 'Grade 62.0% WO3 attested · conflict-free origin verified',
      completedAt: new Date('2026-10-20T00:00:00.000Z'),
    },
  });

  const lot120 = await prisma.mineralLot.upsert({
    where: { lotCode: 'LOT-00120' },
    update: {},
    create: {
      lotCode: 'LOT-00120',
      mineralType: 'Cassiterite',
      quantityGrams: BigInt(1_800_000),
      gradePct: 68.4,
      status: 'REGISTERED',
      ownerWallet: wallet,
      custodianWallet: wallet,
      organizationId: org.id,
      siteId: gatumba.id,
      events: {
        create: [
          {
            eventType: 'REGISTERED',
            actorWallet: wallet,
            actorName: 'Jean Uwimana',
            actorRole: 'Miner',
            dataHash: hash('LOT-00120:REGISTERED'),
            detail: '1,800 kg Cassiterite registered at Gatumba Mine · declared grade 68.4%',
          },
        ],
      },
    },
  });

  const listing1 = await prisma.listing.upsert({
    where: { code: 'LST-0001' },
    update: {},
    create: {
      code: 'LST-0001',
      lotId: lot117.id,
      organizationId: org.id,
      pricePerKg: 14.5,
      quantityKg: 900,
      currency: 'USD',
      status: 'SOLD',
      notes: 'FOB Kigali, conflict-free ICGLR certified',
    },
  });

  await prisma.buyerRequest.upsert({
    where: { code: 'REQ-0001' },
    update: {},
    create: {
      code: 'REQ-0001',
      buyerName: 'Great Lakes Minerals Co.',
      buyerWallet: '0x9999000000000000000000000000000000000201',
      verified: true,
      mineralType: 'Cassiterite',
      requiredKg: 2500,
      remainingKg: 2500,
      targetGrade: '65%+ Sn',
      pricePerKg: 18.2,
      currency: 'USD',
      city: 'Kigali',
      country: 'Rwanda',
      deadline: new Date('2026-12-31T00:00:00.000Z'),
      status: 'OPEN',
    },
  });

  const offer1 = await prisma.offer.upsert({
    where: { code: 'OFF-0001' },
    update: {},
    create: {
      code: 'OFF-0001',
      lotId: lot117.id,
      listingId: listing1.id,
      buyerName: 'Rwanda Minerals Export SA',
      buyerWallet: '0x8888000000000000000000000000000000000301',
      pricePerKg: 14.5,
      quantityKg: 900,
      currency: 'USD',
      status: 'ACCEPTED',
      messages: {
        create: {
          senderSide: 'BUYER',
          pricePerKg: 14.5,
          quantityKg: 900,
          note: 'Accepted listing price; ready for escrow lock.',
        },
      },
    },
  });

  await prisma.escrow.upsert({
    where: { code: 'ESC-0001' },
    update: {},
    create: {
      code: 'ESC-0001',
      lotId: lot117.id,
      offerId: offer1.id,
      buyerName: 'Rwanda Minerals Export SA',
      buyerWallet: '0x8888000000000000000000000000000000000301',
      amount: 13050,
      currency: 'USD',
      status: 'LOCKED',
    },
  });

  await prisma.custodyTransfer.upsert({
    where: { code: 'TRF-0001' },
    update: {},
    create: {
      code: 'TRF-0001',
      lotId: lot117.id,
      kind: 'TRANSPORT',
      partyName: 'Volcano Freight Ltd',
      partyWallet: '0x4444000000000000000000000000000000000401',
      fromLocation: 'Gatumba Mine',
      toLocation: 'Rwanda Minerals Export SA, Kigali',
      sealId: 'SL-48812',
      vehicle: 'RAD 412 K',
      status: 'IN_TRANSIT',
      senderConfirmed: true,
      receiverConfirmed: true,
    },
  });

  const policy1 = await prisma.insurancePolicy.upsert({
    where: { code: 'POL-0001' },
    update: {},
    create: {
      code: 'POL-0001',
      lotId: lot120.id,
      insurerCode: 'isange',
      insurerName: 'Isange Assurance',
      coverType: 'STORAGE',
      sumInsured: 32760,
      premium: 131,
      currency: 'USD',
      status: 'ACTIVE',
      validFrom: new Date('2026-11-01T00:00:00.000Z'),
      validTo: new Date('2027-02-01T00:00:00.000Z'),
    },
  });

  await prisma.insuranceClaim.upsert({
    where: { code: 'CLM-0001' },
    update: {},
    create: {
      code: 'CLM-0001',
      policyId: policy1.id,
      lotId: lot120.id,
      reason: 'Water damage to 40 kg in bay C-14 after roof leak',
      amount: 720,
      currency: 'USD',
      status: 'FILED',
    },
  });

  await prisma.loan.upsert({
    where: { code: 'LN-0001' },
    update: {},
    create: {
      code: 'LN-0001',
      lotId: lot120.id,
      financierCode: 'umurenge',
      financierName: 'Umurenge Trade Finance',
      amount: 12000,
      currency: 'USD',
      ratePct: 11,
      termDays: 90,
      purpose: 'Working capital',
      status: 'ACTIVE',
      dueAt: new Date('2027-02-26T00:00:00.000Z'),
    },
  });

  await prisma.worker.upsert({
    where: { code: 'WRK-0001' },
    update: {},
    create: {
      code: 'WRK-0001',
      fullName: 'Emmanuel Habimana',
      category: 'Driller',
      phone: '+250 788 112 233',
      accessBadge: 'QR ready',
      status: 'ACTIVE',
      organizationId: org.id,
      siteId: gatumba.id,
    },
  });

  await prisma.extractionRecord.upsert({
    where: { code: 'EXT-0001' },
    update: {},
    create: {
      code: 'EXT-0001',
      siteId: gatumba.id,
      shaftId: shaftA.id,
      mineralType: 'Coltan',
      quantityKg: 420,
      status: 'APPROVED',
    },
  });

  await prisma.safetyIncident.upsert({
    where: { code: 'INC-0001' },
    update: {},
    create: {
      code: 'INC-0001',
      siteId: gatumba.id,
      severity: 'LOW',
      title: 'Ventilation fan maintenance alert',
      description: 'Scheduled backup switchover completed with zero downtime.',
      reportedBy: 'Jean Uwimana',
      status: 'RESOLVED',
      resolvedAt: new Date(),
    },
  });

  await prisma.b2bAgreement.upsert({
    where: { code: 'AGR-0001' },
    update: {},
    create: {
      code: 'AGR-0001',
      kind: 'SUPPLY',
      organizationId: org.id,
      counterpartyName: 'Kigali Tin Smelter Ltd',
      mineralOrService: 'Cassiterite concentrate (monthly supply)',
      quantityKg: 5000,
      unitPrice: 18.0,
      currency: 'USD',
      startDate: new Date('2026-12-01T00:00:00.000Z'),
      endDate: new Date('2027-12-01T00:00:00.000Z'),
      status: 'ACTIVE',
      terms: 'Monthly delivery in sealed lots; escrow settlement within 5 days.',
    },
  });

  const existingNotifs = await prisma.notification.count();
  if (existingNotifs === 0) {
    await prisma.notification.createMany({
      data: [
        {
          audience: 'miner',
          kind: 'custody',
          text: 'LOT-00117 is in transit with Volcano Freight Ltd (seal SL-48812)',
          href: '/miner/mineral-lots/LOT-00117',
          organizationId: org.id,
        },
        {
          audience: 'insurer:isange',
          kind: 'alert',
          text: 'New claim CLM-0001 from Uwimana Mining Cooperative on LOT-00120: USD 720',
          href: '/insurer/claims/CLM-0001',
          organizationId: org.id,
        },
      ],
    });
  }

  await prisma.siteReport.upsert({
    where: { code: 'REP-0001' },
    update: {},
    create: {
      code: 'REP-0001',
      siteId: gatumba.id,
      period: '2026-11',
      author: 'Jean Uwimana',
      summary: 'Monthly output on target; all shaft inspections passed.',
      productionKg: 2700,
      safetyScore: 98,
      complianceNotes: 'EIA water runoff monitoring within RMB limits.',
      status: 'SUBMITTED',
    },
  });

  await prisma.supportTicket.upsert({
    where: { code: 'TKT-0001' },
    update: {},
    create: {
      code: 'TKT-0001',
      portal: 'miner',
      category: 'Licence & Compliance',
      subject: 'Question about 2027 licence renewal window',
      message: 'When can we submit our updated EIA document for ML-2025-081?',
      submittedBy: 'Jean Uwimana',
      organizationId: org.id,
      status: 'OPEN',
    },
  });

  console.log(
    `Seeded full MineNet dataset for "${org.name}" (${org.id}).`,
  );
}

main()
  .catch((err) => {
    console.error(err);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
    await pool.end();
  });
