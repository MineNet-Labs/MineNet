import {
  ConflictException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { OrgStatus, Prisma } from '@prisma/client';
import { PrismaService } from '../../prisma/prisma.service.js';
import { CreateOrganizationDto } from './dto/create-organization.dto.js';
import { UpdateOrganizationDto } from './dto/update-organization.dto.js';

@Injectable()
export class OrganizationsService {
  constructor(private readonly prisma: PrismaService) {}

  async create(dto: CreateOrganizationDto) {
    try {
      return await this.prisma.organization.create({
        data: {
          ...dto,
          licenceIssuedAt: dto.licenceIssuedAt
            ? new Date(dto.licenceIssuedAt)
            : undefined,
          licenceExpiryAt: dto.licenceExpiryAt
            ? new Date(dto.licenceExpiryAt)
            : undefined,
        },
      });
    } catch (error) {
      if (
        error instanceof Prisma.PrismaClientKnownRequestError &&
        error.code === 'P2002'
      ) {
        throw new ConflictException(
          'An organization with that RDB number or on-chain ID already exists.',
        );
      }
      throw error;
    }
  }

  async findAll(filters?: { status?: OrgStatus; kind?: string }) {
    return this.prisma.organization.findMany({
      where: {
        status: filters?.status,
        kind: filters?.kind
          ? { contains: filters.kind, mode: 'insensitive' }
          : undefined,
      },
      include: {
        _count: {
          select: { sites: true, lots: true, users: true },
        },
      },
      orderBy: { createdAt: 'desc' },
    });
  }

  async findOne(id: string) {
    const org = await this.prisma.organization.findUnique({
      where: { id },
      include: {
        sites: {
          include: { _count: { select: { shafts: true, lots: true } } },
          orderBy: { name: 'asc' },
        },
        _count: {
          select: { sites: true, lots: true, users: true, documents: true },
        },
      },
    });
    if (!org) {
      throw new NotFoundException(`Organization ${id} not found`);
    }
    return org;
  }

  async update(id: string, dto: UpdateOrganizationDto) {
    await this.findOne(id);
    try {
      return await this.prisma.organization.update({
        where: { id },
        data: {
          ...dto,
          licenceIssuedAt: dto.licenceIssuedAt
            ? new Date(dto.licenceIssuedAt)
            : undefined,
          licenceExpiryAt: dto.licenceExpiryAt
            ? new Date(dto.licenceExpiryAt)
            : undefined,
        },
      });
    } catch (error) {
      if (
        error instanceof Prisma.PrismaClientKnownRequestError &&
        error.code === 'P2002'
      ) {
        throw new ConflictException(
          'An organization with that RDB number or on-chain ID already exists.',
        );
      }
      throw error;
    }
  }

  async updateStatus(id: string, status: OrgStatus) {
    await this.findOne(id);
    return this.prisma.organization.update({
      where: { id },
      data: { status },
    });
  }

  async requestLicenceRenewal(id: string, note?: string) {
    await this.findOne(id);
    return this.prisma.organization.update({
      where: { id },
      data: {
        renewalRequestedAt: new Date(),
        renewalNote: note,
      },
    });
  }

  async remove(id: string) {
    await this.findOne(id);
    return this.prisma.organization.delete({ where: { id } });
  }
}
