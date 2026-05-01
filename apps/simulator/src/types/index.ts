import type { AssetType } from "@geosentinel/shared";

export interface Waypoint {
  lat: number;
  lng: number;
}

export interface AgentConfig {
  id: string;
  name: string;
  type: AssetType;
  apiKey: string;
  startPos: Waypoint;
}

export interface PositionPayload {
  lat: number;
  lng: number;
  speed: number;
  heading: number;
  battery: number;
  recordedAt: string;
}
