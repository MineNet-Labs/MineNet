import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import {
  IsIn,
  IsNumber,
  IsOptional,
  IsPositive,
  IsString,
  Min,
} from 'class-validator';

export class CreateEscrowDto {
  @ApiProperty({ description: 'MineralLot ID' })
  @IsString()
  lotId: string;

  @ApiPropertyOptional({ description: 'Optional accepted Offer ID' })
  @IsOptional()
  @IsString()
  offerId?: string;

  @ApiProperty({ example: 'Rwanda Minerals Export SA' })
  @IsString()
  buyerName: string;

  @ApiPropertyOptional({
    example: '0x8888000000000000000000000000000000000301',
  })
  @IsOptional()
  @IsString()
  buyerWallet?: string;

  @ApiProperty({ example: 13050 })
  @IsNumber()
  @IsPositive()
  amount: number;

  @ApiPropertyOptional({ enum: ['USD', 'RWF'], default: 'USD' })
  @IsOptional()
  @IsIn(['USD', 'RWF'])
  currency?: 'USD' | 'RWF';

  @ApiPropertyOptional({ description: 'Optional on-chain lock txHash' })
  @IsOptional()
  @IsString()
  txHash?: string;
}

export class ReleaseEscrowDto {
  @ApiPropertyOptional({
    example: 0,
    description: 'Amount deducted to repay active financier lien first',
  })
  @IsOptional()
  @IsNumber()
  @Min(0)
  lienRepaid?: number;

  @ApiPropertyOptional({ description: 'Optional on-chain release txHash' })
  @IsOptional()
  @IsString()
  txHash?: string;
}

export class RefundEscrowDto {
  @ApiProperty({ example: 'Delivery cancelled by mutual agreement' })
  @IsString()
  reason: string;

  @ApiPropertyOptional({ description: 'Optional on-chain refund txHash' })
  @IsOptional()
  @IsString()
  txHash?: string;
}
