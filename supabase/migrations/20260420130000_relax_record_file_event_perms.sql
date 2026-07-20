-- Split record_file_event authorization by action type.
--
-- The original function required documents:write for every action, which
-- was wrong for read-level actions: a documents:read user can legitimately
-- comment on a visible file (file_comments RLS allows it), but then fails
-- to record the 'commented' event — the audit trail silently drops their
-- activity. Similarly for 'downloaded' / 'shared', which are observer
-- actions on files the user can already see.
--
-- New rule:
--   read-level actions  → require documents:read  AND file_is_visible()
--   write-level actions → require documents:write (unchanged)
--
-- Identity spoofing is still prevented: actor_id always comes from
-- auth.uid(), not from the caller. Clients can't insert directly — this
-- RPC remains the only path.

CREATE OR REPLACE FUNCTION public.record_file_event(
  p_file_attachment_id UUID,
  p_action TEXT,
  p_payload JSONB DEFAULT '{}'::jsonb
) RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_workspace_id UUID;
  v_event_id UUID;
  v_is_write_action BOOLEAN;
BEGIN
  SELECT fa.workspace_id INTO v_workspace_id
  FROM public.file_attachments fa
  WHERE fa.id = p_file_attachment_id;

  IF v_workspace_id IS NULL THEN
    RAISE EXCEPTION 'file_attachment % not found', p_file_attachment_id
      USING ERRCODE = 'no_data_found';
  END IF;

  -- Classify: write actions mutate the file record itself or its bytes /
  -- tags; read actions are observations by someone who already has access.
  v_is_write_action := p_action IN (
    'uploaded',
    'renamed',
    'described',
    'moved',
    'tagged_added',
    'tagged_removed',
    'deleted',
    'marked_up',
    'reverted_markup'
  );

  IF v_is_write_action THEN
    IF NOT public.has_workspace_module_permission(
      v_workspace_id, 'documents', 'write'
    ) THEN
      RAISE EXCEPTION 'not authorized to record write events for this file'
        USING ERRCODE = 'insufficient_privilege';
    END IF;
  ELSIF p_action IN ('commented', 'shared', 'downloaded') THEN
    -- Read-level: must be able to read files in this workspace AND the
    -- file itself must pass the tag visibility gate (so role-gated files
    -- don't leak events to users who can't see them).
    IF NOT public.has_workspace_module_permission(
      v_workspace_id, 'documents', 'read'
    ) OR NOT public.file_is_visible(p_file_attachment_id) THEN
      RAISE EXCEPTION 'not authorized to record events for this file'
        USING ERRCODE = 'insufficient_privilege';
    END IF;
  ELSE
    RAISE EXCEPTION 'unknown file event action: %', p_action
      USING ERRCODE = 'invalid_parameter_value';
  END IF;

  INSERT INTO public.file_events (
    workspace_id, file_attachment_id, actor_id, action, payload
  ) VALUES (
    v_workspace_id, p_file_attachment_id, auth.uid(), p_action, p_payload
  )
  RETURNING id INTO v_event_id;

  RETURN v_event_id;
END;
$$;

COMMENT ON FUNCTION public.record_file_event(UUID, TEXT, JSONB) IS
  'Append a row to file_events. Write-level actions require documents:write; '
  'read-level actions (commented, shared, downloaded) require documents:read '
  'plus file_is_visible(). actor_id is always stamped from auth.uid().';
