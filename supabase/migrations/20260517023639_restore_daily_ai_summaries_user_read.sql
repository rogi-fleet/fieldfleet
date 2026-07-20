-- Restore the user-read policy on daily_ai_summaries that the previous
-- batch (drop_legacy_overlapping_rls_policies) swept up by accident: its
-- original name had a space ("Users can read their own daily summaries")
-- so it matched the legacy-name filter even though it was the only
-- user-facing read policy on the table. Recreated under a snake_case
-- name so future cleanup leaves it alone.

CREATE POLICY daily_ai_summaries_user_read ON public.daily_ai_summaries
  AS PERMISSIVE FOR SELECT
  USING (user_id = (SELECT auth.uid()));
