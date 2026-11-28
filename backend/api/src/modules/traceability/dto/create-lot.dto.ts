import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import {
  IsNumber,
  IsOptional,
  IsPositive,
  IsString,
  Max,
  Min,
  MinLength,
} from 'class-validator';

export class CreateLotDto {
  @ApiPropertyOptional({
    example: 'LOT-00125',
    description: 'Unique lot code (auto-generated if omitted)',
  })
  @IsOptional()
  @IsString()
  @MinLength(3)
  lotCode?: string;

  @ApiProperty({ example: 'Coltan' })
  @IsString()
  @MinLength(2)
  mineralType: string;

  @ApiProperty({
    example: 900,
    description: 'Lot weight in kilograms (stored as grams internally)',
  })
  @IsNumber()
  @IsPositive()
  quantityKg: number;

  @ApiPropertyOptional({
    example: 62.5,
    description: 'Declared mineral grade percentage (0-100)',
  })
  @IsOptional()
  @IsNumber()
  @Min(0)
  @Max(100)
  gradePct?: number;

  @ApiProperty({ description: 'Owning Organization ID' })
  @IsString()
  organizationId: string;

  @ApiProperty({ description: 'Originating MineSite ID' })
  @IsString()
  siteId: string;

  @ApiPropertyOptional({ description: 'Optional MineShaft ID' })
  @IsOptional()
  @IsString()
  shaftId?: string;

  @ApiPropertyOptional({
    example: '0x7A3f9c21B4e8D05a6C1d2E9f0B3a4C5d6E7f8091',
    description: 'Defaults to organization payoutWallet if omitted',
  })
  @IsOptional()
  @IsString()
  ownerWallet?: string;

  @ApiPropertyOptional({ example: 'Jean Uwimana' })
  @IsOptional()
  @IsString()
  actorName?: string;
}
