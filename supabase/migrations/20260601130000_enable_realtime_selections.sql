-- Enable Supabase Realtime for selections + selection_options.
--
-- Symptom (found 2026-06-01): creating a selection on the project Selections
-- board did not show the new card until a manual page reload. The summary strip
-- (Total Allowance / Pending) also stayed stale. SupabaseSelectionService
-- .watchByProject() uses two `.stream()` subscriptions (selections and
-- selection_options), but neither table was in the `supabase_realtime`
-- publication, so the streams only ever delivered their initial snapshot and
-- never any live INSERT/UPDATE/DELETE — hence the reload requirement.
--
-- Root cause: the tables were created (20260521020000_add_selections) without
-- being added to the realtime publication, and the app-wide REPLICA IDENTITY
-- FULL sweep (20260529015456) only touched tables ALREADY in the publication,
-- so it skipped these two on both counts.
--
-- Fix (two parts, mirroring the established pattern):
--   1. ADD both tables to the supabase_realtime publication (idempotent guard,
--      same as 011_enable_realtime_budget_items).
--   2. Set REPLICA IDENTITY FULL on both so UPDATE/DELETE events carry the full
--      old row — Realtime needs it to evaluate the RLS SELECT policy on those
--      events and forward them (per 20260529015456). Without this, approving /
--      declining / deleting a selection still wouldn't live-update — only
--      inserts would. Fully reversible (REPLICA IDENTITY DEFAULT); modest WAL
--      cost on UPDATE/DELETE for these two low-volume tables.
--
-- Safe to re-run.

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'selections'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE selections;
    RAISE NOTICE 'Added public.selections to supabase_realtime';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'selection_options'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE selection_options;
    RAISE NOTICE 'Added public.selection_options to supabase_realtime';
  END IF;
END $$;

ALTER TABLE public.selections        REPLICA IDENTITY FULL;
ALTER TABLE public.selection_options REPLICA IDENTITY FULL;
