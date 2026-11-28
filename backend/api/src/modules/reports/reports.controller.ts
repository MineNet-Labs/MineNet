import { Controller, Get, Query, Res } from '@nestjs/common';
import { ApiOperation, ApiQuery, ApiTags } from '@nestjs/swagger';
import type { Response } from 'express';
import { ReportsService } from './reports.service.js';

@ApiTags('reports')
@Controller('reports')
export class ReportsController {
  constructor(private readonly reportsService: ReportsService) {}

  @Get('summary')
  @ApiOperation({
    summary: 'Get dashboard KPI summary across lots, trade, insurance, financing & workforce',
  })
  @ApiQuery({ name: 'organizationId', required: false })
  getSummary(@Query('organizationId') organizationId?: string) {
    return this.reportsService.getDashboardSummary(organizationId);
  }

  @Get('lots.csv')
  @ApiOperation({ summary: 'Export mineral lots as a CSV report' })
  @ApiQuery({ name: 'organizationId', required: false })
  async exportLotsCsv(
    @Res() res: Response,
    @Query('organizationId') organizationId?: string,
  ) {
    const csv = await this.reportsService.exportLotsCsv(organizationId);
    res.setHeader('Content-Type', 'text/csv; charset=utf-8');
    res.setHeader(
      'Content-Disposition',
      'attachment; filename="minenet-lots-report.csv"',
    );
    res.send(csv);
  }
}
