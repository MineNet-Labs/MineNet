import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { IsOptional, IsString, MinLength } from 'class-validator';

export class CreateLotEventDto {
  @ApiProperty({
    example: 'INSPECTED',
    description:
      'Event kind (e.g. REGISTERED, INSPECTED, HANDOVER, IN_TRANSIT, STORED, DELIVERED, LISTED, SOLD, DOCUMENT_ADDED, FLAG_RAISED, FROZEN, UNFROZEN)',
  })
  @IsString()
  @MinLength(2)
  eventType: string;

  @ApiProperty({
    example: '0x7A3f9c21B4e8D05a6C1d2E9f0B3a4C5d6E7f8091',
  })
  @IsString()
  actorWallet: string;

  @ApiPropertyOptional({ example: 'Eric Nshimiyimana' })
  @IsOptional()
  @IsString()
  actorName?: string;

  @ApiPropertyOptional({ example: 'Inspector' })
  @IsOptional()
  @IsString()
  actorRole?: string;

  @ApiPropertyOptional({
    example: '0x0000000000000000000000000000000000000000',
    description: 'Counterparty wallet (for custody handovers or sales)',
  })
  @IsOptional()
  @IsString()
  counterparty?: string;

  @ApiProperty({
    example: 'Grade 62.5% Ta attested · conflict-free verified',
  })
  @IsString()
  detail: string;

  @ApiPropertyOptional({
    description:
      'Optional SHA-256 / keccak256 evidence hash (auto-computed if omitted)',
  })
  @IsOptional()
  @IsString()
  dataHash?: string;

  @ApiPropertyOptional({
    description: 'Optional on-chain transaction hash once anchored on Base',
  })
  @IsOptional()
  @IsString()
  txHash?: string;

  @ApiPropertyOptional({
    description: 'Optional block number if anchored on-chain',
  })
  @IsOptional()
  @IsString()
  blockNumber?: string;
}
