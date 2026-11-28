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
import { AgreementKind, AgreementStatus } from '@prisma/client';
import {
  CreateAgreementDto,
  UpdateAgreementStatusDto,
} from './dto/agreement.dto.js';
import { B2bService } from './b2b.service.js';

@ApiTags('b2b-agreements')
@Controller('b2b/agreements')
export class B2bController {
  constructor(private readonly b2bService: B2bService) {}

  @Post()
  @ApiOperation({ summary: 'Create a B2B supply or service agreement' })
  create(@Body() dto: CreateAgreementDto) {
    return this.b2bService.create(dto);
  }

  @Get()
  @ApiOperation({ summary: 'List B2B agreements' })
  @ApiQuery({ name: 'organizationId', required: false })
  @ApiQuery({ name: 'kind', enum: AgreementKind, required: false })
  @ApiQuery({ name: 'status', enum: AgreementStatus, required: false })
  findAll(
    @Query('organizationId') organizationId?: string,
    @Query('kind') kind?: AgreementKind,
    @Query('status') status?: AgreementStatus,
  ) {
    return this.b2bService.findAll({ organizationId, kind, status });
  }

  @Get(':id')
  @ApiOperation({ summary: 'Get B2B agreement details' })
  findOne(@Param('id') id: string) {
    return this.b2bService.findOne(id);
  }

  @Patch(':id/status')
  @ApiOperation({ summary: 'Update B2B agreement status' })
  updateStatus(
    @Param('id') id: string,
    @Body() dto: UpdateAgreementStatusDto,
  ) {
    return this.b2bService.updateStatus(id, dto.status);
  }
}
