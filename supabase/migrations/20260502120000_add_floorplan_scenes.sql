-- 2D Planner: structured floorplan scenes per construction_plan.
--
-- A scene is the vector data for an interactive floorplan editor — walls,
-- doors, windows, areas (auto-derived), items, annotations. Stored as one
-- JSONB blob per construction_plan (UNIQUE on plan_id). Editor-only plans
-- (drawn from scratch, no PDF) get a construction_plans row with NULL
-- file_url and a floorplan_scenes row holding the geometry.
--
-- Scene JSON shape lives in lib/services/floorplan/scene_io.dart; the JSON
-- is opaque to Postgres beyond storage. See lib/models/floorplan/scene.dart
-- for the typed Dart model.
--
-- Also fixes a long-standing schema/code mismatch: SupabasePlanService
-- references construction_plans.storage_path (added below) and the upload
-- flow now needs file_url to be nullable so editor-only plans can exist.

-- ---------------------------------------------------------------------------
-- Backfill construction_plans for editor support
-- ---------------------------------------------------------------------------
ALTER TABLE public.construction_plans
  ADD COLUMN IF NOT EXISTS storage_path TEXT;

ALTER TABLE public.construction_plans
  ALTER COLUMN file_url DROP NOT NULL;

ALTER TABLE public.construction_plans
  ALTER COLUMN file_name DROP NOT NULL;

ALTER TABLE public.construction_plans
  ALTER COLUMN file_size DROP NOT NULL;

COMMENT ON COLUMN public.construction_plans.storage_path IS
  'Storage object path inside the project-plans bucket. NULL for editor-only plans.';

-- The "plans" view aliases construction_plans for service-layer compatibility
-- (see migration 004). It must be recreated to expose the new storage_path
-- column so SupabasePlanService.uploadPlanBytes can write through it.
--
-- Postgres CREATE OR REPLACE VIEW only allows *appending* columns — it
-- refuses if existing column positions or names change. So we keep the
-- original column order intact and tack storage_path on the end.
CREATE OR REPLACE VIEW public.plans AS
SELECT
  id,
  workspace_id,
  project_id,
  name,
  discipline,
  sheet_number,
  version,
  is_current_version,
  drawing_date,
  file_url,
  file_name,
  file_size,
  uploaded_by,
  uploaded_at,
  notes,
  linked_task_ids,
  created_at,
  updated_at,
  storage_path
FROM public.construction_plans;

-- ---------------------------------------------------------------------------
-- floorplan_scenes — one row per construction_plan
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.floorplan_scenes (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  plan_id UUID NOT NULL UNIQUE
    REFERENCES public.construction_plans(id) ON DELETE CASCADE,
  workspace_id UUID NOT NULL REFERENCES public.workspaces(id) ON DELETE CASCADE,
  project_id UUID NOT NULL REFERENCES public.projects(id) ON DELETE CASCADE,
  scene_json JSONB NOT NULL,
  thumbnail_url TEXT,
  scene_version INTEGER NOT NULL DEFAULT 1,
  last_edited_by UUID REFERENCES public.users(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_floorplan_scenes_workspace
  ON public.floorplan_scenes (workspace_id);
CREATE INDEX IF NOT EXISTS idx_floorplan_scenes_project
  ON public.floorplan_scenes (project_id);

CREATE OR REPLACE TRIGGER update_floorplan_scenes_updated_at
  BEFORE UPDATE ON public.floorplan_scenes
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

COMMENT ON TABLE public.floorplan_scenes IS
  '2D planner scene (vector floorplan) attached 1:1 to a construction_plan. '
  'scene_json is the typed scene; thumbnail_url is a rendered PNG preview.';
COMMENT ON COLUMN public.floorplan_scenes.scene_version IS
  'Optimistic-locking counter. Bumped on every upsert; client compares to '
  'detect concurrent edits and warns the user before overwriting.';

-- ---------------------------------------------------------------------------
-- RLS — same workspace-membership rules as construction_plans
-- ---------------------------------------------------------------------------
ALTER TABLE public.floorplan_scenes ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS floorplan_scenes_select ON public.floorplan_scenes;
CREATE POLICY floorplan_scenes_select ON public.floorplan_scenes
  FOR SELECT USING (is_workspace_member(workspace_id));

DROP POLICY IF EXISTS floorplan_scenes_insert ON public.floorplan_scenes;
CREATE POLICY floorplan_scenes_insert ON public.floorplan_scenes
  FOR INSERT WITH CHECK (is_workspace_member(workspace_id));

DROP POLICY IF EXISTS floorplan_scenes_update ON public.floorplan_scenes;
CREATE POLICY floorplan_scenes_update ON public.floorplan_scenes
  FOR UPDATE USING (is_workspace_member(workspace_id));

DROP POLICY IF EXISTS floorplan_scenes_delete ON public.floorplan_scenes;
CREATE POLICY floorplan_scenes_delete ON public.floorplan_scenes
  FOR DELETE USING (is_pm_or_admin(workspace_id));

-- ---------------------------------------------------------------------------
-- Realtime — clients subscribe to scene updates for live collab + autosave
-- conflict detection
-- ---------------------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'floorplan_scenes'
  ) THEN
    EXECUTE 'ALTER PUBLICATION supabase_realtime ADD TABLE floorplan_scenes';
  END IF;
END $$;
