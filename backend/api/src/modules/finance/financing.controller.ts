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
import { LoanStatus } from '@prisma/client';
import { RequestLoanDto } from './dto/loan.dto.js';
import { FinancingService } from './financing.service.js';

@ApiTags('financing')
@Controller('financing')
export class FinancingController {
  constructor(private readonly financingService: FinancingService) {}

  @Post('loans')
  @ApiOperation({
    summary: 'Request a lot-backed loan (blocks double-pledging)',
  })
  requestLoan(@Body() dto: RequestLoanDto) {
    return this.financingService.requestLoan(dto);
  }

  @Get('loans')
  @ApiOperation({ summary: 'List lot-backed loans' })
  @ApiQuery({ name: 'lotId', required: false })
  @ApiQuery({ name: 'status', enum: LoanStatus, required: false })
  findAll(
    @Query('lotId') lotId?: string,
    @Query('status') status?: LoanStatus,
  ) {
    return this.financingService.findAll({ lotId, status });
  }

  @Get('loans/:id')
  @ApiOperation({ summary: 'Get loan details' })
  findOne(@Param('id') id: string) {
    return this.financingService.findOne(id);
  }

  @Patch('loans/:id/approve')
  @ApiOperation({
    summary: 'Approve loan, record lien, and append FINANCED passport event',
  })
  approve(@Param('id') id: string) {
    return this.financingService.approve(id);
  }

  @Patch('loans/:id/repay')
  @ApiOperation({
    summary: 'Mark loan repaid and append LIEN_RELEASED passport event',
  })
  repay(@Param('id') id: string) {
    return this.financingService.repay(id);
  }

  @Patch('loans/:id/decline')
  @ApiOperation({ summary: 'Decline a loan request' })
  decline(@Param('id') id: string) {
    return this.financingService.decline(id);
  }
}
