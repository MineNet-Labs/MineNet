import {
  ArgumentsHost,
  Catch,
  ExceptionFilter,
  HttpStatus,
} from '@nestjs/common';
import { Prisma } from '@prisma/client';
import type { Response } from 'express';

@Catch(Prisma.PrismaClientKnownRequestError)
export class PrismaExceptionFilter implements ExceptionFilter {
  catch(
    exception: Prisma.PrismaClientKnownRequestError,
    host: ArgumentsHost,
  ) {
    const res = host.switchToHttp().getResponse<Response>();

    let status = HttpStatus.BAD_REQUEST;
    let message = 'Database request failed';

    switch (exception.code) {
      case 'P2002':
        status = HttpStatus.CONFLICT;
        message = 'A record with this unique value already exists';
        break;
      case 'P2003':
        status = HttpStatus.BAD_REQUEST;
        message = 'Referenced parent record does not exist';
        break;
      case 'P2025':
        status = HttpStatus.NOT_FOUND;
        message = 'Requested record was not found';
        break;
      default:
        status = HttpStatus.INTERNAL_SERVER_ERROR;
        message = `Database error (${exception.code})`;
    }

    res.status(status).json({
      statusCode: status,
      error: HttpStatus[status],
      message,
    });
  }
}
