import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { IsOptional, IsString, MinLength } from 'class-validator';

export class UploadDocumentDto {
  @ApiProperty({
    example: 'Certificate',
    description: 'Document category (Licence, Certificate, AssayReport, Permit, Photo, Policy, Claim)',
  })
  @IsString()
  @MinLength(2)
  docType: string;

  @ApiProperty({ example: 'Jean Uwimana' })
  @IsString()
  @MinLength(2)
  uploadedBy: string;

  @ApiPropertyOptional({ description: 'Optional Organization ID' })
  @IsOptional()
  @IsString()
  organizationId?: string;

  @ApiPropertyOptional({
    description: 'Optional MineralLot ID (appends DOCUMENT_ADDED passport event)',
  })
  @IsOptional()
  @IsString()
  lotId?: string;
}

export class VerifyDocumentHashDto {
  @ApiPropertyOptional({
    description: 'SHA-256 hex hash to compare (with or without 0x prefix)',
  })
  @IsOptional()
  @IsString()
  sha256Hash?: string;

  @ApiPropertyOptional({
    description: 'keccak256 hex hash to compare (with 0x prefix)',
  })
  @IsOptional()
  @IsString()
  keccak256Hash?: string;
}
