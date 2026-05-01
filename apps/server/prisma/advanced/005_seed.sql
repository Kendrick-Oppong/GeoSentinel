-- =============================================================================
-- GeoSentinel Migration 005: Development Seed Data
-- =============================================================================
-- Seeds realistic data for local development and demo purposes.
-- Uses real locations in and around Accra, Ghana.
--
-- Seeds:
--   - 10 assets (5 vehicles, 3 workers, 2 equipment)
--   - 10 API keys (one per asset)
--   - 5 geofences (real areas in Accra)
--   - 50 historical positions per asset (last 30 minutes of movement)
--   - 8 sample alerts
--   - system_settings defaults
--
-- Run with:
--   psql $DATABASE_URL -f 005_seed.sql
--
-- DO NOT run in production. Guard is below.
-- =============================================================================

DO $$
BEGIN
  IF current_database() LIKE '%prod%' OR current_database() LIKE '%production%' THEN
    RAISE EXCEPTION 'Refusing to seed production database: %', current_database();
  END IF;
END
$$;

BEGIN;

-- =============================================================================
-- TRUNCATE (clean slate for re-seeding during development)
-- =============================================================================

-- Truncate in dependency order to avoid FK violations
TRUNCATE TABLE
  ingestion_log,
  alerts,
  geofence_memberships,
  positions,
  api_keys,
  asset_settings,
  geofences,
  assets,
  audit_log
RESTART IDENTITY CASCADE;

-- =============================================================================
-- ASSETS (Dynamic generation for Scale Mode)
-- =============================================================================

INSERT INTO assets (id, name, type, status, description, identifier, color)
SELECT
  'a0000000-0000-0000-0000-' || LPAD(step::text, 12, '0'),
  CASE
    WHEN step % 3 = 1 THEN 'Vehicle '
    WHEN step % 3 = 2 THEN 'Worker '
    ELSE 'Equipment '
  END || LPAD(step::text, 4, '0'),
  CASE
    WHEN step % 3 = 1 THEN 'VEHICLE'::asset_type
    WHEN step % 3 = 2 THEN 'WORKER'::asset_type
    ELSE 'EQUIPMENT'::asset_type
  END,
  'ACTIVE',
  'Simulated asset for high-scale testing',
  'SIM-' || LPAD(step::text, 4, '0'),
  CASE
    WHEN step % 3 = 1 THEN '#3B82F6'
    WHEN step % 3 = 2 THEN '#10B981'
    ELSE '#F59E0B'
  END
FROM generate_series(1, 1000) AS step;

-- =============================================================================
-- API KEYS (Dynamic generation to match simulator)
-- =============================================================================

INSERT INTO api_keys (id, asset_id, key_hash, key_prefix, label, status)
SELECT
  gen_random_uuid(),
  'a0000000-0000-0000-0000-' || LPAD(step::text, 12, '0'),
  'geosentinel_sim_key_' || LPAD(step::text, 4, '0'), -- Storing raw key in hash for dev lookup
  'geosentinel_',
  'Simulated Key ' || LPAD(step::text, 4, '0'),
  'ACTIVE'
FROM generate_series(1, 1000) AS step;

-- =============================================================================
-- GEOFENCES
-- Real named areas in and around Accra, Ghana
-- boundary column added via raw SQL (PostGIS not in Prisma)
-- =============================================================================

INSERT INTO geofences (id, name, description, color, stroke_color, area_km2, alert_mode, is_active) VALUES
  (
    'f0000001-0000-0000-0000-000000000001',
    'Kotoka Airport Zone',
    'Restricted area around Kotoka International Airport. All vehicle entry/exit logged.',
    '#EF4444',
    '#DC2626',
    2.4,
    'BREACH',
    true
  ),
  (
    'f0000001-0000-0000-0000-000000000002',
    'Tema Industrial Area',
    'Main operations zone — assets should remain within this boundary during work hours.',
    '#3B82F6',
    '#2563EB',
    15.8,
    'EXIT_ONLY',
    true
  ),
  (
    'f0000001-0000-0000-0000-000000000003',
    'Accra Central Depot',
    'Asset staging and maintenance depot. Entry/exit tracked for scheduling.',
    '#10B981',
    '#059669',
    0.8,
    'BREACH',
    true
  ),
  (
    'f0000001-0000-0000-0000-000000000004',
    'Legon University Campus',
    'Personnel only zone — vehicles require authorization to enter.',
    '#F59E0B',
    '#D97706',
    3.2,
    'ENTRY_ONLY',
    true
  ),
  (
    'f0000001-0000-0000-0000-000000000005',
    'Achimota Staging Area',
    'Informational boundary — equipment staging point north of the city.',
    '#8B5CF6',
    '#7C3AED',
    1.1,
    'INFORMATIONAL',
    true
  );

