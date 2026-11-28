import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import {
  IsBoolean,
  IsNumber,
  IsOptional,
  IsString,
  Max,
  Min,
  MinLength,
} from 'class-validator';

export class CreateInspectionDto {
  @ApiProperty({ description: 'MineralLot ID to inspect' })
  @IsString()
  lotId: string;

  @ApiProperty({ example: 'Pre-export certification' })
  @IsString()
  @MinLength(2)
  type: string;

  @ApiPropertyOptional({ example: 'North Tunnel A' })
  @IsOptional()
  @IsString()
  shaft?: string;

  @ApiPropertyOptional({ example: 'Jean Uwimana' })
  @IsOptional()
  @IsString()
  requestedByName?: string;
}

export class AssignInspectorDto {
  @ApiProperty({ example: 'Eric Nshimiyimana' })
  @IsString()
  inspectorName: string;

  @ApiPropertyOptional({
    example: '0x2B9e000000000000000000000000000000000102',
  })
  @IsOptional()
  @IsString()
  inspectorWallet?: string;
}

export class SubmitInspectionResultDto {
  @ApiProperty({ example: true, description: 'True if lot passed inspection' })
  @IsBoolean()
  passed: boolean;

  @ApiProperty({ example: 68.4, description: 'Measured grade percentage (0-100)' })
  @IsNumber()
  @Min(0)
  @Max(100)
  measuredGradePct: number;

  @ApiProperty({ example: 'SMP-2026-0412' })
  @IsString()
  sampleId: string;

  @ApiProperty({ example: 'XRF Spectrometry' })
  @IsString()
  method: string;

  @ApiProperty({
    example: 'Grade 68.4% Sn confirmed; conflict-free origin verified',
  })
  @IsString()
  findings: string;

  @ApiPropertyOptional({ example: 'Eric Nshimiyimana' })
  @IsOptional()
  @IsString()
  inspectorName?: string;

  @ApiPropertyOptional({
    example: '0x2B9e000000000000000000000000000000000102',
  })
  @IsOptional()
  @IsString()
  inspectorWallet?: string;
}
