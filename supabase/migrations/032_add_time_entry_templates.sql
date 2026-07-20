-- Add time entry templates for quick time logging
CREATE TABLE IF NOT EXISTS time_entry_templates (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  task_id UUID NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
  default_hours NUMERIC DEFAULT 0,
  default_break_minutes INT DEFAULT 0,
  notes_template TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_time_entry_templates_workspace ON time_entry_templates(workspace_id);
CREATE INDEX IF NOT EXISTS idx_time_entry_templates_user ON time_entry_templates(user_id);

ALTER TABLE time_entry_templates ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS time_entry_templates_select ON time_entry_templates;
CREATE POLICY time_entry_templates_select ON time_entry_templates
  FOR SELECT USING (is_workspace_member(workspace_id));

DROP POLICY IF EXISTS time_entry_templates_insert ON time_entry_templates;
CREATE POLICY time_entry_templates_insert ON time_entry_templates
  FOR INSERT WITH CHECK (
    is_workspace_member(workspace_id)
    AND (
      (user_id IS NULL AND is_pm_or_admin(workspace_id))
      OR (user_id = auth.uid())
    )
  );

DROP POLICY IF EXISTS time_entry_templates_update ON time_entry_templates;
CREATE POLICY time_entry_templates_update ON time_entry_templates
  FOR UPDATE USING (
    is_workspace_member(workspace_id)
    AND (
      (user_id IS NULL AND is_pm_or_admin(workspace_id))
      OR (user_id = auth.uid())
    )
  );

DROP POLICY IF EXISTS time_entry_templates_delete ON time_entry_templates;
CREATE POLICY time_entry_templates_delete ON time_entry_templates
  FOR DELETE USING (
    is_workspace_member(workspace_id)
    AND (
      (user_id IS NULL AND is_pm_or_admin(workspace_id))
      OR (user_id = auth.uid())
    )
  );

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'set_time_entry_templates_updated_at') THEN
    CREATE TRIGGER set_time_entry_templates_updated_at
    BEFORE UPDATE ON time_entry_templates
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();
  END IF;
END $$;
