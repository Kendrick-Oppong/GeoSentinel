import { Injectable } from '@nestjs/common';
import { PrismaPg } from '@prisma/adapter-pg';
import { ENV_KEYS } from '@geosentinel/shared';
import { PrismaClient } from '../../generated/prisma/client';

@Injectable()
export class PrismaService extends PrismaClient {
  constructor() {
    const connectionString = process.env[ENV_KEYS.DATABASE_URL];

    if (!connectionString) {
      throw new Error(
        `${ENV_KEYS.DATABASE_URL} is required to initialize PrismaClient`,
      );
    }

    const adapter = new PrismaPg({
      connectionString,
    });

    super({ adapter });
  }
}
