import { Injectable } from '@nestjs/common';
import { BuyerRequestStatus } from '@prisma/client';
import { PrismaService } from '../../prisma/prisma.service.js';

const REFERENCE_PRICES: Record<string, { usdPerKg: number; refGrade: number }> = {
  Gold: { usdPerKg: 82_000, refGrade: 99 },
  Coltan: { usdPerKg: 42, refGrade: 30 },
  Tantalum: { usdPerKg: 160, refGrade: 95 },
  Tin: { usdPerKg: 31, refGrade: 95 },
  Cassiterite: { usdPerKg: 18, refGrade: 65 },
  Wolframite: { usdPerKg: 14.5, refGrade: 60 },
};

@Injectable()
export class RatesService {
  constructor(private readonly prisma: PrismaService) {}

  getRates() {
    return {
      updatedAt: new Date().toISOString(),
      fx: {
        USD_RWF: 1380,
        RWF_USD: Number((1 / 1380).toFixed(6)),
      },
      minerals: REFERENCE_PRICES,
    };
  }

  async getPriceGuidance(mineral: string, gradePct: number) {
    const key =
      Object.keys(REFERENCE_PRICES).find(
        (k) => k.toLowerCase() === mineral.toLowerCase(),
      ) ?? mineral;
    const ref = REFERENCE_PRICES[key] ?? {
      usdPerKg: 10,
      refGrade: gradePct || 1,
    };
    const gradeFactor = Math.min(1.25, Math.max(0.6, gradePct / ref.refGrade));

    const openRequests = await this.prisma.buyerRequest.findMany({
      where: {
        mineralType: { equals: key, mode: 'insensitive' },
        status: BuyerRequestStatus.OPEN,
      },
      select: { pricePerKg: true },
    });

    const demand = openRequests.length
      ? openRequests.reduce((sum, r) => sum + r.pricePerKg, 0) /
        openRequests.length
      : null;

    const base = ref.usdPerKg * gradeFactor;
    const mid = demand ? base * 0.6 + demand * 0.4 : base;
    const round = (n: number) =>
      n >= 1000 ? Math.round(n / 10) * 10 : Math.round(n * 100) / 100;

    return {
      mineral: key,
      gradePct,
      currency: 'USD',
      low: round(mid * 0.92),
      mid: round(mid),
      high: round(mid * 1.08),
      openBuyerRequests: openRequests.length,
      basis: `Reference ${key} price adjusted for ${gradePct}% grade${demand ? `, blended with ${openRequests.length} open buyer request(s)` : ''}.`,
    };
  }
}
