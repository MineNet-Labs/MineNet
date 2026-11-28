import { ApiProperty, ApiPropertyOptional, PartialType } from '@nestjs/swagger';
import {
  ApprovalStatus,
  AttendanceStatus,
  IncidentSeverity,
  IncidentStatus,
  WorkerStatus,
} from '@prisma/client';
import {
  IsDateString,
  IsEnum,
  IsIn,
  IsNumber,
  IsOptional,
  IsPositive,
  IsString,
  Min,
  MinLength,
} from 'class-validator';

export class CreateWorkerDto {
  @ApiProperty({ example: 'Emmanuel Habimana' })
  @IsString()
  @MinLength(2)
  fullName: string;

  @ApiProperty({ example: 'Driller' })
  @IsString()
  category: string;

  @ApiPropertyOptional({ example: '+250 788 112 233' })
  @IsOptional()
  @IsString()
  phone?: string;

  @ApiPropertyOptional({ example: 'QR ready' })
  @IsOptional()
  @IsString()
  accessBadge?: string;

  @ApiProperty({ description: 'Organization ID' })
  @IsString()
  organizationId: string;

  @ApiProperty({ description: 'Assigned MineSite ID' })
  @IsString()
  siteId: string;
}

export class UpdateWorkerDto extends PartialType(CreateWorkerDto) {
  @ApiPropertyOptional({ enum: WorkerStatus })
  @IsOptional()
  @IsEnum(WorkerStatus)
  status?: WorkerStatus;
}

export class RecordAttendanceDto {
  @ApiProperty({ description: 'Worker ID' })
  @IsString()
  workerId: string;

  @ApiProperty({ example: '2026-11-28T00:00:00.000Z' })
  @IsDateString()
  date: string;

  @ApiPropertyOptional({
    enum: AttendanceStatus,
    default: AttendanceStatus.PRESENT,
  })
  @IsOptional()
  @IsEnum(AttendanceStatus)
  status?: AttendanceStatus;

  @ApiPropertyOptional({ example: 8, default: 8 })
  @IsOptional()
  @IsNumber()
  @Min(0)
  hoursWorked?: number;

  @ApiPropertyOptional({ example: 'Morning shift at North Tunnel A' })
  @IsOptional()
  @IsString()
  note?: string;
}

export class CreateLeaveRequestDto {
  @ApiProperty({ description: 'Worker ID' })
  @IsString()
  workerId: string;

  @ApiProperty({ example: 'Annual leave' })
  @IsString()
  leaveType: string;

  @ApiProperty({ example: '2026-12-05T00:00:00.000Z' })
  @IsDateString()
  startDate: string;

  @ApiProperty({ example: '2026-12-10T00:00:00.000Z' })
  @IsDateString()
  endDate: string;

  @ApiProperty({ example: 'Family visit' })
  @IsString()
  reason: string;
}

export class DecideApprovalDto {
  @ApiProperty({ enum: [ApprovalStatus.APPROVED, ApprovalStatus.REJECTED] })
  @IsIn([ApprovalStatus.APPROVED, ApprovalStatus.REJECTED])
  status: 'APPROVED' | 'REJECTED';

  @ApiPropertyOptional({ example: 'Jean Uwimana' })
  @IsOptional()
  @IsString()
  decidedBy?: string;
}

export class CreatePayrollDto {
  @ApiProperty({ description: 'Worker ID' })
  @IsString()
  workerId: string;

  @ApiProperty({ example: '2026-11' })
  @IsString()
  period: string;

  @ApiProperty({ example: 250000 })
  @IsNumber()
  @Min(0)
  basePay: number;

  @ApiPropertyOptional({ example: 25000, default: 0 })
  @IsOptional()
  @IsNumber()
  @Min(0)
  bonus?: number;

  @ApiPropertyOptional({ example: 10000, default: 0 })
  @IsOptional()
  @IsNumber()
  @Min(0)
  deductions?: number;

  @ApiPropertyOptional({ enum: ['RWF', 'USD'], default: 'RWF' })
  @IsOptional()
  @IsIn(['RWF', 'USD'])
  currency?: 'RWF' | 'USD';
}

export class CreateExtractionRecordDto {
  @ApiProperty({ description: 'MineSite ID' })
  @IsString()
  siteId: string;

  @ApiPropertyOptional({ description: 'Optional MineShaft ID' })
  @IsOptional()
  @IsString()
  shaftId?: string;

  @ApiProperty({ example: 'Coltan' })
  @IsString()
  mineralType: string;

  @ApiProperty({ example: 420 })
  @IsNumber()
  @IsPositive()
  quantityKg: number;

  @ApiPropertyOptional({ example: '2026-11-28T00:00:00.000Z' })
  @IsOptional()
  @IsDateString()
  extractedAt?: string;
}

export class CreateIncidentDto {
  @ApiProperty({ description: 'MineSite ID' })
  @IsString()
  siteId: string;

  @ApiPropertyOptional({
    enum: IncidentSeverity,
    default: IncidentSeverity.MEDIUM,
  })
  @IsOptional()
  @IsEnum(IncidentSeverity)
  severity?: IncidentSeverity;

  @ApiProperty({ example: 'Ventilation fan outage in West Adit B' })
  @IsString()
  @MinLength(3)
  title: string;

  @ApiProperty({ example: 'Backup generator engaged; shaft cleared safely.' })
  @IsString()
  description: string;

  @ApiProperty({ example: 'Claudine Mukamana' })
  @IsString()
  reportedBy: string;
}

export class UpdateIncidentStatusDto {
  @ApiProperty({ enum: IncidentStatus, example: IncidentStatus.RESOLVED })
  @IsEnum(IncidentStatus)
  status: IncidentStatus;
}
