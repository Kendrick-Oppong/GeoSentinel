-- =============================================================================
-- GeoSentinel Migration 003: Table Partitioning
-- =============================================================================
-- Converts `positions` to a RANGE-partitioned table on recorded_at.
-- Also partitions `ingestion_log` by day (higher volume).
--
-- WHY PARTITIONING:
--   At 10 assets × 20 updates/min × 1440 min/day = 288,000 rows/day
--   At 90 days retention = ~26 million rows
--   Without partitioning: queries slow down as table grows
--   With partitioning: each query only scans relevant month's partition
--   Dropping old data = DROP TABLE (instant) not DELETE (slow, bloat)
--
-- STRATEGY:
--   positions    → monthly partitions (manageable volume)
--   ingestion_log → daily partitions (higher volume, shorter retention)
--
-- IMPORTANT: Prisma cannot manage partitioned tables directly.
-- The Prisma migration creates `positions` as a regular table.
-- This migration:
--   1. Renames the existing table to positions_legacy
--   2. Creates new partitioned table positions
--   3. Creates initial partitions
--   4. Copies any existing data
--   5. Drops legacy table
--   6. Recreates all indexes on the partitioned table
--
-- Run with:
--   psql $DATABASE_URL -f 003_partitioning.sql
-- =============================================================================

BEGIN;

-- =============================================================================
-- POSITIONS PARTITIONING
-- =============================================================================

-- Step 1: Rename existing table (only if it's a regular table, not partitioned)
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE c.relname = 'positions'
      AND n.nspname = 'public'
      AND c.relkind = 'r' -- Regular table
  ) THEN
    ALTER TABLE positions RENAME TO positions_legacy;
    RAISE NOTICE 'Renamed regular table positions to positions_legacy';
  ELSIF EXISTS (
    SELECT 1 FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE c.relname = 'positions'
      AND n.nspname = 'public'
      AND c.relkind = 'p' -- Partitioned table
  ) THEN
    RAISE NOTICE 'Table positions is already partitioned. Skipping re-partitioning steps.';
  END IF;
END
$$;

-- Step 2: Drop indexes on legacy table (only if legacy exists)
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_class WHERE relname = 'positions_legacy') THEN
    DROP INDEX IF EXISTS positions_asset_id_recorded_at_key;
    DROP INDEX IF EXISTS idx_positions_asset_id_recorded_at;
    DROP INDEX IF EXISTS idx_positions_location_gist;
    DROP INDEX IF EXISTS idx_positions_location_clean_gist;
    DROP INDEX IF EXISTS idx_positions_recorded_at_brin;
  END IF;
END
$$;

-- Step 3: Create partitioned parent table
CREATE TABLE IF NOT EXISTS positions (
  id              BIGSERIAL,
  asset_id        UUID NOT NULL,
  location        GEOGRAPHY(POINT, 4326) NOT NULL,
  speed           NUMERIC(6, 2),
  heading         NUMERIC(5, 2),
  battery         SMALLINT,
  altitude        NUMERIC(8, 2),
  accuracy        NUMERIC(6, 2),
  is_drift        BOOLEAN NOT NULL DEFAULT false,
  is_suspect      BOOLEAN NOT NULL DEFAULT false,
  is_interpolated BOOLEAN NOT NULL DEFAULT false,
  recorded_at     TIMESTAMPTZ NOT NULL,
  received_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  -- Constraints
  CONSTRAINT positions_asset_id_fkey
    FOREIGN KEY (asset_id) REFERENCES assets(id),
  CONSTRAINT positions_battery_check
    CHECK (battery IS NULL OR (battery >= 0 AND battery <= 100)),
  CONSTRAINT positions_speed_check
    CHECK (speed IS NULL OR speed >= 0),
  CONSTRAINT positions_heading_check
    CHECK (heading IS NULL OR (heading >= 0 AND heading < 360)),

  PRIMARY KEY (id, recorded_at)  -- Partition key must be in primary key
) PARTITION BY RANGE (recorded_at);

-- Step 4: Create initial partitions (current month + next 2 months + catch-all)
-- The scheduler creates future partitions automatically before they're needed.

-- Previous month (for late-arriving positions)
CREATE TABLE IF NOT EXISTS positions_2026_04
  PARTITION OF positions
  FOR VALUES FROM ('2026-04-01 00:00:00+00') TO ('2026-05-01 00:00:00+00');

-- Current month
CREATE TABLE IF NOT EXISTS positions_2026_05
  PARTITION OF positions
  FOR VALUES FROM ('2026-05-01 00:00:00+00') TO ('2026-06-01 00:00:00+00');

-- Next month (pre-created so inserts never fail)
CREATE TABLE IF NOT EXISTS positions_2026_06
  PARTITION OF positions
  FOR VALUES FROM ('2026-06-01 00:00:00+00') TO ('2026-07-01 00:00:00+00');

-- Two months ahead (buffer)
CREATE TABLE IF NOT EXISTS positions_2026_07
  PARTITION OF positions
  FOR VALUES FROM ('2026-07-01 00:00:00+00') TO ('2026-08-01 00:00:00+00');

