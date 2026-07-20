-- =============================================================================
-- Vehicle expenses table + maintenance_logs mileage column repair
-- =============================================================================
-- The app (lib/services/supabase/vehicle_service.dart) queries a
-- `vehicle_expenses` table that was never created by any migration — every
-- read/write 404s. It also writes `next_maintenance_mileage` to
-- `maintenance_logs`, but migration 004 only ever added a `mileage` column,
-- so maintenance inserts 400.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1. vehicle_expenses
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS vehicle_expenses (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id   UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
  vehicle_id     UUID NOT NULL REFERENCES vehicles(id) ON DELETE CASCADE,
  date           DATE NOT NULL DEFAULT CURRENT_DATE,
  category       TEXT NOT NULL DEFAULT 'other',
  amount         NUMERIC(12,2) NOT NULL DEFAULT 0,
  description    TEXT,
  odometer       INTEGER,
  vendor         TEXT,
  attachment_url TEXT,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_vehicle_expenses_workspace
  ON vehicle_expenses(workspace_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_expenses_vehicle
  ON vehicle_expenses(vehicle_id, date DESC);

CREATE OR REPLACE TRIGGER update_vehicle_expenses_updated_at
  BEFORE UPDATE ON vehicle_expenses
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

ALTER TABLE vehicle_expenses ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Members can view vehicle expenses" ON vehicle_expenses;
CREATE POLICY "Members can view vehicle expenses"
  ON vehicle_expenses FOR SELECT
  USING (is_workspace_member(workspace_id));

DROP POLICY IF EXISTS "Members can insert vehicle expenses" ON vehicle_expenses;
CREATE POLICY "Members can insert vehicle expenses"
  ON vehicle_expenses FOR INSERT
  WITH CHECK (is_workspace_member(workspace_id));

DROP POLICY IF EXISTS "Members can update vehicle expenses" ON vehicle_expenses;
CREATE POLICY "Members can update vehicle expenses"
  ON vehicle_expenses FOR UPDATE
  USING (is_workspace_member(workspace_id));

DROP POLICY IF EXISTS "Members can delete vehicle expenses" ON vehicle_expenses;
CREATE POLICY "Members can delete vehicle expenses"
  ON vehicle_expenses FOR DELETE
  USING (is_workspace_member(workspace_id));

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'vehicle_expenses'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE vehicle_expenses;
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- 2. maintenance_logs: align mileage column name with the app
-- ---------------------------------------------------------------------------
-- Migration 004 added `mileage`; the app reads/writes `next_maintenance_mileage`.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'maintenance_logs' AND column_name = 'mileage'
  ) AND NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'maintenance_logs'
      AND column_name = 'next_maintenance_mileage'
  ) THEN
    ALTER TABLE maintenance_logs RENAME COLUMN mileage TO next_maintenance_mileage;
  END IF;
END $$;

ALTER TABLE maintenance_logs
  ADD COLUMN IF NOT EXISTS next_maintenance_mileage INTEGER;