-- Add PostGIS boundaries for geofences
-- Using real approximate polygons for Accra locations (WGS84 / EPSG:4326)
-- Coordinates are [longitude, latitude] pairs

UPDATE geofences SET boundary = ST_GeographyFromText(
  'SRID=4326;POLYGON((-0.1720 5.6050, -0.1650 5.6050, -0.1650 5.5990, -0.1720 5.5990, -0.1720 5.6050))'
) WHERE id = 'f0000001-0000-0000-0000-000000000001'; -- Kotoka Airport Zone

UPDATE geofences SET boundary = ST_GeographyFromText(
  'SRID=4326;POLYGON((-0.0200 5.6500, 0.0100 5.6500, 0.0100 5.6200, -0.0200 5.6200, -0.0200 5.6500))'
) WHERE id = 'f0000001-0000-0000-0000-000000000002'; -- Tema Industrial Area

UPDATE geofences SET boundary = ST_GeographyFromText(
  'SRID=4326;POLYGON((-0.2050 5.5500, -0.1950 5.5500, -0.1950 5.5440, -0.2050 5.5440, -0.2050 5.5500))'
) WHERE id = 'f0000001-0000-0000-0000-000000000003'; -- Accra Central Depot

UPDATE geofences SET boundary = ST_GeographyFromText(
  'SRID=4326;POLYGON((-0.1940 5.6530, -0.1820 5.6530, -0.1820 5.6450, -0.1940 5.6450, -0.1940 5.6530))'
) WHERE id = 'f0000001-0000-0000-0000-000000000004'; -- Legon University Campus

UPDATE geofences SET boundary = ST_GeographyFromText(
  'SRID=4326;POLYGON((-0.2270 5.6250, -0.2180 5.6250, -0.2180 5.6180, -0.2270 5.6180, -0.2270 5.6250))'
) WHERE id = 'f0000001-0000-0000-0000-000000000005'; -- Achimota Staging Area

-- =============================================================================
-- POSITIONS (historical — last 30 minutes, simulated movement)
-- Generates a realistic trail for each asset.
-- Using generate_series to create time-spaced points with slight movement.
-- =============================================================================

-- Cargo Van 01 — moving along Ring Road area
INSERT INTO positions (asset_id, location, speed, heading, battery, recorded_at)
SELECT
  'a0000001-0000-0000-0000-000000000001',
  ST_MakePoint(
    -0.1870 + (step * 0.0003) + (RANDOM() * 0.0001 - 0.00005),  -- lng: moving east
    5.6037  + (step * 0.0001) + (RANDOM() * 0.0001 - 0.00005)   -- lat: slight north drift
  )::GEOGRAPHY,
  35 + (RANDOM() * 20)::NUMERIC(6,2),     -- speed 35–55 km/h
  85 + (RANDOM() * 10)::NUMERIC(5,2),     -- heading ~east (85°)
  (88 - step * 0.1)::INT,                  -- battery draining slowly
  NOW() - (INTERVAL '30 minutes') + (step * INTERVAL '36 seconds')
FROM generate_series(0, 49) AS step;

-- Pickup Truck 02 — moving south toward coast
INSERT INTO positions (asset_id, location, speed, heading, battery, recorded_at)
SELECT
  'a0000001-0000-0000-0000-000000000002',
  ST_MakePoint(
    -0.2100 + (RANDOM() * 0.0002 - 0.0001),
    5.5900  - (step * 0.0002) + (RANDOM() * 0.0001 - 0.00005)  -- moving south
  )::GEOGRAPHY,
  28 + (RANDOM() * 15)::NUMERIC(6,2),
  175 + (RANDOM() * 10)::NUMERIC(5,2),    -- heading ~south
  (92 - step * 0.08)::INT,
  NOW() - (INTERVAL '30 minutes') + (step * INTERVAL '36 seconds')
