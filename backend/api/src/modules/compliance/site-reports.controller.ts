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
import { ReportStatus } from '@prisma/client';
import {
  CreateSiteReportDto,
  UpdateSiteReportStatusDto,
} from './dto/site-report.dto.js';
import { SiteReportsService } from './site-reports.service.js';

@ApiTags('site-reports')
@Controller('site-reports')
export class SiteReportsController {
  constructor(private readonly siteReportsService: SiteReportsService) {}

  @Post()
  @ApiOperation({ summary: 'Submit a periodic mine site report' })
  create(@Body() dto: CreateSiteReportDto) {
    return this.siteReportsService.create(dto);
  }

  @Get()
  @ApiOperation({ summary: 'List mine site reports' })
  @ApiQuery({ name: 'siteId', required: false })
  @ApiQuery({ name: 'period', required: false, example: '2026-11' })
  @ApiQuery({ name: 'status', enum: ReportStatus, required: false })
  findAll(
    @Query('siteId') siteId?: string,
    @Query('period') period?: string,
    @Query('status') status?: ReportStatus,
  ) {
    return this.siteReportsService.findAll({ siteId, period, status });
  }

  @Get(':id')
  @ApiOperation({ summary: 'Get site report details' })
  findOne(@Param('id') id: string) {
    return this.siteReportsService.findOne(id);
  }

  @Patch(':id/status')
  @ApiOperation({ summary: 'Update site report review status' })
  updateStatus(
    @Param('id') id: string,
    @Body() dto: UpdateSiteReportStatusDto,
  ) {
    return this.siteReportsService.updateStatus(id, dto.status);
  }
}
