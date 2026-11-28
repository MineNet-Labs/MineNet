import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { ReportStatus } from '@prisma/client';
import {
  IsEnum,
  IsInt,
  IsNumber,
  IsOptional,
  IsString,
  Max,
  Min,
  MinLength,
} from 'class-validator';

export class CreateSiteReportDto {
  @ApiProperty({ description: 'MineSite ID' })
  @IsString()
  siteId: string;

  @ApiProperty({ example: '2026-11' })
  @IsString()
  period: string;

  @ApiProperty({ example: 'Jean Uwimana' })
  @IsString()
  @MinLength(2)
  author: string;

  @ApiProperty({
    example: 'Monthly production on target; all shaft safety checks passed.',
  })
  @IsString()
  summary: string;

  @ApiPropertyOptional({ example: 2700, default: 0 })
  @IsOptional()
  @IsNumber()
  @Min(0)
  productionKg?: number;

  @ApiPropertyOptional({ example: 96, default: 100 })
  @IsOptional()
  @IsInt()
  @Min(0)
  @Max(100)
  safetyScore?: number;

  @ApiPropertyOptional({ example: 'EIA water runoff monitoring within limits.' })
  @IsOptional()
  @IsString()
  complianceNotes?: string;

  @ApiPropertyOptional({ enum: ReportStatus, default: ReportStatus.SUBMITTED })
  @IsOptional()
  @IsEnum(ReportStatus)
  status?: ReportStatus;
}

export class UpdateSiteReportStatusDto {
  @ApiProperty({ enum: ReportStatus, example: ReportStatus.REVIEWED })
  @IsEnum(ReportStatus)
  status: ReportStatus;
}
