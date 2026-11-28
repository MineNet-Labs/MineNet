import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { IsOptional, IsString } from 'class-validator';

export class CreateNotificationDto {
  @ApiPropertyOptional({
    example: 'miner',
    description: 'Target audience, e.g. "miner" or "insurer:isange"',
    default: 'miner',
  })
  @IsOptional()
  @IsString()
  audience?: string;

  @ApiProperty({
    example: 'inspection',
    description: 'inspection | licence | offer | custody | payment | finance | alert',
  })
  @IsString()
  kind: string;

  @ApiProperty({ example: 'Inspection INS-2026-0001 has been completed' })
  @IsString()
  text: string;

  @ApiPropertyOptional({ example: '/miner/inspections/INS-2026-0001' })
  @IsOptional()
  @IsString()
  href?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  organizationId?: string;
}
