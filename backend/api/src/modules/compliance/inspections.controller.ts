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
import { InspectionStatus } from '@prisma/client';
import {
  AssignInspectorDto,
  CreateInspectionDto,
  SubmitInspectionResultDto,
} from './dto/inspection.dto.js';
import { InspectionsService } from './inspections.service.js';

@ApiTags('inspections')
@Controller('inspections')
export class InspectionsController {
  constructor(private readonly inspectionsService: InspectionsService) {}

  @Post()
  @ApiOperation({
    summary: 'Request an inspection for a mineral lot (appends passport event)',
  })
  create(@Body() dto: CreateInspectionDto) {
    return this.inspectionsService.create(dto);
  }

  @Get()
  @ApiOperation({ summary: 'List inspections' })
  @ApiQuery({ name: 'lotId', required: false })
  @ApiQuery({ name: 'status', enum: InspectionStatus, required: false })
  findAll(
    @Query('lotId') lotId?: string,
    @Query('status') status?: InspectionStatus,
  ) {
    return this.inspectionsService.findAll({ lotId, status });
  }

  @Get(':id')
  @ApiOperation({ summary: 'Get inspection details' })
  findOne(@Param('id') id: string) {
    return this.inspectionsService.findOne(id);
  }

  @Patch(':id/assign')
  @ApiOperation({ summary: 'Assign an inspector to an inspection' })
  assign(@Param('id') id: string, @Body() dto: AssignInspectorDto) {
    return this.inspectionsService.assignInspector(id, dto);
  }

  @Patch(':id/result')
  @ApiOperation({
    summary:
      'Submit inspection assay result (updates lot status & appends INSPECTED passport event)',
  })
  submitResult(
    @Param('id') id: string,
    @Body() dto: SubmitInspectionResultDto,
  ) {
    return this.inspectionsService.submitResult(id, dto);
  }
}
