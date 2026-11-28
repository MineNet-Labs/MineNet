import { Controller, Get, Query } from '@nestjs/common';
import { ApiOperation, ApiQuery, ApiTags } from '@nestjs/swagger';
import { RatesService } from './rates.service.js';

@ApiTags('finance-rates')
@Controller('finance')
export class RatesController {
  constructor(private readonly ratesService: RatesService) {}

  @Get('rates')
  @ApiOperation({ summary: 'Get FX rates (USD/RWF) and mineral reference prices' })
  getRates() {
    return this.ratesService.getRates();
  }

  @Get('price-guidance')
  @ApiOperation({
    summary: 'Compute indicative USD/kg price band for a mineral & grade',
  })
  @ApiQuery({ name: 'mineral', required: true, example: 'Coltan' })
  @ApiQuery({ name: 'grade', required: true, example: 30 })
  getPriceGuidance(
    @Query('mineral') mineral = 'Coltan',
    @Query('grade') grade = '30',
  ) {
    return this.ratesService.getPriceGuidance(mineral, Number(grade) || 30);
  }
}