FROM generate_series(0, 49) AS step;

-- Minibus 03 — currently idle (tiny position variance)
INSERT INTO positions (asset_id, location, speed, heading, battery, recorded_at)
SELECT
  'a0000001-0000-0000-0000-000000000003',
  ST_MakePoint(
    0.0050 + (RANDOM() * 0.00008 - 0.00004),   -- tiny variance (GPS drift simulation)
    5.6350 + (RANDOM() * 0.00008 - 0.00004)
  )::GEOGRAPHY,
  (RANDOM() * 1.5)::NUMERIC(6,2),              -- nearly zero speed
  (RANDOM() * 360)::NUMERIC(5,2),
  (75 - step * 0.05)::INT,
  NOW() - (INTERVAL '30 minutes') + (step * INTERVAL '36 seconds')
FROM generate_series(0, 49) AS step;

-- Flatbed 04 — moving through Tema Industrial Area
INSERT INTO positions (asset_id, location, speed, heading, battery, recorded_at)
SELECT
  'a0000001-0000-0000-0000-000000000004',
  ST_MakePoint(
    -0.0100 + (step * 0.0004) + (RANDOM() * 0.0001 - 0.00005),
    5.6350  + (RANDOM() * 0.0001 - 0.00005)
  )::GEOGRAPHY,
  20 + (RANDOM() * 15)::NUMERIC(6,2),          -- slower, heavy vehicle
  90 + (RANDOM() * 5)::NUMERIC(5,2),
  (82 - step * 0.07)::INT,
  NOW() - (INTERVAL '30 minutes') + (step * INTERVAL '36 seconds')
FROM generate_series(0, 49) AS step;

-- Utility Van 05 — stale (last ping > 2 min ago, stopped updating)
INSERT INTO positions (asset_id, location, speed, heading, battery, recorded_at)
SELECT
  'a0000001-0000-0000-0000-000000000005',
  ST_MakePoint(
    -0.1940 + (step * 0.0002),
    5.6480  + (step * 0.0001)
  )::GEOGRAPHY,
  30 + (RANDOM() * 20)::NUMERIC(6,2),
  45 + (RANDOM() * 10)::NUMERIC(5,2),
  (45 - step * 0.3)::INT,                      -- low battery (caused stale)
  NOW() - (INTERVAL '30 minutes') + (step * INTERVAL '30 seconds')
FROM generate_series(0, 39) AS step;  -- Only 40 points, last one was >5 min ago

-- Kofi Mensah (Worker) — walking pace near Tema
INSERT INTO positions (asset_id, location, speed, heading, battery, recorded_at)
SELECT
  'a0000002-0000-0000-0000-000000000006',
  ST_MakePoint(
    -0.0050 + (step * 0.00005) + (RANDOM() * 0.00003 - 0.000015),
    5.6420  + (step * 0.00003) + (RANDOM() * 0.00003 - 0.000015)
  )::GEOGRAPHY,
  3 + (RANDOM() * 3)::NUMERIC(6,2),            -- walking speed 3–6 km/h
  (RANDOM() * 360)::NUMERIC(5,2),
  (65 - step * 0.2)::INT,
  NOW() - (INTERVAL '30 minutes') + (step * INTERVAL '36 seconds')
FROM generate_series(0, 49) AS step;

-- Ama Owusu (Worker) — at site, slight movement
INSERT INTO positions (asset_id, location, speed, heading, battery, recorded_at)
SELECT
  'a0000002-0000-0000-0000-000000000007',
  ST_MakePoint(
    0.0030 + (RANDOM() * 0.00015 - 0.000075),
    5.6310 + (RANDOM() * 0.00015 - 0.000075)
  )::GEOGRAPHY,
  1.5 + (RANDOM() * 2.5)::NUMERIC(6,2),
  (RANDOM() * 360)::NUMERIC(5,2),
  (78 - step * 0.15)::INT,
  NOW() - (INTERVAL '30 minutes') + (step * INTERVAL '36 seconds')
FROM generate_series(0, 49) AS step;

