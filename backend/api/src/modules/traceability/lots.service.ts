import { createHash } from 'node:crypto';
import {
  BadRequestException,
  ConflictException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { LotStatus, OrgStatus, Prisma, SiteStatus } from '@prisma/client';
import { PrismaService } from '../../prisma/prisma.service.js';
import { CreateLotEventDto } from './dto/create-lot-event.dto.js';
import { CreateLotDto } from './dto/create-lot.dto.js';
import { ToggleLotFreezeDto, UpdateLotDto } from './dto/update-lot.dto.js';

function sha256Hex(payload: string): string {
  return `0x${createHash('sha256').update(payload).digest('hex')}`;
}

@Injectable()
export class LotsService {
  constructor(private readonly prisma: PrismaService) {}

  private serializeEvent<
    T extends { blockNumber: bigint | null },
  >(event: T) {
    return {
      ...event,
      blockNumber:
        event.blockNumber !== null ? event.blockNumber.toString() : null,
    };
  }

  private serializeLot<
    T extends {
      quantityGrams: bigint;
      tokenId: bigint | null;
      events?: Array<{ blockNumber: bigint | null }>;
    },
  >(lot: T) {
    const quantityGramsNumber = Number(lot.quantityGrams);
    return {
      ...lot,
      quantityGrams: lot.quantityGrams.toString(),
      quantityKg: Math.round((quantityGramsNumber / 1000) * 1000) / 1000,
      tokenId: lot.tokenId !== null ? lot.tokenId.toString() : null,
      ...(lot.events
        ? { events: lot.events.map((e) => this.serializeEvent(e)) }
        : {}),
    };
  }

  private async generateLotCode(): Promise<string> {
    const count = await this.prisma.mineralLot.count();
    return `LOT-${String(count + 101).padStart(5, '0')}`;
  }

  async create(dto: CreateLotDto) {
    const [org, site] = await Promise.all([
      this.prisma.organization.findUnique({
        where: { id: dto.organizationId },
      }),
      this.prisma.mineSite.findUnique({ where: { id: dto.siteId } }),
    ]);

    if (!org) {
      throw new NotFoundException(`Organization ${dto.organizationId} not found`);
    }
    if (!site) {
      throw new NotFoundException(`Mine site ${dto.siteId} not found`);
    }
    if (site.organizationId !== org.id) {
      throw new BadRequestException(
        'Mine site does not belong to the specified organization',
      );
    }

    // Licence-gated registration rule (mirrors LotPassport + domain.ts)
    if (org.status !== OrgStatus.VALIDATED) {
      throw new BadRequestException(
        `Organization must be VALIDATED before registering lots (current: ${org.status})`,
      );
    }
    if (org.licenceExpiryAt && org.licenceExpiryAt.getTime() < Date.now()) {
      throw new BadRequestException('Organization licence has expired');
    }
    if (site.status !== SiteStatus.ACTIVE) {
      throw new BadRequestException(
        `Mine site ${site.code} is not ACTIVE`,
      );
    }
    if (site.licenceExpiry.getTime() < Date.now()) {
      throw new BadRequestException(
        `Mine site ${site.code} licence has expired`,
      );
    }

    const lotCode = dto.lotCode ?? (await this.generateLotCode());
    const quantityGrams = BigInt(Math.round(dto.quantityKg * 1000));
    const ownerWallet =
      dto.ownerWallet ?? org.payoutWallet ?? '0x0000000000000000000000000000000000000000';
    const actorName = dto.actorName ?? org.contactName ?? org.name;
    const detail = `${dto.quantityKg} kg ${dto.mineralType} registered at ${site.name}${dto.gradePct !== undefined ? ` · declared grade ${dto.gradePct}%` : ''}`;
    const dataHash = sha256Hex(
      JSON.stringify({
        lotCode,
        mineralType: dto.mineralType,
        quantityGrams: quantityGrams.toString(),
        siteId: site.id,
        organizationId: org.id,
      }),
    );

    try {
      const lot = await this.prisma.mineralLot.create({
        data: {
          lotCode,
          mineralType: dto.mineralType,
          quantityGrams,
          gradePct: dto.gradePct,
          ownerWallet,
          custodianWallet: ownerWallet,
          organizationId: org.id,
          siteId: site.id,
          shaftId: dto.shaftId,
          events: {
            create: {
              eventType: 'REGISTERED',
              actorWallet: ownerWallet,
              actorName,
              actorRole: 'Miner',
              dataHash,
              detail,
            },
          },
        },
        include: {
          organization: { select: { id: true, name: true, status: true } },
          site: { select: { id: true, code: true, name: true, district: true } },
          events: { orderBy: { occurredAt: 'asc' } },
        },
      });

      return this.serializeLot(lot);
    } catch (error) {
      if (
        error instanceof Prisma.PrismaClientKnownRequestError &&
        error.code === 'P2002'
      ) {
        throw new ConflictException(`Lot code ${lotCode} already exists`);
      }
      throw error;
    }
  }

  async findAll(filters?: {
    organizationId?: string;
    siteId?: string;
    status?: LotStatus;
    mineralType?: string;
  }) {
    const lots = await this.prisma.mineralLot.findMany({
      where: {
        organizationId: filters?.organizationId,
        siteId: filters?.siteId,
        status: filters?.status,
        mineralType: filters?.mineralType
          ? { contains: filters.mineralType, mode: 'insensitive' }
          : undefined,
      },
      include: {
        organization: { select: { id: true, name: true } },
        site: { select: { id: true, code: true, name: true, district: true } },
        _count: { select: { events: true, documents: true } },
      },
      orderBy: { createdAt: 'desc' },
    });

    return lots.map((lot) => this.serializeLot(lot));
  }

  async findOne(id: string) {
    const lot = await this.prisma.mineralLot.findUnique({
      where: { id },
      include: {
        organization: {
          select: { id: true, name: true, status: true, licenceNumber: true },
        },
        site: {
          select: {
            id: true,
            code: true,
            name: true,
            district: true,
            licence: true,
            licenceExpiry: true,
          },
        },
        events: { orderBy: { occurredAt: 'asc' } },
        documents: { orderBy: { createdAt: 'desc' } },
      },
    });
    if (!lot) {
      throw new NotFoundException(`Mineral lot ${id} not found`);
    }
    return this.serializeLot(lot);
  }

  async update(id: string, dto: UpdateLotDto) {
    await this.findOne(id);
    const updated = await this.prisma.mineralLot.update({
      where: { id },
      data: {
        gradePct: dto.gradePct,
        status: dto.status,
        ownerWallet: dto.ownerWallet,
        custodianWallet: dto.custodianWallet,
        tokenId: dto.tokenId !== undefined ? BigInt(dto.tokenId) : undefined,
      },
      include: {
        organization: { select: { id: true, name: true } },
        site: { select: { id: true, code: true, name: true } },
      },
    });
    return this.serializeLot(updated);
  }

  async getPassportEvents(lotId: string) {
    await this.findOne(lotId);
    const events = await this.prisma.lotEvent.findMany({
      where: { lotId },
      orderBy: { occurredAt: 'asc' },
    });
    return events.map((e) => this.serializeEvent(e));
  }

  /** Append-only passport event (never modifies or deletes previous events). */
  async appendEvent(lotId: string, dto: CreateLotEventDto) {
    const lot = await this.prisma.mineralLot.findUnique({
      where: { id: lotId },
    });
    if (!lot) {
      throw new NotFoundException(`Mineral lot ${lotId} not found`);
    }

    const dataHash =
      dto.dataHash ??
      sha256Hex(
        JSON.stringify({
          lotId,
          eventType: dto.eventType,
          actorWallet: dto.actorWallet,
          detail: dto.detail,
          timestamp: Date.now(),
        }),
      );

    const event = await this.prisma.lotEvent.create({
      data: {
        lotId,
        eventType: dto.eventType,
        actorWallet: dto.actorWallet,
        actorName: dto.actorName,
        actorRole: dto.actorRole,
        counterparty: dto.counterparty,
        dataHash,
        txHash: dto.txHash,
        blockNumber:
          dto.blockNumber !== undefined ? BigInt(dto.blockNumber) : undefined,
        detail: dto.detail,
      },
    });

    // Apply safe side-effects on the lot for well-known custody/flag events
    const normalized = dto.eventType.toUpperCase();
    if (normalized === 'CUSTODY_CONFIRMED' && dto.counterparty) {
      await this.prisma.mineralLot.update({
        where: { id: lotId },
        data: { custodianWallet: dto.counterparty },
      });
    } else if (normalized === 'FLAG_RAISED') {
      await this.prisma.mineralLot.update({
        where: { id: lotId },
        data: { openFlags: { increment: 1 } },
      });
    } else if (normalized === 'FLAG_RESOLVED' && lot.openFlags > 0) {
      await this.prisma.mineralLot.update({
        where: { id: lotId },
        data: { openFlags: { decrement: 1 } },
      });
    }

    return this.serializeEvent(event);
  }

  async toggleFreeze(lotId: string, dto: ToggleLotFreezeDto) {
    await this.findOne(lotId);
    const eventType = dto.frozen ? 'FROZEN' : 'UNFROZEN';
    const actorWallet =
      dto.actorWallet ?? '0x0000000000000000000000000000000000000001';

    const updated = await this.prisma.mineralLot.update({
      where: { id: lotId },
      data: {
        regulatorHold: dto.frozen,
        events: {
          create: {
            eventType,
            actorWallet,
            actorName: dto.actorName ?? 'RMB Regulator',
            actorRole: 'Regulator',
            detail: dto.reason,
            dataHash: sha256Hex(
              JSON.stringify({ lotId, eventType, reason: dto.reason }),
            ),
          },
        },
      },
      include: {
        events: { orderBy: { occurredAt: 'asc' } },
      },
    });

    return this.serializeLot(updated);
  }
}
