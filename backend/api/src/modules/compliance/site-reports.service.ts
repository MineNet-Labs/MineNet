import { Injectable, NotFoundException } from '@nestjs/common';
import { ReportStatus } from '@prisma/client';
import { PrismaService } from '../../prisma/prisma.service.js';
import { CreateSiteReportDto } from './dto/site-report.dto.js';

@Injectable()
export class SiteReportsService {
  constructor(private readonly prisma: PrismaService) {}

  async create(dto: CreateSiteReportDto) {
    const site = await this.prisma.mineSite.findUnique({
      where: { id: dto.siteId },
    });
    if (!site) {
      throw new NotFoundException(`Mine site ${dto.siteId} not found`);
    }

    const count = await this.prisma.siteReport.count();
    const code = `REP-${String(count + 1).padStart(4, '0')}`;

    return this.prisma.siteReport.create({
      data: {
        code,
        siteId: dto.siteId,
        period: dto.period,
        author: dto.author,
        summary: dto.summary,
        productionKg: dto.productionKg ?? 0,
        safetyScore: dto.safetyScore ?? 100,
        complianceNotes: dto.complianceNotes,
        status: dto.status ?? ReportStatus.SUBMITTED,
      },
      include: { site: { select: { id: true, code: true, name: true } } },
    });
  }

  findAll(filters?: { siteId?: string; period?: string; status?: ReportStatus }) {
    return this.prisma.siteReport.findMany({
      where: {
        siteId: filters?.siteId,
        period: filters?.period,
        status: filters?.status,
      },
      include: { site: { select: { id: true, code: true, name: true } } },
      orderBy: { createdAt: 'desc' },
    });
  }

  async findOne(id: string) {
    const report = await this.prisma.siteReport.findUnique({
      where: { id },
      include: { site: { select: { id: true, code: true, name: true } } },
    });
    if (!report) throw new NotFoundException(`Site report ${id} not found`);
    return report;
  }

  async updateStatus(id: string, status: ReportStatus) {
    await this.findOne(id);
    return this.prisma.siteReport.update({
      where: { id },
      data: { status },
    });
  }
}
