import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { TicketStatus } from '@prisma/client';
import { IsEnum, IsIn, IsOptional, IsString, MinLength } from 'class-validator';

export class CreateSupportTicketDto {
  @ApiPropertyOptional({ enum: ['miner', 'insurer'], default: 'miner' })
  @IsOptional()
  @IsIn(['miner', 'insurer'])
  portal?: 'miner' | 'insurer';

  @ApiProperty({ example: 'Licence & Compliance' })
  @IsString()
  category: string;

  @ApiProperty({ example: 'Need help uploading updated EIA certificate' })
  @IsString()
  @MinLength(3)
  subject: string;

  @ApiProperty({ example: 'PDF upload timed out on mobile network.' })
  @IsString()
  message: string;

  @ApiProperty({ example: 'Jean Uwimana' })
  @IsString()
  submittedBy: string;

  @ApiPropertyOptional({ description: 'Optional Organization ID' })
  @IsOptional()
  @IsString()
  organizationId?: string;
}

export class UpdateSupportTicketDto {
  @ApiProperty({ enum: TicketStatus, example: TicketStatus.RESOLVED })
  @IsEnum(TicketStatus)
  status: TicketStatus;

  @ApiPropertyOptional({ example: 'Resolved after re-uploading compressed PDF.' })
  @IsOptional()
  @IsString()
  resolutionNote?: string;
}
