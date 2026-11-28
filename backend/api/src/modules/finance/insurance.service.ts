import { createHash } from 'node:crypto';
import {
  BadRequestException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { ClaimStatus, PolicyStatus } from '@prisma/client';
import { PrismaService } from '../../prisma/prisma.service.js';
import {
  DecideClaimDto,
  FileClaimDto,
  QuotePolicyDto,
  RequestPolicyDto,
} from './dto/insurance.dto.js';

function sha256Hex(payload: string): string {
  return `0x${createHash('sha256').update(payload).digest('hex')}`;
}

@Injectable()
export class InsuranceService {
  constructor(private readonly prisma: PrismaService) {}

  async requestPolicy(dto: RequestPolicyDto) {
    const lot = await this.prisma.mineralLot.findUnique({
      where: { id: dto.lotId },
    });
    if (!lot) {
      throw new NotFoundException(`Mineral lot ${dto.lotId} not found`);
    }

    const count = await this.prisma.insurancePolicy.count();
    const code = `POL-${String(count + 1).padStart(4, '0')}`;

    return this.prisma.insurancePolicy.create({
      data: {
        code,
        lotId: dto.lotId,
        insurerCode: dto.insurerCode,
        insurerName: dto.insurerName,
        coverType: dto.coverType,
        sumInsured: dto.sumInsured,
        currency: dto.currency ?? 'USD',
        status: PolicyStatus.REQUESTED,
        validFrom: new Date(dto.validFrom),
        validTo: new Date(dto.validTo),
      },
      include: {
        lot: { select: { id: true, lotCode: true, mineralType: true } },
      },
    });
  }

  async findAllPolicies(filters?: {
    insurerCode?: string;
    lotId?: string;
    status?: PolicyStatus;
  }) {
    return this.prisma.insurancePolicy.findMany({
      where: {
        insurerCode: filters?.insurerCode,
        lotId: filters?.lotId,
        status: filters?.status,
      },
      include: {
        lot: {
          select: {
            id: true,
            lotCode: true,
            mineralType: true,
            organization: { select: { id: true, name: true } },
          },
        },
        _count: { select: { claims: true } },
      },
      orderBy: { createdAt: 'desc' },
    });
  }

  async findOnePolicy(id: string) {
    const policy = await this.prisma.insurancePolicy.findUnique({
      where: { id },
      include: {
        lot: {
          select: {
            id: true,
            lotCode: true,
            mineralType: true,
            organization: { select: { id: true, name: true } },
          },
        },
        claims: { orderBy: { filedAt: 'desc' } },
      },
    });
    if (!policy) {
      throw new NotFoundException(`Insurance policy ${id} not found`);
    }
    return policy;
  }

  async quotePolicy(id: string, dto: QuotePolicyDto) {
    const policy = await this.findOnePolicy(id);
    if (policy.status !== PolicyStatus.REQUESTED) {
      throw new BadRequestException(
        `Policy ${policy.code} cannot be quoted (current: ${policy.status})`,
      );
    }
    return this.prisma.insurancePolicy.update({
      where: { id },
      data: { premium: dto.premium, status: PolicyStatus.QUOTED },
    });
  }

  async activatePolicy(id: string) {
    const policy = await this.findOnePolicy(id);
    if (
      policy.status !== PolicyStatus.QUOTED &&
      policy.status !== PolicyStatus.REQUESTED
    ) {
      throw new BadRequestException(
        `Policy ${policy.code} cannot be activated (current: ${policy.status})`,
      );
    }

    return this.prisma.$transaction(async (tx) => {
      const updated = await tx.insurancePolicy.update({
        where: { id },
        data: { status: PolicyStatus.ACTIVE },
      });

      await tx.lotEvent.create({
        data: {
          lotId: policy.lotId,
          eventType: 'INSURED',
          actorWallet: '0x0000000000000000000000000000000000000501',
          actorName: policy.insurerName,
          actorRole: 'Insurer',
          detail: `${policy.coverType} cover ${policy.code} active · ${policy.currency} ${policy.sumInsured.toLocaleString()}`,
          dataHash: sha256Hex(
            JSON.stringify({
              policyCode: policy.code,
              lotId: policy.lotId,
              sumInsured: policy.sumInsured,
            }),
          ),
        },
      });

      return updated;
    });
  }

  async declinePolicy(id: string) {
    await this.findOnePolicy(id);
    return this.prisma.insurancePolicy.update({
      where: { id },
      data: { status: PolicyStatus.DECLINED },
    });
  }

  /* --------------------------------------------------------------- Claims */

  async fileClaim(dto: FileClaimDto) {
    const policy = await this.findOnePolicy(dto.policyId);
    if (policy.status !== PolicyStatus.ACTIVE) {
      throw new BadRequestException(
        `Policy ${policy.code} must be ACTIVE to file a claim (current: ${policy.status})`,
      );
    }

    const count = await this.prisma.insuranceClaim.count();
    const code = `CLM-${String(count + 1).padStart(4, '0')}`;

    return this.prisma.insuranceClaim.create({
      data: {
        code,
        policyId: policy.id,
        lotId: policy.lotId,
        reason: dto.reason,
        amount: dto.amount,
        currency: policy.currency,
        status: ClaimStatus.FILED,
      },
      include: {
        policy: { select: { id: true, code: true, insurerName: true } },
        lot: { select: { id: true, lotCode: true, mineralType: true } },
      },
    });
  }

  async findAllClaims(filters?: {
    insurerCode?: string;
    lotId?: string;
    status?: ClaimStatus;
  }) {
    return this.prisma.insuranceClaim.findMany({
      where: {
        lotId: filters?.lotId,
        status: filters?.status,
        policy: filters?.insurerCode
          ? { insurerCode: filters.insurerCode }
          : undefined,
      },
      include: {
        policy: {
          select: { id: true, code: true, insurerCode: true, insurerName: true },
        },
        lot: { select: { id: true, lotCode: true, mineralType: true } },
      },
      orderBy: { filedAt: 'desc' },
    });
  }

  async decideClaim(id: string, dto: DecideClaimDto) {
    const claim = await this.prisma.insuranceClaim.findUnique({
      where: { id },
    });
    if (!claim) {
      throw new NotFoundException(`Insurance claim ${id} not found`);
    }
    if (claim.status !== ClaimStatus.FILED) {
      throw new BadRequestException(
        `Claim ${claim.code} has already been decided (${claim.status})`,
      );
    }

    return this.prisma.insuranceClaim.update({
      where: { id },
      data: {
        status: dto.approved ? ClaimStatus.APPROVED : ClaimStatus.REJECTED,
        decisionNote: dto.decisionNote,
        decidedAt: new Date(),
      },
    });
  }

  /* --------------------------------------------------- Clients & Risk */

  async getClients(insurerCode?: string) {
    const policies = await this.prisma.insurancePolicy.findMany({
      where: insurerCode ? { insurerCode } : undefined,
      include: {
        lot: {
          select: {
            organization: {
              select: {
                id: true,
                name: true,
                kind: true,
                status: true,
                licenceNumber: true,
              },
            },
          },
        },
        claims: { select: { amount: true, status: true } },
      },
    });

    const byOrg = new Map<
      string,
      {
        organization: {
          id: string;
          name: string;
          kind: string;
          status: string;
          licenceNumber: string | null;
        };
        policyCount: number;
        activeExposure: number;
        totalPremium: number;
        claimsCount: number;
      }
    >();

    for (const p of policies) {
      const org = p.lot.organization;
      const entry = byOrg.get(org.id) ?? {
        organization: org,
        policyCount: 0,
        activeExposure: 0,
        totalPremium: 0,
        claimsCount: 0,
      };
      entry.policyCount += 1;
      if (p.status === PolicyStatus.ACTIVE) {
        entry.activeExposure += p.sumInsured;
      }
      entry.totalPremium += p.premium ?? 0;
      entry.claimsCount += p.claims.length;
      byOrg.set(org.id, entry);
    }

    return Array.from(byOrg.values());
  }

  async getRiskOverview(insurerCode?: string) {
    const [policies, claims] = await Promise.all([
      this.prisma.insurancePolicy.findMany({
        where: insurerCode ? { insurerCode } : undefined,
        include: {
          lot: {
            select: {
              id: true,
              lotCode: true,
              mineralType: true,
              regulatorHold: true,
              openFlags: true,
            },
          },
        },
      }),
      this.prisma.insuranceClaim.findMany({
        where: insurerCode ? { policy: { insurerCode } } : undefined,
      }),
    ]);

    const activePolicies = policies.filter((p) => p.status === PolicyStatus.ACTIVE);
    const totalExposure = activePolicies.reduce((s, p) => s + p.sumInsured, 0);
    const totalPremium = activePolicies.reduce((s, p) => s + (p.premium ?? 0), 0);
    const totalClaimed = claims.reduce((s, c) => s + c.amount, 0);
    const flaggedLots = activePolicies
      .filter((p) => p.lot.regulatorHold || p.lot.openFlags > 0)
      .map((p) => ({
        policyCode: p.code,
        lotCode: p.lot.lotCode,
        mineralType: p.lot.mineralType,
        sumInsured: p.sumInsured,
        regulatorHold: p.lot.regulatorHold,
        openFlags: p.lot.openFlags,
      }));

    return {
      insurerCode: insurerCode ?? 'all',
      activePolicyCount: activePolicies.length,
      totalExposure,
      totalPremium,
      claimCount: claims.length,
      openClaimCount: claims.filter((c) => c.status === ClaimStatus.FILED).length,
      totalClaimed,
      lossRatioPct:
        totalPremium > 0
          ? Math.round((totalClaimed / totalPremium) * 10000) / 100
          : 0,
      flaggedLots,
    };
  }
}
