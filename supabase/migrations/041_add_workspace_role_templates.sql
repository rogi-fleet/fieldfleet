-- Migration: Add workspace-level role permission templates

CREATE TABLE IF NOT EXISTS workspace_role_templates (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  role TEXT,
  module_permissions JSONB NOT NULL DEFAULT '{}'::jsonb,
  is_system BOOLEAN NOT NULL DEFAULT FALSE,
  created_by UUID REFERENCES users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT workspace_role_templates_role_check CHECK (
    role IS NULL OR role IN ('admin', 'project_manager', 'field_technician', 'client')
  ),
  CONSTRAINT workspace_role_templates_permissions_object CHECK (
    jsonb_typeof(module_permissions) = 'object'
  ),
  CONSTRAINT workspace_role_templates_workspace_name_unique UNIQUE (workspace_id, name)
);

CREATE INDEX IF NOT EXISTS idx_workspace_role_templates_workspace
  ON workspace_role_templates(workspace_id);

CREATE INDEX IF NOT EXISTS idx_workspace_role_templates_role
  ON workspace_role_templates(workspace_id, role);

ALTER TABLE workspace_role_templates ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS workspace_role_templates_select ON workspace_role_templates;
CREATE POLICY workspace_role_templates_select ON workspace_role_templates
  FOR SELECT USING (is_workspace_member(workspace_id));

DROP POLICY IF EXISTS workspace_role_templates_insert ON workspace_role_templates;
CREATE POLICY workspace_role_templates_insert ON workspace_role_templates
  FOR INSERT WITH CHECK (is_workspace_admin(workspace_id));

DROP POLICY IF EXISTS workspace_role_templates_update ON workspace_role_templates;
CREATE POLICY workspace_role_templates_update ON workspace_role_templates
  FOR UPDATE USING (is_workspace_admin(workspace_id));

DROP POLICY IF EXISTS workspace_role_templates_delete ON workspace_role_templates;
CREATE POLICY workspace_role_templates_delete ON workspace_role_templates
  FOR DELETE USING (is_workspace_admin(workspace_id));

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = 'set_workspace_role_templates_updated_at'
  ) THEN
    CREATE TRIGGER set_workspace_role_templates_updated_at
    BEFORE UPDATE ON workspace_role_templates
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();
  END IF;
END $$;

CREATE OR REPLACE FUNCTION seed_default_workspace_role_templates(
  p_workspace_id UUID,
  p_created_by UUID DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
  INSERT INTO workspace_role_templates (
    workspace_id,
    name,
    role,
    module_permissions,
    is_system,
    created_by
  )
  VALUES
    (
      p_workspace_id,
      'Admin',
      'admin',
      '{"projects":"write","budget":"write","documents":"write","team":"write","settings":"write"}'::jsonb,
      TRUE,
      p_created_by
    ),
    (
      p_workspace_id,
      'Project Manager',
      'project_manager',
      '{"projects":"write","budget":"write","documents":"write","team":"write","settings":"read"}'::jsonb,
      TRUE,
      p_created_by
    ),
    (
      p_workspace_id,
      'Field Technician',
      'field_technician',
      '{"projects":"write","budget":"none","documents":"read","team":"read","settings":"none"}'::jsonb,
      TRUE,
      p_created_by
    ),
    (
      p_workspace_id,
      'Client',
      'client',
      '{"projects":"read","budget":"none","documents":"read","team":"none","settings":"none"}'::jsonb,
      TRUE,
      p_created_by
    )
  ON CONFLICT (workspace_id, name) DO NOTHING;
END;
$$;

-- Seed defaults for existing workspaces
SELECT seed_default_workspace_role_templates(id, owner_id)
FROM workspaces;

CREATE OR REPLACE FUNCTION trigger_seed_default_workspace_role_templates()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  PERFORM seed_default_workspace_role_templates(NEW.id, NEW.owner_id);
  RETURN NEW;
END;
$$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = 'seed_workspace_role_templates_on_workspace_create'
  ) THEN
    CREATE TRIGGER seed_workspace_role_templates_on_workspace_create
    AFTER INSERT ON workspaces
    FOR EACH ROW
    EXECUTE FUNCTION trigger_seed_default_workspace_role_templates();
  END IF;
END $$;
