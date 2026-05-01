-- =============================================================================
-- GeoSentinel Migration 004: Constraints, Triggers, Functions & Views
-- =============================================================================
-- Adds:
--   - Additional CHECK constraints beyond what Prisma generates
--   - Trigger: auto-update assets.updated_at
--   - Trigger: auto-update assets.status based on last position time
--   - Trigger: prevent hard deletes on assets (enforce soft delete)
--   - Function: get_latest_position(asset_id) → most recent non-drift position
--   - Function: compute_asset_speed(asset_id) → speed between last 2 positions
--   - Function: check_geofence_membership() → called by NestJS service
--   - View: v_assets_live → assets joined with latest position (used by GET /assets)
--   - View: v_fleet_summary → aggregate counts for FleetStatusBar
--   - View: v_active_alerts → unread alerts with asset + geofence names
--   - Singleton enforcement on system_settings
-- =============================================================================

BEGIN;

-- =============================================================================
-- ADDITIONAL CONSTRAINTS
-- =============================================================================

-- Geofence area must be positive when set
ALTER TABLE geofences DROP CONSTRAINT IF EXISTS geofences_area_positive;
ALTER TABLE geofences
  ADD CONSTRAINT geofences_area_positive
  CHECK (area_km2 IS NULL OR area_km2 > 0);

-- Geofence area limit: max 500 km²
ALTER TABLE geofences DROP CONSTRAINT IF EXISTS geofences_area_limit;
ALTER TABLE geofences
  ADD CONSTRAINT geofences_area_limit
  CHECK (area_km2 IS NULL OR area_km2 <= 500);

-- Geofence opacity must be 0.0 to 1.0
ALTER TABLE geofences DROP CONSTRAINT IF EXISTS geofences_opacity_range;
ALTER TABLE geofences
  ADD CONSTRAINT geofences_opacity_range
  CHECK (opacity >= 0 AND opacity <= 1);

-- Alert distance must be positive
ALTER TABLE alerts DROP CONSTRAINT IF EXISTS alerts_distance_positive;
ALTER TABLE alerts
  ADD CONSTRAINT alerts_distance_positive
  CHECK (distance_metres IS NULL OR distance_metres >= 0);

-- Singleton enforcement on system_settings — only one row allowed ever
ALTER TABLE system_settings DROP CONSTRAINT IF EXISTS system_settings_singleton;
ALTER TABLE system_settings
  ADD CONSTRAINT system_settings_singleton
  CHECK (id = 1);

-- Asset color must be valid hex
ALTER TABLE assets DROP CONSTRAINT IF EXISTS assets_color_hex;
ALTER TABLE assets
  ADD CONSTRAINT assets_color_hex
  CHECK (color ~ '^#[0-9A-Fa-f]{6}$');

-- Geofence color must be valid hex
ALTER TABLE geofences DROP CONSTRAINT IF EXISTS geofences_color_hex;
ALTER TABLE geofences
  ADD CONSTRAINT geofences_color_hex
  CHECK (color ~ '^#[0-9A-Fa-f]{6}$' AND stroke_color ~ '^#[0-9A-Fa-f]{6}$');

-- API key: expires_at must be in the future if set
-- (Enforced at application layer, not DB — allows importing historical keys)

-- Rate limit must be positive
ALTER TABLE api_keys DROP CONSTRAINT IF EXISTS api_keys_rate_limit_positive;
ALTER TABLE api_keys
  ADD CONSTRAINT api_keys_rate_limit_positive
  CHECK (rate_limit_per_minute > 0);

-- =============================================================================
-- TRIGGER: Auto-update assets.updated_at
-- =============================================================================

CREATE OR REPLACE FUNCTION trigger_set_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;

-- Apply to all tables with updated_at (Prisma's @updatedAt doesn't use triggers)
DROP TRIGGER IF EXISTS set_assets_updated_at ON assets;
CREATE TRIGGER set_assets_updated_at
  BEFORE INSERT OR UPDATE ON assets
  FOR EACH ROW
  EXECUTE FUNCTION trigger_set_updated_at();

DROP TRIGGER IF EXISTS set_geofences_updated_at ON geofences;
CREATE TRIGGER set_geofences_updated_at
  BEFORE INSERT OR UPDATE ON geofences
  FOR EACH ROW
  EXECUTE FUNCTION trigger_set_updated_at();

