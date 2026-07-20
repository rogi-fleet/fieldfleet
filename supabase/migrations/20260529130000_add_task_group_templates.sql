-- Task group templates: save a group/phase of tasks (with hierarchy,
-- relative schedule, dependencies, checklists, and assignees) as a reusable
-- template that can be imported into any existing project.
--
-- Mirrors the project_templates pattern (migration 050) but is scoped to a
-- subtree of tasks that gets instantiated INTO an existing project rather than
-- creating a whole new project.
CREATE TABLE IF NOT EXISTS task_group_templates (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  description TEXT,
  -- Array of TaskGroupTemplateTask objects. Each carries a temp_id /
  -- parent_temp_id for hierarchy, a start_offset_days for relative scheduling,
  -- predecessor_temp_ids for in-set dependencies, assigned_to_ids, and
  -- checklist_items (titles).
  tasks JSONB NOT NULL DEFAULT '[]'::jsonb,
  created_by UUID NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_task_group_templates_workspace
  ON task_group_templates(workspace_id);

ALTER TABLE task_group_templates ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS task_group_templates_select ON task_group_templates;
CREATE POLICY task_group_templates_select ON task_group_templates
  FOR SELECT USING (is_workspace_member(workspace_id));

DROP POLICY IF EXISTS task_group_templates_insert ON task_group_templates;
CREATE POLICY task_group_templates_insert ON task_group_templates
  FOR INSERT WITH CHECK (is_workspace_member(workspace_id));

DROP POLICY IF EXISTS task_group_templates_update ON task_group_templates;
CREATE POLICY task_group_templates_update ON task_group_templates
  FOR UPDATE USING (is_workspace_member(workspace_id));

DROP POLICY IF EXISTS task_group_templates_delete ON task_group_templates;
CREATE POLICY task_group_templates_delete ON task_group_templates
  FOR DELETE USING (is_workspace_member(workspace_id));

DROP TRIGGER IF EXISTS set_task_group_templates_updated_at
  ON task_group_templates;
CREATE TRIGGER set_task_group_templates_updated_at
  BEFORE UPDATE ON task_group_templates
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();

-- Realtime: the template picker subscribes via .stream(), so the table must be
-- in the supabase_realtime publication for live updates (new/deleted templates).
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'task_group_templates'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE task_group_templates;
    RAISE NOTICE 'Added public.task_group_templates to supabase_realtime';
  END IF;
END $$;

ALTER TABLE public.task_group_templates REPLICA IDENTITY FULL;
