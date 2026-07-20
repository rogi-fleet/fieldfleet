-- Custom field definitions + per-entity value column.
--
-- v1 covers projects only. The `entity_type` discriminator is in place for
-- customers / cost_items / vendors / vendor_contacts in later phases — those
-- will require their own value column + validation trigger but no schema
-- change to this table.
--
-- Design notes (see docs/plans/custom-fields.md):
--   * `key` is a stable surrogate (nanoid in client) — NEVER derived from
--     `label`. Renaming the label is free; delete+recreate gets a fresh key
--     so values never silently inherit.
--   * `field_group` is admin-defined free text used purely for UI grouping
--     (collapsible subsection in the project form). NULL = renders in
--     "Other".
--   * Archive (not delete). Existing project values for archived defs stay
--     visible read-only.
--   * `groupable` flips on a per-field basis. The actual side-table sync
--     trigger lives in the next migration; toggling this flag without that
--     migration is a no-op.

-- ---------------------------------------------------------------------------
-- custom_field_definitions
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS custom_field_definitions (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
  entity_type TEXT NOT NULL
    CHECK (entity_type IN ('project')),  -- expand: 'customer', 'cost_item', 'vendor', 'vendor_contact'
  key TEXT NOT NULL,
  label TEXT NOT NULL,
  field_group TEXT,
  type TEXT NOT NULL
    CHECK (type IN (
      'text', 'longText', 'number', 'date',
      'picklist', 'multiSelect', 'checkbox', 'file', 'photo'
    )),
  options JSONB,
  default_value JSONB,
  is_required BOOLEAN NOT NULL DEFAULT FALSE,
  show_in_form BOOLEAN NOT NULL DEFAULT TRUE,
  groupable BOOLEAN NOT NULL DEFAULT FALSE,
  sort_order INT NOT NULL DEFAULT 0,
  archived_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_by UUID REFERENCES users(id),
  UNIQUE (workspace_id, entity_type, key)
);

CREATE INDEX IF NOT EXISTS idx_custom_field_definitions_active
  ON custom_field_definitions (workspace_id, entity_type, sort_order)
  WHERE archived_at IS NULL;

CREATE OR REPLACE TRIGGER update_custom_field_definitions_updated_at
  BEFORE UPDATE ON custom_field_definitions
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------
ALTER TABLE custom_field_definitions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS custom_field_definitions_select ON custom_field_definitions;
CREATE POLICY custom_field_definitions_select ON custom_field_definitions
  FOR SELECT USING (is_workspace_member(workspace_id));

-- Only PMs/admins can mutate definitions. Field users cannot create or
-- archive — they only fill in values on records.
DROP POLICY IF EXISTS custom_field_definitions_insert ON custom_field_definitions;
CREATE POLICY custom_field_definitions_insert ON custom_field_definitions
  FOR INSERT WITH CHECK (is_pm_or_admin(workspace_id));

DROP POLICY IF EXISTS custom_field_definitions_update ON custom_field_definitions;
CREATE POLICY custom_field_definitions_update ON custom_field_definitions
  FOR UPDATE USING (is_pm_or_admin(workspace_id));

DROP POLICY IF EXISTS custom_field_definitions_delete ON custom_field_definitions;
CREATE POLICY custom_field_definitions_delete ON custom_field_definitions
  FOR DELETE USING (is_pm_or_admin(workspace_id));

-- ---------------------------------------------------------------------------
-- Soft cap: 50 active definitions per (workspace, entity_type).
--
-- Surfaced in the UI as a warning before the cap; this trigger is the hard
-- backstop so CSV import / API can't blow past it.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION enforce_custom_field_definitions_cap()
RETURNS TRIGGER
LANGUAGE plpgsql AS $$
DECLARE
  v_active_count INT;
BEGIN
  IF NEW.archived_at IS NOT NULL THEN
    RETURN NEW;
  END IF;
  SELECT COUNT(*) INTO v_active_count
  FROM custom_field_definitions
  WHERE workspace_id = NEW.workspace_id
    AND entity_type = NEW.entity_type
    AND archived_at IS NULL
    AND id IS DISTINCT FROM NEW.id;
  IF v_active_count >= 50 THEN
    RAISE EXCEPTION
      'custom field cap reached: % already has 50 active fields on %',
      NEW.workspace_id, NEW.entity_type
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_enforce_cfd_cap ON custom_field_definitions;
CREATE TRIGGER trg_enforce_cfd_cap
  BEFORE INSERT OR UPDATE OF archived_at ON custom_field_definitions
  FOR EACH ROW EXECUTE FUNCTION enforce_custom_field_definitions_cap();