DROP TRIGGER IF EXISTS set_asset_settings_updated_at ON asset_settings;
CREATE TRIGGER set_asset_settings_updated_at
  BEFORE INSERT OR UPDATE ON asset_settings
  FOR EACH ROW
  EXECUTE FUNCTION trigger_set_updated_at();

DROP TRIGGER IF EXISTS set_system_settings_updated_at ON system_settings;
CREATE TRIGGER set_system_settings_updated_at
  BEFORE INSERT OR UPDATE ON system_settings
  FOR EACH ROW
  EXECUTE FUNCTION trigger_set_updated_at();

-- =============================================================================
-- TRIGGER: Prevent hard deletes on assets (enforce soft delete only)
-- =============================================================================

CREATE OR REPLACE FUNCTION prevent_asset_hard_delete()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  RAISE EXCEPTION
    'Hard delete on assets is not allowed. Use soft delete: UPDATE assets SET is_deleted = true WHERE id = %',
    OLD.id;
  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS enforce_soft_delete_assets ON assets;
CREATE TRIGGER enforce_soft_delete_assets
  BEFORE DELETE ON assets
  FOR EACH ROW
  EXECUTE FUNCTION prevent_asset_hard_delete();

-- =============================================================================
-- TRIGGER: Auto-create AssetSettings when Asset is created
-- =============================================================================

CREATE OR REPLACE FUNCTION create_asset_settings_on_insert()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  INSERT INTO asset_settings (id, asset_id)
  VALUES (gen_random_uuid(), NEW.id)
  ON CONFLICT (asset_id) DO NOTHING;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS auto_create_asset_settings ON assets;
CREATE TRIGGER auto_create_asset_settings
  AFTER INSERT ON assets
  FOR EACH ROW
  EXECUTE FUNCTION create_asset_settings_on_insert();

-- =============================================================================
-- TRIGGER: Set alert read_at timestamp when is_read is set to true
-- =============================================================================

CREATE OR REPLACE FUNCTION set_alert_read_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.is_read = true AND OLD.is_read = false THEN
    NEW.read_at = NOW();
  END IF;
  IF NEW.is_read = false THEN
    NEW.read_at = NULL;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS set_alert_read_timestamp ON alerts;
CREATE TRIGGER set_alert_read_timestamp
  BEFORE UPDATE ON alerts
  FOR EACH ROW
  EXECUTE FUNCTION set_alert_read_at();

-- =============================================================================
-- FUNCTION: get_latest_position(asset_id)
-- Returns the most recent non-drift, non-suspect position for an asset.
-- Used by: geofence checks, proximity checks, asset live state queries.
-- =============================================================================

CREATE OR REPLACE FUNCTION get_latest_position(p_asset_id UUID)
RETURNS TABLE (
  id          BIGINT,
  location    GEOGRAPHY,
  speed       NUMERIC,
  heading     NUMERIC,
  battery     SMALLINT,
  recorded_at TIMESTAMPTZ
)
LANGUAGE sql
STABLE  -- Same inputs always return same outputs within a transaction
AS $$
  SELECT
    id,
    location,
    speed,
    heading,
    battery,
    recorded_at
  FROM positions
  WHERE asset_id = p_asset_id
    AND is_drift = false
    AND is_suspect = false
  ORDER BY recorded_at DESC
  LIMIT 1;
$$;

-- =============================================================================
-- FUNCTION: get_asset_distance_metres(asset_id_a, asset_id_b)
-- Returns the current distance in metres between two assets' latest positions.
-- Used by: proximity alert checks.
-- =============================================================================

CREATE OR REPLACE FUNCTION get_asset_distance_metres(
  p_asset_id_a UUID,
  p_asset_id_b UUID
)
RETURNS NUMERIC
LANGUAGE sql
STABLE
AS $$
  SELECT ST_Distance(a.location, b.location)
  FROM get_latest_position(p_asset_id_a) a,
       get_latest_position(p_asset_id_b) b;
$$;

-- =============================================================================
-- FUNCTION: check_geofence_memberships(asset_id, lat, lng)
-- Returns which geofences the asset is NOW inside.
-- NestJS service compares this against geofence_memberships table to
-- detect enter/exit events.
-- =============================================================================

CREATE OR REPLACE FUNCTION check_geofence_memberships(
  p_asset_id UUID,
  p_lat      DOUBLE PRECISION,
  p_lng      DOUBLE PRECISION
)
RETURNS TABLE (
  geofence_id   UUID,
  geofence_name TEXT,
  alert_mode    TEXT
)
LANGUAGE sql
STABLE
AS $$
  SELECT
    g.id,
    g.name,
    g.alert_mode::TEXT
  FROM geofences g
  WHERE g.is_active = true
    AND g.is_deleted = false
    AND g.boundary IS NOT NULL
    AND ST_Covers(
      g.boundary::GEOMETRY,
      ST_MakePoint(p_lng, p_lat)::GEOMETRY
    );
