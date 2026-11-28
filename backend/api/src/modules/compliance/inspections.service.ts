import { createHash } from 'node:crypto';
import {
  BadRequestException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { InspectionStatus, LotStatus } from '@prisma/client';
import { PrismaService } from '../../prisma/prisma.service.js';
import {
  AssignInspectorDto,
  CreateInspectionDto,
  SubmitInspectionResultDto,
} from './dto/inspection.dto.js';

function sha256Hex(payload: string): string {
  return `0x${createHash('sha256').update(payload).digest('hex')}`;
}

@Injectable()
export class InspectionsService {
  constructor(private readonly prisma: PrismaService) {}

  private async generateCode(): Promise<string> {
    const count = await this.prisma.inspection.count();
    const year = new Date().getFullYear();
    return `INS-${year}-${String(count + 1).padStart(4, '0')}`;
  }

  async create(dto: CreateInspectionDto) {
    const lot = await this.prisma.mineralLot.findUnique({
      where: { id: dto.lotId },
      include: { organization: { select: { name: true, contactName: true } } },
    });
    if (!lot) {
      throw new NotFoundException(`Mineral lot ${dto.lotId} not found`);
    }

    const code = await this.generateCode();
    const detail = `${dto.type} requested (${code})`;

    const inspection = await this.prisma.$transaction(async (tx) => {
      const created = await tx.inspection.create({
        data: {
          code,
          lotId: lot.id,
          siteId: lot.siteId,
          shaft: dto.shaft,
          type: dto.type,
          status: InspectionStatus.PENDING,
        },
        include: {
          lot: { select: { id: true, lotCode: true, mineralType: true } },
        },
      });

      await tx.lotEvent.create({
        data: {
          lotId: lot.id,
          eventType: 'INSPECTION_REQUESTED',
          actorWallet: lot.ownerWallet,
          actorName:
            dto.requestedByName ??
            lot.organization.contactName ??
            lot.organization.name,
          actorRole: 'Miner',
          detail,
          dataHash: sha256Hex(JSON.stringify({ code, lotId: lot.id, type: dto.type })),
        },
      });

      return created;
    });

    return inspection;
  }

  async findAll(filters?: { lotId?: string; status?: InspectionStatus }) {
    return this.prisma.inspection.findMany({
      where: {
        lotId: filters?.lotId,
        status: filters?.status,
      },
      include: {
        lot: {
          select: {
            id: true,
            lotCode: true,
            mineralType: true,
            status: true,
          },
        },
      },
      orderBy: { submittedAt: 'desc' },
    });
  }

  async findOne(id: string) {
    const inspection = await this.prisma.inspection.findUnique({
      where: { id },
      include: {
        lot: {
          select: {
            id: true,
            lotCode: true,
            mineralType: true,
            gradePct: true,
            status: true,
          },
        },
      },
    });
    if (!inspection) {
      throw new NotFoundException(`Inspection ${id} not found`);
    }
    return inspection;
  }

  async assignInspector(id: string, dto: AssignInspectorDto) {
    const existing = await this.findOne(id);
    if (
      existing.status === InspectionStatus.COMPLETED ||
      existing.status === InspectionStatus.REJECTED
    ) {
      throw new BadRequestException(
        `Inspection ${existing.code} is already finalized (${existing.status})`,
      );
    }

    return this.prisma.inspection.update({
      where: { id },
      data: {
        inspectorName: dto.inspectorName,
        inspectorWallet: dto.inspectorWallet,
        status: InspectionStatus.SCHEDULED,
      },
    });
  }

  async submitResult(id: string, dto: SubmitInspectionResultDto) {
    const existing = await this.findOne(id);
    if (
      existing.status === InspectionStatus.COMPLETED ||
      existing.status === InspectionStatus.REJECTED
    ) {
      throw new BadRequestException(
        `Inspection ${existing.code} already has a final result`,
      );
    }

    const nextInspectionStatus = dto.passed
      ? InspectionStatus.COMPLETED
      : InspectionStatus.REJECTED;
    const nextLotStatus = dto.passed ? LotStatus.INSPECTED : LotStatus.REJECTED;
    const inspectorName =
      dto.inspectorName ?? existing.inspectorName ?? 'RMB Inspector';
    const inspectorWallet =
      dto.inspectorWallet ??
      existing.inspectorWallet ??
      '0x0000000000000000000000000000000000000102';
    const detail = `${existing.type} (${existing.code}) · measured grade ${dto.measuredGradePct}% · ${dto.passed ? 'passed' : 'rejected'} · ${dto.findings}`;

    return this.prisma.$transaction(async (tx) => {
      const updated = await tx.inspection.update({
        where: { id },
        data: {
          status: nextInspectionStatus,
          measuredGradePct: dto.measuredGradePct,
          sampleId: dto.sampleId,
          method: dto.method,
          findings: dto.findings,
          inspectorName,
          inspectorWallet,
          completedAt: new Date(),
        },
        include: {
          lot: { select: { id: true, lotCode: true, mineralType: true } },
        },
      });

      await tx.mineralLot.update({
        where: { id: existing.lotId },
        data: {
          status: nextLotStatus,
          gradePct: dto.measuredGradePct,
        },
      });

      await tx.lotEvent.create({
        data: {
          lotId: existing.lotId,
          eventType: 'INSPECTED',
          actorWallet: inspectorWallet,
          actorName: inspectorName,
          actorRole: 'Inspector',
          detail,
          dataHash: sha256Hex(
            JSON.stringify({
              inspectionCode: existing.code,
              lotId: existing.lotId,
              passed: dto.passed,
              measuredGradePct: dto.measuredGradePct,
              sampleId: dto.sampleId,
              method: dto.method,
            }),
          ),
        },
      });

      return updated;
    });
  }
}
