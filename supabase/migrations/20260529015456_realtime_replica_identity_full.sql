-- Realtime DELETE events: enable them across the app by giving every
-- RLS-enabled, realtime-published table a FULL replica identity.
--
-- Symptom (found 2026-05-29): deleting a structure on the project info
-- tab left the row visible in the list until a manual page reload, even though
-- the row was already gone from the database. Inserts and updates streamed
-- live; only deletes were missing.
--
-- Root cause: Supabase Realtime applies the table's RLS SELECT policy to every
-- change before forwarding it to a subscribed client. For INSERT/UPDATE it has
-- the full new row to evaluate the policy against. For DELETE, a table with the
-- default replica identity only emits the primary key in the WAL old-tuple, so
-- Realtime cannot evaluate RLS on the deleted row and therefore withholds the
-- DELETE event entirely. Audit showed ALL ~130 RLS + realtime tables had
-- REPLICA IDENTITY = default, so this affected every `.stream()`-backed list in
-- the app, not just properties.
--
-- Fix: REPLICA IDENTITY FULL writes the entire old row to the WAL on
-- UPDATE/DELETE, which lets Realtime run the RLS policy on deletes and broadcast
-- them. Cost is a modest increase in WAL volume on UPDATE/DELETE for these
-- tables — acceptable here and fully reversible (REPLICA IDENTITY DEFAULT).
--
-- Applied dynamically so it covers exactly the affected set and stays idempotent
-- (only touches tables still on the default identity); safe to re-run.

DO $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN
    SELECT c.relname
    FROM pg_publication_tables pt
    JOIN pg_class c ON c.relname = pt.tablename
    JOIN pg_namespace n ON n.oid = c.relnamespace AND n.nspname = pt.schemaname
    WHERE pt.pubname = 'supabase_realtime'
      AND pt.schemaname = 'public'
      AND c.relrowsecurity = true
      AND c.relreplident = 'd'  -- 'd' = default; skip anything already full/index/nothing
    ORDER BY c.relname
  LOOP
    EXECUTE format('ALTER TABLE public.%I REPLICA IDENTITY FULL;', r.relname);
    RAISE NOTICE 'Set REPLICA IDENTITY FULL on public.%', r.relname;
  END LOOP;
END $$;
