import { createHash } from 'node:crypto';
import {
  BadRequestException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { TransferKind, TransferStatus } from '@prisma/client';
import { PrismaService } from '../../prisma/prisma.service.js';
import { CreateTransferDto } from './dto/transfer.dto.js';

function sha256Hex(payload: string): string {
  return `0x${createHash('sha256').update(payload).digest('hex')}`;
}

@Injectable()
export class TransfersService {
  constructor(private readonly prisma: PrismaService) {}

  async create(dto: CreateTransferDto) {
    const lot = await this.prisma.mineralLot.findUnique({
      where: { id: dto.lotId },
    });
    if (!lot) {
      throw new NotFoundException(`Mineral lot ${dto.lotId} not found`);
    }
    if (lot.regulatorHold || lot.openFlags > 0) {
      throw new BadRequestException(
        `Lot ${lot.lotCode} is frozen or has open flags and cannot be transferred`,
      );
    }

    const count = await this.prisma.custodyTransfer.count();
    const code = `TRF-${String(count + 1).padStart(4, '0')}`;

    return this.prisma.custodyTransfer.create({
      data: {
        code,
        lotId: dto.lotId,
        kind: dto.kind,
        partyName: dto.partyName,
        partyWallet: dto.partyWallet,
        fromLocation: dto.fromLocation,
        toLocation: dto.toLocation,
        sealId: dto.sealId,
        vehicle: dto.vehicle,
        status: TransferStatus.AWAITING_HANDOVER,
        senderConfirmed: true,
        receiverConfirmed: false,
      },
      include: {
        lot: { select: { id: true, lotCode: true, mineralType: true } },
      },
    });
  }

  async findAll(filters?: { lotId?: string; status?: TransferStatus }) {
    return this.prisma.custodyTransfer.findMany({
      where: {
        lotId: filters?.lotId,
        status: filters?.status,
      },
      include: {
        lot: { select: { id: true, lotCode: true, mineralType: true } },
      },
      orderBy: { createdAt: 'desc' },
    });
  }

  async findOne(id: string) {
    const transfer = await this.prisma.custodyTransfer.findUnique({
      where: { id },
      include: {
        lot: { select: { id: true, lotCode: true, mineralType: true } },
      },
    });
    if (!transfer) {
      throw new NotFoundException(`Custody transfer ${id} not found`);
    }
    return transfer;
  }

  async confirmReceiver(id: string) {
    const transfer = await this.findOne(id);
    if (transfer.status !== TransferStatus.AWAITING_HANDOVER) {
      throw new BadRequestException(
        `Transfer ${transfer.code} is not awaiting handover (current: ${transfer.status})`,
      );
    }

    const nextStatus =
      transfer.kind === TransferKind.TRANSPORT
        ? TransferStatus.IN_TRANSIT
        : TransferStatus.STORED;
    const eventType =
      transfer.kind === TransferKind.TRANSPORT ? 'HANDOVER' : 'STORED';
    const role =
      transfer.kind === TransferKind.TRANSPORT ? 'Transporter' : 'Warehouse';

    return this.prisma.$transaction(async (tx) => {
      const updated = await tx.custodyTransfer.update({
        where: { id },
        data: {
          receiverConfirmed: true,
          status: nextStatus,
        },
      });

      if (transfer.partyWallet) {
        await tx.mineralLot.update({
          where: { id: transfer.lotId },
          data: { custodianWallet: transfer.partyWallet },
        });
      }

      await tx.lotEvent.create({
        data: {
          lotId: transfer.lotId,
          eventType,
          actorWallet:
            transfer.partyWallet ?? '0x0000000000000000000000000000000000000000',
          actorName: transfer.partyName,
          actorRole: role,
          detail:
            transfer.kind === TransferKind.TRANSPORT
              ? `Custody confirmed by ${transfer.partyName} · seal ${transfer.sealId} (${transfer.fromLocation} -> ${transfer.toLocation})`
              : `Stored at ${transfer.partyName} (${transfer.toLocation}) · seal ${transfer.sealId}`,
          dataHash: sha256Hex(
            JSON.stringify({
              transferCode: transfer.code,
              sealId: transfer.sealId,
              status: nextStatus,
            }),
          ),
        },
      });

      return updated;
    });
  }

  async complete(id: string) {
    const transfer = await this.findOne(id);
    if (
      transfer.status !== TransferStatus.IN_TRANSIT &&
      transfer.status !== TransferStatus.STORED
    ) {
      throw new BadRequestException(
        `Transfer ${transfer.code} must be IN_TRANSIT or STORED to complete (current: ${transfer.status})`,
      );
    }

    return this.prisma.$transaction(async (tx) => {
      const updated = await tx.custodyTransfer.update({
        where: { id },
        data: { status: TransferStatus.DELIVERED },
      });

      await tx.lotEvent.create({
        data: {
          lotId: transfer.lotId,
          eventType: 'DELIVERED',
          actorWallet:
            transfer.partyWallet ?? '0x0000000000000000000000000000000000000000',
          actorName: transfer.partyName,
          actorRole:
            transfer.kind === TransferKind.TRANSPORT ? 'Transporter' : 'Warehouse',
          detail: `Delivered to ${transfer.toLocation} · seal ${transfer.sealId} intact`,
          dataHash: sha256Hex(
            JSON.stringify({
              transferCode: transfer.code,
              status: 'DELIVERED',
            }),
          ),
        },
      });

      return updated;
    });
  }

  async cancel(id: string) {
    const transfer = await this.findOne(id);
    if (transfer.status === TransferStatus.DELIVERED) {
      throw new BadRequestException('Cannot cancel a delivered transfer');
    }
    return this.prisma.custodyTransfer.update({
      where: { id },
      data: { status: TransferStatus.CANCELLED },
    });
  }
}
