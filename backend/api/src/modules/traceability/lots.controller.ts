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
import { LotStatus } from '@prisma/client';
import { CreateLotEventDto } from './dto/create-lot-event.dto.js';
import { CreateLotDto } from './dto/create-lot.dto.js';
import { ToggleLotFreezeDto, UpdateLotDto } from './dto/update-lot.dto.js';
import { LotsService } from './lots.service.js';

@ApiTags('mineral-lots')
@Controller('lots')
export class LotsController {
  constructor(private readonly lotsService: LotsService) {}

  @Post()
  @ApiOperation({
    summary:
      'Register a new mineral lot (licence-gated; creates initial REGISTERED passport event)',
  })
  create(@Body() dto: CreateLotDto) {
    return this.lotsService.create(dto);
  }

  @Get()
  @ApiOperation({ summary: 'List mineral lots' })
  @ApiQuery({ name: 'organizationId', required: false })
  @ApiQuery({ name: 'siteId', required: false })
  @ApiQuery({ name: 'status', enum: LotStatus, required: false })
  @ApiQuery({ name: 'mineralType', required: false })
  findAll(
    @Query('organizationId') organizationId?: string,
    @Query('siteId') siteId?: string,
    @Query('status') status?: LotStatus,
    @Query('mineralType') mineralType?: string,
  ) {
    return this.lotsService.findAll({
      organizationId,
      siteId,
      status,
      mineralType,
    });
  }

  @Get(':id')
  @ApiOperation({
    summary: 'Get mineral lot details with full passport timeline & documents',
  })
  findOne(@Param('id') id: string) {
    return this.lotsService.findOne(id);
  }

  @Patch(':id')
  @ApiOperation({ summary: 'Update lot metadata (grade, status, wallets, tokenId)' })
  update(@Param('id') id: string, @Body() dto: UpdateLotDto) {
    return this.lotsService.update(id, dto);
  }

  @Get(':id/events')
  @ApiOperation({ summary: 'Get append-only passport event timeline for a lot' })
  getEvents(@Param('id') id: string) {
    return this.lotsService.getPassportEvents(id);
  }

  @Post(':id/events')
  @ApiOperation({ summary: 'Append a signed event to a lot passport' })
  appendEvent(@Param('id') id: string, @Body() dto: CreateLotEventDto) {
    return this.lotsService.appendEvent(id, dto);
  }

  @Patch(':id/freeze')
  @ApiOperation({
    summary: 'Freeze or unfreeze a lot (regulator hold + passport event)',
  })
  toggleFreeze(@Param('id') id: string, @Body() dto: ToggleLotFreezeDto) {
    return this.lotsService.toggleFreeze(id, dto);
  }
}
