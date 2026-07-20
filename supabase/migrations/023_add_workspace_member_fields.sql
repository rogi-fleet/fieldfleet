-- Migration: Add hourly_rate and module_permissions to workspace_members
-- Change ID: add-team-access-and-rates
-- Description: Adds per-workspace hourly rates and module-based access control.

ALTER TABLE workspace_members
  ADD COLUMN IF NOT EXISTS hourly_rate DECIMAL(10,2),
  ADD COLUMN IF NOT EXISTS module_permissions JSONB DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT NOW();

-- Create trigger to automatically update updated_at if it doesn't exist
-- Note: update_updated_at_column function is usually already present in Supabase standard setups
-- if not, it should be defined elsewhere. Assuming it exists based on project conventions.

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'set_workspace_members_updated_at') THEN
        CREATE TRIGGER set_workspace_members_updated_at
        BEFORE UPDATE ON workspace_members
        FOR EACH ROW
        EXECUTE FUNCTION update_updated_at_column();
    END IF;
END $$;
