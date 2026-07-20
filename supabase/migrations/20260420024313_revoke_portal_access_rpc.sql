-- Revoke a portal link in one atomic step: null out the contact's user_id
-- and remove their workspace_member row. Only workspace admins can invoke.
-- The auth user still exists on auth.users so they can be re-invited later
-- if needed, but they lose every piece of workspace access immediately.

CREATE OR REPLACE FUNCTION public.revoke_portal_contact_access(
  contact_id UUID,
  contact_kind TEXT  -- 'customer' | 'vendor'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  workspace_uuid UUID;
  linked_user_id UUID;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'You must be signed in';
  END IF;

  IF contact_kind NOT IN ('customer', 'vendor') THEN
    RAISE EXCEPTION 'contact_kind must be customer or vendor';
  END IF;

  IF contact_kind = 'customer' THEN
    SELECT c.workspace_id, cc.user_id
    INTO workspace_uuid, linked_user_id
    FROM customer_contacts cc
    JOIN customers c ON c.id = cc.customer_id
    WHERE cc.id = contact_id;
  ELSE
    SELECT v.workspace_id, vc.user_id
    INTO workspace_uuid, linked_user_id
    FROM vendor_contacts vc
    JOIN vendors v ON v.id = vc.vendor_id
    WHERE vc.id = contact_id;
  END IF;

  IF workspace_uuid IS NULL THEN
    RAISE EXCEPTION 'Contact not found';
  END IF;

  IF NOT public.is_workspace_admin(workspace_uuid) THEN
    RAISE EXCEPTION 'Only workspace admins can revoke portal access';
  END IF;

  IF linked_user_id IS NULL THEN
    -- Nothing to revoke; still idempotent.
    RETURN jsonb_build_object('alreadyRevoked', TRUE);
  END IF;

  IF contact_kind = 'customer' THEN
    UPDATE customer_contacts SET user_id = NULL WHERE id = contact_id;
  ELSE
    UPDATE vendor_contacts SET user_id = NULL WHERE id = contact_id;
  END IF;

  DELETE FROM workspace_members
  WHERE workspace_id = workspace_uuid
    AND user_id = linked_user_id;

  RETURN jsonb_build_object(
    'workspaceId', workspace_uuid,
    'revokedUserId', linked_user_id
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.revoke_portal_contact_access(UUID, TEXT)
  TO authenticated;
