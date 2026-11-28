import { Injectable, NotFoundException } from '@nestjs/common';
import {
  ApprovalStatus,
  IncidentStatus,
  PayrollStatus,
  WorkerStatus,
} from '@prisma/client';
import { PrismaService } from '../../prisma/prisma.service.js';
import {
  CreateExtractionRecordDto,
  CreateIncidentDto,
  CreateLeaveRequestDto,
  CreatePayrollDto,
  CreateWorkerDto,
  DecideApprovalDto,
  RecordAttendanceDto,
  UpdateIncidentStatusDto,
  UpdateWorkerDto,
} from './dto/workforce.dto.js';

@Injectable()
export class WorkforceService {
  constructor(private readonly prisma: PrismaService) {}

  /* -------------------------------------------------------------- Workers */

  async createWorker(dto: CreateWorkerDto) {
    const count = await this.prisma.worker.count();
    const code = `WRK-${String(count + 1).padStart(4, '0')}`;
    return this.prisma.worker.create({
      data: { ...dto, code },
      include: { site: { select: { id: true, code: true, name: true } } },
    });
  }

  async findAllWorkers(filters?: {
    organizationId?: string;
    siteId?: string;
    status?: WorkerStatus;
  }) {
    return this.prisma.worker.findMany({
      where: {
        organizationId: filters?.organizationId,
        siteId: filters?.siteId,
        status: filters?.status,
      },
      include: { site: { select: { id: true, code: true, name: true } } },
      orderBy: { fullName: 'asc' },
    });
  }

  async findOneWorker(id: string) {
    const worker = await this.prisma.worker.findUnique({
      where: { id },
      include: {
        site: { select: { id: true, code: true, name: true } },
        attendance: { orderBy: { date: 'desc' }, take: 30 },
        leaveRequests: { orderBy: { createdAt: 'desc' }, take: 10 },
        payrolls: { orderBy: { period: 'desc' }, take: 12 },
      },
    });
    if (!worker) throw new NotFoundException(`Worker ${id} not found`);
    return worker;
  }

  async updateWorker(id: string, dto: UpdateWorkerDto) {
    await this.findOneWorker(id);
    return this.prisma.worker.update({ where: { id }, data: dto });
  }

  async removeWorker(id: string) {
    await this.findOneWorker(id);
    return this.prisma.worker.delete({ where: { id } });
  }

  /* ----------------------------------------------------------- Attendance */

  async recordAttendance(dto: RecordAttendanceDto) {
    await this.findOneWorker(dto.workerId);
    return this.prisma.attendanceRecord.create({
      data: {
        workerId: dto.workerId,
        date: new Date(dto.date),
        status: dto.status,
        hoursWorked: dto.hoursWorked ?? 8,
        note: dto.note,
      },
    });
  }

  async listAttendance(workerId?: string) {
    return this.prisma.attendanceRecord.findMany({
      where: { workerId },
      include: { worker: { select: { id: true, code: true, fullName: true } } },
      orderBy: { date: 'desc' },
      take: 100,
    });
  }

  /* ------------------------------------------------------- Leave Requests */

  async createLeave(dto: CreateLeaveRequestDto) {
    await this.findOneWorker(dto.workerId);
    return this.prisma.leaveRequest.create({
      data: {
        workerId: dto.workerId,
        leaveType: dto.leaveType,
        startDate: new Date(dto.startDate),
        endDate: new Date(dto.endDate),
        reason: dto.reason,
      },
      include: { worker: { select: { id: true, code: true, fullName: true } } },
    });
  }

  async listLeave(status?: ApprovalStatus) {
    return this.prisma.leaveRequest.findMany({
      where: { status },
      include: { worker: { select: { id: true, code: true, fullName: true } } },
      orderBy: { createdAt: 'desc' },
    });
  }

  async decideLeave(id: string, dto: DecideApprovalDto) {
    const leave = await this.prisma.leaveRequest.findUnique({ where: { id } });
    if (!leave) throw new NotFoundException(`Leave request ${id} not found`);
    return this.prisma.leaveRequest.update({
      where: { id },
      data: {
        status: dto.status,
        decidedBy: dto.decidedBy,
        decidedAt: new Date(),
      },
    });
  }

  /* -------------------------------------------------------------- Payroll */

