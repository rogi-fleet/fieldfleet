-- Phase 2: role-based tag visibility + soft-archive for file_tags.
--
-- Tags gain a visible_to_roles TEXT[] column that gates access via UNION
-- semantics: a file tagged with at least one role-gated tag is visible to
-- users whose user_role_tokens(workspace) overlaps any gated tag's role
-- list. Ungated tags (empty array) remain visible to every workspace
-- member. Files with no gated tags stay visible by default — the gate
-- only kicks in once at least one tag attached to the file is gated.
--
-- Archived tags survive but disappear from pickers; existing join rows on
-- files keep rendering the archived label until the user removes them.

-- ---------------------------------------------------------------------------
-- Columns
-- ---------------------------------------------------------------------------
ALTER TABLE public.file_tags
  ADD COLUMN IF NOT EXISTS visible_to_roles TEXT[] NOT NULL DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS archived_at TIMESTAMPTZ;

COMMENT ON COLUMN public.file_tags.visible_to_roles IS
  'When non-empty, only users whose user_role_tokens() overlap this array '
  'can see files tagged exclusively with role-gated tags. Empty array = '
  'visible to every workspace member. Admin sentinel ''*'' always matches.';
COMMENT ON COLUMN public.file_tags.archived_at IS
  'Soft-delete marker. Archived tags hide from pickers but remain attached '
  'to files that already carry them.';

-- ---------------------------------------------------------------------------
-- file_is_visible(fa_id) — union semantics
-- ---------------------------------------------------------------------------
--
-- Returns TRUE iff the caller can see the file. Rules:
--   - If the file has no tags, OR none of its tags are role-gated, TRUE.
--   - Else (some tag is gated) TRUE iff any gated tag's visible_to_roles
--     overlaps the caller's user_role_tokens() for this file's workspace.
--
-- STABLE so the planner may memoize per row within a single query.
CREATE OR REPLACE FUNCTION public.file_is_visible(fa_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  WITH fa AS (
    SELECT workspace_id FROM public.file_attachments WHERE id = fa_id
  ),
  tags AS (
    SELECT ft.visible_to_roles
    FROM public.file_attachment_tags fat
    JOIN public.file_tags ft ON ft.id = fat.file_tag_id
    WHERE fat.file_attachment_id = fa_id
  ),
  gated AS (
    SELECT visible_to_roles FROM tags
    WHERE visible_to_roles IS NOT NULL
      AND array_length(visible_to_roles, 1) > 0
  )
  SELECT
    NOT EXISTS (SELECT 1 FROM gated)
    OR EXISTS (
      SELECT 1 FROM gated g, fa
      WHERE g.visible_to_roles
            && public.user_role_tokens(fa.workspace_id)
    );
$$;

REVOKE ALL ON FUNCTION public.file_is_visible(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.file_is_visible(UUID) TO authenticated;

COMMENT ON FUNCTION public.file_is_visible(UUID) IS
  'Caller-aware visibility check for a file_attachment row. Returns true '
  'when every role-gated tag on the file overlaps the caller''s role '
  'tokens (union semantics), or when the file has no role-gated tags.';

-- ---------------------------------------------------------------------------
-- file_attachments_select — AND in the visibility gate
-- ---------------------------------------------------------------------------
-- Existing policy already checks documents:read; we extend with the gate.
DROP POLICY IF EXISTS file_attachments_select ON public.file_attachments;
CREATE POLICY file_attachments_select ON public.file_attachments
  FOR SELECT USING (
    public.has_workspace_module_permission(workspace_id, 'documents', 'read')
    AND public.file_is_visible(id)
  );

-- ---------------------------------------------------------------------------
-- file_tags_select — hide gated tags from users who lack the role + hide
-- archived tags from default reads (callers that want archived opt in via
-- a separate RPC or admin-only query).
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS file_tags_select ON public.file_tags;
CREATE POLICY file_tags_select ON public.file_tags
  FOR SELECT USING (
    public.has_workspace_module_permission(workspace_id, 'documents', 'read')
    AND (
      -- Ungated tag: visible to any reader.
      visible_to_roles IS NULL
      OR array_length(visible_to_roles, 1) IS NULL
      OR array_length(visible_to_roles, 1) = 0
      -- Gated tag: visible iff caller's role tokens overlap.
      OR visible_to_roles && public.user_role_tokens(workspace_id)
    )
  );

-- Note: we deliberately do NOT filter archived tags in the SELECT policy.
-- Archived tags must remain visible when already attached to a file so the
-- detail panel renders their chips. The tag manager screen filters archived
-- on the client side.