$$;

-- =============================================================================
-- FUNCTION: check_proximity_alerts(asset_id, lat, lng, threshold_metres)
-- Returns all OTHER assets within threshold_metres of the given position.
-- Uses ST_DWithin on GEOGRAPHY type → real metres, no projection needed.
-- =============================================================================

CREATE OR REPLACE FUNCTION check_proximity_alerts(
  p_asset_id        UUID,
  p_lat             DOUBLE PRECISION,
  p_lng             DOUBLE PRECISION,
  p_threshold_metres INT DEFAULT 50
)
RETURNS TABLE (
  nearby_asset_id   UUID,
  nearby_asset_name TEXT,
  nearby_asset_type TEXT,
  distance_metres   NUMERIC
)
LANGUAGE sql
STABLE
AS $$
  SELECT
    a.id,
    a.name,
    a.type::TEXT,
    ROUND(ST_Distance(
      latest.location,
      ST_MakePoint(p_lng, p_lat)::GEOGRAPHY
    )::NUMERIC, 2) AS distance_metres
  FROM assets a
  CROSS JOIN LATERAL get_latest_position(a.id) AS latest
  WHERE a.id != p_asset_id
    AND a.is_deleted = false
    AND a.status != 'OFFLINE'
    AND latest.location IS NOT NULL
    AND latest.recorded_at > NOW() - INTERVAL '5 minutes'  -- Only recently active assets
    AND ST_DWithin(
      latest.location,
      ST_MakePoint(p_lng, p_lat)::GEOGRAPHY,
      p_threshold_metres
    )
  ORDER BY distance_metres ASC;
$$;

-- =============================================================================
-- FUNCTION: get_asset_route_geojson(asset_id, from_ts, to_ts)
-- Returns the full route as a GeoJSON LineString for the replay feature.
-- Uses ST_MakeLine to construct from ordered position points.
-- =============================================================================

CREATE OR REPLACE FUNCTION get_asset_route_geojson(
  p_asset_id UUID,
  p_from     TIMESTAMPTZ,
  p_to       TIMESTAMPTZ
)
RETURNS TEXT
LANGUAGE sql
STABLE
AS $$
  SELECT ST_AsGeoJSON(
    ST_MakeLine(
      location::GEOMETRY
      ORDER BY recorded_at ASC
    )
  )
  FROM positions
  WHERE asset_id = p_asset_id
    AND recorded_at BETWEEN p_from AND p_to
    AND is_drift = false
    AND is_suspect = false
    AND location IS NOT NULL;
$$;

-- =============================================================================
-- FUNCTION: get_asset_total_distance_km(asset_id, from_ts, to_ts)
-- Returns total distance travelled in km over a time range.
-- Uses ST_Length on the constructed route LineString.
-- GEOGRAPHY type → result is in metres → divide by 1000 for km.
-- =============================================================================

CREATE OR REPLACE FUNCTION get_asset_total_distance_km(
  p_asset_id UUID,
  p_from     TIMESTAMPTZ,
  p_to       TIMESTAMPTZ
)
RETURNS NUMERIC
LANGUAGE sql
STABLE
AS $$
  SELECT ROUND(
    (ST_Length(
      ST_MakeLine(
        location::GEOMETRY
        ORDER BY recorded_at ASC
      )::GEOGRAPHY
    ) / 1000.0)::NUMERIC,
    3
  )
  FROM positions
  WHERE asset_id = p_asset_id
    AND recorded_at BETWEEN p_from AND p_to
    AND is_drift = false
    AND is_suspect = false
    AND location IS NOT NULL;
$$;

-- =============================================================================
-- FUNCTION: validate_position_ingestion(asset_id, lat, lng, speed, recorded_at)
-- Returns flags for drift and suspect detection.
-- Called by NestJS PositionsService before inserting a position.
-- Computes displacement and implied speed from previous position.
-- =============================================================================

