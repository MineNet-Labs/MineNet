import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { OrgStatus } from '@prisma/client';
import {
  IsDateString,
  IsEmail,
  IsEnum,
  IsOptional,
  IsString,
  MinLength,
} from 'class-validator';

export class CreateOrganizationDto {
  @ApiProperty({ example: 'Uwimana Mining Cooperative' })
  @IsString()
  @MinLength(2)
  name: string;

  @ApiProperty({ example: 'Mining cooperative' })
  @IsString()
  @MinLength(2)
  kind: string;

  @ApiPropertyOptional({ example: 'RDB-108452317' })
  @IsOptional()
  @IsString()
  rdbNumber?: string;

  @ApiPropertyOptional({ example: 'TIN 102 445 781' })
  @IsOptional()
  @IsString()
  tin?: string;

  @ApiPropertyOptional({
    example: 'Rwanda Mines, Petroleum and Gas Board (RMB)',
  })
  @IsOptional()
  @IsString()
  regulatorName?: string;

  @ApiPropertyOptional({ example: 'ML-2025-081' })
  @IsOptional()
  @IsString()
  licenceNumber?: string;

  @ApiPropertyOptional({ example: '2025-03-14T00:00:00.000Z' })
  @IsOptional()
  @IsDateString()
  licenceIssuedAt?: string;

  @ApiPropertyOptional({ example: '2027-03-14T00:00:00.000Z' })
  @IsOptional()
  @IsDateString()
  licenceExpiryAt?: string;

  @ApiPropertyOptional({ enum: OrgStatus, default: OrgStatus.PENDING })
  @IsOptional()
  @IsEnum(OrgStatus)
  status?: OrgStatus;

  @ApiPropertyOptional({
    example: '0x7A3f9c21B4e8D05a6C1d2E9f0B3a4C5d6E7f8091',
  })
  @IsOptional()
  @IsString()
  payoutWallet?: string;

  @ApiPropertyOptional({ example: 'Jean Uwimana' })
  @IsOptional()
  @IsString()
  contactName?: string;

  @ApiPropertyOptional({ example: 'jean@uwimana-coop.rw' })
  @IsOptional()
  @IsEmail()
  contactEmail?: string;

  @ApiPropertyOptional({ example: '+250 788 000 184' })
  @IsOptional()
  @IsString()
  contactPhone?: string;

  @ApiPropertyOptional({ example: 'KG 9 Ave, Gasabo, Kigali' })
  @IsOptional()
  @IsString()
  address?: string;
}
