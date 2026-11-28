import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { AgreementKind, AgreementStatus } from '@prisma/client';
import {
  IsDateString,
  IsEnum,
  IsIn,
  IsNumber,
  IsOptional,
  IsPositive,
  IsString,
} from 'class-validator';

export class CreateAgreementDto {
  @ApiProperty({ enum: AgreementKind, example: AgreementKind.SUPPLY })
  @IsEnum(AgreementKind)
  kind: AgreementKind;

  @ApiProperty({ description: 'Organization ID' })
  @IsString()
  organizationId: string;

  @ApiProperty({ example: 'Kigali Tin Smelter Ltd' })
  @IsString()
  counterpartyName: string;

  @ApiProperty({ example: 'Cassiterite concentrate (monthly supply)' })
  @IsString()
  mineralOrService: string;

  @ApiPropertyOptional({ example: 5000 })
  @IsOptional()
  @IsNumber()
  @IsPositive()
  quantityKg?: number;

  @ApiProperty({ example: 18.0 })
  @IsNumber()
  @IsPositive()
  unitPrice: number;

  @ApiPropertyOptional({ enum: ['USD', 'RWF'], default: 'USD' })
  @IsOptional()
  @IsIn(['USD', 'RWF'])
  currency?: 'USD' | 'RWF';

  @ApiProperty({ example: '2026-12-01T00:00:00.000Z' })
  @IsDateString()
  startDate: string;

  @ApiProperty({ example: '2027-12-01T00:00:00.000Z' })
  @IsDateString()
  endDate: string;

  @ApiPropertyOptional({ example: 'Monthly delivery in sealed lots; escrow settlement within 5 days' })
  @IsOptional()
  @IsString()
  terms?: string;
}

export class UpdateAgreementStatusDto {
  @ApiProperty({ enum: AgreementStatus, example: AgreementStatus.ACTIVE })
  @IsEnum(AgreementStatus)
  status: AgreementStatus;
}
