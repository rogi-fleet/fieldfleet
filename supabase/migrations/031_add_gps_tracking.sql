-- Migration: Add GPS tracking and geofencing support for time entries
-- Created: 2026-02-08

-- ============================================================================
-- GPS TRACKING FOR TIME ENTRIES
-- ============================================================================

-- Add GPS coordinate columns to time_entries table
ALTER TABLE time_entries
ADD COLUMN IF NOT EXISTS clock_in_latitude DECIMAL(10, 8),
ADD COLUMN IF NOT EXISTS clock_in_longitude DECIMAL(11, 8),
ADD COLUMN IF NOT EXISTS clock_out_latitude DECIMAL(10, 8),
ADD COLUMN IF NOT EXISTS clock_out_longitude DECIMAL(11, 8),
ADD COLUMN IF NOT EXISTS location_accuracy DECIMAL(8, 2),
ADD COLUMN IF NOT EXISTS distance_from_project DECIMAL(10, 2);

-- Add index for efficient location-based queries
CREATE INDEX IF NOT EXISTS idx_time_entries_location ON time_entries(clock_in_latitude, clock_in_longitude)
WHERE clock_in_latitude IS NOT NULL;

-- ============================================================================
-- GEOFENCING FOR PROJECTS
-- ============================================================================

-- Add geofencing columns to projects table
ALTER TABLE projects
ADD COLUMN IF NOT EXISTS geofence_radius_meters INTEGER DEFAULT 500,
ADD COLUMN IF NOT EXISTS require_geofence_validation BOOLEAN DEFAULT FALSE,
ADD COLUMN IF NOT EXISTS allow_clock_in_outside_geofence BOOLEAN DEFAULT TRUE;

-- Add index for geofence queries
CREATE INDEX IF NOT EXISTS idx_projects_geofence ON projects(geofence_radius_meters)
WHERE geofence_radius_meters IS NOT NULL;

-- ============================================================================
-- GEOFENCING FOR WORKSPACES (GLOBAL SETTINGS)
-- ============================================================================

-- Add workspace-level geofencing settings
ALTER TABLE workspaces
ADD COLUMN IF NOT EXISTS default_geofence_radius_meters INTEGER DEFAULT 500,
ADD COLUMN IF NOT EXISTS enforce_geofencing BOOLEAN DEFAULT FALSE,
ADD COLUMN IF NOT EXISTS allow_clock_in_without_location BOOLEAN DEFAULT TRUE;

-- ============================================================================
-- LOCATION AUDIT LOG
-- ============================================================================

