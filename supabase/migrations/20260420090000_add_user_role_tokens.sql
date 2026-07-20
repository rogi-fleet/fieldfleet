-- user_role_tokens(workspace_uuid) — returns every "role token" the current
-- user satisfies in the given workspace. Used by downstream visibility
-- gates (file_tags.visible_to_roles, and future per-entity ACLs) to check
-- "does the user have ANY role in this required set?" via PostgreSQL's
-- array overlap operator (&&).
--
-- Tokens returned:
--   - legacy role enum string (e.g. 'admin', 'project_manager')
--   - role_template_id as text (when the member has a custom template)
--   - sentinel '*' for admins / master admins / is_admin templates
--     so they satisfy every gate without needing to enumerate roles
--
-- SECURITY DEFINER so callers in RLS policies don't need direct SELECT on
-- workspace_members; the function only reads the caller's own row.

CREATE OR REPLACE FUNCTION public.user_role_tokens(workspace_uuid UUID)
RETURNS TEXT[]
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  WITH membership AS (
    SELECT wm.role::TEXT AS role_str,
           wm.role_template_id,
           wm.role::TEXT IN ('admin', 'master_admin')
             OR coalesce(wrt.is_admin, FALSE) AS is_admin
    FROM public.workspace_members wm
    LEFT JOIN public.workspace_role_templates wrt
      ON wrt.id = wm.role_template_id
    WHERE wm.workspace_id = workspace_uuid
      AND wm.user_id = auth.uid()
    LIMIT 1
  )
  SELECT COALESCE(
    ARRAY(
      SELECT DISTINCT t FROM (
        SELECT role_str AS t FROM membership WHERE role_str IS NOT NULL
        UNION ALL
        SELECT role_template_id::TEXT FROM membership
          WHERE role_template_id IS NOT NULL
        UNION ALL
        SELECT '*' FROM membership WHERE is_admin
      ) s
    ),
    ARRAY[]::TEXT[]
  );
$$;

REVOKE ALL ON FUNCTION public.user_role_tokens(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.user_role_tokens(UUID) TO authenticated;

COMMENT ON FUNCTION public.user_role_tokens(UUID) IS
  'Returns the set of role tokens the calling user holds in the workspace. '
  'Includes the workspace_member_role enum string, the role_template_id '
  '(when set), and the sentinel ''*'' for admins. Use with array-overlap '
  '(&&) against a required_roles TEXT[] column to gate visibility.';
