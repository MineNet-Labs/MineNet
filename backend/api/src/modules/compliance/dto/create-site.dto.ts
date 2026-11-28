import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { SiteStatus } from '@prisma/client';
import {
  IsArray,
  IsDateString,
  IsEnum,
  IsNumber,
  IsOptional,
  IsString,
  Min,
  MinLength,
} from 'class-validator';

export class CreateSiteDto {
  @ApiProperty({ example: 'SITE-001' })
  @IsString()
  @MinLength(2)
  code: string;

  @ApiProperty({ example: 'Gatumba Mine' })
  @IsString()
  @MinLength(2)
  name: string;

  @ApiProperty({ example: 'Ngororero' })
  @IsString()
  district: string;

  @ApiProperty({ example: 'Gatumba Sector, Western Province' })
  @IsString()
  location: string;

  @ApiProperty({ example: -1.918 })
  @IsNumber()
  lat: number;

  @ApiProperty({ example: 29.654 })
  @IsNumber()
  lng: number;

  @ApiPropertyOptional({ enum: SiteStatus, default: SiteStatus.ACTIVE })
  @IsOptional()
  @IsEnum(SiteStatus)
  status?: SiteStatus;

  @ApiProperty({ example: 145.5 })
  @IsNumber()
  @Min(0)
  areaHa: number;

  @ApiProperty({ example: ['Coltan', 'Cassiterite', 'Wolframite'] })
  @IsArray()
  @IsString({ each: true })
  minerals: string[];

  @ApiProperty({ example: 'ML-2025-081' })
  @IsString()
  licence: string;

  @ApiProperty({ example: '2027-03-14T00:00:00.000Z' })
  @IsDateString()
  licenceExpiry: string;

  @ApiProperty({ example: 'Jean Uwimana' })
  @IsString()
  manager: string;

  @ApiProperty({ description: 'Owning Organization ID' })
  @IsString()
  organizationId: string;
}
