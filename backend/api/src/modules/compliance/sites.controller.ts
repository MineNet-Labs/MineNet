import {
  Body,
  Controller,
  Delete,
  Get,
  Param,
  Patch,
  Post,
  Query,
} from '@nestjs/common';
import { ApiOperation, ApiQuery, ApiTags } from '@nestjs/swagger';
import { SiteStatus } from '@prisma/client';
import { CreateShaftDto } from './dto/create-shaft.dto.js';
import { CreateSiteDto } from './dto/create-site.dto.js';
import { UpdateShaftDto } from './dto/update-shaft.dto.js';
import { UpdateSiteDto } from './dto/update-site.dto.js';
import { SitesService } from './sites.service.js';

@ApiTags('mine-sites')
@Controller('sites')
export class SitesController {
  constructor(private readonly sitesService: SitesService) {}

  @Post()
  @ApiOperation({ summary: 'Register a new mining site' })
  createSite(@Body() dto: CreateSiteDto) {
    return this.sitesService.createSite(dto);
  }

  @Get()
  @ApiOperation({ summary: 'List mining sites with licence status' })
  @ApiQuery({ name: 'organizationId', required: false })
  @ApiQuery({ name: 'status', enum: SiteStatus, required: false })
  @ApiQuery({ name: 'district', required: false })
  findAllSites(
    @Query('organizationId') organizationId?: string,
    @Query('status') status?: SiteStatus,
    @Query('district') district?: string,
  ) {
    return this.sitesService.findAllSites({ organizationId, status, district });
  }

  @Get(':id')
  @ApiOperation({ summary: 'Get mining site details and its shafts' })
  findOneSite(@Param('id') id: string) {
    return this.sitesService.findOneSite(id);
  }

  @Patch(':id')
  @ApiOperation({ summary: 'Update a mining site' })
  updateSite(@Param('id') id: string, @Body() dto: UpdateSiteDto) {
    return this.sitesService.updateSite(id, dto);
  }

  @Delete(':id')
  @ApiOperation({ summary: 'Delete a mining site' })
  removeSite(@Param('id') id: string) {
    return this.sitesService.removeSite(id);
  }

  @Post(':siteId/shafts')
  @ApiOperation({ summary: 'Add a mine shaft to a site' })
  createShaft(@Param('siteId') siteId: string, @Body() dto: CreateShaftDto) {
    return this.sitesService.createShaft(siteId, dto);
  }

  @Get(':siteId/shafts')
  @ApiOperation({ summary: 'List all shafts at a mining site' })
  findShafts(@Param('siteId') siteId: string) {
    return this.sitesService.findShaftsBySite(siteId);
  }

  @Patch('shafts/:shaftId')
  @ApiOperation({ summary: 'Update a mine shaft' })
  updateShaft(
    @Param('shaftId') shaftId: string,
    @Body() dto: UpdateShaftDto,
  ) {
    return this.sitesService.updateShaft(shaftId, dto);
  }

  @Delete('shafts/:shaftId')
  @ApiOperation({ summary: 'Delete a mine shaft' })
  removeShaft(@Param('shaftId') shaftId: string) {
    return this.sitesService.removeShaft(shaftId);
  }
}
