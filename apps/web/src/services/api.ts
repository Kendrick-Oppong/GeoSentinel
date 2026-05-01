import axios from 'axios';
import { ENV_KEYS } from '@geosentinel/shared';

export const api = axios.create({
  baseURL: import.meta.env[ENV_KEYS.VITE_API_URL],
});
