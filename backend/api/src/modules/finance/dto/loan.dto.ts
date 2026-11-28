import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import {
  IsIn,
  IsInt,
  IsNumber,
  IsOptional,
  IsPositive,
  IsString,
  Max,
  Min,
} from 'class-validator';

export class RequestLoanDto {
  @ApiProperty({ description: 'MineralLot ID pledged as collateral' })
  @IsString()
  lotId: string;

  @ApiProperty({ example: 'umurenge' })
  @IsString()
  financierCode: string;

  @ApiProperty({ example: 'Umurenge Trade Finance' })
  @IsString()
  financierName: string;

  @ApiProperty({ example: 12000 })
  @IsNumber()
  @IsPositive()
  amount: number;

  @ApiPropertyOptional({ enum: ['USD', 'RWF'], default: 'USD' })
  @IsOptional()
  @IsIn(['USD', 'RWF'])
  currency?: 'USD' | 'RWF';

  @ApiProperty({ example: 11, description: 'Annual interest rate percentage' })
  @IsNumber()
  @Min(0)
  @Max(100)
  ratePct: number;

  @ApiProperty({ example: 90, description: 'Loan duration in days' })
  @IsInt()
  @IsPositive()
  termDays: number;

  @ApiProperty({ example: 'Working capital for processing and transport' })
  @IsString()
  purpose: string;
}