CREATE OR REPLACE FUNCTION validate_position_ingestion(
  p_asset_id   UUID,
  p_lat        DOUBLE PRECISION,
  p_lng        DOUBLE PRECISION,
  p_speed      NUMERIC,
  p_recorded_at TIMESTAMPTZ
)
RETURNS TABLE (
  is_drift          BOOLEAN,
  is_suspect        BOOLEAN,
  displacement_m    NUMERIC,
  implied_speed_kmh NUMERIC,
  seconds_since_last INT
)
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  v_last_location   GEOGRAPHY;
  v_last_time       TIMESTAMPTZ;
  v_displacement_m  NUMERIC := 0;
  v_time_diff_s     INT := 0;
  v_implied_speed   NUMERIC := 0;
  v_is_drift        BOOLEAN := false;
  v_is_suspect      BOOLEAN := false;
  v_new_point       GEOGRAPHY;
BEGIN
  -- Get last clean position
  SELECT location, recorded_at
  INTO v_last_location, v_last_time
  FROM positions
  WHERE asset_id = p_asset_id
    AND is_drift = false
    AND is_suspect = false
    AND location IS NOT NULL
  ORDER BY recorded_at DESC
  LIMIT 1;

  -- Build new point
  v_new_point := ST_MakePoint(p_lng, p_lat)::GEOGRAPHY;

  IF v_last_location IS NOT NULL THEN
    -- Calculate displacement in metres (GEOGRAPHY → real metres)
    v_displacement_m := ST_Distance(v_last_location, v_new_point);

    -- Calculate time difference in seconds
    v_time_diff_s := EXTRACT(EPOCH FROM (p_recorded_at - v_last_time))::INT;

    -- Compute implied speed (km/h) from displacement and time
    IF v_time_diff_s > 0 THEN
      v_implied_speed := ROUND(((v_displacement_m / v_time_diff_s) * 3.6)::NUMERIC, 2);
    END IF;

    -- Drift detection: tiny displacement + very low speed
    -- GPS noise causes <10m variation even when stationary
    IF v_displacement_m < 10 AND (p_speed IS NULL OR p_speed < 2) THEN
      v_is_drift := true;
    END IF;

    -- Anomaly detection: implied speed physically impossible
    -- 250 km/h covers even high-speed rail/aircraft edge cases
    IF v_implied_speed > 250 AND v_time_diff_s > 0 THEN
      v_is_suspect := true;
    END IF;
  END IF;

  RETURN QUERY SELECT
    v_is_drift,
    v_is_suspect,
    ROUND(v_displacement_m::NUMERIC, 2),
    v_implied_speed,
    v_time_diff_s;
END;
$$;

-- =============================================================================
-- VIEW: v_assets_live
-- Assets joined with their latest position — the primary query for GET /assets.
-- Using LATERAL JOIN to efficiently get latest position per asset.
-- =============================================================================

CREATE OR REPLACE VIEW v_assets_live AS
SELECT
  a.id,
  a.name,
  a.type,
  a.status,
  a.description,
  a.identifier,
  a.color,
  a.is_deleted,
  a.created_at,
  a.updated_at,

  -- Latest position fields (NULL if no positions yet)
  latest.location,
  ST_Y(latest.location::GEOMETRY)   AS lat,
  ST_X(latest.location::GEOMETRY)   AS lng,
  latest.speed,
  latest.heading,
  latest.battery,
  latest.recorded_at                 AS last_seen_at,

  -- Time since last ping (useful for stale detection UI)
  EXTRACT(EPOCH FROM (NOW() - latest.recorded_at))::INT AS seconds_since_last_ping,

  -- Count of unread alerts for this asset
  (
    SELECT COUNT(*)
    FROM alerts al
    WHERE al.asset_id = a.id
      AND al.is_read = false
  ) AS unread_alert_count

FROM assets a
LEFT JOIN LATERAL (
  SELECT
    location,
    speed,
    heading,
    battery,
    recorded_at
  FROM positions p
  WHERE p.asset_id = a.id
    AND p.is_drift = false
    AND p.is_suspect = false
    AND p.location IS NOT NULL
  ORDER BY p.recorded_at DESC
  LIMIT 1
) latest ON true
WHERE a.is_deleted = false;

-- =============================================================================
-- VIEW: v_fleet_summary
-- Single-row aggregate for the FleetStatusBar component.
-- Updated on every query — no caching needed (fast aggregate on indexed columns).
-- =============================================================================

