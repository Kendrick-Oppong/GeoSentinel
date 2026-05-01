import { config } from 'dotenv';
import { ENV_KEYS } from '@geosentinel/shared';

config();

const apiUrl = process.env[ENV_KEYS.API_URL as string];

if (!apiUrl) {
  throw new Error(`${ENV_KEYS.API_URL} must be set in the .env file`);
}

console.log(`GeoSentinel simulator ready. Target API: ${apiUrl}`);
