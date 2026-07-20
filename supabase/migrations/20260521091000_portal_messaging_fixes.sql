-- Fixes from architect review of 20260521090000_add_portal_messaging.sql:
--   1. Race on lazy thread creation could yield duplicates → unique partial
--      index, plus catch unique_violation in the RPC.
--   2. Staff users were not seeded into participant_ids, so the staff inbox
--      (RLS-gated on auth.uid() = ANY(participant_ids)) wouldn't surface the
--      portal thread. Seed every admin and project_manager in the project's
--      workspace alongside the project_manager_id.

-- ---------------------------------------------------------------------------
-- Unique partial index: at most one portal-visible project thread per project.
-- ---------------------------------------------------------------------------
CREATE UNIQUE INDEX IF NOT EXISTS conversations_one_portal_thread_per_project
  ON public.conversations (scope_reference_id)
  WHERE portal_visible = TRUE AND scope = 'project';

-- ---------------------------------------------------------------------------
-- Re-create portal_get_or_create_project_thread with staff seeding +
-- unique_violation retry.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.portal_get_or_create_project_thread(
  p_project_id UUID,
  p_preview_customer_id UUID DEFAULT NULL
) RETURNS public.conversations
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_project   public.projects;
  v_conv      public.conversations;
  v_preview   BOOLEAN := public._portal_preview_authorized(p_preview_customer_id);
  v_caller_id UUID := auth.uid();
  v_participants UUID[] := ARRAY[]::UUID[];
  v_names     JSONB := '{}'::jsonb;
  v_unread    JSONB := '{}'::jsonb;
  v_subject   TEXT;
  v_staff     RECORD;
BEGIN
  SELECT * INTO v_project FROM public.projects WHERE id = p_project_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Project not found';
  END IF;

  -- Authorize (same rules as portal_get_project).
  IF v_preview THEN
    IF v_project.client_id <> p_preview_customer_id
       OR NOT EXISTS (
         SELECT 1 FROM public.workspace_members wm
         WHERE wm.user_id = v_caller_id
           AND wm.workspace_id = v_project.workspace_id
       ) THEN
      RAISE EXCEPTION 'Not authorized';
    END IF;
  ELSE
    IF v_project.client_id IS NULL
       OR NOT EXISTS (
         SELECT 1 FROM public.customer_contacts cc
         WHERE cc.customer_id = v_project.client_id
           AND cc.is_active = TRUE
           AND lower(cc.email) = lower(coalesce(auth.email(), ''))
       ) THEN
      RAISE EXCEPTION 'Not authorized';
    END IF;
  END IF;

  -- Return existing thread if any.
  SELECT * INTO v_conv FROM public.conversations
   WHERE scope = 'project'
     AND scope_reference_id = p_project_id
     AND portal_visible = TRUE
   ORDER BY created_at ASC
   LIMIT 1;

  IF FOUND THEN
    IF NOT v_preview AND NOT (v_caller_id = ANY(v_conv.participant_ids)) THEN
      UPDATE public.conversations
         SET participant_ids = array_append(participant_ids, v_caller_id),
             unread_counts = COALESCE(unread_counts, '{}'::jsonb)
                              || jsonb_build_object(v_caller_id::text, 0)
       WHERE id = v_conv.id
       RETURNING * INTO v_conv;
    END IF;
    RETURN v_conv;
  END IF;

  -- Seed staff: every admin + project_manager in the workspace, plus the
  -- project's project_manager_id (if not already covered).
  FOR v_staff IN
    SELECT DISTINCT wm.user_id, COALESCE(u.display_name, u.email) AS name
      FROM public.workspace_members wm
      JOIN public.users u ON u.id = wm.user_id
     WHERE wm.workspace_id = v_project.workspace_id
       AND wm.role IN ('admin', 'project_manager')
  LOOP
    v_participants := array_append(v_participants, v_staff.user_id);
    v_names := v_names || jsonb_build_object(v_staff.user_id::text,
                            COALESCE(v_staff.name, 'Team member'));
    v_unread := v_unread || jsonb_build_object(v_staff.user_id::text, 0);
  END LOOP;

  IF v_project.project_manager_id IS NOT NULL
     AND NOT (v_project.project_manager_id = ANY(v_participants)) THEN
    v_participants := array_append(v_participants, v_project.project_manager_id);
    v_names := v_names || jsonb_build_object(
      v_project.project_manager_id::text,
      COALESCE((SELECT COALESCE(display_name, email) FROM public.users
                  WHERE id = v_project.project_manager_id), 'Project Manager'));
    v_unread := v_unread || jsonb_build_object(
      v_project.project_manager_id::text, 0);
  END IF;

  IF NOT v_preview AND NOT (v_caller_id = ANY(v_participants)) THEN
    v_participants := array_append(v_participants, v_caller_id);
    v_unread := v_unread || jsonb_build_object(v_caller_id::text, 0);
    v_names := v_names || jsonb_build_object(
      v_caller_id::text,
      COALESCE(
        (SELECT cc.name FROM public.customer_contacts cc
          WHERE cc.customer_id = v_project.client_id
            AND cc.is_active = TRUE
            AND lower(cc.email) = lower(coalesce(auth.email(), ''))
          LIMIT 1),
        'Customer'));
  END IF;

  IF array_length(v_participants, 1) IS NULL THEN
    -- Fall back to a workspace owner.
    SELECT user_id INTO v_caller_id FROM public.workspace_members
     WHERE workspace_id = v_project.workspace_id LIMIT 1;
    IF v_caller_id IS NOT NULL THEN
      v_participants := ARRAY[v_caller_id]::UUID[];
      v_unread := v_unread || jsonb_build_object(v_caller_id::text, 0);
    END IF;
  END IF;

  v_subject := COALESCE(v_project.name, 'Project') || ' — Customer thread';

  BEGIN
    INSERT INTO public.conversations (
      workspace_id, participant_ids, participant_names, subject,
      type, scope, scope_reference_id, scope_reference_name,
      unread_counts, portal_visible
    ) VALUES (
      v_project.workspace_id, v_participants, v_names, v_subject,
      'group', 'project', p_project_id, v_project.name,
      v_unread, TRUE
    )
    RETURNING * INTO v_conv;
  EXCEPTION
    WHEN unique_violation THEN
      -- Lost the race; fetch the thread the other caller just created.
      SELECT * INTO v_conv FROM public.conversations
       WHERE scope = 'project'
         AND scope_reference_id = p_project_id
         AND portal_visible = TRUE
       ORDER BY created_at ASC
       LIMIT 1;
      IF NOT v_preview AND NOT (v_caller_id = ANY(v_conv.participant_ids)) THEN
        UPDATE public.conversations
           SET participant_ids = array_append(participant_ids, v_caller_id),
               unread_counts = COALESCE(unread_counts, '{}'::jsonb)
                                || jsonb_build_object(v_caller_id::text, 0)
         WHERE id = v_conv.id
         RETURNING * INTO v_conv;
      END IF;
  END;

  RETURN v_conv;
END;
$$;

REVOKE ALL ON FUNCTION public.portal_get_or_create_project_thread(UUID, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.portal_get_or_create_project_thread(UUID, UUID) TO authenticated;
