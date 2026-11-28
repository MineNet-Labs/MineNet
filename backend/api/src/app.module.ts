import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { AppController } from './app.controller.js';
import { AppService } from './app.service.js';
import { HealthModule } from './health/health.module.js';
import { AccessModule } from './modules/access/access.module.js';
import { AuthModule } from './modules/auth/auth.module.js';
import { B2bModule } from './modules/b2b/b2b.module.js';
import { ComplianceModule } from './modules/compliance/compliance.module.js';
import { DocumentsModule } from './modules/documents/documents.module.js';
import { FinanceModule } from './modules/finance/finance.module.js';
import { NotificationsModule } from './modules/notifications/notifications.module.js';
import { ReportsModule } from './modules/reports/reports.module.js';
import { SupportModule } from './modules/support/support.module.js';
import { TraceabilityModule } from './modules/traceability/traceability.module.js';
import { TradeModule } from './modules/trade/trade.module.js';
import { WorkforceModule } from './modules/workforce/workforce.module.js';
import { PrismaModule } from './prisma/prisma.module.js';

@Module({
  imports: [
    ConfigModule.forRoot({
      isGlobal: true,
    }),
    PrismaModule,
    HealthModule,
    AuthModule,
    AccessModule,
    ComplianceModule,
    TraceabilityModule,
    TradeModule,
    B2bModule,
    FinanceModule,
    WorkforceModule,
    DocumentsModule,
    NotificationsModule,
    ReportsModule,
    SupportModule,
  ],
  controllers: [AppController],
  providers: [AppService],
})
export class AppModule {}
