import { ApiProperty, ApiPropertyOptional, PartialType } from '@nestjs/swagger';
import { OrgStatus } from '@prisma/client';
import { IsEnum, IsOptional, IsString } from 'class-validator';
import { CreateOrganizationDto } from './create-organization.dto.js';

export class UpdateOrganizationDto extends PartialType(CreateOrganizationDto) {}

export class UpdateOrganizationStatusDto {
  @ApiProperty({ enum: OrgStatus, example: OrgStatus.VALIDATED })
  @IsEnum(OrgStatus)
  status: OrgStatus;
}

export class RequestLicenceRenewalDto {
  @ApiPropertyOptional({
    example: 'Updated EIA certificate and tax clearance attached for 2027-2029 renewal.',
  })
  @IsOptional()
  @IsString()
  note?: string;
}