-- Create table for location validation audits
CREATE TABLE IF NOT EXISTS time_entry_location_audits (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  time_entry_id UUID NOT NULL REFERENCES time_entries(id) ON DELETE CASCADE,
  workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
  project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  worker_id UUID NOT NULL REFERENCES users(id),

  -- Location data at time of validation
  worker_latitude DECIMAL(10, 8),
  worker_longitude DECIMAL(11, 8),
  project_latitude DECIMAL(10, 8),
  project_longitude DECIMAL(11, 8),
  distance_meters DECIMAL(10, 2),
  geofence_radius_meters INTEGER,

  -- Validation result
  is_within_geofence BOOLEAN,
  validation_type VARCHAR(20) CHECK (validation_type IN ('clock_in', 'clock_out', 'manual')),

  -- If validation was bypassed
  bypassed BOOLEAN DEFAULT FALSE,
  bypass_reason TEXT,
  bypassed_by UUID REFERENCES users(id),

  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Create indexes for location audit queries
CREATE INDEX IF NOT EXISTS idx_location_audits_time_entry ON time_entry_location_audits(time_entry_id);
CREATE INDEX IF NOT EXISTS idx_location_audits_workspace ON time_entry_location_audits(workspace_id);
CREATE INDEX IF NOT EXISTS idx_location_audits_project ON time_entry_location_audits(project_id);
CREATE INDEX IF NOT EXISTS idx_location_audits_worker ON time_entry_location_audits(worker_id);
CREATE INDEX IF NOT EXISTS idx_location_audits_created ON time_entry_location_audits(created_at);

-- Enable RLS on location audits
ALTER TABLE time_entry_location_audits ENABLE ROW LEVEL SECURITY;

-- RLS Policies for location audits
DROP POLICY IF EXISTS time_entry_location_audits_select ON time_entry_location_audits;
CREATE POLICY time_entry_location_audits_select ON time_entry_location_audits
  FOR SELECT USING (
    worker_id = auth.uid() OR
    is_pm_or_admin(workspace_id)
  );

DROP POLICY IF EXISTS time_entry_location_audits_insert ON time_entry_location_audits;
CREATE POLICY time_entry_location_audits_insert ON time_entry_location_audits
  FOR INSERT WITH CHECK (
    is_workspace_member(workspace_id) AND
    worker_id = auth.uid()
  );

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

-- Function to calculate distance between two coordinates in meters using Haversine formula
CREATE OR REPLACE FUNCTION calculate_distance_meters(
  lat1 DECIMAL(10, 8),
  lon1 DECIMAL(11, 8),
  lat2 DECIMAL(10, 8),
  lon2 DECIMAL(11, 8)
)
RETURNS DECIMAL(10, 2) AS $$
DECLARE
  R DECIMAL := 6371000; -- Earth's radius in meters
  dLat DECIMAL;
  dLon DECIMAL;
  a DECIMAL;
  c DECIMAL;
BEGIN
  -- Convert to radians
  dLat := RADIANS(lat2 - lat1);
  dLon := RADIANS(lon2 - lon1);

  a := SIN(dLat/2) * SIN(dLat/2) +
       COS(RADIANS(lat1)) * COS(RADIANS(lat2)) *
       SIN(dLon/2) * SIN(dLon/2);

  c := 2 * ATAN2(SQRT(a), SQRT(1-a));

  RETURN ROUND((R * c)::DECIMAL, 2);
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- Function to validate if a location is within project geofence
CREATE OR REPLACE FUNCTION is_within_project_geofence(
  worker_lat DECIMAL(10, 8),
  worker_lon DECIMAL(11, 8),
  project_id UUID
)
RETURNS TABLE (
  is_within BOOLEAN,
  distance_meters DECIMAL(10, 2),
  geofence_radius INTEGER
) AS $$
BEGIN
  RETURN QUERY
  SELECT
    CASE
      WHEN p.latitude IS NULL OR p.longitude IS NULL THEN TRUE  -- No project location set
      WHEN calculate_distance_meters(worker_lat, worker_lon, p.latitude, p.longitude) <= p.geofence_radius_meters THEN TRUE
      ELSE FALSE
    END as is_within,
    COALESCE(calculate_distance_meters(worker_lat, worker_lon, p.latitude, p.longitude), 0) as distance_meters,
    p.geofence_radius_meters
  FROM projects p
  WHERE p.id = project_id;
END;
$$ LANGUAGE plpgsql STABLE;

-- ============================================================================
-- ENABLE REALTIME FOR NEW TABLE
-- ============================================================================

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'time_entry_location_audits'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE time_entry_location_audits;
  END IF;
END $$;

-- ============================================================================
-- UPDATE TRIGGER FOR LOCATION DISTANCE
-- ============================================================================

-- Trigger to auto-calculate distance from project when coordinates are added
CREATE OR REPLACE FUNCTION update_time_entry_distance()
RETURNS TRIGGER AS $$
DECLARE
  proj_lat DECIMAL(10, 8);
  proj_lon DECIMAL(11, 8);
BEGIN
  -- Only calculate if we have clock in coordinates and project exists
  IF NEW.clock_in_latitude IS NOT NULL AND NEW.clock_in_longitude IS NOT NULL THEN
    SELECT latitude, longitude INTO proj_lat, proj_lon
    FROM projects
    WHERE id = NEW.project_id;

    IF proj_lat IS NOT NULL AND proj_lon IS NOT NULL THEN
      NEW.distance_from_project := calculate_distance_meters(
        NEW.clock_in_latitude,
        NEW.clock_in_longitude,
        proj_lat,
        proj_lon
      );
    END IF;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER update_time_entry_distance_trigger
  BEFORE INSERT OR UPDATE ON time_entries
  FOR EACH ROW
  EXECUTE FUNCTION update_time_entry_distance();
