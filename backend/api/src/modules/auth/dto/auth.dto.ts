import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { ParticipantRole } from '@prisma/client';
import {
  IsArray,
  IsEmail,
  IsEnum,
  IsInt,
  IsOptional,
  IsPositive,
  IsString,
  MinLength,
} from 'class-validator';

export class RegisterUserDto {
  @ApiProperty({ example: 'jean@uwimana-coop.rw' })
  @IsEmail()
  email: string;

  @ApiProperty({ example: 'StrongPass123!' })
  @IsString()
  @MinLength(6)
  password: string;

  @ApiProperty({ example: 'Jean Uwimana' })
  @IsString()
  @MinLength(2)
  fullName: string;

  @ApiPropertyOptional({
    enum: ParticipantRole,
    isArray: true,
    default: [ParticipantRole.MINER],
  })
  @IsOptional()
  @IsArray()
  @IsEnum(ParticipantRole, { each: true })
  roles?: ParticipantRole[];

  @ApiPropertyOptional({
    example: '0x7A3f9c21B4e8D05a6C1d2E9f0B3a4C5d6E7f8091',
  })
  @IsOptional()
  @IsString()
  walletAddress?: string;

  @ApiPropertyOptional({ description: 'Organization ID' })
  @IsOptional()
  @IsString()
  organizationId?: string;
}

export class LoginDto {
  @ApiProperty({ example: 'jean@uwimana-coop.rw' })
  @IsEmail()
  email: string;

  @ApiProperty({ example: 'StrongPass123!' })
  @IsString()
  password: string;
}

export class WalletNonceDto {
  @ApiProperty({ example: '0x7A3f9c21B4e8D05a6C1d2E9f0B3a4C5d6E7f8091' })
  @IsString()
  walletAddress: string;
}

export class WalletVerifyDto {
  @ApiProperty({ example: '0x7A3f9c21B4e8D05a6C1d2E9f0B3a4C5d6E7f8091' })
  @IsString()
  walletAddress: string;

  @ApiProperty({ description: 'EIP-191 personal_sign signature hex' })
  @IsString()
  signature: string;
}

export class CreateInviteDto {
  @ApiProperty({ example: 'claudine@uwimana-coop.rw' })
  @IsEmail()
  email: string;

  @ApiPropertyOptional({ example: 'Claudine Mukamana' })
  @IsOptional()
  @IsString()
  fullName?: string;

  @ApiProperty({
    enum: ParticipantRole,
    isArray: true,
    example: [ParticipantRole.MINER],
  })
  @IsArray()
  @IsEnum(ParticipantRole, { each: true })
  roles: ParticipantRole[];

  @ApiProperty({ description: 'Organization ID' })
  @IsString()
  organizationId: string;

  @ApiPropertyOptional({ example: 7, default: 7 })
  @IsOptional()
  @IsInt()
  @IsPositive()
  expiresInDays?: number;
}

export class AcceptInviteDto {
  @ApiProperty({ example: 'Claudine Mukamana' })
  @IsString()
  @MinLength(2)
  fullName: string;

  @ApiProperty({ example: 'StrongPass123!' })
  @IsString()
  @MinLength(6)
  password: string;

  @ApiPropertyOptional({
    example: '0x3333000000000000000000000000000000000333',
  })
  @IsOptional()
  @IsString()
  walletAddress?: string;
}
