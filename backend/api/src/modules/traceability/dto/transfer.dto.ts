import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { TransferKind } from '@prisma/client';
import { IsEnum, IsOptional, IsString, MinLength } from 'class-validator';

export class CreateTransferDto {
  @ApiProperty({ description: 'MineralLot ID' })
  @IsString()
  lotId: string;

  @ApiProperty({ enum: TransferKind, example: TransferKind.TRANSPORT })
  @IsEnum(TransferKind)
  kind: TransferKind;

  @ApiProperty({ example: 'Volcano Freight Ltd' })
  @IsString()
  @MinLength(2)
  partyName: string;

  @ApiPropertyOptional({
    example: '0x4444000000000000000000000000000000000401',
  })
  @IsOptional()
  @IsString()
  partyWallet?: string;

  @ApiProperty({ example: 'Gatumba Mine' })
  @IsString()
  fromLocation: string;

  @ApiProperty({ example: 'Kigali Bonded Warehouse' })
  @IsString()
  toLocation: string;

  @ApiProperty({ example: 'SL-48812' })
  @IsString()
  sealId: string;

  @ApiPropertyOptional({ example: 'RAD 412 K' })
  @IsOptional()
  @IsString()
  vehicle?: string;
}
