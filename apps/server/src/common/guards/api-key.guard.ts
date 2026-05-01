import { PrismaService } from '@/database/prisma.service';
import {
  CanActivate,
  ExecutionContext,
  Injectable,
  UnauthorizedException,
} from '@nestjs/common';
import type { Request } from 'express';

@Injectable()
export class ApiKeyGuard implements CanActivate {
  constructor(private readonly prisma: PrismaService) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const request = context
      .switchToHttp()
      .getRequest<Request & { assetId?: string }>();

    // Double cast to resolve 'error typed' or 'any' from request headers
    const apiKeyHeader = request.headers['x-api-key'];

    if (!apiKeyHeader) {
      throw new UnauthorizedException('API key is missing');
    }

 
    const keyRecord = (await this.prisma.apiKey.findFirst({
      where: {
        key_hash: apiKeyHeader as string,
        status: 'ACTIVE',
      },
    }))

    if (!keyRecord) {
      throw new UnauthorizedException('Invalid API key');
    }

    // Attach asset ID to request for the controller to use
    request.assetId = keyRecord.asset_id;
    return true;
  }
}
