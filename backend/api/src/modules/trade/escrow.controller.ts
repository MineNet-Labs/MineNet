import {
  Body,
  Controller,
  Get,
  Param,
  Patch,
  Post,
  Query,
} from '@nestjs/common';
import { ApiOperation, ApiQuery, ApiTags } from '@nestjs/swagger';
import { EscrowStatus } from '@prisma/client';
import {
  CreateEscrowDto,
  RefundEscrowDto,
  ReleaseEscrowDto,
} from './dto/escrow.dto.js';
import { EscrowService } from './escrow.service.js';

@ApiTags('escrows')
@Controller('escrows')
export class EscrowController {
  constructor(private readonly escrowService: EscrowService) {}

  @Post()
  @ApiOperation({ summary: 'Record a new locked escrow payment' })
  create(@Body() dto: CreateEscrowDto) {
    return this.escrowService.create(dto);
  }

  @Get()
  @ApiOperation({ summary: 'List escrow payment records' })
  @ApiQuery({ name: 'lotId', required: false })
  @ApiQuery({ name: 'status', enum: EscrowStatus, required: false })
  findAll(
    @Query('lotId') lotId?: string,
    @Query('status') status?: EscrowStatus,
  ) {
    return this.escrowService.findAll({ lotId, status });
  }

  @Get(':id')
  @ApiOperation({ summary: 'Get escrow details' })
  findOne(@Param('id') id: string) {
    return this.escrowService.findOne(id);
  }

  @Patch(':id/release')
  @ApiOperation({
    summary: 'Release locked escrow to seller (appends ESCROW_RELEASED event)',
  })
  release(@Param('id') id: string, @Body() dto: ReleaseEscrowDto) {
    return this.escrowService.release(id, dto);
  }

  @Patch(':id/refund')
  @ApiOperation({
    summary: 'Refund locked escrow to buyer (appends ESCROW_REFUNDED event)',
  })
  refund(@Param('id') id: string, @Body() dto: RefundEscrowDto) {
    return this.escrowService.refund(id, dto);
  }
}
