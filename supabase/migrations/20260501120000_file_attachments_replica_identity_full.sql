-- Realtime DELETE events for file_attachments were being dropped by the
-- server-side `eq('workspace_id', ...)` filter on `.stream()` subscribers,
-- because the default REPLICA IDENTITY only replicates the primary key on
-- DELETE — leaving workspace_id null in the OLD payload, so the filter
-- never matched. The client only saw deletions on the next stream rebuild
-- (e.g. tab switch).
--
-- REPLICA IDENTITY FULL ships the full row with DELETE/UPDATE WAL entries
-- so realtime filters on any column work for deletes as well.

ALTER TABLE public.file_attachments REPLICA IDENTITY FULL;
