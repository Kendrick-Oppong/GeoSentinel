import 'dotenv/config';
import { defineConfig } from 'prisma/config';
import { ENV_KEYS } from '@geosentinel/shared';

export default defineConfig({
  schema: 'prisma/schema.prisma',
  migrations: {
    path: 'prisma/migrations',
  },
  datasource: {
    url: process.env[ENV_KEYS.DATABASE_URL],
  },
});
