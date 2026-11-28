import { Module } from '@nestjs/common';
import { FinancingController } from './financing.controller.js';
import { FinancingService } from './financing.service.js';
import { InsuranceController } from './insurance.controller.js';
import { InsuranceService } from './insurance.service.js';
import { RatesController } from './rates.controller.js';
import { RatesService } from './rates.service.js';

@Module({
  controllers: [InsuranceController, FinancingController, RatesController],
  providers: [InsuranceService, FinancingService, RatesService],
  exports: [InsuranceService, FinancingService, RatesService],
})
export class FinanceModule {}
