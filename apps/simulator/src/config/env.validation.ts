import { z } from "zod";
import dotenv from "dotenv";
import { ENV_KEYS } from "@geosentinel/shared";

dotenv.config();

const envSchema = z.object({
  [ENV_KEYS.API_URL]: z.string(),
  [ENV_KEYS.OSRM_BASE_URL]: z.string(),
  TICK_RATE_MS: z.string().transform(Number).default("2000"),
  BATCH_SIZE: z.string().transform(Number).default("10"),
  AGENT_COUNT: z.string().transform(Number).default("500"),
});

export const env = envSchema.parse(process.env);
