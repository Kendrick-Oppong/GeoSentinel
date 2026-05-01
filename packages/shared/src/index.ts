export { ENV_KEYS, type EnvKey } from './env-keys.js';

export type AssetType = 'VEHICLE' | 'WORKER' | 'EQUIPMENT';
export type AssetStatus = 'ACTIVE' | 'IDLE' | 'STALE' | 'OFFLINE';

export type PositionUpdate = {
  assetId: string;
  lat: number;
  lng: number;
  speed: number;
  heading: number;
  battery: number | null;
  recordedAt: string;
};

export type AlertEvent = {
  id: string;
  assetId: string;
  type: string;
  severity: 'INFO' | 'WARNING' | 'CRITICAL';
  message: string;
  createdAt: string;
};

export type ServerToClientEvents = {
  'position:update': PositionUpdate;
  'alert:new': AlertEvent;
  'asset:state_change': {
    assetId: string;
    previousStatus: AssetStatus;
    nextStatus: AssetStatus;
    changedAt: string;
  };
};
