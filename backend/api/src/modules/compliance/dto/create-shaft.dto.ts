import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { ShaftStatus } from '@prisma/client';
import {
  IsDateString,
  IsEnum,
  IsNumber,
  IsOptional,
  IsString,
  Min,
  MinLength,
} from 'class-validator';

export class CreateShaftDto {
  @ApiProperty({ example: 'SHF-001' })
  @IsString()
  @MinLength(2)
  code: string;

  @ApiProperty({ example: 'North Tunnel A' })
  @IsString()
  @MinLength(2)
  name: string;

  @ApiProperty({ example: 85 })
  @IsNumber()
  @Min(0)
  depthM: number;

  @ApiProperty({ example: 'Coltan' })
  @IsString()
  mineral: string;

  @ApiPropertyOptional({
    enum: ShaftStatus,
    default: ShaftStatus.OPERATIONAL,
  })
  @IsOptional()
  @IsEnum(ShaftStatus)
  status?: ShaftStatus;

  @ApiPropertyOptional({ example: '2026-10-15T00:00:00.000Z' })
  @IsOptional()
  @IsDateString()
  lastInspection?: string;
}
