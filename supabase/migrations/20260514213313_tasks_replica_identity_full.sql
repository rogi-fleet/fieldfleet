-- =============================================================================
-- tasks: REPLICA IDENTITY FULL for correct realtime DELETE events
-- =============================================================================
-- The task list/board views subscribe via
-- `_supabase.from('tasks').stream(primaryKey: ['id']).eq('workspace_id', ...)`.
-- With the default REPLICA IDENTITY, realtime DELETE events only carry the
-- primary key in the OLD record — they have no `workspace_id`/`project_id`,
-- so the SDK's `.eq()` filter can never match a delete and the removed row
-- lingers in the UI until a manual reload.
--
-- REPLICA IDENTITY FULL makes Postgres emit the full OLD row on DELETE, so the
-- filter matches and deletions propagate to subscribed clients immediately.
-- =============================================================================

ALTER TABLE public.tasks REPLICA IDENTITY FULL;
