-- =============================================================================
-- GeoSentinel Migration 001: Enable PostGIS Extension
-- =============================================================================
-- Run this AFTER prisma migrate dev creates the base tables.
-- This must run before 002_spatial_columns.sql.
--
-- Run with:
--   psql $DATABASE_URL -f 001_enable_postgis.sql
--   OR via Neon SQL editor
-- =============================================================================

-- Enable PostGIS (includes PostGIS topology functions)
CREATE EXTENSION IF NOT EXISTS postgis;

-- Enable PostGIS topology (for advanced area calculations)
-- CREATE EXTENSION IF NOT EXISTS postgis_topology;

-- Verify installation
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_extension WHERE extname = 'postgis'
  ) THEN
    RAISE EXCEPTION 'PostGIS extension failed to install. Check your database supports it.';
  END IF;

  RAISE NOTICE 'PostGIS version: %', PostGIS_Version();
  RAISE NOTICE '001_enable_postgis.sql completed successfully.';
END
$$;
