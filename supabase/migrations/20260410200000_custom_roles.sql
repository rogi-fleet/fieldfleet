-- Migration: Custom Roles & Permissions
-- Evolve workspace_role_templates into the primary role system.
-- Members get linked to templates via role_template_id.
-- Legacy role enum column kept for backward compat and RLS fallback.

-- ============================================================================
-- 1. Extend workspace_role_templates with new columns
-- ============================================================================

ALTER TABLE workspace_role_templates
  ADD COLUMN IF NOT EXISTS is_admin BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS default_interface_mode TEXT NOT NULL DEFAULT 'manager'
    CHECK (default_interface_mode IN ('manager', 'field')),
  ADD COLUMN IF NOT EXISTS description TEXT,
  ADD COLUMN IF NOT EXISTS color TEXT;

-- Backfill is_admin for existing Admin system templates
UPDATE workspace_role_templates SET is_admin = TRUE WHERE role = 'admin';

-- Backfill default_interface_mode for Field Technician templates
UPDATE workspace_role_templates SET default_interface_mode = 'field' WHERE role = 'field_technician';

-- Remove role CHECK constraint so custom roles can have any role text or NULL
ALTER TABLE workspace_role_templates DROP CONSTRAINT IF EXISTS workspace_role_templates_role_check;

-- ============================================================================
-- 2. Add role_template_id FK to workspace_members
-- ============================================================================

ALTER TABLE workspace_members
  ADD COLUMN IF NOT EXISTS role_template_id UUID REFERENCES workspace_role_templates(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_workspace_members_role_template
  ON workspace_members(role_template_id);

-- ============================================================================
-- 3. Add role_template_id FK to workspace_invitations
-- ============================================================================

ALTER TABLE workspace_invitations
  ADD COLUMN IF NOT EXISTS role_template_id UUID REFERENCES workspace_role_templates(id) ON DELETE SET NULL;

-- ============================================================================
-- 4. Backfill role_template_id for existing members
-- ============================================================================

UPDATE workspace_members wm
SET role_template_id = wrt.id
FROM workspace_role_templates wrt
WHERE wm.workspace_id = wrt.workspace_id
  AND wm.role::TEXT = wrt.role
  AND wrt.is_system = TRUE
  AND wm.role_template_id IS NULL;

-- ============================================================================
-- 5. Update RLS helper functions (backward-compatible OR logic)
-- ============================================================================

CREATE OR REPLACE FUNCTION is_workspace_admin(workspace_uuid UUID)
RETURNS BOOLEAN AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM workspace_members wm
    LEFT JOIN workspace_role_templates wrt ON wrt.id = wm.role_template_id
    WHERE wm.workspace_id = workspace_uuid
      AND wm.user_id = auth.uid()
      AND (
        wrt.is_admin = TRUE       -- new: template-based
        OR wm.role = 'admin'      -- legacy: enum-based fallback
      )
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION is_pm_or_admin(workspace_uuid UUID)
RETURNS BOOLEAN AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM workspace_members wm
    LEFT JOIN workspace_role_templates wrt ON wrt.id = wm.role_template_id
    WHERE wm.workspace_id = workspace_uuid
      AND wm.user_id = auth.uid()
      AND (
        wrt.is_admin = TRUE
        OR (wrt.module_permissions->>'projects') = 'write'
        OR wm.role IN ('admin', 'project_manager')  -- legacy fallback
      )
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- 6. Update seed function to include new columns
-- ============================================================================

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
    is_admin,
    default_interface_mode,
    description,
    created_by
  )
  VALUES
    (
      p_workspace_id,
      'Admin',
      'admin',
      '{"projects":"write","budget":"write","documents":"write","team":"write","settings":"write"}'::jsonb,
      TRUE,
      TRUE,
      'manager',
      'Full access to all features and settings',
      p_created_by
    ),
    (
      p_workspace_id,
      'Project Manager',
      'project_manager',
      '{"projects":"write","budget":"write","documents":"write","team":"write","settings":"read"}'::jsonb,
      TRUE,
      FALSE,
      'manager',
      'Manage projects, budgets, and team members',
      p_created_by
    ),
    (
      p_workspace_id,
      'Field Technician',
      'field_technician',
      '{"projects":"write","budget":"none","documents":"read","team":"read","settings":"none"}'::jsonb,
      TRUE,
      FALSE,
      'field',
      'Field work, time tracking, and assigned tasks',
      p_created_by
    ),
    (
      p_workspace_id,
      'Client',
      'client',
      '{"projects":"read","budget":"none","documents":"read","team":"none","settings":"none"}'::jsonb,
      TRUE,
      FALSE,
      'manager',
      'Read-only access to shared project information',
      p_created_by
    )
  ON CONFLICT (workspace_id, name) DO NOTHING;
END;
$$;

-- Re-create trigger as SECURITY DEFINER (preserving fix from migration 058)
CREATE OR REPLACE FUNCTION trigger_seed_default_workspace_role_templates()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM seed_default_workspace_role_templates(NEW.id, NEW.owner_id);
  RETURN NEW;
END;
$$;
