-- Portal messaging: expose project conversation threads to portal users.
--
-- Adds a `portal_visible` flag on conversations. The single thread per project
-- flagged portal_visible=true is the customer-facing thread. Read/write happen
-- via SECURITY DEFINER RPCs to match the rest of portal_* design.
--
-- Authorization mirrors portal_get_project:
--   - real portal user: auth.email() must match an active customer_contacts row
--     on the project's client
--   - preview: caller must be a workspace_member of the project's workspace
--     (via _portal_preview_authorized).
--
-- Write paths (send, mark-read) are blocked in preview mode.

-- ---------------------------------------------------------------------------
-- Schema
-- ---------------------------------------------------------------------------

ALTER TABLE public.conversations
  ADD COLUMN IF NOT EXISTS portal_visible BOOLEAN NOT NULL DEFAULT FALSE;

CREATE INDEX IF NOT EXISTS conversations_portal_visible_idx
  ON public.conversations (scope_reference_id)
  WHERE portal_visible = TRUE AND scope = 'project';

-- messages.sender_id originally REFERENCES public.users(id). Portal-authenticated
-- customer contacts authenticate via auth.users but typically have no
-- public.users row. Drop the FK so portal-sent messages can record the
-- auth.uid() as sender. (The column stays a UUID; staff messages still use
-- public.users.id which equals auth.users.id, so nothing changes for them.)
DO $$
DECLARE
  v_name TEXT;
BEGIN
  SELECT conname INTO v_name
  FROM pg_constraint
  WHERE conrelid = 'public.messages'::regclass
    AND contype = 'f'
    AND pg_get_constraintdef(oid) ILIKE '%REFERENCES users(id)%';
  IF v_name IS NOT NULL THEN
    EXECUTE format('ALTER TABLE public.messages DROP CONSTRAINT %I', v_name);
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- Authorization helper
-- ---------------------------------------------------------------------------

-- Returns the conversation row if the caller is authorized to read it via the
-- portal (real or preview). NULL otherwise. SECURITY DEFINER so it can read
-- across RLS.
CREATE OR REPLACE FUNCTION public._portal_conversation_authorized(
  p_conversation_id UUID,
  p_preview_customer_id UUID DEFAULT NULL
) RETURNS public.conversations
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
DECLARE
  v_conv      public.conversations;
  v_project   public.projects;
  v_preview   BOOLEAN := public._portal_preview_authorized(p_preview_customer_id);
  v_caller_id UUID := auth.uid();
BEGIN
  SELECT * INTO v_conv FROM public.conversations WHERE id = p_conversation_id;
  IF NOT FOUND THEN
    RETURN NULL;
  END IF;

  -- Only project-scoped, portal-visible threads are exposed.
  IF v_conv.scope <> 'project'
     OR v_conv.scope_reference_id IS NULL
     OR v_conv.portal_visible IS NOT TRUE THEN
    RETURN NULL;
  END IF;

  SELECT * INTO v_project FROM public.projects WHERE id = v_conv.scope_reference_id;
  IF NOT FOUND THEN
    RETURN NULL;
  END IF;

  IF v_preview THEN
    -- Preview: caller is a workspace_member of the project's workspace AND
    -- the project belongs to the preview customer.
    IF v_project.client_id = p_preview_customer_id
       AND EXISTS (
         SELECT 1 FROM public.workspace_members wm
         WHERE wm.user_id = v_caller_id
           AND wm.workspace_id = v_project.workspace_id
       ) THEN
      RETURN v_conv;
    END IF;
    RETURN NULL;
  END IF;

  -- Real portal user: email match on the project's client.
  IF v_project.client_id IS NOT NULL
     AND EXISTS (
       SELECT 1 FROM public.customer_contacts cc
       WHERE cc.customer_id = v_project.client_id
         AND cc.is_active = TRUE
         AND lower(cc.email) = lower(coalesce(auth.email(), ''))
     ) THEN
    RETURN v_conv;
  END IF;

  RETURN NULL;
END;
$$;

