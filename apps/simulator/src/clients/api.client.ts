import axios from "axios";
import { env } from "../config/env.validation";
import { API_ENDPOINTS } from "../config/constants";
import type { PositionPayload } from "../types";

export class ApiClient {
  private readonly client;
  private buffer: PositionPayload[] = [];

  constructor(apiKey: string) {
    this.client = axios.create({
      baseURL: env.API_URL,
      headers: {
        "x-api-key": apiKey,
        "Content-Type": "application/json",
      },
    });
  }

  async sendPosition(payload: PositionPayload) {
    this.buffer.push(payload);

    if (this.buffer.length >= env.BATCH_SIZE) {
      await this.flush();
    }
  }

  async flush() {
    if (this.buffer.length === 0) return;

    const payload = [...this.buffer];
    this.buffer = [];

    try {
      await this.client.post(API_ENDPOINTS.POSITIONS_INGEST, payload);
    } catch (error) {
      if (axios.isAxiosError(error)) {
        console.error(`[API] Failed to flush batch: ${error.message}`);
      } else {
        console.error(`[API] Failed to flush batch: ${error}`);
      }
      // Optional: Re-add to buffer on failure if needed
    }
  }
}
