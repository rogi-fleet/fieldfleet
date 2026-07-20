-- Include workspace and inviter context in token-based invitation lookups.
-- This allows invite recipients (including anon users) to see workspace details
-- without direct table read permissions.
CREATE OR REPLACE FUNCTION public.get_workspace_invitation_by_token(invite_token TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  invitation_row workspace_invitations%ROWTYPE;
  workspace_name TEXT;
  inviter_name TEXT;
BEGIN
  SELECT *
  INTO invitation_row
  FROM workspace_invitations
  WHERE token = invite_token
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN NULL;
  END IF;

  SELECT name
  INTO workspace_name
  FROM workspaces
  WHERE id = invitation_row.workspace_id
  LIMIT 1;

  SELECT COALESCE(NULLIF(display_name, ''), email)
  INTO inviter_name
  FROM users
  WHERE id = invitation_row.invited_by
  LIMIT 1;

  RETURN to_jsonb(invitation_row) || jsonb_build_object(
    'workspace_name', COALESCE(workspace_name, 'Workspace'),
    'inviter_name', COALESCE(inviter_name, 'A team member')
  );
END;
$$;

REVOKE ALL ON FUNCTION public.get_workspace_invitation_by_token(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_workspace_invitation_by_token(TEXT) TO anon, authenticated;