REVOKE ALL ON FUNCTION public._portal_conversation_authorized(UUID, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public._portal_conversation_authorized(UUID, UUID) TO authenticated;

-- ---------------------------------------------------------------------------
-- Get-or-create the project's portal-visible thread
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
  v_pm_name   TEXT;
  v_subject   TEXT;
  v_participants UUID[];
  v_names     JSONB := '{}'::jsonb;
  v_unread    JSONB := '{}'::jsonb;
BEGIN
  SELECT * INTO v_project FROM public.projects WHERE id = p_project_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Project not found';
  END IF;

  -- Authorize: same rules as portal_get_project.
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

  -- Return existing portal-visible thread if any.
  SELECT * INTO v_conv FROM public.conversations
   WHERE scope = 'project'
     AND scope_reference_id = p_project_id
     AND portal_visible = TRUE
   ORDER BY created_at ASC
   LIMIT 1;

  IF FOUND THEN
    -- Best-effort: ensure the real portal user's auth.uid() is in participants
    -- so unread_counts works for them. Skip in preview.
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

  -- Create one. Seed with PM (if any) + the real caller (if not preview).
  v_participants := ARRAY[]::UUID[];
  IF v_project.project_manager_id IS NOT NULL THEN
    v_participants := array_append(v_participants, v_project.project_manager_id);
    SELECT COALESCE(display_name, email) INTO v_pm_name
      FROM public.users WHERE id = v_project.project_manager_id;
    IF v_pm_name IS NOT NULL THEN
      v_names := v_names || jsonb_build_object(
        v_project.project_manager_id::text, v_pm_name);
      v_unread := v_unread || jsonb_build_object(
        v_project.project_manager_id::text, 0);
    END IF;
  END IF;

  IF NOT v_preview AND NOT (v_caller_id = ANY(v_participants)) THEN
    v_participants := array_append(v_participants, v_caller_id);
    v_unread := v_unread || jsonb_build_object(v_caller_id::text, 0);
    v_names := v_names || jsonb_build_object(
      v_caller_id::text,
      coalesce(
        (SELECT cc.name FROM public.customer_contacts cc
          WHERE cc.customer_id = v_project.client_id
            AND cc.is_active = TRUE
            AND lower(cc.email) = lower(coalesce(auth.email(), ''))
          LIMIT 1),
        'Customer'
      )
    );
  END IF;

  -- Must have at least one participant for NOT NULL satisfaction.
  IF array_length(v_participants, 1) IS NULL THEN
    -- Fall back to project's created_by or workspace owner.
    SELECT created_by INTO v_caller_id FROM public.projects WHERE id = p_project_id;
    IF v_caller_id IS NULL THEN
      SELECT user_id INTO v_caller_id FROM public.workspace_members
       WHERE workspace_id = v_project.workspace_id LIMIT 1;
    END IF;
    IF v_caller_id IS NOT NULL THEN
      v_participants := ARRAY[v_caller_id]::UUID[];
      v_unread := v_unread || jsonb_build_object(v_caller_id::text, 0);
    END IF;
  END IF;

  v_subject := COALESCE(v_project.name, 'Project') || ' — Customer thread';

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

  RETURN v_conv;
END;
$$;

REVOKE ALL ON FUNCTION public.portal_get_or_create_project_thread(UUID, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.portal_get_or_create_project_thread(UUID, UUID) TO authenticated;

-- ---------------------------------------------------------------------------
-- Read messages (paginated, oldest-first within page; caller paginates by
-- p_before created_at).
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.portal_get_thread_messages(
  p_conversation_id UUID,
  p_preview_customer_id UUID DEFAULT NULL,
  p_limit INT DEFAULT 100,
  p_before TIMESTAMPTZ DEFAULT NULL
) RETURNS TABLE (
  id UUID,
  conversation_id UUID,
  sender_id UUID,
  sender_name TEXT,
  content TEXT,
  attachments JSONB,
  created_at TIMESTAMPTZ,
  edited_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
DECLARE
  v_conv public.conversations;
BEGIN
  v_conv := public._portal_conversation_authorized(p_conversation_id, p_preview_customer_id);
  IF v_conv.id IS NULL THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;

  RETURN QUERY
    SELECT m.id, m.conversation_id, m.sender_id, m.sender_name,
           m.content, m.attachments, m.created_at, m.edited_at
      FROM public.messages m
     WHERE m.conversation_id = p_conversation_id
       AND (p_before IS NULL OR m.created_at < p_before)
     ORDER BY m.created_at DESC
     LIMIT GREATEST(1, LEAST(p_limit, 200));
END;
$$;

REVOKE ALL ON FUNCTION public.portal_get_thread_messages(UUID, UUID, INT, TIMESTAMPTZ) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.portal_get_thread_messages(UUID, UUID, INT, TIMESTAMPTZ) TO authenticated;

-- ---------------------------------------------------------------------------
-- Send message (blocked in preview)
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.portal_send_message(
  p_conversation_id UUID,
  p_content TEXT,
  p_attachments JSONB DEFAULT '[]'::jsonb
) RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_conv      public.conversations;
  v_caller_id UUID := auth.uid();
  v_sender_name TEXT;
  v_message_id UUID;
  v_other_ids UUID[];
  v_unread JSONB;
  v_id UUID;
BEGIN
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  IF p_content IS NULL OR length(trim(p_content)) = 0 THEN
    RAISE EXCEPTION 'Empty content';
  END IF;

  -- Authorize for real portal user only (preview is read-only).
  v_conv := public._portal_conversation_authorized(p_conversation_id, NULL);
  IF v_conv.id IS NULL THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;

  -- Resolve sender_name from customer_contacts.
  SELECT cc.name INTO v_sender_name
    FROM public.customer_contacts cc
    JOIN public.projects p ON p.client_id = cc.customer_id
   WHERE p.id = v_conv.scope_reference_id
     AND cc.is_active = TRUE
     AND lower(cc.email) = lower(coalesce(auth.email(), ''))
   LIMIT 1;

  IF v_sender_name IS NULL THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;

  -- Ensure caller is in participant_ids (idempotent).
  IF NOT (v_caller_id = ANY(v_conv.participant_ids)) THEN
    UPDATE public.conversations
       SET participant_ids = array_append(participant_ids, v_caller_id),
           participant_names = COALESCE(participant_names, '{}'::jsonb)
                                || jsonb_build_object(v_caller_id::text, v_sender_name),
           unread_counts = COALESCE(unread_counts, '{}'::jsonb)
                            || jsonb_build_object(v_caller_id::text, 0)
     WHERE id = v_conv.id
     RETURNING * INTO v_conv;
  END IF;

  INSERT INTO public.messages (
    conversation_id, workspace_id, sender_id, sender_name,
    content, attachments
  ) VALUES (
    p_conversation_id, v_conv.workspace_id, v_caller_id, v_sender_name,
    p_content, COALESCE(p_attachments, '[]'::jsonb)
  )
  RETURNING id INTO v_message_id;

  -- Bump unread counts for everyone except sender.
  v_unread := COALESCE(v_conv.unread_counts, '{}'::jsonb);
  FOREACH v_id IN ARRAY v_conv.participant_ids LOOP
    IF v_id <> v_caller_id THEN
      v_unread := v_unread || jsonb_build_object(
        v_id::text,
        COALESCE((v_unread ->> v_id::text)::int, 0) + 1
      );
    END IF;
  END LOOP;
  -- Ensure sender key is zero.
  v_unread := v_unread || jsonb_build_object(v_caller_id::text, 0);

  UPDATE public.conversations
     SET last_message = LEFT(p_content, 500),
         last_message_at = NOW(),
         unread_counts = v_unread,
         updated_at = NOW()
   WHERE id = p_conversation_id;

  RETURN v_message_id;
END;
$$;

REVOKE ALL ON FUNCTION public.portal_send_message(UUID, TEXT, JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.portal_send_message(UUID, TEXT, JSONB) TO authenticated;

-- ---------------------------------------------------------------------------
-- Mark read (blocked in preview)
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.portal_mark_thread_read(
  p_conversation_id UUID
) RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_conv      public.conversations;
  v_caller_id UUID := auth.uid();
BEGIN
  v_conv := public._portal_conversation_authorized(p_conversation_id, NULL);
  IF v_conv.id IS NULL THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;

  UPDATE public.conversations
     SET unread_counts = COALESCE(unread_counts, '{}'::jsonb)
                          || jsonb_build_object(v_caller_id::text, 0)
   WHERE id = p_conversation_id;
END;
$$;

REVOKE ALL ON FUNCTION public.portal_mark_thread_read(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.portal_mark_thread_read(UUID) TO authenticated;

COMMENT ON COLUMN public.conversations.portal_visible IS
  'When TRUE and scope=project, this thread is exposed to the project''s customer via portal_* RPCs.';
COMMENT ON FUNCTION public.portal_get_or_create_project_thread(UUID, UUID) IS
  'Returns (or lazily creates) the single portal-visible project thread for a project the caller can access.';
COMMENT ON FUNCTION public.portal_get_thread_messages(UUID, UUID, INT, TIMESTAMPTZ) IS
  'Reads messages from a portal-visible thread the caller can access.';
COMMENT ON FUNCTION public.portal_send_message(UUID, TEXT, JSONB) IS
  'Portal user posts a message to a portal-visible thread. Blocked in preview mode.';
COMMENT ON FUNCTION public.portal_mark_thread_read(UUID) IS
  'Clears unread count for the calling portal user on a portal-visible thread.';
