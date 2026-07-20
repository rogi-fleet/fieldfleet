-- AI text-to-floorplan generation rows.
--
-- One row per generation attempt for a given construction_plan. The
-- editor's `floorplan_scenes` row remains the head-only state (the
-- thing the user is editing). This table records the prompt, the
-- intermediate AI plan JSON, and the lifecycle status so the UI can
-- show progress / errors and we have an audit trail of what the model
-- produced if a user wants to "regenerate from previous" later.
--
-- Mirrors the shape of `ai_generated_plans` (see proposals/improve-
-- ai-project-onboarding.md): pre-insert with status='generating',
-- backend dispatch via unawaited(), realtime subscription on the UI
-- side. RLS matches construction_plans (workspace member for
-- read/write/insert/update; pm-or-admin for delete).

CREATE TABLE IF NOT EXISTS public.floorplan_generations (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  plan_id UUID NOT NULL
    REFERENCES public.construction_plans(id) ON DELETE CASCADE,
  workspace_id UUID NOT NULL
    REFERENCES public.workspaces(id) ON DELETE CASCADE,
  project_id UUID NOT NULL
    REFERENCES public.projects(id) ON DELETE CASCADE,
  user_id UUID REFERENCES public.users(id),
  prompt TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'generating',
  ai_plan_json JSONB,
  error_message TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT floorplan_generations_status_check
    CHECK (status IN ('generating', 'ready', 'failed'))
);

CREATE INDEX IF NOT EXISTS idx_floorplan_generations_plan
  ON public.floorplan_generations (plan_id);
CREATE INDEX IF NOT EXISTS idx_floorplan_generations_workspace
  ON public.floorplan_generations (workspace_id);

CREATE OR REPLACE TRIGGER update_floorplan_generations_updated_at
  BEFORE UPDATE ON public.floorplan_generations
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

COMMENT ON TABLE public.floorplan_generations IS
  'AI text-to-floorplan generation runs. One row per attempt; status '
  'transitions generating → ready | failed. ai_plan_json is the '
  'intermediate DSL the model produced (audit trail). The resulting '
  'Scene lands in floorplan_scenes.scene_json on success.';

-- ---------------------------------------------------------------------------
-- RLS — same workspace-membership rules as construction_plans.
-- ---------------------------------------------------------------------------
ALTER TABLE public.floorplan_generations ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS floorplan_generations_select ON public.floorplan_generations;
CREATE POLICY floorplan_generations_select ON public.floorplan_generations
  FOR SELECT USING (is_workspace_member(workspace_id));

DROP POLICY IF EXISTS floorplan_generations_insert ON public.floorplan_generations;
CREATE POLICY floorplan_generations_insert ON public.floorplan_generations
  FOR INSERT WITH CHECK (is_workspace_member(workspace_id));

DROP POLICY IF EXISTS floorplan_generations_update ON public.floorplan_generations;
CREATE POLICY floorplan_generations_update ON public.floorplan_generations
  FOR UPDATE USING (is_workspace_member(workspace_id));

DROP POLICY IF EXISTS floorplan_generations_delete ON public.floorplan_generations;
CREATE POLICY floorplan_generations_delete ON public.floorplan_generations
  FOR DELETE USING (is_pm_or_admin(workspace_id));

-- ---------------------------------------------------------------------------
-- Realtime — UI subscribes to status flips.
-- ---------------------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND tablename = 'floorplan_generations'
  ) THEN
    EXECUTE 'ALTER PUBLICATION supabase_realtime ADD TABLE floorplan_generations';
  END IF;
END $$;
