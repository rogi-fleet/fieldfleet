-- Migration: Workspace settings profiles for reusable workspace configuration bundles

CREATE TABLE IF NOT EXISTS workspace_settings_profiles (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  project_terminology TEXT,
  enabled_project_tabs TEXT[] NOT NULL DEFAULT '{}',
  enabled_navigation_tabs TEXT[] NOT NULL DEFAULT '{}',
  show_business_days_only BOOLEAN NOT NULL DEFAULT FALSE,
  currency_code TEXT NOT NULL DEFAULT 'USD',
  timezone TEXT NOT NULL DEFAULT 'UTC',
  hourly_rate NUMERIC,
  weekly_wage NUMERIC,
  created_by UUID REFERENCES users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT workspace_settings_profiles_workspace_name_unique UNIQUE (workspace_id, name)
);

CREATE INDEX IF NOT EXISTS idx_workspace_settings_profiles_workspace
  ON workspace_settings_profiles(workspace_id);

ALTER TABLE workspace_settings_profiles ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS workspace_settings_profiles_select ON workspace_settings_profiles;
CREATE POLICY workspace_settings_profiles_select ON workspace_settings_profiles
  FOR SELECT USING (is_workspace_member(workspace_id));

DROP POLICY IF EXISTS workspace_settings_profiles_insert ON workspace_settings_profiles;
CREATE POLICY workspace_settings_profiles_insert ON workspace_settings_profiles
  FOR INSERT WITH CHECK (is_workspace_admin(workspace_id));

DROP POLICY IF EXISTS workspace_settings_profiles_update ON workspace_settings_profiles;
CREATE POLICY workspace_settings_profiles_update ON workspace_settings_profiles
  FOR UPDATE USING (is_workspace_admin(workspace_id));

DROP POLICY IF EXISTS workspace_settings_profiles_delete ON workspace_settings_profiles;
CREATE POLICY workspace_settings_profiles_delete ON workspace_settings_profiles
  FOR DELETE USING (is_workspace_admin(workspace_id));

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = 'set_workspace_settings_profiles_updated_at'
  ) THEN
    CREATE TRIGGER set_workspace_settings_profiles_updated_at
    BEFORE UPDATE ON workspace_settings_profiles
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();
  END IF;
END $$;
