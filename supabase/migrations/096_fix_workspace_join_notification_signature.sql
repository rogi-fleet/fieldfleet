-- Fix invitation acceptance when the joined role is passed as the
-- workspace_member_role enum instead of plain text.

CREATE OR REPLACE FUNCTION public.create_workspace_member_join_notifications(
  p_workspace_id UUID,
  p_joined_user_id UUID,
  p_joined_role public.workspace_member_role
)
RETURNS INTEGER
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.create_workspace_member_join_notifications(
    p_workspace_id,
    p_joined_user_id,
    p_joined_role::TEXT
  );
$$;

REVOKE ALL ON FUNCTION public.create_workspace_member_join_notifications(UUID, UUID, public.workspace_member_role) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_workspace_member_join_notifications(UUID, UUID, public.workspace_member_role) TO authenticated;

CREATE OR REPLACE FUNCTION public.accept_workspace_invitation(invite_token TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  now_ts TIMESTAMPTZ := NOW();
  current_user_id UUID := auth.uid();
  current_user_email TEXT;
  invitation_row workspace_invitations%ROWTYPE;
  already_member BOOLEAN := FALSE;
BEGIN
  IF current_user_id IS NULL THEN
    RAISE EXCEPTION 'You must be signed in to accept an invitation';
  END IF;

  SELECT *
  INTO invitation_row
  FROM workspace_invitations
  WHERE token = invite_token
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Invitation not found or invalid';
  END IF;

  IF invitation_row.status <> 'pending' THEN
    RAISE EXCEPTION 'This invitation is no longer pending';
  END IF;

  IF invitation_row.expires_at < now_ts THEN
    UPDATE workspace_invitations
    SET status = 'expired'
    WHERE id = invitation_row.id;
    RAISE EXCEPTION 'This invitation has expired';
  END IF;

  SELECT LOWER(email)
  INTO current_user_email
  FROM users
  WHERE id = current_user_id;

  IF current_user_email IS NULL THEN
    RAISE EXCEPTION 'User account not found';
  END IF;

  IF current_user_email <> LOWER(invitation_row.email) THEN
    RAISE EXCEPTION 'This invitation was sent to a different email address';
  END IF;

  SELECT EXISTS (
    SELECT 1
    FROM workspace_members
    WHERE workspace_id = invitation_row.workspace_id
      AND user_id = current_user_id
  )
  INTO already_member;

  IF NOT already_member THEN
    INSERT INTO workspace_members (
      workspace_id,
      user_id,
      role,
      interface_mode,
      created_at,
      updated_at
    )
    VALUES (
      invitation_row.workspace_id,
      current_user_id,
      invitation_row.role,
      COALESCE(invitation_row.interface_mode, 'manager'),
      now_ts,
      now_ts
    );
  END IF;

  UPDATE users
  SET active_workspace_id = invitation_row.workspace_id,
      updated_at = now_ts
  WHERE id = current_user_id;

  UPDATE workspace_invitations
  SET status = 'accepted',
      accepted_at = now_ts,
      accepted_by = current_user_id
  WHERE id = invitation_row.id;

  IF NOT already_member THEN
    PERFORM public.create_workspace_member_join_notifications(
      invitation_row.workspace_id,
      current_user_id,
      invitation_row.role::TEXT
    );
  END IF;

  RETURN jsonb_build_object(
    'invitationId', invitation_row.id,
    'workspaceId', invitation_row.workspace_id,
    'userId', current_user_id,
    'alreadyMember', already_member
  );
END;
$$;

REVOKE ALL ON FUNCTION public.accept_workspace_invitation(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.accept_workspace_invitation(TEXT) TO authenticated;
