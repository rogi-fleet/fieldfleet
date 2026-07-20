-- ============================================================================
-- STORAGE HELPER FUNCTION (in public schema)
-- ============================================================================

-- Helper function for storage policies (must be in public schema)
CREATE OR REPLACE FUNCTION public.get_workspace_from_storage_path(path TEXT)
RETURNS UUID AS $$
DECLARE
  workspace_uuid UUID;
BEGIN
  -- Path format: {workspace_id}/{rest_of_path}
  BEGIN
    workspace_uuid := (string_to_array(path, '/'))[1]::UUID;
    RETURN workspace_uuid;
  EXCEPTION WHEN OTHERS THEN
    RETURN NULL;
  END;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Note: Storage buckets are configured in config.toml for local development
-- For production, buckets are created via Supabase dashboard or API

-- Storage policies will be created via Supabase dashboard or after buckets exist
-- The policies reference the helper function above and the RLS functions from migration 002
