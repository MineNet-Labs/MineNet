import { Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service.js';
import { CreateNotificationDto } from './dto/notification.dto.js';

@Injectable()
export class NotificationsService {
  constructor(private readonly prisma: PrismaService) {}

  create(dto: CreateNotificationDto) {
    return this.prisma.notification.create({
      data: {
        audience: dto.audience ?? 'miner',
        kind: dto.kind,
        text: dto.text,
        href: dto.href,
        organizationId: dto.organizationId,
      },
    });
  }

  findAll(filters?: { audience?: string; unreadOnly?: boolean }) {
    return this.prisma.notification.findMany({
      where: {
        audience: filters?.audience,
        read: filters?.unreadOnly ? false : undefined,
      },
      orderBy: { createdAt: 'desc' },
      take: 100,
    });
  }

  async markRead(id: string) {
    const n = await this.prisma.notification.findUnique({ where: { id } });
    if (!n) throw new NotFoundException(`Notification ${id} not found`);
    return this.prisma.notification.update({
      where: { id },
      data: { read: true },
    });
  }

  async markAllRead(audience?: string) {
    const result = await this.prisma.notification.updateMany({
      where: { audience, read: false },
      data: { read: true },
    });
    return { updatedCount: result.count };
  }
}
