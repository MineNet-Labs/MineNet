import { Injectable } from '@nestjs/common';
import {
  ClaimStatus,
  EscrowStatus,
  IncidentStatus,
  InspectionStatus,
  LoanStatus,
  LotStatus,
  PolicyStatus,
  WorkerStatus,
} from '@prisma/client';
import { PrismaService } from '../../prisma/prisma.service.js';

@Injectable()
export class ReportsService {
  constructor(private readonly prisma: PrismaService) {}

  async getDashboardSummary(organizationId?: string) {
    const lotWhere = organizationId ? { organizationId } : undefined;
    const [
      totalLots,
      inspectedLots,
      pendingInspections,
      activeListings,
      lockedEscrows,
      releasedEscrows,
      activePolicies,
      openClaims,
      activeLoans,
      activeWorkers,
      openIncidents,
    ] = await Promise.all([
      this.prisma.mineralLot.count({ where: lotWhere }),
      this.prisma.mineralLot.count({
        where: { ...lotWhere, status: LotStatus.INSPECTED },
      }),
      this.prisma.inspection.count({
        where: { status: InspectionStatus.PENDING },
      }),
      this.prisma.listing.count({
        where: { organizationId, status: 'ACTIVE' },
      }),
      this.prisma.escrow.aggregate({
        where: { status: EscrowStatus.LOCKED },
        _sum: { amount: true },
        _count: true,
      }),
      this.prisma.escrow.aggregate({
        where: { status: EscrowStatus.RELEASED },
        _sum: { amount: true },
        _count: true,
      }),
      this.prisma.insurancePolicy.count({
        where: { status: PolicyStatus.ACTIVE },
      }),
      this.prisma.insuranceClaim.count({
        where: { status: ClaimStatus.FILED },
      }),
      this.prisma.loan.aggregate({
        where: { status: LoanStatus.ACTIVE },
        _sum: { amount: true },
        _count: true,
      }),
      this.prisma.worker.count({
        where: { organizationId, status: WorkerStatus.ACTIVE },
      }),
      this.prisma.safetyIncident.count({
        where: { status: { not: IncidentStatus.RESOLVED } },
      }),
    ]);

    return {
      generatedAt: new Date().toISOString(),
      lots: { total: totalLots, inspected: inspectedLots },
      inspections: { pending: pendingInspections },
      marketplace: { activeListings },
      escrow: {
        lockedCount: lockedEscrows._count,
        lockedAmount: lockedEscrows._sum.amount ?? 0,
        releasedCount: releasedEscrows._count,
        releasedAmount: releasedEscrows._sum.amount ?? 0,
      },
      insurance: { activePolicies, openClaims },
      financing: {
        activeLoanCount: activeLoans._count,
        activeLoanAmount: activeLoans._sum.amount ?? 0,
      },
      workforce: { activeWorkers, openIncidents },
    };
  }

  async exportLotsCsv(organizationId?: string): Promise<string> {
    const lots = await this.prisma.mineralLot.findMany({
      where: organizationId ? { organizationId } : undefined,
      include: {
        organization: { select: { name: true } },
        site: { select: { code: true, name: true } },
      },
      orderBy: { createdAt: 'desc' },
    });

    const header =
      'lotCode,mineralType,quantityKg,gradePct,status,regulatorHold,organization,site,createdAt';
    const rows = lots.map((l) =>
      [
        l.lotCode,
        l.mineralType,
        (Number(l.quantityGrams) / 1000).toFixed(3),
        l.gradePct ?? '',
        l.status,
        l.regulatorHold,
        `"${l.organization.name.replace(/"/g, '""')}"`,
        `"${(l.site?.name ?? '').replace(/"/g, '""')}"`,
        l.createdAt.toISOString(),
      ].join(','),
    );
    return [header, ...rows].join('\n');
  }
}