  async createPayroll(dto: CreatePayrollDto) {
    await this.findOneWorker(dto.workerId);
    const bonus = dto.bonus ?? 0;
    const deductions = dto.deductions ?? 0;
    const netPay = Math.max(0, dto.basePay + bonus - deductions);
    return this.prisma.payrollRecord.create({
      data: {
        workerId: dto.workerId,
        period: dto.period,
        basePay: dto.basePay,
        bonus,
        deductions,
        netPay,
        currency: dto.currency ?? 'RWF',
      },
      include: { worker: { select: { id: true, code: true, fullName: true } } },
    });
  }

  async listPayroll(period?: string, status?: PayrollStatus) {
    return this.prisma.payrollRecord.findMany({
      where: { period, status },
      include: { worker: { select: { id: true, code: true, fullName: true } } },
      orderBy: { createdAt: 'desc' },
    });
  }

  async markPayrollPaid(id: string) {
    const rec = await this.prisma.payrollRecord.findUnique({ where: { id } });
    if (!rec) throw new NotFoundException(`Payroll record ${id} not found`);
    return this.prisma.payrollRecord.update({
      where: { id },
      data: { status: PayrollStatus.PAID, paidAt: new Date() },
    });
  }

  /* --------------------------------------------------- Extraction Records */

  async createExtraction(dto: CreateExtractionRecordDto) {
    const count = await this.prisma.extractionRecord.count();
    const code = `EXT-${String(count + 1).padStart(4, '0')}`;
    return this.prisma.extractionRecord.create({
      data: {
        code,
        siteId: dto.siteId,
        shaftId: dto.shaftId,
        mineralType: dto.mineralType,
        quantityKg: dto.quantityKg,
        extractedAt: dto.extractedAt ? new Date(dto.extractedAt) : new Date(),
      },
      include: { site: { select: { id: true, code: true, name: true } } },
    });
  }

  async listExtractions(siteId?: string, status?: ApprovalStatus) {
    return this.prisma.extractionRecord.findMany({
      where: { siteId, status },
      include: { site: { select: { id: true, code: true, name: true } } },
      orderBy: { extractedAt: 'desc' },
    });
  }

  async decideExtraction(id: string, dto: DecideApprovalDto) {
    const rec = await this.prisma.extractionRecord.findUnique({
      where: { id },
    });
    if (!rec) throw new NotFoundException(`Extraction record ${id} not found`);
    return this.prisma.extractionRecord.update({
      where: { id },
      data: { status: dto.status },
    });
  }

  /* ----------------------------------------------------- Safety Incidents */

  async createIncident(dto: CreateIncidentDto) {
    const count = await this.prisma.safetyIncident.count();
    const code = `INC-${String(count + 1).padStart(4, '0')}`;
    return this.prisma.safetyIncident.create({
      data: { ...dto, code },
      include: { site: { select: { id: true, code: true, name: true } } },
    });
  }

  async listIncidents(siteId?: string, status?: IncidentStatus) {
    return this.prisma.safetyIncident.findMany({
      where: { siteId, status },
      include: { site: { select: { id: true, code: true, name: true } } },
      orderBy: { createdAt: 'desc' },
    });
  }

  async updateIncidentStatus(id: string, dto: UpdateIncidentStatusDto) {
    const inc = await this.prisma.safetyIncident.findUnique({ where: { id } });
    if (!inc) throw new NotFoundException(`Safety incident ${id} not found`);
    return this.prisma.safetyIncident.update({
      where: { id },
      data: {
        status: dto.status,
        resolvedAt: dto.status === IncidentStatus.RESOLVED ? new Date() : null,
      },
    });
  }

  /* --------------------------------------------------- Unified Approvals */

  async listPendingApprovals() {
    const [pendingLeaves, pendingExtractions] = await Promise.all([
      this.prisma.leaveRequest.findMany({
        where: { status: ApprovalStatus.PENDING },
        include: { worker: { select: { id: true, code: true, fullName: true } } },
        orderBy: { createdAt: 'desc' },
      }),
      this.prisma.extractionRecord.findMany({
        where: { status: ApprovalStatus.PENDING },
        include: { site: { select: { id: true, code: true, name: true } } },
        orderBy: { createdAt: 'desc' },
      }),
    ]);

    return {
      totalPending: pendingLeaves.length + pendingExtractions.length,
      leaveRequests: pendingLeaves,
      extractionRecords: pendingExtractions,
    };
  }
}
