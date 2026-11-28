import { Injectable, NotFoundException } from '@nestjs/common';
import { AgreementKind, AgreementStatus } from '@prisma/client';
import { PrismaService } from '../../prisma/prisma.service.js';
import { CreateAgreementDto } from './dto/agreement.dto.js';

@Injectable()
export class B2bService {
  constructor(private readonly prisma: PrismaService) {}

  async create(dto: CreateAgreementDto) {
    const count = await this.prisma.b2bAgreement.count();
    const code = `AGR-${String(count + 1).padStart(4, '0')}`;
    return this.prisma.b2bAgreement.create({
      data: {
        code,
        kind: dto.kind,
        organizationId: dto.organizationId,
        counterpartyName: dto.counterpartyName,
        mineralOrService: dto.mineralOrService,
        quantityKg: dto.quantityKg,
        unitPrice: dto.unitPrice,
        currency: dto.currency ?? 'USD',
        startDate: new Date(dto.startDate),
        endDate: new Date(dto.endDate),
        terms: dto.terms,
      },
      include: { organization: { select: { id: true, name: true } } },
    });
  }

  findAll(filters?: {
    organizationId?: string;
    kind?: AgreementKind;
    status?: AgreementStatus;
  }) {
    return this.prisma.b2bAgreement.findMany({
      where: {
        organizationId: filters?.organizationId,
        kind: filters?.kind,
        status: filters?.status,
      },
      include: { organization: { select: { id: true, name: true } } },
      orderBy: { createdAt: 'desc' },
    });
  }

  async findOne(id: string) {
    const agr = await this.prisma.b2bAgreement.findUnique({
      where: { id },
      include: { organization: { select: { id: true, name: true } } },
    });
    if (!agr) throw new NotFoundException(`B2B agreement ${id} not found`);
    return agr;
  }

  async updateStatus(id: string, status: AgreementStatus) {
    await this.findOne(id);
    return this.prisma.b2bAgreement.update({
      where: { id },
      data: { status },
    });
  }
}
