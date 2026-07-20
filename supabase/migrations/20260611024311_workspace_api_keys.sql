-- P1: workspace API keys for the public API / MCP server.
--
-- Keys are shown ONCE at creation (create_workspace_api_key returns the
-- plaintext); only the SHA-256 hash is stored. The mcp-server edge function
-- authenticates callers by hashing the presented bearer key and matching
-- key_hash with the service role. Admin-only management via RLS.

CREATE TABLE IF NOT EXISTS workspace_api_keys (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  key_prefix TEXT NOT NULL,             -- e.g. 'tfk_ab12cd34' for display
  key_hash TEXT NOT NULL UNIQUE,        -- sha256 hex of the full key
  scopes TEXT[] NOT NULL DEFAULT ARRAY['read','write'],
  created_by UUID REFERENCES users(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_used_at TIMESTAMPTZ,
  revoked_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_workspace_api_keys_workspace
  ON workspace_api_keys(workspace_id);

ALTER TABLE workspace_api_keys ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS workspace_api_keys_select ON workspace_api_keys;
CREATE POLICY workspace_api_keys_select ON workspace_api_keys
  FOR SELECT USING (is_workspace_admin(workspace_id));
DROP POLICY IF EXISTS workspace_api_keys_update ON workspace_api_keys;
CREATE POLICY workspace_api_keys_update ON workspace_api_keys
  FOR UPDATE USING (is_workspace_admin(workspace_id));
DROP POLICY IF EXISTS workspace_api_keys_delete ON workspace_api_keys;
CREATE POLICY workspace_api_keys_delete ON workspace_api_keys
  FOR DELETE USING (is_workspace_admin(workspace_id));
-- No INSERT policy: rows are only created via create_workspace_api_key().

CREATE OR REPLACE FUNCTION public.create_workspace_api_key(
  p_workspace_id uuid,
  p_name text,
  p_scopes text[] DEFAULT ARRAY['read','write']
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
  v_key    text;
  v_hash   text;
  v_id     uuid;
BEGIN
  IF NOT is_workspace_admin(p_workspace_id) THEN
    RAISE EXCEPTION 'Only workspace admins can create API keys';
  END IF;
  IF p_name IS NULL OR length(trim(p_name)) = 0 THEN
    RAISE EXCEPTION 'API key name is required';
  END IF;

  v_key := 'tfk_' || encode(extensions.gen_random_bytes(24), 'hex');
  v_hash := encode(extensions.digest(v_key, 'sha256'), 'hex');

  INSERT INTO workspace_api_keys (
    workspace_id, name, key_prefix, key_hash, scopes, created_by
  ) VALUES (
    p_workspace_id, trim(p_name), left(v_key, 12), v_hash, p_scopes,
    auth.uid()
  ) RETURNING id INTO v_id;

  -- The only time the plaintext key ever leaves the database.
  RETURN jsonb_build_object('id', v_id, 'key', v_key);
END;
$$;

REVOKE ALL ON FUNCTION public.create_workspace_api_key(uuid, text, text[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_workspace_api_key(uuid, text, text[]) TO authenticated;
