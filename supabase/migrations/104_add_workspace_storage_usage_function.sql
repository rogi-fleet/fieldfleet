-- Function to get total storage usage for a workspace (in bytes)
CREATE OR REPLACE FUNCTION get_workspace_storage_usage(p_workspace_id UUID)
RETURNS BIGINT
LANGUAGE SQL
STABLE
AS $$
  SELECT COALESCE(SUM(file_size), 0)::BIGINT
  FROM file_attachments
  WHERE workspace_id = p_workspace_id;
$$;
