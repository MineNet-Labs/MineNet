import { createHash } from 'node:crypto';
import {
  BadRequestException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { EscrowStatus } from '@prisma/client';
import { PrismaService } from '../../prisma/prisma.service.js';
import {
  CreateEscrowDto,
  RefundEscrowDto,
  ReleaseEscrowDto,
} from './dto/escrow.dto.js';

function sha256Hex(payload: string): string {
  return `0x${createHash('sha256').update(payload).digest('hex')}`;
}

@Injectable()
export class EscrowService {
  constructor(private readonly prisma: PrismaService) {}

  async create(dto: CreateEscrowDto) {
    const lot = await this.prisma.mineralLot.findUnique({
      where: { id: dto.lotId },
    });
    if (!lot) {
      throw new NotFoundException(`Mineral lot ${dto.lotId} not found`);
    }

    const count = await this.prisma.escrow.count();
    const code = `ESC-${String(count + 1).padStart(4, '0')}`;
    const currency = dto.currency ?? 'USD';

    return this.prisma.$transaction(async (tx) => {
      const escrow = await tx.escrow.create({
        data: {
          code,
          lotId: dto.lotId,
          offerId: dto.offerId,
          buyerName: dto.buyerName,
          buyerWallet: dto.buyerWallet,
          amount: dto.amount,
          currency,
          txHash: dto.txHash,
          status: EscrowStatus.LOCKED,
        },
        include: {
          lot: { select: { id: true, lotCode: true, mineralType: true } },
        },
      });

      await tx.lotEvent.create({
        data: {
          lotId: dto.lotId,
          eventType: 'ESCROW_LOCKED',
          actorWallet:
            dto.buyerWallet ?? '0x0000000000000000000000000000000000000000',
          actorName: dto.buyerName,
          actorRole: 'Buyer',
          txHash: dto.txHash,
          detail: `${currency} ${dto.amount.toLocaleString()} locked in escrow ${code}`,
          dataHash: sha256Hex(
            JSON.stringify({ code, lotId: dto.lotId, amount: dto.amount }),
          ),
        },
      });

      return escrow;
    });
  }

  async findAll(filters?: { lotId?: string; status?: EscrowStatus }) {
    return this.prisma.escrow.findMany({
      where: {
        lotId: filters?.lotId,
        status: filters?.status,
      },
      include: {
        lot: { select: { id: true, lotCode: true, mineralType: true } },
        offer: { select: { id: true, code: true } },
      },
      orderBy: { lockedAt: 'desc' },
    });
  }

  async findOne(id: string) {
    const escrow = await this.prisma.escrow.findUnique({
      where: { id },
      include: {
        lot: { select: { id: true, lotCode: true, mineralType: true } },
        offer: true,
      },
    });
    if (!escrow) {
      throw new NotFoundException(`Escrow ${id} not found`);
    }
    return escrow;
  }

  async release(id: string, dto: ReleaseEscrowDto) {
    const escrow = await this.findOne(id);
    if (escrow.status !== EscrowStatus.LOCKED) {
      throw new BadRequestException(
        `Escrow ${escrow.code} cannot be released (current: ${escrow.status})`,
      );
    }

    const lienNote =
      dto.lienRepaid && dto.lienRepaid > 0
        ? ` · lien repaid first (${escrow.currency} ${dto.lienRepaid.toLocaleString()})`
        : '';

    return this.prisma.$transaction(async (tx) => {
      const updated = await tx.escrow.update({
        where: { id },
        data: {
          status: EscrowStatus.RELEASED,
          lienRepaid: dto.lienRepaid,
          txHash: dto.txHash ?? escrow.txHash,
          releasedAt: new Date(),
        },
      });

      await tx.lotEvent.create({
        data: {
          lotId: escrow.lotId,
          eventType: 'ESCROW_RELEASED',
          actorWallet:
            escrow.buyerWallet ?? '0x0000000000000000000000000000000000000000',
          actorName: 'Escrow settlement',
          actorRole: 'System',
          txHash: dto.txHash,
          detail: `${escrow.currency} ${escrow.amount.toLocaleString()} released from ${escrow.code}${lienNote}`,
          dataHash: sha256Hex(
            JSON.stringify({
              escrowCode: escrow.code,
              action: 'RELEASED',
              lienRepaid: dto.lienRepaid ?? 0,
            }),
          ),
        },
      });

      return updated;
    });
  }

  async refund(id: string, dto: RefundEscrowDto) {
    const escrow = await this.findOne(id);
    if (escrow.status !== EscrowStatus.LOCKED) {
      throw new BadRequestException(
        `Escrow ${escrow.code} cannot be refunded (current: ${escrow.status})`,
      );
    }

    return this.prisma.$transaction(async (tx) => {
      const updated = await tx.escrow.update({
        where: { id },
        data: {
          status: EscrowStatus.REFUNDED,
          txHash: dto.txHash ?? escrow.txHash,
          releasedAt: new Date(),
        },
      });

      await tx.lotEvent.create({
        data: {
          lotId: escrow.lotId,
          eventType: 'ESCROW_REFUNDED',
          actorWallet:
            escrow.buyerWallet ?? '0x0000000000000000000000000000000000000000',
          actorName: 'Escrow settlement',
          actorRole: 'System',
          txHash: dto.txHash,
          detail: `${escrow.currency} ${escrow.amount.toLocaleString()} refunded from ${escrow.code} · ${dto.reason}`,
          dataHash: sha256Hex(
            JSON.stringify({
              escrowCode: escrow.code,
              action: 'REFUNDED',
              reason: dto.reason,
            }),
          ),
        },
      });

      return updated;
    });
  }
}