-- Default partition: catches anything outside the created ranges
-- Prevents insert failures if a partition is missing (better to store than fail)
CREATE TABLE IF NOT EXISTS positions_overflow
  PARTITION OF positions DEFAULT;

-- Step 5: Recreate all indexes on the partitioned table
-- Indexes on the parent table propagate to all partitions automatically.

-- Primary spatial index
CREATE INDEX IF NOT EXISTS idx_positions_location_gist
  ON positions USING GIST (location);

-- Clean spatial index (excludes drift and suspect positions)
CREATE INDEX IF NOT EXISTS idx_positions_location_clean_gist
  ON positions USING GIST (location)
  WHERE is_drift = false AND is_suspect = false;

-- Composite index for the most common query pattern: asset history
CREATE INDEX IF NOT EXISTS idx_positions_asset_recorded_at
  ON positions (asset_id, recorded_at DESC);

-- BRIN index for time-range scans (very space-efficient for sequential data)
CREATE INDEX IF NOT EXISTS idx_positions_recorded_at_brin
  ON positions USING BRIN (recorded_at)
  WITH (pages_per_range = 128);

-- Unique constraint to prevent duplicate ingestion
-- Implemented as a unique index (required for partitioned tables — not constraint)
CREATE UNIQUE INDEX IF NOT EXISTS idx_positions_unique_asset_time
  ON positions (asset_id, recorded_at);

-- Step 6: Migrate data from legacy table
DO $$
DECLARE
  legacy_count BIGINT;
  migrated_count BIGINT;
BEGIN
  IF to_regclass('positions_legacy') IS NOT NULL THEN
    EXECUTE 'SELECT COUNT(*) FROM positions_legacy' INTO legacy_count;

    IF legacy_count > 0 THEN
      INSERT INTO positions
      SELECT * FROM positions_legacy;

      SELECT COUNT(*) INTO migrated_count FROM positions;

      IF migrated_count < legacy_count THEN
        RAISE EXCEPTION 'Migration incomplete: % rows in legacy, only % migrated',
          legacy_count, migrated_count;
      END IF;

      RAISE NOTICE 'Migrated % rows from positions_legacy to partitioned positions', migrated_count;
    ELSE
      RAISE NOTICE 'positions_legacy was empty — no data to migrate';
    END IF;
  ELSE
    RAISE NOTICE 'positions_legacy does not exist — skipping migration';
  END IF;
END
$$;

-- Step 7: Drop legacy table
DROP TABLE IF EXISTS positions_legacy;

-- =============================================================================
-- INGESTION_LOG PARTITIONING
-- =============================================================================
-- Higher volume than positions — daily partitions, 30-day retention

-- Step 1: Rename existing table (only if it's a regular table, not partitioned)
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE c.relname = 'ingestion_log'
      AND n.nspname = 'public'
      AND c.relkind = 'r' -- Regular table
  ) THEN
    ALTER TABLE ingestion_log RENAME TO ingestion_log_legacy;
    RAISE NOTICE 'Renamed regular table ingestion_log to ingestion_log_legacy';
  ELSIF EXISTS (
    SELECT 1 FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE c.relname = 'ingestion_log'
      AND n.nspname = 'public'
      AND c.relkind = 'p' -- Partitioned table
  ) THEN
    RAISE NOTICE 'Table ingestion_log is already partitioned. Skipping re-partitioning steps.';
  END IF;
END
$$;

CREATE TABLE IF NOT EXISTS ingestion_log (
  id                    BIGSERIAL,
  asset_id              UUID,
  key_prefix            VARCHAR(20),
  success               BOOLEAN NOT NULL,
  failure_reason        VARCHAR(200),
  alerts_triggered_count INT NOT NULL DEFAULT 0,
  was_drift             BOOLEAN NOT NULL DEFAULT false,
  was_suspect           BOOLEAN NOT NULL DEFAULT false,
  raw_lat               NUMERIC(10, 7),
  raw_lng               NUMERIC(10, 7),
  raw_speed             NUMERIC(6, 2),
  raw_battery           SMALLINT,
  processing_ms         INTEGER,
  received_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  PRIMARY KEY (id, received_at)
) PARTITION BY RANGE (received_at);

-- Create daily partitions for current week + next 7 days
DO $$
DECLARE
  d DATE;
BEGIN
  FOR d IN
    SELECT generate_series(
      DATE_TRUNC('day', NOW()) - INTERVAL '1 day',
      DATE_TRUNC('day', NOW()) + INTERVAL '7 days',
      INTERVAL '1 day'
    )::DATE
  LOOP
    EXECUTE format(
      'CREATE TABLE IF NOT EXISTS ingestion_log_%s
       PARTITION OF ingestion_log
       FOR VALUES FROM (%L) TO (%L)',
      TO_CHAR(d, 'YYYY_MM_DD'),
      d,
      d + INTERVAL '1 day'
    );
  END LOOP;

  RAISE NOTICE 'Created ingestion_log daily partitions';
