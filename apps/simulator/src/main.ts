import { AssetType } from "@geosentinel/shared";
import { AssetAgent } from "./agents/AssetAgent";
import { env } from "./config/env.validation";
import type { AgentConfig } from "./types";

/**
 * Deterministically generates agent configurations based on a count.
 * This allows the simulator to scale to thousands of agents while
 * matching the database seed data.
 */
function generateAgents(count: number): AgentConfig[] {
  const agents: AgentConfig[] = [];
  const types: AssetType[] = ["VEHICLE", "WORKER", "EQUIPMENT"];

  for (let i = 1; i <= count; i++) {
    // Determine type (balanced distribution)
    const type = types[i % types.length];
    if (!type) continue;

    // Predictable IDs and Keys for seeding
    const id = `a0000000-0000-0000-0000-${i.toString().padStart(12, "0")}`;
    const apiKey = `geosentinel_sim_key_${i.toString().padStart(4, "0")}`;

    // Random start positions around Accra
    const startPos = {
      lat: 5.6034 + (Math.random() * 0.2 - 0.1),
      lng: -0.187 + (Math.random() * 0.2 - 0.1),
    };

    agents.push({
      id,
      name: `${type.charAt(0) + type.slice(1).toLowerCase()} ${i.toString().padStart(4, "0")}`,
      type,
      apiKey,
      startPos,
    });
  }

  return agents;
}

async function bootstrap() {
  const agentConfigs = generateAgents(env.AGENT_COUNT);
  const agents = agentConfigs.map((config) => new AssetAgent(config));

  console.log("--- GeoSentinel Asset Simulator (Scale Mode) ---");
  console.log(`Target Server: ${env.API_URL}`);
  console.log(`Agent Count:   ${agents.length}`);
  console.log(`Tick Rate:     ${env.TICK_RATE_MS}ms`);
  console.log("-----------------------------------------------");

  // Start agents with a slight staggered delay to avoid thundering herd
  for (let i = 0; i < agents.length; i++) {
    const agent = agents[i];
    await agent?.start();

    // Small delay every 10 agents to spread the load
    if (i % 10 === 0) {
      await new Promise((resolve) => setTimeout(resolve, 50));
    }
  }

  process.on("SIGINT", async () => {
    console.log("\nShutting down simulator...");
    for (const agent of agents) {
      await agent.stop();
    }
    process.exit();
  });
}

bootstrap().catch((err) => {
  console.error("Failed to start simulator:", err);
  process.exit(1);
});
