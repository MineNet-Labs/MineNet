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
import { TransferStatus } from '@prisma/client';
import { CreateTransferDto } from './dto/transfer.dto.js';
import { TransfersService } from './transfers.service.js';

@ApiTags('custody-transfers')
@Controller('transfers')
export class TransfersController {
  constructor(private readonly transfersService: TransfersService) {}

  @Post()
  @ApiOperation({ summary: 'Initiate a transport or warehouse custody transfer' })
  create(@Body() dto: CreateTransferDto) {
    return this.transfersService.create(dto);
  }

  @Get()
  @ApiOperation({ summary: 'List custody transfers' })
  @ApiQuery({ name: 'lotId', required: false })
  @ApiQuery({ name: 'status', enum: TransferStatus, required: false })
  findAll(
    @Query('lotId') lotId?: string,
    @Query('status') status?: TransferStatus,
  ) {
    return this.transfersService.findAll({ lotId, status });
  }

  @Get(':id')
  @ApiOperation({ summary: 'Get custody transfer details' })
  findOne(@Param('id') id: string) {
    return this.transfersService.findOne(id);
  }

  @Patch(':id/confirm-receiver')
  @ApiOperation({
    summary:
      'Receiver confirms handover (moves to IN_TRANSIT or STORED, updates custodian & passport)',
  })
  confirmReceiver(@Param('id') id: string) {
    return this.transfersService.confirmReceiver(id);
  }

  @Patch(':id/complete')
  @ApiOperation({
    summary: 'Mark custody transfer DELIVERED and append passport event',
  })
  complete(@Param('id') id: string) {
    return this.transfersService.complete(id);
  }

  @Patch(':id/cancel')
  @ApiOperation({ summary: 'Cancel a custody transfer' })
  cancel(@Param('id') id: string) {
    return this.transfersService.cancel(id);
  }
}
