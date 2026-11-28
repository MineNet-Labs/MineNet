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
import { ClaimStatus, PolicyStatus } from '@prisma/client';
import {
  DecideClaimDto,
  FileClaimDto,
  QuotePolicyDto,
  RequestPolicyDto,
} from './dto/insurance.dto.js';
import { InsuranceService } from './insurance.service.js';

@ApiTags('insurance')
@Controller('insurance')
export class InsuranceController {
  constructor(private readonly insuranceService: InsuranceService) {}

  @Post('policies')
  @ApiOperation({ summary: 'Request an insurance policy for a mineral lot' })
  requestPolicy(@Body() dto: RequestPolicyDto) {
    return this.insuranceService.requestPolicy(dto);
  }

  @Get('policies')
  @ApiOperation({ summary: 'List insurance policies (filter by insurerCode for insurer portal)' })
  @ApiQuery({ name: 'insurerCode', required: false })
  @ApiQuery({ name: 'lotId', required: false })
  @ApiQuery({ name: 'status', enum: PolicyStatus, required: false })
  findAllPolicies(
    @Query('insurerCode') insurerCode?: string,
    @Query('lotId') lotId?: string,
    @Query('status') status?: PolicyStatus,
  ) {
    return this.insuranceService.findAllPolicies({
      insurerCode,
      lotId,
      status,
    });
  }

  @Get('policies/:id')
  @ApiOperation({ summary: 'Get insurance policy details and claims' })
  findOnePolicy(@Param('id') id: string) {
    return this.insuranceService.findOnePolicy(id);
  }

  @Patch('policies/:id/quote')
  @ApiOperation({ summary: 'Insurer quotes premium for a policy request' })
  quotePolicy(@Param('id') id: string, @Body() dto: QuotePolicyDto) {
    return this.insuranceService.quotePolicy(id, dto);
  }

  @Patch('policies/:id/activate')
  @ApiOperation({
    summary: 'Activate an insurance policy and append INSURED passport event',
  })
  activatePolicy(@Param('id') id: string) {
    return this.insuranceService.activatePolicy(id);
  }

  @Patch('policies/:id/decline')
  @ApiOperation({ summary: 'Decline a policy request' })
  declinePolicy(@Param('id') id: string) {
    return this.insuranceService.declinePolicy(id);
  }

  @Post('claims')
  @ApiOperation({ summary: 'File an insurance claim against an active policy' })
  fileClaim(@Body() dto: FileClaimDto) {
    return this.insuranceService.fileClaim(dto);
  }

  @Get('claims')
  @ApiOperation({ summary: 'List insurance claims' })
  @ApiQuery({ name: 'insurerCode', required: false })
  @ApiQuery({ name: 'lotId', required: false })
  @ApiQuery({ name: 'status', enum: ClaimStatus, required: false })
  findAllClaims(
    @Query('insurerCode') insurerCode?: string,
    @Query('lotId') lotId?: string,
    @Query('status') status?: ClaimStatus,
  ) {
    return this.insuranceService.findAllClaims({ insurerCode, lotId, status });
  }

  @Patch('claims/:id/decide')
  @ApiOperation({ summary: 'Approve or reject an insurance claim' })
  decideClaim(@Param('id') id: string, @Body() dto: DecideClaimDto) {
    return this.insuranceService.decideClaim(id, dto);
  }

  @Get('clients')
  @ApiOperation({
    summary: 'List insured client organizations with exposure & claim counts',
  })
  @ApiQuery({ name: 'insurerCode', required: false, example: 'isange' })
  getClients(@Query('insurerCode') insurerCode?: string) {
    return this.insuranceService.getClients(insurerCode);
  }

  @Get('risk')
  @ApiOperation({
    summary: 'Get insurer portfolio risk overview, loss ratio & flagged lots',
  })
  @ApiQuery({ name: 'insurerCode', required: false, example: 'isange' })
  getRiskOverview(@Query('insurerCode') insurerCode?: string) {
    return this.insuranceService.getRiskOverview(insurerCode);
  }
}
