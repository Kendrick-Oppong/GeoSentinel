import { Injectable } from '@nestjs/common';
import { PrismaPg } from '@prisma/adapter-pg';
import { ENV_KEYS } from '@geosentinel/shared';
import { PrismaClient } from '../../generated/prisma/client';

@Injectable()
export class PrismaService extends PrismaClient {
  constructor() {
    const adapter = new PrismaPg({
      connectionString: process.env[ENV_KEYS.DATABASE_URL],
    });
    super({ adapter });
  }
}
