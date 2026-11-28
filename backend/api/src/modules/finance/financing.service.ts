import { createHash } from 'node:crypto';
import {
  BadRequestException,
  ConflictException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { LoanStatus } from '@prisma/client';
import { PrismaService } from '../../prisma/prisma.service.js';
import { RequestLoanDto } from './dto/loan.dto.js';

function sha256Hex(payload: string): string {
  return `0x${createHash('sha256').update(payload).digest('hex')}`;
}

@Injectable()
export class FinancingService {
  constructor(private readonly prisma: PrismaService) {}

  async requestLoan(dto: RequestLoanDto) {
    const lot = await this.prisma.mineralLot.findUnique({
      where: { id: dto.lotId },
    });
    if (!lot) {
      throw new NotFoundException(`Mineral lot ${dto.lotId} not found`);
    }

    const activeLien = await this.prisma.loan.findFirst({
      where: { lotId: dto.lotId, status: LoanStatus.ACTIVE },
    });
    if (activeLien) {
      throw new ConflictException(
        `Lot ${lot.lotCode} already has an active lien (${activeLien.code})`,
      );
    }

    const count = await this.prisma.loan.count();
    const code = `LN-${String(count + 1).padStart(4, '0')}`;

    return this.prisma.loan.create({
      data: {
        code,
        lotId: dto.lotId,
        financierCode: dto.financierCode,
        financierName: dto.financierName,
        amount: dto.amount,
        currency: dto.currency ?? 'USD',
        ratePct: dto.ratePct,
        termDays: dto.termDays,
        purpose: dto.purpose,
        status: LoanStatus.REQUESTED,
      },
      include: {
        lot: { select: { id: true, lotCode: true, mineralType: true } },
      },
    });
  }

  async findAll(filters?: { lotId?: string; status?: LoanStatus }) {
    return this.prisma.loan.findMany({
      where: {
        lotId: filters?.lotId,
        status: filters?.status,
      },
      include: {
        lot: { select: { id: true, lotCode: true, mineralType: true } },
      },
      orderBy: { requestedAt: 'desc' },
    });
  }

  async findOne(id: string) {
    const loan = await this.prisma.loan.findUnique({
      where: { id },
      include: {
        lot: { select: { id: true, lotCode: true, mineralType: true } },
      },
    });
    if (!loan) {
      throw new NotFoundException(`Loan ${id} not found`);
    }
    return loan;
  }

  async approve(id: string) {
    const loan = await this.findOne(id);
    if (loan.status !== LoanStatus.REQUESTED) {
      throw new BadRequestException(
        `Loan ${loan.code} cannot be approved (current: ${loan.status})`,
      );
    }

    const activeLien = await this.prisma.loan.findFirst({
      where: { lotId: loan.lotId, status: LoanStatus.ACTIVE },
    });
    if (activeLien) {
      throw new ConflictException(
        `Lot already has an active lien (${activeLien.code}); double-pledging blocked`,
      );
    }

    const dueAt = new Date(Date.now() + loan.termDays * 86_400_000);

    return this.prisma.$transaction(async (tx) => {
      const updated = await tx.loan.update({
        where: { id },
        data: { status: LoanStatus.ACTIVE, dueAt },
      });

      await tx.lotEvent.create({
        data: {
          lotId: loan.lotId,
          eventType: 'FINANCED',
          actorWallet: '0x0000000000000000000000000000000000000601',
          actorName: loan.financierName,
          actorRole: 'Financier',
          detail: `Loan ${loan.code} · ${loan.currency} ${loan.amount.toLocaleString()} · lien recorded`,
          dataHash: sha256Hex(
            JSON.stringify({
              loanCode: loan.code,
              lotId: loan.lotId,
              amount: loan.amount,
            }),
          ),
        },
      });

      return updated;
    });
  }

  async repay(id: string) {
    const loan = await this.findOne(id);
    if (loan.status !== LoanStatus.ACTIVE) {
      throw new BadRequestException(
        `Loan ${loan.code} is not ACTIVE (current: ${loan.status})`,
      );
    }

    return this.prisma.$transaction(async (tx) => {
      const updated = await tx.loan.update({
        where: { id },
        data: { status: LoanStatus.REPAID, repaidAt: new Date() },
      });

      await tx.lotEvent.create({
        data: {
          lotId: loan.lotId,
          eventType: 'LIEN_RELEASED',
          actorWallet: '0x0000000000000000000000000000000000000601',
          actorName: loan.financierName,
          actorRole: 'Financier',
          detail: `Loan ${loan.code} repaid · lien released`,
          dataHash: sha256Hex(
            JSON.stringify({ loanCode: loan.code, status: 'REPAID' }),
          ),
        },
      });

      return updated;
    });
  }

  async decline(id: string) {
    const loan = await this.findOne(id);
    if (loan.status !== LoanStatus.REQUESTED) {
      throw new BadRequestException(
        `Loan ${loan.code} cannot be declined (current: ${loan.status})`,
      );
    }
    return this.prisma.loan.update({
      where: { id },
      data: { status: LoanStatus.DECLINED },
    });
  }
}
