import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import {
  IsBoolean,
  IsDateString,
  IsIn,
  IsNumber,
  IsOptional,
  IsPositive,
  IsString,
  MinLength,
} from 'class-validator';

export class CreateListingDto {
  @ApiProperty({ description: 'Verified (INSPECTED) MineralLot ID' })
  @IsString()
  lotId: string;

  @ApiProperty({ example: 14.5 })
  @IsNumber()
  @IsPositive()
  pricePerKg: number;

  @ApiPropertyOptional({
    example: 900,
    description: 'Defaults to full lot quantityKg if omitted',
  })
  @IsOptional()
  @IsNumber()
  @IsPositive()
  quantityKg?: number;

  @ApiPropertyOptional({ enum: ['USD', 'RWF'], default: 'USD' })
  @IsOptional()
  @IsIn(['USD', 'RWF'])
  currency?: 'USD' | 'RWF';

  @ApiPropertyOptional({ example: 'FOB Kigali, conflict-free ICGLR certified' })
  @IsOptional()
  @IsString()
  notes?: string;
}

export class CreateBuyerRequestDto {
  @ApiProperty({ example: 'Great Lakes Minerals Co.' })
  @IsString()
  @MinLength(2)
  buyerName: string;

  @ApiPropertyOptional({
    example: '0x9999000000000000000000000000000000000201',
  })
  @IsOptional()
  @IsString()
  buyerWallet?: string;

  @ApiPropertyOptional({ default: true })
  @IsOptional()
  @IsBoolean()
  verified?: boolean;

  @ApiProperty({ example: 'Coltan' })
  @IsString()
  mineralType: string;

  @ApiProperty({ example: 2500 })
  @IsNumber()
  @IsPositive()
  requiredKg: number;

  @ApiProperty({ example: '30%+ Ta2O5' })
  @IsString()
  targetGrade: string;

  @ApiProperty({ example: 42.5 })
  @IsNumber()
  @IsPositive()
  pricePerKg: number;

  @ApiPropertyOptional({ enum: ['USD', 'RWF'], default: 'USD' })
  @IsOptional()
  @IsIn(['USD', 'RWF'])
  currency?: 'USD' | 'RWF';

  @ApiProperty({ example: 'Kigali' })
  @IsString()
  city: string;

  @ApiProperty({ example: 'Rwanda' })
  @IsString()
  country: string;

  @ApiProperty({ example: '2026-12-31T00:00:00.000Z' })
  @IsDateString()
  deadline: string;
}

export class CreateOfferDto {
  @ApiProperty({ description: 'MineralLot ID' })
  @IsString()
  lotId: string;

  @ApiPropertyOptional({ description: 'Optional Listing ID' })
  @IsOptional()
  @IsString()
  listingId?: string;

  @ApiPropertyOptional({ description: 'Optional BuyerRequest ID' })
  @IsOptional()
  @IsString()
  buyerRequestId?: string;

  @ApiProperty({ example: 'Rwanda Minerals Export SA' })
  @IsString()
  buyerName: string;

  @ApiPropertyOptional({
    example: '0x8888000000000000000000000000000000000301',
  })
  @IsOptional()
  @IsString()
  buyerWallet?: string;

  @ApiProperty({ example: 14.5 })
  @IsNumber()
  @IsPositive()
  pricePerKg: number;

  @ApiProperty({ example: 900 })
  @IsNumber()
  @IsPositive()
  quantityKg: number;

  @ApiPropertyOptional({ enum: ['USD', 'RWF'], default: 'USD' })
  @IsOptional()
  @IsIn(['USD', 'RWF'])
  currency?: 'USD' | 'RWF';

  @ApiPropertyOptional({ example: 'Ready for immediate escrow lock' })
  @IsOptional()
  @IsString()
  note?: string;
}

export class CounterOfferDto {
  @ApiProperty({ enum: ['SELLER', 'BUYER'], example: 'SELLER' })
  @IsIn(['SELLER', 'BUYER'])
  senderSide: 'SELLER' | 'BUYER';

  @ApiProperty({ example: 15.0 })
  @IsNumber()
  @IsPositive()
  pricePerKg: number;

  @ApiProperty({ example: 900 })
  @IsNumber()
  @IsPositive()
  quantityKg: number;

  @ApiPropertyOptional({ example: 'Can do $15.00/kg including Kigali delivery' })
  @IsOptional()
  @IsString()
  note?: string;
}
