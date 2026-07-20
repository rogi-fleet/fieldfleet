-- Helper RPC for account bootstrap:
-- lets authenticated users determine whether they have pending workspace
-- invitations without broad table read access.

CREATE OR REPLACE FUNCTION public.auth_user_has_pending_workspace_invitation()
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  current_user_id UUID := auth.uid();
  current_user_email TEXT := LOWER(COALESCE(auth.jwt() ->> 'email', ''));
BEGIN
  IF current_user_id IS NULL THEN
    RETURN FALSE;
  END IF;

  IF current_user_email = '' THEN
    RETURN FALSE;
  END IF;

  RETURN EXISTS (
    SELECT 1
    FROM workspace_invitations wi
    WHERE LOWER(wi.email) = current_user_email
      AND wi.status = 'pending'
      AND wi.expires_at >= NOW()
  );
END;
$$;

REVOKE ALL ON FUNCTION public.auth_user_has_pending_workspace_invitation() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.auth_user_has_pending_workspace_invitation() TO authenticated;
