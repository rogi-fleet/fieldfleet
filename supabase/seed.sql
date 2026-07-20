-- Seed file for local development
-- This runs after migrations during `supabase db reset`

-- Note: Auth users are not created automatically by this seed. For a
-- disposable local login, run:
--   scripts/create_local_demo_user.sh
-- The helper is local-only and uses the normal first-login bootstrap path.

-- Sample cost categories (created for any workspace)
-- These will be created once a workspace exists

-- Function to seed data for a workspace (call manually after creating workspace)
CREATE OR REPLACE FUNCTION seed_workspace_data(workspace_uuid UUID)
RETURNS void AS $$
BEGIN
  -- Default cost categories
  INSERT INTO cost_categories (workspace_id, name, color, is_default) VALUES
    (workspace_uuid, 'Materials', '#3B82F6', true),
    (workspace_uuid, 'Labor', '#10B981', true),
    (workspace_uuid, 'Equipment', '#F59E0B', true),
    (workspace_uuid, 'Subcontractor', '#8B5CF6', true),
    (workspace_uuid, 'Permits & Fees', '#EF4444', true),
    (workspace_uuid, 'Overhead', '#6B7280', true)
  ON CONFLICT DO NOTHING;

  -- Default skills
  INSERT INTO skills (workspace_id, name, category) VALUES
    (workspace_uuid, 'General Labor', 'Labor'),
    (workspace_uuid, 'Carpentry', 'Trade'),
    (workspace_uuid, 'Electrical', 'Trade'),
    (workspace_uuid, 'Plumbing', 'Trade'),
    (workspace_uuid, 'HVAC', 'Trade'),
    (workspace_uuid, 'Painting', 'Finishing'),
    (workspace_uuid, 'Drywall', 'Finishing'),
    (workspace_uuid, 'Flooring', 'Finishing'),
    (workspace_uuid, 'Roofing', 'Trade'),
    (workspace_uuid, 'Project Management', 'Management')
  ON CONFLICT DO NOTHING;
END;
$$ LANGUAGE plpgsql;

-- Instructions for local testing:
-- 1. Start Supabase: supabase start
-- 2. Apply migrations: supabase migration up --local
-- 3. Optional demo login: scripts/create_local_demo_user.sh
-- 4. Open Studio: http://127.0.0.1:55323
-- 5. Create or log in as a user; the app bootstraps the workspace.
-- 6. Optional extra sample data:
--    SELECT seed_workspace_data('your-workspace-uuid');
