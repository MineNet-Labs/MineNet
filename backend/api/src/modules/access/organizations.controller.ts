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
import { OrgStatus } from '@prisma/client';
import { CreateOrganizationDto } from './dto/create-organization.dto.js';
import {
  RequestLicenceRenewalDto,
  UpdateOrganizationDto,
  UpdateOrganizationStatusDto,
} from './dto/update-organization.dto.js';
import { OrganizationsService } from './organizations.service.js';

@ApiTags('organizations')
@Controller('organizations')
export class OrganizationsController {
  constructor(private readonly organizationsService: OrganizationsService) {}

  @Post()
  @ApiOperation({ summary: 'Register a new organization' })
  create(@Body() dto: CreateOrganizationDto) {
    return this.organizationsService.create(dto);
  }

  @Get()
  @ApiOperation({ summary: 'List all organizations' })
  @ApiQuery({ name: 'status', enum: OrgStatus, required: false })
  @ApiQuery({ name: 'kind', required: false })
  findAll(
    @Query('status') status?: OrgStatus,
    @Query('kind') kind?: string,
  ) {
    return this.organizationsService.findAll({ status, kind });
  }

  @Get(':id')
  @ApiOperation({ summary: 'Get an organization and its mine sites' })
  findOne(@Param('id') id: string) {
    return this.organizationsService.findOne(id);
  }

  @Patch(':id')
  @ApiOperation({ summary: 'Update organization details' })
  update(@Param('id') id: string, @Body() dto: UpdateOrganizationDto) {
    return this.organizationsService.update(id, dto);
  }

  @Patch(':id/status')
  @ApiOperation({ summary: 'Update regulator validation status' })
  updateStatus(
    @Param('id') id: string,
    @Body() dto: UpdateOrganizationStatusDto,
  ) {
    return this.organizationsService.updateStatus(id, dto.status);
  }

  @Post(':id/renewal-request')
  @ApiOperation({
    summary: 'Submit a licence renewal request for an organization',
  })
  requestLicenceRenewal(
    @Param('id') id: string,
    @Body() dto: RequestLicenceRenewalDto,
  ) {
    return this.organizationsService.requestLicenceRenewal(id, dto.note);
  }

  @Delete(':id')
  @ApiOperation({ summary: 'Delete an organization' })
  remove(@Param('id') id: string) {
    return this.organizationsService.remove(id);
  }
}