CREATE OR REPLACE VIEW v_fleet_summary AS
SELECT
  COUNT(*) FILTER (WHERE status = 'ACTIVE')   AS active_count,
  COUNT(*) FILTER (WHERE status = 'IDLE')     AS idle_count,
  COUNT(*) FILTER (WHERE status = 'STALE')    AS stale_count,
  COUNT(*) FILTER (WHERE status = 'OFFLINE')  AS offline_count,
  COUNT(*)                                     AS total_count,

  -- Assets with unread critical alerts
  COUNT(*) FILTER (
    WHERE EXISTS (
      SELECT 1 FROM alerts al
      WHERE al.asset_id = assets.id
        AND al.is_read = false
        AND al.severity = 'CRITICAL'
    )
  ) AS critical_alert_count,

  -- Total unread alerts across fleet
  (SELECT COUNT(*) FROM alerts WHERE is_read = false) AS total_unread_alerts

FROM assets
WHERE is_deleted = false;

-- =============================================================================
-- VIEW: v_active_alerts
-- Unread alerts enriched with asset and geofence names.
-- Used by AlertFeed component — no joins needed in application code.
-- =============================================================================

CREATE OR REPLACE VIEW v_active_alerts AS
SELECT
  al.id,
  al.type,
  al.severity,
  al.message,
  al.is_read,
  al.distance_metres,
  al.computed_speed_kmh,
  al.created_at,

  -- Alert location for map flyTo
  ST_Y(al.location_at_event::GEOMETRY)  AS alert_lat,
  ST_X(al.location_at_event::GEOMETRY)  AS alert_lng,

  -- Asset info
  a.id    AS asset_id,
  a.name  AS asset_name,
  a.type  AS asset_type,
  a.color AS asset_color,

  -- Geofence info (NULL for non-geofence alerts)
  g.id    AS geofence_id,
  g.name  AS geofence_name,
  g.color AS geofence_color,

  -- Related asset info (NULL for non-proximity alerts)
  ra.id   AS related_asset_id,
  ra.name AS related_asset_name,
  ra.type AS related_asset_type

FROM alerts al
JOIN assets a ON a.id = al.asset_id
LEFT JOIN geofences g ON g.id = al.geofence_id
LEFT JOIN assets ra ON ra.id = al.related_asset_id
WHERE al.is_read = false
ORDER BY
  -- Critical alerts always first
  CASE al.severity
    WHEN 'CRITICAL' THEN 1
    WHEN 'WARNING'  THEN 2
    WHEN 'INFO'     THEN 3
  END,
  al.created_at DESC;

-- =============================================================================
-- VIEW: v_geofence_occupancy
-- Each geofence with its current occupancy count and asset list.
-- =============================================================================

CREATE OR REPLACE VIEW v_geofence_occupancy AS
SELECT
  g.id,
  g.name,
  g.description,
  g.color,
  g.stroke_color,
  g.area_km2,
  g.alert_mode,
  g.is_active,
  g.created_at,

  -- Current occupancy
  COUNT(gm.asset_id) AS asset_count,

  -- JSON array of assets currently inside
  COALESCE(
    JSON_AGG(
      JSON_BUILD_OBJECT(
        'id',   a.id,
        'name', a.name,
        'type', a.type
      )
    ) FILTER (WHERE a.id IS NOT NULL),
    '[]'::JSON
  ) AS assets_inside

FROM geofences g
LEFT JOIN geofence_memberships gm ON gm.geofence_id = g.id
LEFT JOIN assets a ON a.id = gm.asset_id AND a.is_deleted = false
WHERE g.is_deleted = false
GROUP BY g.id, g.name, g.description, g.color, g.stroke_color,
         g.area_km2, g.alert_mode, g.is_active, g.created_at;

-- =============================================================================
-- INITIAL SYSTEM SETTINGS ROW (singleton)
-- =============================================================================

INSERT INTO system_settings (id, updated_at)
VALUES (1, NOW())
ON CONFLICT (id) DO NOTHING;

-- =============================================================================
-- VERIFICATION
-- =============================================================================

DO $$
DECLARE
  trigger_count INT;
  function_count INT;
  view_count INT;
BEGIN
  SELECT COUNT(*) INTO trigger_count
  FROM information_schema.triggers
  WHERE trigger_schema = 'public';

  SELECT COUNT(*) INTO function_count
  FROM information_schema.routines
  WHERE routine_schema = 'public'
    AND routine_type = 'FUNCTION';

  SELECT COUNT(*) INTO view_count
  FROM information_schema.views
  WHERE table_schema = 'public';

  RAISE NOTICE '004_functions_views.sql: % triggers, % functions, % views created.',
    trigger_count, function_count, view_count;
END
$$;

COMMIT;
