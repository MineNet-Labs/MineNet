import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { LotStatus } from '@prisma/client';
import {
  IsBoolean,
  IsEnum,
  IsNumber,
  IsOptional,
  IsString,
  Max,
  Min,
} from 'class-validator';

export class UpdateLotDto {
  @ApiPropertyOptional({ example: 64.2 })
  @IsOptional()
  @IsNumber()
  @Min(0)
  @Max(100)
  gradePct?: number;

  @ApiPropertyOptional({ enum: LotStatus })
  @IsOptional()
  @IsEnum(LotStatus)
  status?: LotStatus;

  @ApiPropertyOptional({
    example: '0x7A3f9c21B4e8D05a6C1d2E9f0B3a4C5d6E7f8091',
  })
  @IsOptional()
  @IsString()
  ownerWallet?: string;

  @ApiPropertyOptional({
    example: '0x7A3f9c21B4e8D05a6C1d2E9f0B3a4C5d6E7f8091',
  })
  @IsOptional()
  @IsString()
  custodianWallet?: string;

  @ApiPropertyOptional({
    example: '117',
    description: 'On-chain ERC-721 tokenId once minted',
  })
  @IsOptional()
  @IsString()
  tokenId?: string;
}

export class ToggleLotFreezeDto {
  @ApiProperty({ example: true })
  @IsBoolean()
  frozen: boolean;

  @ApiProperty({ example: 'Weight discrepancy flagged during audit' })
  @IsString()
  reason: string;

  @ApiPropertyOptional({ example: 'RMB Officer M. Habineza' })
  @IsOptional()
  @IsString()
  actorName?: string;

  @ApiPropertyOptional({
    example: '0x0000000000000000000000000000000000000001',
  })
  @IsOptional()
  @IsString()
  actorWallet?: string;
}
