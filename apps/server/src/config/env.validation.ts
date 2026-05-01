import { z } from 'zod';
import { ENV_KEYS } from '@geosentinel/shared';

const environmentSchema = z
  .object({
    [ENV_KEYS.DATABASE_URL]: z.string().url(),
    [ENV_KEYS.SERVER_PORT]: z.coerce.number().int().min(1).max(65535),
    [ENV_KEYS.WEB_ORIGIN]: z.string().url(),
    [ENV_KEYS.JWT_SECRET]: z.string().min(16),
  })
  .passthrough();

export type Environment = z.infer<typeof environmentSchema>;

export function validateEnv(config: Record<string, unknown>) {
  const result = environmentSchema.safeParse(config);

  if (!result.success) {
    const messages = result.error.issues
      .map((issue) => `${issue.path.join('.')}: ${issue.message}`)
      .join('; ');

    throw new Error(`Environment validation failed: ${messages}`);
  }

  return result.data satisfies Environment;
}
