-- Fan out in-app notifications when a workspace member joins.

CREATE OR REPLACE FUNCTION public.create_workspace_member_join_notifications(
  p_workspace_id UUID,
  p_joined_user_id UUID,
  p_joined_role TEXT DEFAULT NULL
)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  current_user_id UUID := auth.uid();
  joined_name TEXT;
  effective_role TEXT;
  joined_role_label TEXT;
  inserted_count INTEGER := 0;
BEGIN
  IF current_user_id IS NULL THEN
    RAISE EXCEPTION 'You must be signed in to create workspace join notifications';
  END IF;

  IF NOT public.is_workspace_member(p_workspace_id) THEN
    RAISE EXCEPTION 'You do not have access to this workspace';
  END IF;

  SELECT
    COALESCE(NULLIF(TRIM(display_name), ''), NULLIF(TRIM(email), ''))
  INTO joined_name
  FROM public.users
  WHERE id = p_joined_user_id;

  SELECT role
  INTO effective_role
  FROM public.workspace_members
  WHERE workspace_id = p_workspace_id
    AND user_id = p_joined_user_id
  LIMIT 1;

  effective_role := COALESCE(p_joined_role, effective_role);
  joined_role_label := NULLIF(INITCAP(REPLACE(COALESCE(effective_role, ''), '_', ' ')), '');
  joined_name := COALESCE(joined_name, 'A new team member');

  INSERT INTO public.notifications (
    user_id,
    workspace_id,
    type,
    title,
    body,
    metadata
  )
  SELECT
    wm.user_id,
    p_workspace_id,
    'workspace_member_joined',
    joined_name || ' joined the team',
    CASE
      WHEN joined_role_label IS NOT NULL THEN 'Role: ' || joined_role_label
      ELSE NULL
    END,
    jsonb_build_object(
      'target_type', 'workspace',
      'joined_user_id', p_joined_user_id,
      'joined_role', effective_role,
      'tab', 'team',
      'deeplink_path', '/team'
    )
  FROM public.workspace_members wm
  WHERE wm.workspace_id = p_workspace_id
    AND wm.user_id <> p_joined_user_id;

  GET DIAGNOSTICS inserted_count = ROW_COUNT;
  RETURN inserted_count;
END;
$$;

REVOKE ALL ON FUNCTION public.create_workspace_member_join_notifications(UUID, UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_workspace_member_join_notifications(UUID, UUID, TEXT) TO authenticated;

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
      invitation_row.role
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

ALTER TABLE public.notifications DROP CONSTRAINT IF EXISTS notifications_type_check;
ALTER TABLE public.notifications ADD CONSTRAINT notifications_type_check
  CHECK (
    type IN (
      'mention',
      'task_assignment',
      'task_completion',
      'ai_plan_ready',
      'ai_plan_failed',
      'automation',
      'capacity_alert',
      'priority_alert',
      'workspace_member_joined'
    )
  );
