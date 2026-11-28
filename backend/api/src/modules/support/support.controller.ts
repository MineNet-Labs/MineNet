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
import { TicketStatus } from '@prisma/client';
import {
  CreateSupportTicketDto,
  UpdateSupportTicketDto,
} from './dto/support.dto.js';
import { SupportService } from './support.service.js';

@ApiTags('support')
@Controller('support/tickets')
export class SupportController {
  constructor(private readonly supportService: SupportService) {}

  @Post()
  @ApiOperation({ summary: 'Submit a support ticket' })
  create(@Body() dto: CreateSupportTicketDto) {
    return this.supportService.create(dto);
  }

  @Get()
  @ApiOperation({ summary: 'List support tickets' })
  @ApiQuery({ name: 'portal', required: false, example: 'miner' })
  @ApiQuery({ name: 'status', enum: TicketStatus, required: false })
  findAll(
    @Query('portal') portal?: string,
    @Query('status') status?: TicketStatus,
  ) {
    return this.supportService.findAll({ portal, status });
  }

  @Patch(':id')
  @ApiOperation({ summary: 'Update support ticket status / resolution note' })
  updateStatus(@Param('id') id: string, @Body() dto: UpdateSupportTicketDto) {
    return this.supportService.updateStatus(id, dto);
  }
}
