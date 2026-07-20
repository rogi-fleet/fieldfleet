-- SECURITY FIX: Add WITH CHECK clauses to UPDATE RLS policies on
-- floorplan_scenes and floorplan_generations.
--
-- Original migrations (20260502120000 and 20260503120000) wrote
-- UPDATE policies with only USING (...) — Postgres evaluates USING
-- against the OLD row but not the NEW row, so a workspace member
-- could `update floorplan_scenes set workspace_id = '<other>' where ...`
-- and the row would hop into another workspace they happen to also
-- belong to (or back-channel attacks if they don't).
--
-- The fix is to mirror the USING clause as WITH CHECK so the new row
-- must also pass workspace-membership for the UPDATE to be allowed.

-- ---------------------------------------------------------------------------
-- floorplan_scenes
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS floorplan_scenes_update ON public.floorplan_scenes;
CREATE POLICY floorplan_scenes_update ON public.floorplan_scenes
  FOR UPDATE
  USING (is_workspace_member(workspace_id))
  WITH CHECK (is_workspace_member(workspace_id));

-- ---------------------------------------------------------------------------
-- floorplan_generations
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS floorplan_generations_update
  ON public.floorplan_generations;
CREATE POLICY floorplan_generations_update ON public.floorplan_generations
  FOR UPDATE
  USING (is_workspace_member(workspace_id))
  WITH CHECK (is_workspace_member(workspace_id));