END
$$;

-- Default partition for overflow
CREATE TABLE IF NOT EXISTS ingestion_log_overflow
  PARTITION OF ingestion_log DEFAULT;

-- Indexes on ingestion_log
CREATE INDEX IF NOT EXISTS idx_ingestion_log_asset_time
  ON ingestion_log (asset_id, received_at DESC)
  WHERE asset_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_ingestion_log_success
  ON ingestion_log (success, received_at DESC);

-- Migrate ingestion_log data
DO $$
DECLARE row_count BIGINT;
BEGIN
  IF to_regclass('ingestion_log_legacy') IS NOT NULL THEN
    EXECUTE 'SELECT COUNT(*) FROM ingestion_log_legacy' INTO row_count;
    IF row_count > 0 THEN
      INSERT INTO ingestion_log SELECT * FROM ingestion_log_legacy;
      RAISE NOTICE 'Migrated % ingestion_log rows', row_count;
    END IF;
  END IF;
END
$$;

DROP TABLE IF EXISTS ingestion_log_legacy;

-- =============================================================================
-- PARTITION MANAGEMENT FUNCTION
-- Called by NestJS scheduler (@Cron) to maintain partitions automatically
-- =============================================================================

-- Function: Create next month's positions partition if it doesn't exist
CREATE OR REPLACE FUNCTION create_positions_partition_for_month(target_month DATE)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  partition_name TEXT;
  start_date DATE;
  end_date DATE;
BEGIN
  start_date := DATE_TRUNC('month', target_month);
  end_date := start_date + INTERVAL '1 month';
  partition_name := 'positions_' || TO_CHAR(start_date, 'YYYY_MM');

  IF NOT EXISTS (
    SELECT 1 FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE c.relname = partition_name
      AND n.nspname = 'public'
  ) THEN
    EXECUTE format(
      'CREATE TABLE %I PARTITION OF positions FOR VALUES FROM (%L) TO (%L)',
      partition_name, start_date, end_date
    );
    RAISE NOTICE 'Created partition: %', partition_name;
  ELSE
    RAISE NOTICE 'Partition already exists: %', partition_name;
  END IF;
END
$$;

-- Function: Drop positions partition older than N days
CREATE OR REPLACE FUNCTION drop_positions_partition_before(cutoff_date DATE)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  partition_rec RECORD;
BEGIN
  FOR partition_rec IN
    SELECT c.relname AS partition_name
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    JOIN pg_inherits i ON i.inhrelid = c.oid
    JOIN pg_class p ON p.oid = i.inhparent
    WHERE p.relname = 'positions'
      AND n.nspname = 'public'
      AND c.relname LIKE 'positions_20%'  -- Only dated partitions, not overflow
      AND c.relname <> 'positions_overflow'
  LOOP
    -- Extract date from partition name (positions_YYYY_MM)
    DECLARE
      partition_month DATE;
    BEGIN
      partition_month := TO_DATE(
        SUBSTRING(partition_rec.partition_name FROM 'positions_(\d{4}_\d{2})'),
        'YYYY_MM'
      );

      IF partition_month < DATE_TRUNC('month', cutoff_date) THEN
        EXECUTE format('DROP TABLE IF EXISTS %I', partition_rec.partition_name);
        RAISE NOTICE 'Dropped old partition: %', partition_rec.partition_name;
      END IF;
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'Could not parse partition name: %', partition_rec.partition_name;
    END;
  END LOOP;
END
$$;

-- Function: Create tomorrow's ingestion_log partition
CREATE OR REPLACE FUNCTION create_ingestion_log_partition_for_day(target_day DATE)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  partition_name TEXT;
BEGIN
  partition_name := 'ingestion_log_' || TO_CHAR(target_day, 'YYYY_MM_DD');

  IF NOT EXISTS (
    SELECT 1 FROM pg_class c
    WHERE c.relname = partition_name
  ) THEN
    EXECUTE format(
      'CREATE TABLE %I PARTITION OF ingestion_log FOR VALUES FROM (%L) TO (%L)',
      partition_name, target_day, target_day + INTERVAL '1 day'
    );
    RAISE NOTICE 'Created ingestion_log partition: %', partition_name;
  END IF;
END
$$;

-- =============================================================================
-- VERIFICATION
-- =============================================================================

DO $$
DECLARE
  partition_count INT;
BEGIN
  SELECT COUNT(*) INTO partition_count
  FROM pg_class c
  JOIN pg_inherits i ON i.inhrelid = c.oid
  JOIN pg_class p ON p.oid = i.inhparent
  WHERE p.relname = 'positions';

  IF partition_count < 4 THEN
    RAISE EXCEPTION 'Expected at least 4 positions partitions, found %', partition_count;
  END IF;

  RAISE NOTICE '003_partitioning.sql: positions partitioned (% partitions), ingestion_log partitioned.', partition_count;
END
$$;

COMMIT;
