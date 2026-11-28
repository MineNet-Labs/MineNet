import { Module } from '@nestjs/common';
import { LotsController } from './lots.controller.js';
import { LotsService } from './lots.service.js';
import { TransfersController } from './transfers.controller.js';
import { TransfersService } from './transfers.service.js';

@Module({
  controllers: [LotsController, TransfersController],
  providers: [LotsService, TransfersService],
  exports: [LotsService, TransfersService],
})
export class TraceabilityModule {}
