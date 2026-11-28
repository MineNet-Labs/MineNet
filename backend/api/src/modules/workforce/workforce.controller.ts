import {
  Body,
  Controller,
  Delete,
  Get,
  Param,
  Patch,
  Post,
  Query,
} from '@nestjs/common';
import { ApiOperation, ApiQuery, ApiTags } from '@nestjs/swagger';
import {
  ApprovalStatus,
  IncidentStatus,
  PayrollStatus,
  WorkerStatus,
} from '@prisma/client';
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
import { WorkforceService } from './workforce.service.js';

@ApiTags('workforce-operations')
@Controller('workforce')
export class WorkforceController {
  constructor(private readonly workforceService: WorkforceService) {}

  /* -------------------------------------------------------------- Workers */

  @Post('workers')
  @ApiOperation({ summary: 'Register a worker at a mine site' })
  createWorker(@Body() dto: CreateWorkerDto) {
    return this.workforceService.createWorker(dto);
  }

  @Get('workers')
  @ApiOperation({ summary: 'List workers' })
  @ApiQuery({ name: 'organizationId', required: false })
  @ApiQuery({ name: 'siteId', required: false })
  @ApiQuery({ name: 'status', enum: WorkerStatus, required: false })
  findAllWorkers(
    @Query('organizationId') organizationId?: string,
    @Query('siteId') siteId?: string,
    @Query('status') status?: WorkerStatus,
  ) {
    return this.workforceService.findAllWorkers({
      organizationId,
      siteId,
      status,
    });
  }

  @Get('workers/:id')
  @ApiOperation({ summary: 'Get worker profile with attendance, leave & payroll' })
  findOneWorker(@Param('id') id: string) {
    return this.workforceService.findOneWorker(id);
  }

  @Patch('workers/:id')
  @ApiOperation({ summary: 'Update worker details' })
  updateWorker(@Param('id') id: string, @Body() dto: UpdateWorkerDto) {
    return this.workforceService.updateWorker(id, dto);
  }

  @Delete('workers/:id')
  @ApiOperation({ summary: 'Remove worker' })
  removeWorker(@Param('id') id: string) {
    return this.workforceService.removeWorker(id);
  }

  /* ----------------------------------------------------------- Attendance */

  @Post('attendance')
  @ApiOperation({ summary: 'Record daily worker attendance' })
  recordAttendance(@Body() dto: RecordAttendanceDto) {
    return this.workforceService.recordAttendance(dto);
  }

  @Get('attendance')
  @ApiOperation({ summary: 'List attendance records' })
  @ApiQuery({ name: 'workerId', required: false })
  listAttendance(@Query('workerId') workerId?: string) {
    return this.workforceService.listAttendance(workerId);
  }

  /* ------------------------------------------------------- Leave Requests */

  @Post('leave')
  @ApiOperation({ summary: 'Submit a leave request' })
  createLeave(@Body() dto: CreateLeaveRequestDto) {
    return this.workforceService.createLeave(dto);
  }

  @Get('leave')
  @ApiOperation({ summary: 'List leave requests' })
  @ApiQuery({ name: 'status', enum: ApprovalStatus, required: false })
  listLeave(@Query('status') status?: ApprovalStatus) {
    return this.workforceService.listLeave(status);
  }

  @Patch('leave/:id/decide')
  @ApiOperation({ summary: 'Approve or reject a leave request' })
  decideLeave(@Param('id') id: string, @Body() dto: DecideApprovalDto) {
    return this.workforceService.decideLeave(id, dto);
  }

  /* -------------------------------------------------------------- Payroll */

  @Post('payroll')
  @ApiOperation({ summary: 'Create a payroll entry for a worker' })
  createPayroll(@Body() dto: CreatePayrollDto) {
    return this.workforceService.createPayroll(dto);
  }

  @Get('payroll')
  @ApiOperation({ summary: 'List payroll records' })
  @ApiQuery({ name: 'period', required: false })
  @ApiQuery({ name: 'status', enum: PayrollStatus, required: false })
  listPayroll(
    @Query('period') period?: string,
    @Query('status') status?: PayrollStatus,
  ) {
    return this.workforceService.listPayroll(period, status);
  }

  @Patch('payroll/:id/pay')
  @ApiOperation({ summary: 'Mark a payroll record as PAID' })
  markPayrollPaid(@Param('id') id: string) {
    return this.workforceService.markPayrollPaid(id);
  }

  /* --------------------------------------------------- Extraction Records */

  @Post('extractions')
  @ApiOperation({ summary: 'Log a daily mineral extraction record' })
  createExtraction(@Body() dto: CreateExtractionRecordDto) {
    return this.workforceService.createExtraction(dto);
  }

  @Get('extractions')
  @ApiOperation({ summary: 'List extraction records' })
  @ApiQuery({ name: 'siteId', required: false })
  @ApiQuery({ name: 'status', enum: ApprovalStatus, required: false })
  listExtractions(
    @Query('siteId') siteId?: string,
    @Query('status') status?: ApprovalStatus,
  ) {
    return this.workforceService.listExtractions(siteId, status);
  }

  @Patch('extractions/:id/decide')
  @ApiOperation({ summary: 'Approve or reject an extraction record' })
  decideExtraction(@Param('id') id: string, @Body() dto: DecideApprovalDto) {
    return this.workforceService.decideExtraction(id, dto);
  }

  /* ----------------------------------------------------- Safety Incidents */

  @Post('incidents')
  @ApiOperation({ summary: 'Report a mine safety incident' })
  createIncident(@Body() dto: CreateIncidentDto) {
    return this.workforceService.createIncident(dto);
  }

  @Get('incidents')
  @ApiOperation({ summary: 'List safety incidents' })
  @ApiQuery({ name: 'siteId', required: false })
  @ApiQuery({ name: 'status', enum: IncidentStatus, required: false })
  listIncidents(
    @Query('siteId') siteId?: string,
    @Query('status') status?: IncidentStatus,
  ) {
    return this.workforceService.listIncidents(siteId, status);
  }

  @Patch('incidents/:id/status')
  @ApiOperation({ summary: 'Update safety incident status' })
  updateIncidentStatus(
    @Param('id') id: string,
    @Body() dto: UpdateIncidentStatusDto,
  ) {
    return this.workforceService.updateIncidentStatus(id, dto);
  }

  /* --------------------------------------------------- Unified Approvals */

  @Get('approvals')
  @ApiOperation({
    summary:
      'Get unified pending approvals queue (leave requests + extraction records)',
  })
  listPendingApprovals() {
    return this.workforceService.listPendingApprovals();
  }
}
