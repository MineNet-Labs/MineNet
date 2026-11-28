import {
  CanActivate,
  ExecutionContext,
  ForbiddenException,
  Injectable,
  SetMetadata,
} from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { ParticipantRole } from '@prisma/client';
import type { Request } from 'express';
import type { JwtUserPayload } from './jwt-auth.guard.js';

export const ROLES_KEY = 'minenet_roles';
export const Roles = (...roles: ParticipantRole[]) =>
  SetMetadata(ROLES_KEY, roles);

@Injectable()
export class RolesGuard implements CanActivate {
  constructor(private readonly reflector: Reflector) {}

  canActivate(context: ExecutionContext): boolean {
    const requiredRoles = this.reflector.getAllAndOverride<ParticipantRole[]>(
      ROLES_KEY,
      [context.getHandler(), context.getClass()],
    );
    if (!requiredRoles || requiredRoles.length === 0) {
      return true;
    }

    const req = context
      .switchToHttp()
      .getRequest<Request & { user?: JwtUserPayload }>();
    const userRoles = req.user?.roles ?? [];
    const allowed = requiredRoles.some((r) => userRoles.includes(r));
    if (!allowed) {
      throw new ForbiddenException(
        `Requires one of roles: ${requiredRoles.join(', ')}`,
      );
    }
    return true;
  }
}
