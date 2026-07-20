-- =============================================================================
-- Reusable selection-sheet templates (JobTread parity). A template is a JSONB
-- snapshot of a sheet (selections + their options) that can be re-applied to a
-- new project. Builder-only (RLS = workspace member).
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.selection_templates (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id UUID NOT NULL,
  name         TEXT NOT NULL,
  payload      JSONB NOT NULL DEFAULT '[]'::jsonb,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.selection_templates ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS selection_templates_select ON public.selection_templates;
CREATE POLICY selection_templates_select ON public.selection_templates
  FOR SELECT USING (is_workspace_member(workspace_id));
DROP POLICY IF EXISTS selection_templates_insert ON public.selection_templates;
CREATE POLICY selection_templates_insert ON public.selection_templates
  FOR INSERT WITH CHECK (is_workspace_member(workspace_id));
DROP POLICY IF EXISTS selection_templates_delete ON public.selection_templates;
CREATE POLICY selection_templates_delete ON public.selection_templates
  FOR DELETE USING (is_workspace_member(workspace_id));
