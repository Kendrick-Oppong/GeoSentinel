import { ApiClient } from "../clients/api.client";
import { OsrmProvider } from "../routes/osrm.provider";
import { env } from "../config/env.validation";
import type { AgentConfig, Waypoint } from "../types";

export class AssetAgent {
  private readonly config: AgentConfig;
  private readonly apiClient: ApiClient;
  private readonly routeProvider: OsrmProvider;

  private currentPos: Waypoint;
  private route: Waypoint[] = [];
  private routeIndex: number = 0;

  private battery: number = 100;
  private speed: number = 0;
  private heading: number = 0;

  private isRunning: boolean = false;
  private interval: NodeJS.Timeout | null = null;

  constructor(config: AgentConfig) {
    this.config = config;
    this.currentPos = config.startPos;
    this.apiClient = new ApiClient(config.apiKey);
    this.routeProvider = new OsrmProvider();
  }

  async start() {
    console.log(
      `[Agent] Starting ${this.config.name} (${this.config.type})...`,
    );
    this.isRunning = true;

    // Initial fetch of a route
    await this.fetchNewRoute();

    this.interval = setInterval(() => this.tick(), env.TICK_RATE_MS);
  }

  async stop() {
    this.isRunning = false;
    if (this.interval) clearInterval(this.interval);
    await this.apiClient.flush();
    console.log(`[Agent] Stopped ${this.config.name}.`);
  }

  private async tick() {
    if (!this.isRunning) return;

    this.updateState();
    await this.apiClient.sendPosition({
      lat: this.currentPos.lat,
      lng: this.currentPos.lng,
      speed: this.speed,
      heading: this.heading,
      battery: Math.floor(this.battery),
      recordedAt: new Date().toISOString(),
    });

    console.log(
      `[${this.config.name}] Tick: ${this.currentPos.lat.toFixed(5)}, ${this.currentPos.lng.toFixed(5)} | Spd: ${this.speed}km/h | Bat: ${Math.floor(this.battery)}%`,
    );
  }

  private updateState() {
    if (this.route.length === 0 || this.routeIndex >= this.route.length) {
      this.speed = 0;
      this.fetchNewRoute(); // Async fire and forget for next tick
      return;
    }

    const nextWaypoint = this.route[this.routeIndex];
    if (!nextWaypoint) {
      this.speed = 0;
      this.fetchNewRoute();
      return;
    }

    // Calculate heading towards next waypoint
    this.heading = this.calculateHeading(this.currentPos, nextWaypoint);

    // Update position
    this.currentPos = nextWaypoint;
    this.routeIndex++;

    // Update speed realistically based on type
    const baseSpeed =
      this.config.type === "VEHICLE"
        ? 40
        : this.config.type === "WORKER"
          ? 4
          : 0;
    this.speed = baseSpeed + (Math.random() * 5 - 2.5);
    if (this.speed < 0) this.speed = 0;

    // Update battery
    const drainRate = this.config.type === "EQUIPMENT" ? 0.01 : 0.05;
    this.battery -= drainRate;
    if (this.battery < 0) this.battery = 0;
  }

  private async fetchNewRoute() {
    // Random destination in Accra (roughly)
    const dest: Waypoint = {
      lat: 5.6034 + (Math.random() * 0.1 - 0.05),
      lng: -0.187 + (Math.random() * 0.1 - 0.05),
    };

    const newRoute = await this.routeProvider.getRoute(this.currentPos, dest);
    if (newRoute.length > 0) {
      this.route = newRoute;
      this.routeIndex = 0;
      console.log(
        `[${this.config.name}] New route acquired: ${newRoute.length} points.`,
      );
    }
  }

  private calculateHeading(start: Waypoint, end: Waypoint): number {
    const dy = end.lat - start.lat;
    const dx = Math.cos((Math.PI / 180) * start.lat) * (end.lng - start.lng);
    let angle = (Math.atan2(dx, dy) * 180) / Math.PI;
    return (angle + 360) % 360;
  }
}
