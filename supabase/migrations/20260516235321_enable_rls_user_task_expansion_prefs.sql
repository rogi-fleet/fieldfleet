-- =============================================================================
-- Enable RLS on user_task_expansion_prefs.
--
-- The "Users can manage own expansion prefs" policy was already declared on
-- this table (back in migration 009_user_task_expansion_prefs), but RLS was
-- never turned on for the table itself. PostgreSQL silently ignores policies
-- on tables where RLS is disabled, so every authenticated user could read
-- and modify any other user's task-row expansion state.
--
-- Surfaced by the Supabase security advisor as `policy_exists_rls_disabled`.
-- Applied to the live DB via the supabase MCP `apply_migration` tool; this
-- file checks the change into git so re-deploys and fresh environments pick
-- it up too.
-- =============================================================================

ALTER TABLE public.user_task_expansion_prefs ENABLE ROW LEVEL SECURITY;
