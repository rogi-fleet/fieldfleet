-- =============================================================================
-- Per-selection messaging (JobTread parity: "message back-and-forth with your
-- clients" on each selection). A lightweight comment thread per selection.
--
-- Builder (workspace members) read/write via RLS. Clients read/write through
-- SECURITY DEFINER portal RPCs gated to the project's active customer contacts.
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.selection_comments (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  selection_id   UUID NOT NULL REFERENCES public.selections(id) ON DELETE CASCADE,
  workspace_id   UUID NOT NULL,
  body           TEXT NOT NULL,
  author_name    TEXT,
  author_email   TEXT,
  is_from_client BOOLEAN NOT NULL DEFAULT FALSE,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS selection_comments_selection_idx
  ON public.selection_comments (selection_id, created_at);

ALTER TABLE public.selection_comments ENABLE ROW LEVEL SECURITY;

-- Workspace members (builders) can read and post on their workspace's threads.
DROP POLICY IF EXISTS selection_comments_member_select ON public.selection_comments;
CREATE POLICY selection_comments_member_select ON public.selection_comments
  FOR SELECT USING (is_workspace_member(workspace_id));

DROP POLICY IF EXISTS selection_comments_member_insert ON public.selection_comments;
CREATE POLICY selection_comments_member_insert ON public.selection_comments
  FOR INSERT WITH CHECK (is_workspace_member(workspace_id));

-- Live updates on the board/editor.
ALTER TABLE public.selection_comments REPLICA IDENTITY FULL;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
     WHERE pubname = 'supabase_realtime' AND tablename = 'selection_comments'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.selection_comments;
  END IF;
END$$;

-- ── Portal RPCs (client side) ────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.portal_list_selection_comments(
  p_selection_id UUID
)
RETURNS TABLE (
  id             UUID,
  body           TEXT,
  author_name    TEXT,
  is_from_client BOOLEAN,
  created_at     TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  normalized_email TEXT := LOWER(TRIM(COALESCE(auth.jwt() ->> 'email', '')));
  v_allowed BOOLEAN;
BEGIN
  IF normalized_email = '' THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;
  SELECT EXISTS (
    SELECT 1 FROM selections s
    JOIN projects p ON p.id = s.project_id
    JOIN customer_contacts cc ON cc.customer_id = p.client_id
    WHERE s.id = p_selection_id
      AND cc.is_active = TRUE
      AND LOWER(TRIM(COALESCE(cc.email, ''))) = normalized_email
  ) INTO v_allowed;
  IF NOT v_allowed THEN
    RAISE EXCEPTION 'Selection not found or access denied';
  END IF;

  RETURN QUERY
    SELECT c.id, c.body, c.author_name, c.is_from_client, c.created_at
      FROM selection_comments c
     WHERE c.selection_id = p_selection_id
     ORDER BY c.created_at;
END;
$$;

CREATE OR REPLACE FUNCTION public.portal_add_selection_comment(
  p_selection_id UUID,
  p_body TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  normalized_email TEXT := LOWER(TRIM(COALESCE(auth.jwt() ->> 'email', '')));
  v_workspace UUID;
  v_name TEXT;
BEGIN
  IF normalized_email = '' THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;
  IF COALESCE(TRIM(p_body), '') = '' THEN
    RAISE EXCEPTION 'Message cannot be empty';
  END IF;

  SELECT s.workspace_id, cc.name
    INTO v_workspace, v_name
    FROM selections s
    JOIN projects p ON p.id = s.project_id
    JOIN customer_contacts cc ON cc.customer_id = p.client_id
   WHERE s.id = p_selection_id
     AND cc.is_active = TRUE
     AND LOWER(TRIM(COALESCE(cc.email, ''))) = normalized_email
   LIMIT 1;

  IF v_workspace IS NULL THEN
    RAISE EXCEPTION 'Selection not found or access denied';
  END IF;

  INSERT INTO selection_comments
    (selection_id, workspace_id, body, author_name, author_email, is_from_client)
  VALUES
    (p_selection_id, v_workspace, TRIM(p_body),
     COALESCE(NULLIF(TRIM(v_name), ''), 'Client'), normalized_email, TRUE);

  RETURN jsonb_build_object('success', true);
END;
$$;

REVOKE ALL ON FUNCTION public.portal_list_selection_comments(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.portal_list_selection_comments(UUID) TO authenticated;
REVOKE ALL ON FUNCTION public.portal_add_selection_comment(UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.portal_add_selection_comment(UUID, TEXT) TO authenticated;
