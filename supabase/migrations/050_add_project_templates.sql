-- Add project templates for saving and reusing project configurations
CREATE TABLE IF NOT EXISTS project_templates (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  description TEXT,
  project_settings JSONB NOT NULL DEFAULT '{}'::jsonb,
  tasks JSONB DEFAULT '[]'::jsonb,
  budget_items JSONB DEFAULT '[]'::jsonb,
  created_by UUID NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_project_templates_workspace ON project_templates(workspace_id);

ALTER TABLE project_templates ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS project_templates_select ON project_templates;
CREATE POLICY project_templates_select ON project_templates
  FOR SELECT USING (is_workspace_member(workspace_id));

DROP POLICY IF EXISTS project_templates_insert ON project_templates;
CREATE POLICY project_templates_insert ON project_templates
  FOR INSERT WITH CHECK (is_workspace_member(workspace_id));

DROP POLICY IF EXISTS project_templates_update ON project_templates;
CREATE POLICY project_templates_update ON project_templates
  FOR UPDATE USING (is_workspace_member(workspace_id));

DROP POLICY IF EXISTS project_templates_delete ON project_templates;
CREATE POLICY project_templates_delete ON project_templates
  FOR DELETE USING (is_workspace_member(workspace_id));

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'set_project_templates_updated_at') THEN
    CREATE TRIGGER set_project_templates_updated_at
    BEFORE UPDATE ON project_templates
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();
  END IF;
END $$;
