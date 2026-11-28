import { Module } from '@nestjs/common';
import { InspectionsController } from './inspections.controller.js';
import { InspectionsService } from './inspections.service.js';
import { SiteReportsController } from './site-reports.controller.js';
import { SiteReportsService } from './site-reports.service.js';
import { SitesController } from './sites.controller.js';
import { SitesService } from './sites.service.js';

@Module({
  controllers: [SitesController, InspectionsController, SiteReportsController],
  providers: [SitesService, InspectionsService, SiteReportsService],
  exports: [SitesService, InspectionsService, SiteReportsService],
})
export class ComplianceModule {}
