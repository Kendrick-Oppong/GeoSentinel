CREATE EXTENSION IF NOT EXISTS postgis;

CREATE TYPE "AssetType" AS ENUM ('VEHICLE', 'WORKER', 'EQUIPMENT');
CREATE TYPE "AssetStatus" AS ENUM ('ACTIVE', 'IDLE', 'STALE', 'OFFLINE');
CREATE TYPE "AlertType" AS ENUM (
  'GEOFENCE_ENTER',
  'GEOFENCE_EXIT',
  'PROXIMITY',
  'SPEEDING',
  'STALE_ASSET',
  'LOW_BATTERY'
);
CREATE TYPE "AlertSeverity" AS ENUM ('INFO', 'WARNING', 'CRITICAL');

CREATE TABLE "assets" (
  "id" TEXT NOT NULL,
  "name" TEXT NOT NULL,
  "type" "AssetType" NOT NULL,
  "status" "AssetStatus" NOT NULL DEFAULT 'OFFLINE',
  "metadata" JSONB,
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updated_at" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "assets_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "positions" (
  "id" TEXT NOT NULL,
  "asset_id" TEXT NOT NULL,
  "location" geography(Point, 4326) NOT NULL,
  "speed" DOUBLE PRECISION NOT NULL,
  "heading" DOUBLE PRECISION NOT NULL,
  "battery" DOUBLE PRECISION,
  "recorded_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "positions_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "geofences" (
  "id" TEXT NOT NULL,
  "name" TEXT NOT NULL,
  "boundary" geography(Polygon, 4326) NOT NULL,
  "color" TEXT NOT NULL DEFAULT '#0ea5e9',
  "is_active" BOOLEAN NOT NULL DEFAULT true,
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updated_at" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "geofences_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "alerts" (
  "id" TEXT NOT NULL,
  "asset_id" TEXT NOT NULL,
  "geofence_id" TEXT,
  "type" "AlertType" NOT NULL,
  "severity" "AlertSeverity" NOT NULL DEFAULT 'WARNING',
  "message" TEXT NOT NULL,
  "read_at" TIMESTAMP(3),
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "alerts_pkey" PRIMARY KEY ("id")
);

CREATE INDEX "positions_asset_id_recorded_at_idx" ON "positions"("asset_id", "recorded_at");
CREATE INDEX "positions_location_gist_idx" ON "positions" USING GIST ("location");
CREATE INDEX "geofences_boundary_gist_idx" ON "geofences" USING GIST ("boundary");
CREATE INDEX "alerts_asset_id_created_at_idx" ON "alerts"("asset_id", "created_at");
CREATE INDEX "alerts_type_created_at_idx" ON "alerts"("type", "created_at");

ALTER TABLE "positions"
  ADD CONSTRAINT "positions_asset_id_fkey"
  FOREIGN KEY ("asset_id") REFERENCES "assets"("id") ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "alerts"
  ADD CONSTRAINT "alerts_asset_id_fkey"
  FOREIGN KEY ("asset_id") REFERENCES "assets"("id") ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "alerts"
  ADD CONSTRAINT "alerts_geofence_id_fkey"
  FOREIGN KEY ("geofence_id") REFERENCES "geofences"("id") ON DELETE SET NULL ON UPDATE CASCADE;
