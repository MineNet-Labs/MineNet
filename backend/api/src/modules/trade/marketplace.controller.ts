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
import {
  BuyerRequestStatus,
  ListingStatus,
  OfferStatus,
} from '@prisma/client';
import {
  CounterOfferDto,
  CreateBuyerRequestDto,
  CreateListingDto,
  CreateOfferDto,
} from './dto/marketplace.dto.js';
import { MarketplaceService } from './marketplace.service.js';

@ApiTags('marketplace')
@Controller('marketplace')
export class MarketplaceController {
  constructor(private readonly marketplaceService: MarketplaceService) {}

  /* ------------------------------------------------------------- Listings */

  @Post('listings')
  @ApiOperation({
    summary: 'List a verified (INSPECTED) mineral lot on the marketplace',
  })
  createListing(@Body() dto: CreateListingDto) {
    return this.marketplaceService.createListing(dto);
  }

  @Get('listings')
  @ApiOperation({ summary: 'List marketplace listings' })
  @ApiQuery({ name: 'organizationId', required: false })
  @ApiQuery({ name: 'status', enum: ListingStatus, required: false })
  findAllListings(
    @Query('organizationId') organizationId?: string,
    @Query('status') status?: ListingStatus,
  ) {
    return this.marketplaceService.findAllListings({ organizationId, status });
  }

  @Patch('listings/:id/cancel')
  @ApiOperation({ summary: 'Cancel an active marketplace listing' })
  cancelListing(@Param('id') id: string) {
    return this.marketplaceService.cancelListing(id);
  }

  /* ------------------------------------------------------- Buyer Requests */

  @Post('requests')
  @ApiOperation({ summary: 'Create a buyer sourcing request' })
  createBuyerRequest(@Body() dto: CreateBuyerRequestDto) {
    return this.marketplaceService.createBuyerRequest(dto);
  }

  @Get('requests')
  @ApiOperation({ summary: 'List buyer sourcing requests' })
  @ApiQuery({ name: 'mineralType', required: false })
  @ApiQuery({ name: 'status', enum: BuyerRequestStatus, required: false })
  findAllBuyerRequests(
    @Query('mineralType') mineralType?: string,
    @Query('status') status?: BuyerRequestStatus,
  ) {
    return this.marketplaceService.findAllBuyerRequests({
      mineralType,
      status,
    });
  }

  @Get('requests/:id')
  @ApiOperation({ summary: 'Get buyer request details and offers' })
  findOneBuyerRequest(@Param('id') id: string) {
    return this.marketplaceService.findOneBuyerRequest(id);
  }

  /* --------------------------------------------------------------- Offers */

  @Post('offers')
  @ApiOperation({ summary: 'Submit an offer on a lot/listing/request' })
  createOffer(@Body() dto: CreateOfferDto) {
    return this.marketplaceService.createOffer(dto);
  }

  @Get('offers')
  @ApiOperation({ summary: 'List offers with negotiation history' })
  @ApiQuery({ name: 'lotId', required: false })
  @ApiQuery({ name: 'status', enum: OfferStatus, required: false })
  findAllOffers(
    @Query('lotId') lotId?: string,
    @Query('status') status?: OfferStatus,
  ) {
    return this.marketplaceService.findAllOffers({ lotId, status });
  }

  @Get('offers/:id')
  @ApiOperation({ summary: 'Get offer details, messages, and escrow' })
  findOneOffer(@Param('id') id: string) {
    return this.marketplaceService.findOneOffer(id);
  }

  @Post('offers/:id/counter')
  @ApiOperation({ summary: 'Counter an offer with new price/quantity' })
  counterOffer(@Param('id') id: string, @Body() dto: CounterOfferDto) {
    return this.marketplaceService.counterOffer(id, dto);
  }

  @Patch('offers/:id/accept')
  @ApiOperation({
    summary:
      'Accept an offer (marks listing SOLD, locks Escrow, appends SOLD + ESCROW_LOCKED passport events)',
  })
  acceptOffer(@Param('id') id: string) {
    return this.marketplaceService.acceptOffer(id);
  }

  @Patch('offers/:id/reject')
  @ApiOperation({ summary: 'Reject an offer' })
  rejectOffer(@Param('id') id: string) {
    return this.marketplaceService.rejectOffer(id);
  }
}
