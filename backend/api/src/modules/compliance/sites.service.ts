import {
  ConflictException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { OrgStatus, Prisma, SiteStatus } from '@prisma/client';
import { PrismaService } from '../../prisma/prisma.service.js';
import { CreateShaftDto } from './dto/create-shaft.dto.js';
import { CreateSiteDto } from './dto/create-site.dto.js';
import { UpdateShaftDto } from './dto/update-shaft.dto.js';
import { UpdateSiteDto } from './dto/update-site.dto.js';

export type LicenceState = 'Valid' | 'Expiring' | 'Expired';

function computeLicenceState(expiry: Date): LicenceState {
  const days = Math.ceil((expiry.getTime() - Date.now()) / 86_400_000);
  if (days < 0) return 'Expired';
  if (days <= 60) return 'Expiring';
  return 'Valid';
}

@Injectable()
export class SitesService {
  constructor(private readonly prisma: PrismaService) {}

  private withLicenceMeta<
    T extends {
      status: SiteStatus;
      licenceExpiry: Date;
      organization?: { status: OrgStatus; licenceExpiryAt: Date | null };
    },
  >(site: T) {
    const licenceState = computeLicenceState(site.licenceExpiry);
    const orgValid = site.organization
      ? site.organization.status === OrgStatus.VALIDATED &&
        (!site.organization.licenceExpiryAt ||
          computeLicenceState(site.organization.licenceExpiryAt) !== 'Expired')
      : true;

    return {
      ...site,
      licenceState,
      canRegisterLots:
        orgValid &&
        site.status === SiteStatus.ACTIVE &&
        licenceState !== 'Expired',
    };
  }

  async createSite(dto: CreateSiteDto) {
    const org = await this.prisma.organization.findUnique({
      where: { id: dto.organizationId },
    });
    if (!org) {
      throw new NotFoundException(`Organization ${dto.organizationId} not found`);
    }

    try {
      const site = await this.prisma.mineSite.create({
        data: {
          ...dto,
          licenceExpiry: new Date(dto.licenceExpiry),
          lastActivity: new Date(),
        },
        include: {
          organization: {
            select: { id: true, name: true, status: true, licenceExpiryAt: true },
          },
        },
      });
      return this.withLicenceMeta(site);
    } catch (error) {
      if (
        error instanceof Prisma.PrismaClientKnownRequestError &&
        error.code === 'P2002'
      ) {
        throw new ConflictException(`Mine site code ${dto.code} already exists`);
      }
      throw error;
    }
  }

  async findAllSites(filters?: {
    organizationId?: string;
    status?: SiteStatus;
    district?: string;
  }) {
    const sites = await this.prisma.mineSite.findMany({
      where: {
        organizationId: filters?.organizationId,
        status: filters?.status,
        district: filters?.district
          ? { contains: filters.district, mode: 'insensitive' }
          : undefined,
      },
      include: {
        organization: {
          select: { id: true, name: true, status: true, licenceExpiryAt: true },
        },
        _count: { select: { shafts: true, lots: true } },
      },
      orderBy: { name: 'asc' },
    });
    return sites.map((site) => this.withLicenceMeta(site));
  }

  async findOneSite(id: string) {
    const site = await this.prisma.mineSite.findUnique({
      where: { id },
      include: {
        organization: {
          select: { id: true, name: true, status: true, licenceExpiryAt: true },
        },
        shafts: { orderBy: { code: 'asc' } },
        _count: { select: { shafts: true, lots: true } },
      },
    });
    if (!site) {
      throw new NotFoundException(`Mine site ${id} not found`);
    }
    return this.withLicenceMeta(site);
  }

  async updateSite(id: string, dto: UpdateSiteDto) {
    await this.findOneSite(id);
    const site = await this.prisma.mineSite.update({
      where: { id },
      data: {
        ...dto,
        licenceExpiry: dto.licenceExpiry
          ? new Date(dto.licenceExpiry)
          : undefined,
      },
      include: {
        organization: {
          select: { id: true, name: true, status: true, licenceExpiryAt: true },
        },
      },
    });
    return this.withLicenceMeta(site);
  }

  async removeSite(id: string) {
    await this.findOneSite(id);
    return this.prisma.mineSite.delete({ where: { id } });
  }

  async createShaft(siteId: string, dto: CreateShaftDto) {
    await this.findOneSite(siteId);
    try {
      return await this.prisma.mineShaft.create({
        data: {
          ...dto,
          siteId,
          lastInspection: dto.lastInspection
            ? new Date(dto.lastInspection)
            : undefined,
        },
      });
    } catch (error) {
      if (
        error instanceof Prisma.PrismaClientKnownRequestError &&
        error.code === 'P2002'
      ) {
        throw new ConflictException(`Mine shaft code ${dto.code} already exists`);
      }
      throw error;
    }
  }

  async findShaftsBySite(siteId: string) {
    await this.findOneSite(siteId);
    return this.prisma.mineShaft.findMany({
      where: { siteId },
      orderBy: { code: 'asc' },
    });
  }

  async updateShaft(shaftId: string, dto: UpdateShaftDto) {
    const existing = await this.prisma.mineShaft.findUnique({
      where: { id: shaftId },
    });
    if (!existing) {
      throw new NotFoundException(`Mine shaft ${shaftId} not found`);
    }
    return this.prisma.mineShaft.update({
      where: { id: shaftId },
      data: {
        ...dto,
        lastInspection: dto.lastInspection
          ? new Date(dto.lastInspection)
          : undefined,
      },
    });
  }

  async removeShaft(shaftId: string) {
    const existing = await this.prisma.mineShaft.findUnique({
      where: { id: shaftId },
    });
    if (!existing) {
      throw new NotFoundException(`Mine shaft ${shaftId} not found`);
    }
    return this.prisma.mineShaft.delete({ where: { id: shaftId } });
  }
}
