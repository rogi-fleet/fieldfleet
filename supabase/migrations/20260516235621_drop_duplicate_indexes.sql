-- =============================================================================
-- Drop duplicate indexes flagged by the Supabase performance advisor.
--
-- hr_applications has two byte-for-byte identical indexes on job_posting_id
-- (idx_hr_app_jp and idx_hr_apps_posting). messages has two identical partial
-- indexes on reply_to_id (idx_messages_reply_to and messages_reply_to_idx).
-- We keep the shorter / more conventional name in each pair and drop the
-- other so we stop paying maintenance + storage cost for the duplicate.
-- Applied to the live DB via the supabase MCP `apply_migration` tool.
-- =============================================================================

DROP INDEX IF EXISTS public.idx_hr_apps_posting;
DROP INDEX IF EXISTS public.messages_reply_to_idx;
