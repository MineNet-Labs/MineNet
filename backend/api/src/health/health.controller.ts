import { Controller, Get } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { ApiOperation, ApiTags } from '@nestjs/swagger';

@ApiTags('health')
@Controller('health')
export class HealthController {
  constructor(private readonly config: ConfigService) {}

  @Get()
  @ApiOperation({ summary: 'Check API liveness and configuration' })
  check() {
    return {
      status: 'ok',
      service: 'minenet-api',
      chainId: Number(this.config.get<string>('CHAIN_ID') ?? 84532),
      timestamp: new Date().toISOString(),
    };
  }
}
