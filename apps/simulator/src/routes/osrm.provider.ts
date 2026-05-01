import axios from "axios";
import { env } from "../config/env.validation";
import type { Waypoint } from "../types";

export class OsrmProvider {
  async getRoute(start: Waypoint, end: Waypoint): Promise<Waypoint[]> {
    try {
      const url = `${env.OSRM_BASE_URL}/route/v1/driving/${start.lng},${start.lat};${end.lng},${end.lat}?overview=full&geometries=geojson`;
      const response = await axios.get(url);

      if (response.data.code !== "Ok") {
        throw new Error(`OSRM Error: ${response.data.code}`);
      }

      const coordinates = response.data.routes[0].geometry.coordinates;
      return coordinates.map((coord: [number, number]) => ({
        lng: coord[0],
        lat: coord[1],
      }));
    } catch (error) {
      if (axios.isAxiosError(error)) {
        console.error(`[OSRM] Failed to fetch route: ${error.message}`);
      } else {
        console.error(`[OSRM] Failed to fetch route: ${error}`);
      }
      return [];
    }
  }
}
