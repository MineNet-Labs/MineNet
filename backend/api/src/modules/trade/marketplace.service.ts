import { createHash } from 'node:crypto';
import {
  BadRequestException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import {
  BuyerRequestStatus,
  EscrowStatus,
  ListingStatus,
  LotStatus,
  OfferStatus,
} from '@prisma/client';
import { PrismaService } from '../../prisma/prisma.service.js';
import {
  CounterOfferDto,
  CreateBuyerRequestDto,
  CreateListingDto,
  CreateOfferDto,
} from './dto/marketplace.dto.js';

function sha256Hex(payload: string): string {
  return `0x${createHash('sha256').update(payload).digest('hex')}`;
}

@Injectable()
export class MarketplaceService {
  constructor(private readonly prisma: PrismaService) {}

  /* ------------------------------------------------------------- Listings */

  async createListing(dto: CreateListingDto) {
    const lot = await this.prisma.mineralLot.findUnique({
      where: { id: dto.lotId },
      include: {
        organization: { select: { id: true, name: true, contactName: true } },
        listings: { where: { status: ListingStatus.ACTIVE } },
      },
    });
    if (!lot) {
      throw new NotFoundException(`Mineral lot ${dto.lotId} not found`);
    }
    if (lot.status !== LotStatus.INSPECTED) {
      throw new BadRequestException(
        `Lot ${lot.lotCode} must be INSPECTED before listing (current: ${lot.status})`,
      );
    }
    if (lot.regulatorHold || lot.openFlags > 0) {
      throw new BadRequestException(
        `Lot ${lot.lotCode} is frozen or has open flags and cannot be listed`,
      );
    }
    if (lot.listings.length > 0) {
      throw new BadRequestException(
        `Lot ${lot.lotCode} already has an active listing`,
      );
    }

    const count = await this.prisma.listing.count();
    const code = `LST-${String(count + 1).padStart(4, '0')}`;
    const quantityKg = dto.quantityKg ?? Number(lot.quantityGrams) / 1000;
    const currency = dto.currency ?? 'USD';

    return this.prisma.$transaction(async (tx) => {
      const listing = await tx.listing.create({
        data: {
          code,
          lotId: lot.id,
          organizationId: lot.organizationId,
          pricePerKg: dto.pricePerKg,
          quantityKg,
          currency,
          notes: dto.notes,
        },
        include: {
          lot: {
            select: {
              id: true,
              lotCode: true,
              mineralType: true,
              gradePct: true,
              status: true,
            },
          },
        },
      });

      await tx.lotEvent.create({
        data: {
          lotId: lot.id,
          eventType: 'LISTED',
          actorWallet: lot.ownerWallet,
          actorName: lot.organization.contactName ?? lot.organization.name,
          actorRole: 'Miner',
          detail: `Listed as ${code} at ${currency} ${dto.pricePerKg}/kg (${quantityKg} kg)`,
          dataHash: sha256Hex(
            JSON.stringify({ code, lotId: lot.id, pricePerKg: dto.pricePerKg }),
          ),
        },
      });

      return listing;
    });
  }

  async findAllListings(filters?: {
    organizationId?: string;
    status?: ListingStatus;
  }) {
    return this.prisma.listing.findMany({
      where: {
        organizationId: filters?.organizationId,
        status: filters?.status,
      },
      include: {
        lot: {
          select: {
            id: true,
            lotCode: true,
            mineralType: true,
            gradePct: true,
            status: true,
          },
        },
        _count: { select: { offers: true } },
      },
      orderBy: { createdAt: 'desc' },
    });
  }

  async cancelListing(id: string) {
    const listing = await this.prisma.listing.findUnique({ where: { id } });
    if (!listing) {
      throw new NotFoundException(`Listing ${id} not found`);
    }
    if (listing.status === ListingStatus.SOLD) {
      throw new BadRequestException('Cannot cancel a sold listing');
    }
    return this.prisma.listing.update({
      where: { id },
      data: { status: ListingStatus.CANCELLED },
    });
  }

  /* ------------------------------------------------------- Buyer Requests */

  async createBuyerRequest(dto: CreateBuyerRequestDto) {
    const count = await this.prisma.buyerRequest.count();
    const code = `REQ-${String(count + 1).padStart(4, '0')}`;
    return this.prisma.buyerRequest.create({
      data: {
        code,
        buyerName: dto.buyerName,
        buyerWallet: dto.buyerWallet,
        verified: dto.verified ?? true,
        mineralType: dto.mineralType,
        requiredKg: dto.requiredKg,
        remainingKg: dto.requiredKg,
        targetGrade: dto.targetGrade,
        pricePerKg: dto.pricePerKg,
        currency: dto.currency ?? 'USD',
        city: dto.city,
        country: dto.country,
        deadline: new Date(dto.deadline),
      },
    });
  }

  async findAllBuyerRequests(filters?: {
    mineralType?: string;
    status?: BuyerRequestStatus;
  }) {
    return this.prisma.buyerRequest.findMany({
      where: {
        mineralType: filters?.mineralType
          ? { contains: filters.mineralType, mode: 'insensitive' }
          : undefined,
        status: filters?.status,
      },
      include: { _count: { select: { offers: true } } },
      orderBy: { createdAt: 'desc' },
    });
  }

  async findOneBuyerRequest(id: string) {
    const req = await this.prisma.buyerRequest.findUnique({
      where: { id },
      include: { offers: { orderBy: { createdAt: 'desc' } } },
    });
    if (!req) {
      throw new NotFoundException(`Buyer request ${id} not found`);
    }
    return req;
  }

  /* --------------------------------------------------------------- Offers */

  async createOffer(dto: CreateOfferDto) {
    const lot = await this.prisma.mineralLot.findUnique({
      where: { id: dto.lotId },
    });
    if (!lot) {
      throw new NotFoundException(`Mineral lot ${dto.lotId} not found`);
    }

    const count = await this.prisma.offer.count();
    const code = `OFF-${String(count + 1).padStart(4, '0')}`;
    const currency = dto.currency ?? 'USD';

    return this.prisma.offer.create({
      data: {
        code,
        lotId: dto.lotId,
        listingId: dto.listingId,
        buyerRequestId: dto.buyerRequestId,
        buyerName: dto.buyerName,
        buyerWallet: dto.buyerWallet,
        pricePerKg: dto.pricePerKg,
        quantityKg: dto.quantityKg,
        currency,
        messages: {
          create: {
            senderSide: 'BUYER',
            pricePerKg: dto.pricePerKg,
            quantityKg: dto.quantityKg,
            note: dto.note,
          },
        },
      },
      include: {
        lot: { select: { id: true, lotCode: true, mineralType: true } },
        messages: { orderBy: { createdAt: 'asc' } },
      },
    });
  }

  async findAllOffers(filters?: { lotId?: string; status?: OfferStatus }) {
    return this.prisma.offer.findMany({
      where: {
        lotId: filters?.lotId,
        status: filters?.status,
      },
      include: {
        lot: { select: { id: true, lotCode: true, mineralType: true } },
        messages: { orderBy: { createdAt: 'asc' } },
        escrow: true,
      },
      orderBy: { createdAt: 'desc' },
    });
  }

  async findOneOffer(id: string) {
    const offer = await this.prisma.offer.findUnique({
      where: { id },
      include: {
        lot: { select: { id: true, lotCode: true, mineralType: true } },
        listing: true,
        buyerRequest: true,
        messages: { orderBy: { createdAt: 'asc' } },
        escrow: true,
      },
    });
    if (!offer) {
      throw new NotFoundException(`Offer ${id} not found`);
    }
    return offer;
  }

  async counterOffer(id: string, dto: CounterOfferDto) {
    const offer = await this.findOneOffer(id);
    if (
      offer.status === OfferStatus.ACCEPTED ||
      offer.status === OfferStatus.REJECTED ||
      offer.status === OfferStatus.WITHDRAWN
    ) {
      throw new BadRequestException(
        `Offer ${offer.code} is already ${offer.status}`,
      );
    }

    return this.prisma.offer.update({
      where: { id },
      data: {
        pricePerKg: dto.pricePerKg,
        quantityKg: dto.quantityKg,
        status: OfferStatus.COUNTERED,
        messages: {
          create: {
            senderSide: dto.senderSide,
            pricePerKg: dto.pricePerKg,
            quantityKg: dto.quantityKg,
            note: dto.note,
          },
        },
      },
      include: { messages: { orderBy: { createdAt: 'asc' } } },
    });
  }

  /** Accepts an offer, marks any linked listing SOLD, creates a LOCKED escrow, and appends passport events. */
  async acceptOffer(id: string) {
    const offer = await this.findOneOffer(id);
    if (
      offer.status === OfferStatus.ACCEPTED ||
      offer.status === OfferStatus.REJECTED ||
      offer.status === OfferStatus.WITHDRAWN
    ) {
      throw new BadRequestException(
        `Offer ${offer.code} cannot be accepted (current: ${offer.status})`,
      );
    }

    const escrowCount = await this.prisma.escrow.count();
    const escrowCode = `ESC-${String(escrowCount + 1).padStart(4, '0')}`;
    const totalAmount = Math.round(offer.pricePerKg * offer.quantityKg * 100) / 100;
    const buyerWallet =
      offer.buyerWallet ?? '0x0000000000000000000000000000000000000000';

    return this.prisma.$transaction(async (tx) => {
      const updatedOffer = await tx.offer.update({
        where: { id },
        data: { status: OfferStatus.ACCEPTED },
      });

      if (offer.listingId) {
        await tx.listing.update({
          where: { id: offer.listingId },
          data: { status: ListingStatus.SOLD },
        });
      }

      if (offer.buyerRequestId && offer.buyerRequest) {
        const nextRemaining = Math.max(
          0,
          offer.buyerRequest.remainingKg - offer.quantityKg,
        );
        await tx.buyerRequest.update({
          where: { id: offer.buyerRequestId },
          data: {
            remainingKg: nextRemaining,
            status:
              nextRemaining === 0
                ? BuyerRequestStatus.FULFILLED
                : BuyerRequestStatus.OPEN,
          },
        });
      }

      const escrow = await tx.escrow.create({
        data: {
          code: escrowCode,
          lotId: offer.lotId,
          offerId: offer.id,
          buyerName: offer.buyerName,
          buyerWallet: offer.buyerWallet,
          amount: totalAmount,
          currency: offer.currency,
          status: EscrowStatus.LOCKED,
        },
      });

      await tx.lotEvent.createMany({
        data: [
          {
            lotId: offer.lotId,
            eventType: 'SOLD',
            actorWallet: buyerWallet,
            actorName: offer.buyerName,
            actorRole: 'Buyer',
            detail: `Offer ${offer.code} accepted · ${offer.quantityKg} kg at ${offer.currency} ${offer.pricePerKg}/kg`,
            dataHash: sha256Hex(
              JSON.stringify({ offerCode: offer.code, lotId: offer.lotId, totalAmount }),
            ),
          },
          {
            lotId: offer.lotId,
            eventType: 'ESCROW_LOCKED',
            actorWallet: buyerWallet,
            actorName: offer.buyerName,
            actorRole: 'Buyer',
            detail: `${offer.currency} ${totalAmount.toLocaleString()} locked in escrow ${escrowCode}`,
            dataHash: sha256Hex(
              JSON.stringify({ escrowCode, lotId: offer.lotId, totalAmount }),
            ),
          },
        ],
      });

      return { offer: updatedOffer, escrow };
    });
  }

  async rejectOffer(id: string) {
    const offer = await this.findOneOffer(id);
    if (offer.status === OfferStatus.ACCEPTED) {
      throw new BadRequestException('Cannot reject an already accepted offer');
    }
    return this.prisma.offer.update({
      where: { id },
      data: { status: OfferStatus.REJECTED },
    });
  }
}
