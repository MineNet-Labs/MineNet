import { Module } from '@nestjs/common';
import { EscrowController } from './escrow.controller.js';
import { EscrowService } from './escrow.service.js';
import { MarketplaceController } from './marketplace.controller.js';
import { MarketplaceService } from './marketplace.service.js';

@Module({
  controllers: [MarketplaceController, EscrowController],
  providers: [MarketplaceService, EscrowService],
  exports: [MarketplaceService, EscrowService],
})
export class TradeModule {}