-- ---------------------------------------------------------------------------
-- projects.custom_fields — jsonb bag of key -> value, keyed by definition.key
-- ---------------------------------------------------------------------------
ALTER TABLE projects
  ADD COLUMN IF NOT EXISTS custom_fields JSONB NOT NULL DEFAULT '{}'::jsonb;

-- jsonb_path_ops is smaller and faster for containment filters than the
-- default opclass. Group-by uses the side-table from the next migration.
CREATE INDEX IF NOT EXISTS idx_projects_custom_fields_gin
  ON projects USING GIN (custom_fields jsonb_path_ops);

-- ---------------------------------------------------------------------------
-- validate_project_custom_fields — server-side type + required check.
--
-- Dart-side validation gets bypassed by imports / automations / direct API
-- calls. This is the schema's last line of defence.
--
-- NOT defensive about unknown keys (extra entries in the jsonb that don't
-- match any current definition) — those are silently allowed so archived
-- field values can persist on existing projects without blocking saves.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION validate_project_custom_fields()
RETURNS TRIGGER
LANGUAGE plpgsql AS $$
DECLARE
  def RECORD;
  v_value JSONB;
  v_type TEXT;
BEGIN
  IF NEW.custom_fields IS NULL THEN
    NEW.custom_fields := '{}'::jsonb;
    RETURN NEW;
  END IF;

  FOR def IN
    SELECT key, type, options, is_required
    FROM custom_field_definitions
    WHERE workspace_id = NEW.workspace_id
      AND entity_type = 'project'
      AND archived_at IS NULL
  LOOP
    v_value := NEW.custom_fields -> def.key;

    -- Missing or explicit null
    IF v_value IS NULL OR jsonb_typeof(v_value) = 'null' THEN
      IF def.is_required THEN
        RAISE EXCEPTION
          'custom field "%" is required', def.key
          USING ERRCODE = 'check_violation';
      END IF;
      CONTINUE;
    END IF;

    v_type := jsonb_typeof(v_value);

    CASE def.type
      WHEN 'number' THEN
        IF v_type <> 'number' THEN
          RAISE EXCEPTION
            'custom field "%" must be a number, got %', def.key, v_type
            USING ERRCODE = 'check_violation';
        END IF;
      WHEN 'checkbox' THEN
        IF v_type <> 'boolean' THEN
          RAISE EXCEPTION
            'custom field "%" must be a boolean, got %', def.key, v_type
            USING ERRCODE = 'check_violation';
        END IF;
      WHEN 'multiSelect' THEN
        IF v_type <> 'array' THEN
          RAISE EXCEPTION
            'custom field "%" must be an array, got %', def.key, v_type
            USING ERRCODE = 'check_violation';
        END IF;
      ELSE
        -- text, longText, date, picklist, file, photo all serialize as strings
        IF v_type <> 'string' THEN
          RAISE EXCEPTION
            'custom field "%" (%) must be a string, got %',
            def.key, def.type, v_type
            USING ERRCODE = 'check_violation';
        END IF;
    END CASE;
  END LOOP;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_validate_project_custom_fields ON projects;
CREATE TRIGGER trg_validate_project_custom_fields
  BEFORE INSERT OR UPDATE OF custom_fields ON projects
  FOR EACH ROW EXECUTE FUNCTION validate_project_custom_fields();

COMMENT ON TABLE custom_field_definitions IS
  'Workspace-scoped custom field definitions. Values live in the entity row '
  '(e.g. projects.custom_fields jsonb), keyed by `key` (stable surrogate). '
  'See docs/plans/custom-fields.md.';

COMMENT ON COLUMN projects.custom_fields IS
  'jsonb map of definition.key -> value. Validated by '
  'validate_project_custom_fields() trigger against the workspace''s active '
  'custom_field_definitions for entity_type = ''project''.';
