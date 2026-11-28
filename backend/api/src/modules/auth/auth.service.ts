import { randomBytes, scryptSync, timingSafeEqual } from 'node:crypto';
import {
  BadRequestException,
  ConflictException,
  Injectable,
  NotFoundException,
  UnauthorizedException,
} from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { InviteStatus, ParticipantRole } from '@prisma/client';
import { verifyMessage } from 'viem';
import { PrismaService } from '../../prisma/prisma.service.js';
import {
  AcceptInviteDto,
  CreateInviteDto,
  LoginDto,
  RegisterUserDto,
  WalletVerifyDto,
} from './dto/auth.dto.js';

function hashPassword(password: string): string {
  const salt = randomBytes(16).toString('hex');
  const derived = scryptSync(password, salt, 64).toString('hex');
  return `${salt}:${derived}`;
}

function verifyPassword(password: string, stored: string): boolean {
  const [salt, key] = stored.split(':');
  if (!salt || !key) return false;
  const derived = scryptSync(password, salt, 64);
  const keyBuf = Buffer.from(key, 'hex');
  return derived.length === keyBuf.length && timingSafeEqual(derived, keyBuf);
}

@Injectable()
export class AuthService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly jwtService: JwtService,
  ) {}

  private sanitizeUser<T extends { passwordHash?: string | null }>(user: T) {
    const { passwordHash: _passwordHash, ...safe } = user;
    void _passwordHash;
    return safe;
  }

  private async signToken(user: {
    id: string;
    email: string | null;
    walletAddress: string | null;
    roles: ParticipantRole[];
    organizationId: string | null;
  }) {
    const payload = {
      sub: user.id,
      email: user.email,
      walletAddress: user.walletAddress,
      roles: user.roles,
      organizationId: user.organizationId,
    };
    return {
      accessToken: await this.jwtService.signAsync(payload),
      tokenType: 'Bearer',
    };
  }

  async register(dto: RegisterUserDto) {
    const existing = await this.prisma.user.findUnique({
      where: { email: dto.email.toLowerCase() },
    });
    if (existing) {
      throw new ConflictException(`Email ${dto.email} is already registered`);
    }

    const user = await this.prisma.user.create({
      data: {
        email: dto.email.toLowerCase(),
        passwordHash: hashPassword(dto.password),
        fullName: dto.fullName,
        roles: dto.roles?.length ? dto.roles : [ParticipantRole.MINER],
        walletAddress: dto.walletAddress?.toLowerCase(),
        organizationId: dto.organizationId,
      },
    });

    const token = await this.signToken(user);
    return { ...token, user: this.sanitizeUser(user) };
  }

  async login(dto: LoginDto) {
    const user = await this.prisma.user.findUnique({
      where: { email: dto.email.toLowerCase() },
    });
    if (
      !user ||
      !user.passwordHash ||
      !verifyPassword(dto.password, user.passwordHash)
    ) {
      throw new UnauthorizedException('Invalid email or password');
    }
    if (user.isSuspended) {
      throw new UnauthorizedException('Account is suspended');
    }

    const token = await this.signToken(user);
    return { ...token, user: this.sanitizeUser(user) };
  }

  async requestWalletNonce(walletAddress: string) {
    const normalized = walletAddress.toLowerCase();
    const nonce = randomBytes(16).toString('hex');
    const user = await this.prisma.user.upsert({
      where: { walletAddress: normalized },
      update: { nonce },
      create: {
        walletAddress: normalized,
        nonce,
        roles: [ParticipantRole.MINER],
      },
    });
    return {
      walletAddress: user.walletAddress,
      nonce,
      message: `Sign in to MineNet with nonce: ${nonce}`,
    };
  }

  async verifyWalletSignature(dto: WalletVerifyDto) {
    const normalized = dto.walletAddress.toLowerCase();
    const user = await this.prisma.user.findUnique({
      where: { walletAddress: normalized },
    });
    if (!user || !user.nonce) {
      throw new UnauthorizedException('Request a nonce before verifying');
    }

    const message = `Sign in to MineNet with nonce: ${user.nonce}`;
    const valid = await verifyMessage({
      address: dto.walletAddress as `0x${string}`,
      message,
      signature: dto.signature as `0x${string}`,
    }).catch(() => false);

    if (!valid) {
      throw new UnauthorizedException('Invalid wallet signature');
    }

    await this.prisma.user.update({
      where: { id: user.id },
      data: { nonce: null },
    });

    const token = await this.signToken(user);
    return { ...token, user: this.sanitizeUser(user) };
  }

  async getProfile(userId: string) {
    const user = await this.prisma.user.findUnique({
      where: { id: userId },
      include: {
        organization: { select: { id: true, name: true, status: true } },
      },
    });
    if (!user) throw new NotFoundException('User not found');
    return this.sanitizeUser(user);
  }

  /* --------------------------------------------------------- Team Invites */

  async createInvite(dto: CreateInviteDto) {
    const org = await this.prisma.organization.findUnique({
      where: { id: dto.organizationId },
    });
    if (!org) {
      throw new NotFoundException(`Organization ${dto.organizationId} not found`);
    }

    const token = randomBytes(20).toString('hex');
    const expiresAt = new Date(
      Date.now() + (dto.expiresInDays ?? 7) * 86_400_000,
    );

    const invite = await this.prisma.teamInvite.create({
      data: {
        token,
        email: dto.email.toLowerCase(),
        fullName: dto.fullName,
        roles: dto.roles,
        organizationId: dto.organizationId,
        expiresAt,
      },
      include: { organization: { select: { id: true, name: true } } },
    });

    return {
      ...invite,
      inviteUrl: `/invite/${invite.token}`,
    };
  }

  async listInvites(organizationId?: string) {
    return this.prisma.teamInvite.findMany({
      where: { organizationId },
      include: { organization: { select: { id: true, name: true } } },
      orderBy: { createdAt: 'desc' },
    });
  }

  async getInviteByToken(token: string) {
    const invite = await this.prisma.teamInvite.findUnique({
      where: { token },
      include: { organization: { select: { id: true, name: true } } },
    });
    if (!invite) throw new NotFoundException('Invite not found');
    return invite;
  }

  async acceptInvite(token: string, dto: AcceptInviteDto) {
    const invite = await this.getInviteByToken(token);
    if (invite.status !== InviteStatus.PENDING) {
      throw new BadRequestException(`Invite is already ${invite.status}`);
    }
    if (invite.expiresAt.getTime() < Date.now()) {
      await this.prisma.teamInvite.update({
        where: { id: invite.id },
        data: { status: InviteStatus.EXPIRED },
      });
      throw new BadRequestException('Invite has expired');
    }

    const user = await this.prisma.$transaction(async (tx) => {
      const created = await tx.user.upsert({
        where: { email: invite.email },
        update: {
          fullName: dto.fullName,
          passwordHash: hashPassword(dto.password),
          walletAddress: dto.walletAddress?.toLowerCase(),
          roles: invite.roles,
          organizationId: invite.organizationId,
        },
        create: {
          email: invite.email,
          fullName: dto.fullName,
          passwordHash: hashPassword(dto.password),
          walletAddress: dto.walletAddress?.toLowerCase(),
          roles: invite.roles,
          organizationId: invite.organizationId,
        },
      });

      await tx.teamInvite.update({
        where: { id: invite.id },
        data: { status: InviteStatus.ACCEPTED, acceptedAt: new Date() },
      });

      return created;
    });

    const jwt = await this.signToken(user);
    return { ...jwt, user: this.sanitizeUser(user) };
  }
}