-- Kwame Asante (Worker) — idle at depot
INSERT INTO positions (asset_id, location, speed, heading, battery, recorded_at)
SELECT
  'a0000002-0000-0000-0000-000000000008',
  ST_MakePoint(
    -0.2000 + (RANDOM() * 0.00006 - 0.00003),
    5.5470  + (RANDOM() * 0.00006 - 0.00003)
  )::GEOGRAPHY,
  (RANDOM() * 0.8)::NUMERIC(6,2),
  (RANDOM() * 360)::NUMERIC(5,2),
  (91 - step * 0.05)::INT,
  NOW() - (INTERVAL '30 minutes') + (step * INTERVAL '36 seconds')
FROM generate_series(0, 49) AS step;

-- Generator Set A (Equipment) — stationary at site (minimal drift)
INSERT INTO positions (asset_id, location, speed, heading, battery, recorded_at)
SELECT
  'a0000003-0000-0000-0000-000000000009',
  ST_MakePoint(
    -0.0150 + (RANDOM() * 0.00004 - 0.00002),
    5.6480  + (RANDOM() * 0.00004 - 0.00002)
  )::GEOGRAPHY,
  0::NUMERIC(6,2),
  0::NUMERIC(5,2),
  (55 - step * 0.5)::INT,                      -- generator has separate battery tracker
  NOW() - (INTERVAL '30 minutes') + (step * INTERVAL '36 seconds')
FROM generate_series(0, 49) AS step;

-- Survey Drone B (Equipment) — offline (last positions from 45 minutes ago)
INSERT INTO positions (asset_id, location, speed, heading, battery, recorded_at)
SELECT
  'a0000003-0000-0000-0000-000000000010',
  ST_MakePoint(
    -0.1850 + (step * 0.0005),
    5.6100  + (step * 0.0003)
  )::GEOGRAPHY,
  25 + (RANDOM() * 10)::NUMERIC(6,2),
  (RANDOM() * 360)::NUMERIC(5,2),
  (step * 2)::INT,                              -- was charging, then went offline
  NOW() - (INTERVAL '75 minutes') + (step * INTERVAL '60 seconds')
FROM generate_series(0, 29) AS step;            -- 30 points ending 45 min ago

-- =============================================================================
-- GEOFENCE MEMBERSHIPS
-- Seed current memberships based on where assets are seeded
-- =============================================================================

-- Flatbed 04 is inside Tema Industrial Area
INSERT INTO geofence_memberships (asset_id, geofence_id, entered_at)
VALUES (
  'a0000001-0000-0000-0000-000000000004',
  'f0000001-0000-0000-0000-000000000002',
  NOW() - INTERVAL '22 minutes'
);

-- Kofi Mensah is inside Tema Industrial Area
INSERT INTO geofence_memberships (asset_id, geofence_id, entered_at)
VALUES (
  'a0000002-0000-0000-0000-000000000006',
  'f0000001-0000-0000-0000-000000000002',
  NOW() - INTERVAL '28 minutes'
);

-- =============================================================================
-- SAMPLE ALERTS
-- =============================================================================

