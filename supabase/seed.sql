-- Seed file for local development
-- This runs after migrations during `supabase db reset`

-- Note: In local dev, you'll create users via the Supabase Studio or Auth API
-- This seed just creates some sample data for testing

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
-- 2. Open Studio: http://localhost:54323
-- 3. Create a user via Authentication > Users > Add User
-- 4. Create workspace and user records manually or via your app
-- 5. Call: SELECT seed_workspace_data('your-workspace-uuid');
