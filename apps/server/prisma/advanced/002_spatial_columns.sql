-- =============================================================================
-- GeoSentinel Migration 002: Spatial Columns & Indexes
-- =============================================================================
-- Adds PostGIS GEOGRAPHY columns to tables that need them.
-- Prisma cannot define or manage these columns — they live here permanently.
--
-- Tables affected:
--   positions            → location GEOGRAPHY(POINT, 4326)
--   geofences            → boundary GEOGRAPHY(POLYGON, 4326)
--   geofence_memberships → entry_location GEOGRAPHY(POINT, 4326)
--   alerts               → location_at_event GEOGRAPHY(POINT, 4326)
--
-- GEOGRAPHY vs GEOMETRY choice:
--   GEOGRAPHY uses spherical math → distances in real metres, globally accurate.
--   GEOMETRY uses planar math → faster but inaccurate for large distances.
--   We use GEOGRAPHY everywhere because:
--     - ST_DWithin(geography, geography, metres) works in real metres globally
--     - No need to manually convert degrees to metres for proximity checks
--     - Accuracy matters for 50m proximity alerts — planar math would be wrong
--
-- Run with:
--   psql $DATABASE_URL -f 002_spatial_columns.sql
-- =============================================================================

BEGIN;

-- =============================================================================
-- POSITIONS TABLE
-- =============================================================================

-- Add the spatial location column
-- GEOGRAPHY(POINT, 4326): WGS84 coordinate system (standard GPS)
ALTER TABLE positions
  ADD COLUMN IF NOT EXISTS location GEOGRAPHY(POINT, 4326);

-- GIST index on location — required for spatial queries to be fast
-- Without this, ST_DWithin does a full table scan (catastrophic at scale)
-- Named explicitly for easy identification in pg_indexes
CREATE INDEX IF NOT EXISTS idx_positions_location_gist
  ON positions USING GIST (location);

-- Partial GIST index excluding drift-flagged positions
-- Geofence checks skip drift positions — this index speeds those queries
CREATE INDEX IF NOT EXISTS idx_positions_location_clean_gist
  ON positions USING GIST (location)
  WHERE is_drift = false AND is_suspect = false;

-- Composite BRIN index on recorded_at for time-range partition scanning
-- BRIN is extremely compact and efficient for sequential timestamp columns
CREATE INDEX IF NOT EXISTS idx_positions_recorded_at_brin
  ON positions USING BRIN (recorded_at)
  WITH (pages_per_range = 128);

-- =============================================================================
-- GEOFENCES TABLE
-- =============================================================================

-- Add the spatial boundary column
-- GEOGRAPHY(POLYGON, 4326): closed polygon defining the geofence boundary
ALTER TABLE geofences
  ADD COLUMN IF NOT EXISTS boundary GEOGRAPHY(POLYGON, 4326);

-- GIST index on boundary — required for ST_Covers / ST_Within checks
-- Partial index: only active, non-deleted geofences are checked during ingestion
-- This keeps the index small and hot in cache
CREATE INDEX IF NOT EXISTS idx_geofences_boundary_active_gist
  ON geofences USING GIST (boundary)
  WHERE is_active = true AND is_deleted = false;

-- Full index for admin queries that include inactive geofences
CREATE INDEX IF NOT EXISTS idx_geofences_boundary_all_gist
  ON geofences USING GIST (boundary);

-- =============================================================================
-- GEOFENCE_MEMBERSHIPS TABLE
-- =============================================================================

-- Capture the exact entry location for analytics
ALTER TABLE geofence_memberships
  ADD COLUMN IF NOT EXISTS entry_location GEOGRAPHY(POINT, 4326);

-- =============================================================================
-- ALERTS TABLE
-- =============================================================================

-- Store coordinates at the moment the alert fired
-- Used for: map flyTo when operator clicks alert, proximity line rendering
ALTER TABLE alerts
  ADD COLUMN IF NOT EXISTS location_at_event GEOGRAPHY(POINT, 4326);

-- Index for spatial queries on alert locations (e.g. "alerts within this area")
CREATE INDEX IF NOT EXISTS idx_alerts_location_gist
  ON alerts USING GIST (location_at_event)
  WHERE location_at_event IS NOT NULL;

-- =============================================================================
-- ENFORCE NOT NULL ON POSITIONS.LOCATION
-- =============================================================================
-- We defer this until after any existing data migrations.
-- For a fresh database, enforce immediately.
-- For existing data: add after backfilling.

-- Check if table is empty before adding NOT NULL constraint
DO $$
DECLARE
  row_count BIGINT;
BEGIN
  SELECT COUNT(*) INTO row_count FROM positions;
  IF row_count = 0 THEN
    -- Safe to add NOT NULL on empty table
    ALTER TABLE positions ALTER COLUMN location SET NOT NULL;
    RAISE NOTICE 'NOT NULL constraint added to positions.location';
  ELSE
    RAISE NOTICE 'positions table has % rows. NOT NULL constraint skipped.', row_count;
    RAISE NOTICE 'Backfill positions.location manually, then run:';
    RAISE NOTICE '  ALTER TABLE positions ALTER COLUMN location SET NOT NULL;';
  END IF;
END
$$;

-- =============================================================================
-- VERIFICATION
-- =============================================================================

DO $$
DECLARE
  col_count INT;
  idx_count INT;
BEGIN
  -- Verify spatial columns exist
  SELECT COUNT(*) INTO col_count
  FROM information_schema.columns
  WHERE table_name IN ('positions', 'geofences', 'geofence_memberships', 'alerts')
    AND column_name IN ('location', 'boundary', 'entry_location', 'location_at_event');

  IF col_count < 4 THEN
    RAISE EXCEPTION 'Expected 4 spatial columns, found %. Check migration.', col_count;
  END IF;

  -- Verify GIST indexes exist
  SELECT COUNT(*) INTO idx_count
  FROM pg_indexes
  WHERE indexname LIKE '%gist%'
    AND tablename IN ('positions', 'geofences', 'alerts');

  RAISE NOTICE '002_spatial_columns.sql: % spatial columns added, % GIST indexes created.', col_count, idx_count;
END
$$;

COMMIT;