INSERT INTO alerts (
  id, asset_id, geofence_id, related_asset_id,
  type, severity, message, is_read,
  location_at_event, created_at
) VALUES
  -- Geofence breach alert (read)
  (
    gen_random_uuid(),
    'a0000001-0000-0000-0000-000000000001',
    'f0000001-0000-0000-0000-000000000001',
    NULL,
    'GEOFENCE_ENTER',
    'WARNING',
    'Cargo Van 01 entered Kotoka Airport Zone',
    true,
    ST_MakePoint(-0.1685, 5.6020)::GEOGRAPHY,
    NOW() - INTERVAL '45 minutes'
  ),
  -- Geofence exit alert (read)
  (
    gen_random_uuid(),
    'a0000001-0000-0000-0000-000000000001',
    'f0000001-0000-0000-0000-000000000001',
    NULL,
    'GEOFENCE_EXIT',
    'WARNING',
    'Cargo Van 01 exited Kotoka Airport Zone',
    true,
    ST_MakePoint(-0.1720, 5.6050)::GEOGRAPHY,
    NOW() - INTERVAL '38 minutes'
  ),
  -- Proximity warning (unread — will show in alert feed)
  (
    gen_random_uuid(),
    'a0000001-0000-0000-0000-000000000004',
    NULL,
    'a0000002-0000-0000-0000-000000000006',
    'PROXIMITY_WARNING',
    'CRITICAL',
    'Flatbed 04 is within 32m of Kofi Mensah. Reduce speed immediately.',
    false,
    ST_MakePoint(-0.0070, 5.6420)::GEOGRAPHY,
    NOW() - INTERVAL '8 minutes'
  ),
  -- Low battery alert (unread)
  (
    gen_random_uuid(),
    'a0000001-0000-0000-0000-000000000005',
    NULL,
    NULL,
    'LOW_BATTERY',
    'WARNING',
    'Utility Van 05 battery at 18%. Consider returning to depot for charging.',
    false,
    NULL,
    NOW() - INTERVAL '15 minutes'
  ),
  -- Offline alert (unread)
  (
    gen_random_uuid(),
    'a0000003-0000-0000-0000-000000000010',
    NULL,
    NULL,
    'OFFLINE',
    'CRITICAL',
    'Survey Drone B has gone offline. Last known position: Accra Central.',
    false,
    ST_MakePoint(-0.1765, 5.6175)::GEOGRAPHY,
    NOW() - INTERVAL '40 minutes'
  ),
  -- Idle timeout alert (unread)
  (
    gen_random_uuid(),
    'a0000001-0000-0000-0000-000000000003',
    NULL,
    NULL,
    'IDLE_TIMEOUT',
    'INFO',
    'Minibus 03 has been idle for 18 minutes at Tema.',
    false,
    ST_MakePoint(0.0052, 5.6352)::GEOGRAPHY,
    NOW() - INTERVAL '12 minutes'
  ),
  -- Speed anomaly alert (read)
  (
    gen_random_uuid(),
    'a0000001-0000-0000-0000-000000000002',
    NULL,
    NULL,
    'SPEED_ANOMALY',
    'WARNING',
    'Pickup Truck 02 — GPS anomaly detected. Implied speed 312 km/h. Position skipped.',
    true,
    NULL,
    NOW() - INTERVAL '25 minutes'
  ),
  -- Geofence entry for Flatbed in Tema (unread)
  (
    gen_random_uuid(),
    'a0000001-0000-0000-0000-000000000004',
    'f0000001-0000-0000-0000-000000000002',
    NULL,
    'GEOFENCE_ENTER',
    'INFO',
    'Flatbed 04 entered Tema Industrial Area',
    false,
    ST_MakePoint(-0.0195, 5.6352)::GEOGRAPHY,
    NOW() - INTERVAL '22 minutes'
  );

-- =============================================================================
-- VERIFICATION
-- =============================================================================

DO $$
DECLARE
  asset_count   INT;
  position_count BIGINT;
  geofence_count INT;
  alert_count   INT;
  api_key_count INT;
BEGIN
  SELECT COUNT(*) INTO asset_count    FROM assets;
  SELECT COUNT(*) INTO position_count FROM positions;
  SELECT COUNT(*) INTO geofence_count FROM geofences;
  SELECT COUNT(*) INTO alert_count    FROM alerts;
  SELECT COUNT(*) INTO api_key_count  FROM api_keys;

  RAISE NOTICE '005_seed.sql complete:';
  RAISE NOTICE '  Assets:    %', asset_count;
  RAISE NOTICE '  Positions: %', position_count;
  RAISE NOTICE '  Geofences: %', geofence_count;
  RAISE NOTICE '  Alerts:    %', alert_count;
  RAISE NOTICE '  API Keys:  %', api_key_count;

  -- Verify spatial data
  PERFORM 1 FROM geofences WHERE boundary IS NULL;
  IF FOUND THEN
    RAISE WARNING 'Some geofences have NULL boundary — spatial queries will skip them';
  ELSE
    RAISE NOTICE '  Geofence boundaries: all set';
  END IF;

  PERFORM 1 FROM positions WHERE location IS NULL LIMIT 1;
  IF FOUND THEN
    RAISE WARNING 'Some positions have NULL location';
  ELSE
    RAISE NOTICE '  Position locations: all set';
  END IF;
END
$$;

COMMIT;
