import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { CoverType } from '@prisma/client';
import {
  IsBoolean,
  IsDateString,
  IsEnum,
  IsIn,
  IsNumber,
  IsOptional,
  IsPositive,
  IsString,
} from 'class-validator';

export class RequestPolicyDto {
  @ApiProperty({ description: 'MineralLot ID to insure' })
  @IsString()
  lotId: string;

  @ApiProperty({ example: 'isange' })
  @IsString()
  insurerCode: string;

  @ApiProperty({ example: 'Isange Assurance' })
  @IsString()
  insurerName: string;

  @ApiProperty({ enum: CoverType, example: CoverType.STORAGE_AND_TRANSIT })
  @IsEnum(CoverType)
  coverType: CoverType;

  @ApiProperty({ example: 32760 })
  @IsNumber()
  @IsPositive()
  sumInsured: number;

  @ApiPropertyOptional({ enum: ['USD', 'RWF'], default: 'USD' })
  @IsOptional()
  @IsIn(['USD', 'RWF'])
  currency?: 'USD' | 'RWF';

  @ApiProperty({ example: '2026-12-01T00:00:00.000Z' })
  @IsDateString()
  validFrom: string;

  @ApiProperty({ example: '2027-03-01T00:00:00.000Z' })
  @IsDateString()
  validTo: string;
}

export class QuotePolicyDto {
  @ApiProperty({ example: 195 })
  @IsNumber()
  @IsPositive()
  premium: number;
}

export class FileClaimDto {
  @ApiProperty({ description: 'Active InsurancePolicy ID' })
  @IsString()
  policyId: string;

  @ApiProperty({
    example: 'Water damage to 40 kg in bay C-14 after roof leak',
  })
  @IsString()
  reason: string;

  @ApiProperty({ example: 720 })
  @IsNumber()
  @IsPositive()
  amount: number;
}

export class DecideClaimDto {
  @ApiProperty({ example: true })
  @IsBoolean()
  approved: boolean;

  @ApiProperty({ example: 'Verified against warehouse intake & passport records' })
  @IsString()
  decisionNote: string;
}
