/**
 * Environment variable keys used across the GeoSentinel monorepo
 * Single source of truth for all configuration variable names
 */
export const ENV_KEYS = {
  // Database
  DATABASE_URL: 'DATABASE_URL',

  // Server
  SERVER_PORT: 'SERVER_PORT',
  JWT_SECRET: 'JWT_SECRET',
  WEB_ORIGIN: 'WEB_ORIGIN',

  // Frontend
  WEB_PORT: 'WEB_PORT',
  VITE_API_URL: 'VITE_API_URL',
  VITE_SOCKET_URL: 'VITE_SOCKET_URL',

  // Simulator
  API_URL: 'API_URL',
  OSRM_BASE_URL: 'OSRM_BASE_URL',
} as const;

export type EnvKey = typeof ENV_KEYS[keyof typeof ENV_KEYS];
