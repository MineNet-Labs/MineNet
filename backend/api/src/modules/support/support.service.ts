import { Injectable, NotFoundException } from '@nestjs/common';
import { TicketStatus } from '@prisma/client';
import { PrismaService } from '../../prisma/prisma.service.js';
import {
  CreateSupportTicketDto,
  UpdateSupportTicketDto,
} from './dto/support.dto.js';

@Injectable()
export class SupportService {
  constructor(private readonly prisma: PrismaService) {}

  async create(dto: CreateSupportTicketDto) {
    const count = await this.prisma.supportTicket.count();
    const code = `TKT-${String(count + 1).padStart(4, '0')}`;
    return this.prisma.supportTicket.create({
      data: {
        code,
        portal: dto.portal ?? 'miner',
        category: dto.category,
        subject: dto.subject,
        message: dto.message,
        submittedBy: dto.submittedBy,
        organizationId: dto.organizationId,
      },
    });
  }

  findAll(filters?: { portal?: string; status?: TicketStatus }) {
    return this.prisma.supportTicket.findMany({
      where: {
        portal: filters?.portal,
        status: filters?.status,
      },
      orderBy: { createdAt: 'desc' },
    });
  }

  async updateStatus(id: string, dto: UpdateSupportTicketDto) {
    const ticket = await this.prisma.supportTicket.findUnique({
      where: { id },
    });
    if (!ticket) throw new NotFoundException(`Support ticket ${id} not found`);
    return this.prisma.supportTicket.update({
      where: { id },
      data: {
        status: dto.status,
        resolutionNote: dto.resolutionNote,
        resolvedAt: dto.status === TicketStatus.RESOLVED ? new Date() : null,
      },
    });
  }
}
