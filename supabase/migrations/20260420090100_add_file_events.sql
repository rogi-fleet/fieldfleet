-- file_events — append-only audit trail per file_attachment.
--
-- Every meaningful action on a file lands here (upload, rename, move, tag
-- add/remove, comment, markup, revert, delete, download, share). Phase 5
-- of the files/photos plan renders these as a timeline in the detail panel.
--
-- Writes are client-forgery-proof: the only insert path is the
-- `record_file_event` SECURITY DEFINER RPC, which verifies workspace
-- membership and stamps the actor from auth.uid(). Clients have no direct
-- INSERT grant, even though RLS would allow it for members.

CREATE TABLE IF NOT EXISTS public.file_events (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  workspace_id UUID NOT NULL REFERENCES public.workspaces(id) ON DELETE CASCADE,
  file_attachment_id UUID NOT NULL REFERENCES public.file_attachments(id)
    ON DELETE CASCADE,
  actor_id UUID REFERENCES public.users(id),
  action TEXT NOT NULL,
  payload JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_file_events_file
  ON public.file_events (file_attachment_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_file_events_workspace
  ON public.file_events (workspace_id, created_at DESC);

COMMENT ON TABLE public.file_events IS
  'Append-only audit trail for file_attachments. Populated only via '
  'record_file_event(). Rendered as the "Activity" timeline in the file '
  'detail panel.';

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------
ALTER TABLE public.file_events ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS file_events_select ON public.file_events;
CREATE POLICY file_events_select ON public.file_events
  FOR SELECT USING (
    public.has_workspace_module_permission(workspace_id, 'documents', 'read')
  );

-- No insert/update/delete policies: clients never write directly. All writes
-- go through record_file_event() below.
REVOKE INSERT, UPDATE, DELETE ON public.file_events FROM authenticated;

-- ---------------------------------------------------------------------------
-- record_file_event — the only client-callable write path
-- ---------------------------------------------------------------------------
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
BEGIN
  -- Resolve the file's workspace and verify membership + 'documents' write
  -- permission. A user who can't write documents can't record events — this
  -- matches who is allowed to mutate files in the first place.
  SELECT fa.workspace_id INTO v_workspace_id
  FROM public.file_attachments fa
  WHERE fa.id = p_file_attachment_id;

  IF v_workspace_id IS NULL THEN
    RAISE EXCEPTION 'file_attachment % not found', p_file_attachment_id
      USING ERRCODE = 'no_data_found';
  END IF;

  IF NOT public.has_workspace_module_permission(
    v_workspace_id, 'documents', 'write'
  ) THEN
    RAISE EXCEPTION 'not authorized to record events for this file'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- Validate action against the known set. Extend this list as new event
  -- types ship; unknown actions are rejected to keep the timeline clean.
  IF p_action NOT IN (
    'uploaded',
    'renamed',
    'described',
    'moved',
    'tagged_added',
    'tagged_removed',
    'deleted',
    'commented',
    'marked_up',
    'reverted_markup',
    'shared',
    'downloaded'
  ) THEN
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

REVOKE ALL ON FUNCTION public.record_file_event(UUID, TEXT, JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.record_file_event(UUID, TEXT, JSONB)
  TO authenticated;

COMMENT ON FUNCTION public.record_file_event(UUID, TEXT, JSONB) IS
  'Append a row to file_events. Validates the action name, resolves the '
  'file''s workspace, checks documents:write, and stamps actor from '
  'auth.uid(). Only legitimate path for clients to write events.';

-- ---------------------------------------------------------------------------
-- Realtime
-- ---------------------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'file_events'
  ) THEN
    EXECUTE 'ALTER PUBLICATION supabase_realtime ADD TABLE file_events';
  END IF;
END $$;
