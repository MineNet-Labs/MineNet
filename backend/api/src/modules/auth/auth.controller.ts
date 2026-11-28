import {
  Body,
  Controller,
  Get,
  Param,
  Post,
  Query,
  Req,
  UseGuards,
} from '@nestjs/common';
import {
  ApiBearerAuth,
  ApiOperation,
  ApiQuery,
  ApiTags,
} from '@nestjs/swagger';
import type { Request } from 'express';
import { AuthService } from './auth.service.js';
import {
  AcceptInviteDto,
  CreateInviteDto,
  LoginDto,
  RegisterUserDto,
  WalletNonceDto,
  WalletVerifyDto,
} from './dto/auth.dto.js';
import {
  JwtAuthGuard,
  type JwtUserPayload,
} from './guards/jwt-auth.guard.js';

@ApiTags('auth')
@Controller('auth')
export class AuthController {
  constructor(private readonly authService: AuthService) {}

  @Post('register')
  @ApiOperation({ summary: 'Register a new user with email & password' })
  register(@Body() dto: RegisterUserDto) {
    return this.authService.register(dto);
  }

  @Post('login')
  @ApiOperation({ summary: 'Log in with email & password (returns JWT)' })
  login(@Body() dto: LoginDto) {
    return this.authService.login(dto);
  }

  @Post('wallet/nonce')
  @ApiOperation({ summary: 'Request a sign-in nonce for an EVM wallet' })
  requestWalletNonce(@Body() dto: WalletNonceDto) {
    return this.authService.requestWalletNonce(dto.walletAddress);
  }

  @Post('wallet/verify')
  @ApiOperation({ summary: 'Verify wallet signature and return JWT' })
  verifyWallet(@Body() dto: WalletVerifyDto) {
    return this.authService.verifyWalletSignature(dto);
  }

  @Get('me')
  @UseGuards(JwtAuthGuard)
  @ApiBearerAuth()
  @ApiOperation({ summary: 'Get the currently authenticated user profile' })
  me(@Req() req: Request & { user?: JwtUserPayload }) {
    return this.authService.getProfile(req.user!.sub);
  }

  /* --------------------------------------------------------- Team Invites */

  @Post('invites')
  @ApiOperation({
    summary: 'Create a team invite link (/invite/:token) for an organization',
  })
  createInvite(@Body() dto: CreateInviteDto) {
    return this.authService.createInvite(dto);
  }

  @Get('invites')
  @ApiOperation({ summary: 'List team invites' })
  @ApiQuery({ name: 'organizationId', required: false })
  listInvites(@Query('organizationId') organizationId?: string) {
    return this.authService.listInvites(organizationId);
  }

  @Get('invites/:token')
  @ApiOperation({ summary: 'Inspect a team invite by token' })
  getInvite(@Param('token') token: string) {
    return this.authService.getInviteByToken(token);
  }

  @Post('invites/:token/accept')
  @ApiOperation({ summary: 'Accept a team invite and create/link user account' })
  acceptInvite(@Param('token') token: string, @Body() dto: AcceptInviteDto) {
    return this.authService.acceptInvite(token, dto);
  }
}
