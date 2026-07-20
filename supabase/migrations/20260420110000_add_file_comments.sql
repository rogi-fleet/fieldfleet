-- Phase 3: per-file comments with @mentions and inline attachments.
--
-- One level of nesting (parent + replies) via parent_comment_id. Mention
-- deliveries fan out on the Dart side through the existing notification +
-- Resend email edge function that task_comment_service already uses; see
-- lib/services/supabase/file_comment_service.dart. Comment inheritance of
-- file visibility is enforced by RLS checking file_is_visible() against
-- the parent file_attachment row on every read.

CREATE TABLE IF NOT EXISTS public.file_comments (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  workspace_id UUID NOT NULL REFERENCES public.workspaces(id) ON DELETE CASCADE,
  file_attachment_id UUID NOT NULL REFERENCES public.file_attachments(id)
    ON DELETE CASCADE,
  parent_comment_id UUID REFERENCES public.file_comments(id) ON DELETE CASCADE,
  author_id UUID NOT NULL REFERENCES public.users(id),
  body TEXT NOT NULL,
  mentioned_user_ids UUID[] NOT NULL DEFAULT '{}',
  attachment_ids UUID[] NOT NULL DEFAULT '{}',
  edited_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_file_comments_file
  ON public.file_comments (file_attachment_id, created_at);

CREATE INDEX IF NOT EXISTS idx_file_comments_workspace
  ON public.file_comments (workspace_id, created_at);

CREATE INDEX IF NOT EXISTS idx_file_comments_parent
  ON public.file_comments (parent_comment_id)
  WHERE parent_comment_id IS NOT NULL;

COMMENT ON TABLE public.file_comments IS
  'Threaded per-file discussion. Inherits visibility from the parent '
  'file_attachment via file_is_visible(), so role-gated files hide their '
  'comment threads from unauthorized readers.';

-- ---------------------------------------------------------------------------
-- RLS — every operation gates on the parent file's visibility
-- ---------------------------------------------------------------------------
ALTER TABLE public.file_comments ENABLE ROW LEVEL SECURITY;

-- A single helper expression cuts policy boilerplate in half. Re-evaluated
-- per row because RLS doesn't support leakproof subqueries cleanly.
DROP POLICY IF EXISTS file_comments_select ON public.file_comments;
CREATE POLICY file_comments_select ON public.file_comments
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.file_attachments fa
      WHERE fa.id = file_attachment_id
        AND public.has_workspace_module_permission(
          fa.workspace_id, 'documents', 'read'
        )
        AND public.file_is_visible(fa.id)
    )
  );

DROP POLICY IF EXISTS file_comments_insert ON public.file_comments;
CREATE POLICY file_comments_insert ON public.file_comments
  FOR INSERT WITH CHECK (
    author_id = auth.uid()
    AND EXISTS (
      SELECT 1 FROM public.file_attachments fa
      WHERE fa.id = file_attachment_id
        AND public.has_workspace_module_permission(
          fa.workspace_id, 'documents', 'read'
        )
        AND public.file_is_visible(fa.id)
    )
  );

DROP POLICY IF EXISTS file_comments_update ON public.file_comments;
CREATE POLICY file_comments_update ON public.file_comments
  FOR UPDATE
  USING (author_id = auth.uid())
  WITH CHECK (author_id = auth.uid());

DROP POLICY IF EXISTS file_comments_delete ON public.file_comments;
CREATE POLICY file_comments_delete ON public.file_comments
  FOR DELETE USING (
    author_id = auth.uid()
    OR EXISTS (
      SELECT 1 FROM public.file_attachments fa
      WHERE fa.id = file_attachment_id
        AND public.has_workspace_module_permission(
          fa.workspace_id, 'documents', 'write'
        )
    )
  );

-- ---------------------------------------------------------------------------
-- Realtime
-- ---------------------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'file_comments'
  ) THEN
    EXECUTE 'ALTER PUBLICATION supabase_realtime ADD TABLE file_comments';
  END IF;
END $$;
