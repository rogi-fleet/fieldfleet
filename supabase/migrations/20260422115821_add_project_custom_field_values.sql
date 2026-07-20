-- project_custom_field_values — typed side-table for indexable group-by /
-- filter on custom fields marked groupable=true.
--
-- Why a side-table instead of generated columns on projects:
--   * Generated STORED columns require ALTER TABLE per field — ACCESS
--     EXCLUSIVE lock + table rewrite + per-tenant bloat (architect review).
--   * jsonb expression indexes work but each index is per-key, and you
--     can't parameterize the WHERE clause by tenant.
--   * A normalized side-table indexes once per type column and scales
--     cleanly across entity types when customers / cost_items / vendors
--     gain custom fields too.
--
-- The trigger below is a no-op for workspaces that have no groupable
-- definitions, so the cost is paid only by tenants who opt in to reporting.
-- Backfill on flipping `groupable = true` is deferred to PR5.

CREATE TABLE IF NOT EXISTS project_custom_field_values (
  project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  definition_id UUID NOT NULL
    REFERENCES custom_field_definitions(id) ON DELETE CASCADE,
  workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
  -- Denormalized typed slots — only the slot matching the def.type is
  -- populated. NULL for irrelevant slots so partial indexes stay tight.
  value_text TEXT,
  value_numeric NUMERIC,
  value_date DATE,
  value_bool BOOLEAN,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (project_id, definition_id)
);

CREATE INDEX IF NOT EXISTS idx_pcfv_text
  ON project_custom_field_values (workspace_id, definition_id, value_text)
  WHERE value_text IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_pcfv_numeric
  ON project_custom_field_values (workspace_id, definition_id, value_numeric)
  WHERE value_numeric IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_pcfv_date
  ON project_custom_field_values (workspace_id, definition_id, value_date)
  WHERE value_date IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_pcfv_bool
  ON project_custom_field_values (workspace_id, definition_id, value_bool)
  WHERE value_bool IS NOT NULL;

ALTER TABLE project_custom_field_values ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pcfv_select ON project_custom_field_values;
CREATE POLICY pcfv_select ON project_custom_field_values
  FOR SELECT USING (is_workspace_member(workspace_id));

-- Writes are trigger-driven only; clients have no direct grant.
REVOKE INSERT, UPDATE, DELETE ON project_custom_field_values FROM authenticated;

-- ---------------------------------------------------------------------------
-- sync_project_custom_field_values — keep the side-table in sync with
-- projects.custom_fields, but ONLY for definitions where groupable = true.
--
-- Cheap when no groupable defs exist (single SELECT returns 0 rows). If a
-- def is later promoted to groupable, run the PR5 backfill RPC to populate
-- existing projects; this trigger only handles the steady-state write path.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION sync_project_custom_field_values()
RETURNS TRIGGER
LANGUAGE plpgsql AS $$
DECLARE
  def RECORD;
  v_value JSONB;
  v_text TEXT;
  v_numeric NUMERIC;
  v_date DATE;
  v_bool BOOLEAN;
BEGIN
  -- Wipe rows for definitions that are no longer present or no longer
  -- groupable; the loop below will re-insert what's still relevant.
  DELETE FROM project_custom_field_values
  WHERE project_id = NEW.id;

  IF NEW.custom_fields IS NULL OR NEW.custom_fields = '{}'::jsonb THEN
    RETURN NEW;
  END IF;

  FOR def IN
    SELECT id, key, type
    FROM custom_field_definitions
    WHERE workspace_id = NEW.workspace_id
      AND entity_type = 'project'
      AND archived_at IS NULL
      AND groupable = TRUE
  LOOP
    v_value := NEW.custom_fields -> def.key;
    IF v_value IS NULL OR jsonb_typeof(v_value) = 'null' THEN
      CONTINUE;
    END IF;

    v_text := NULL;
    v_numeric := NULL;
    v_date := NULL;
    v_bool := NULL;

    BEGIN
      CASE def.type
        WHEN 'number' THEN
          v_numeric := (v_value #>> '{}')::numeric;
        WHEN 'checkbox' THEN
          v_bool := (v_value #>> '{}')::boolean;
        WHEN 'date' THEN
          v_date := (v_value #>> '{}')::date;
        WHEN 'multiSelect' THEN
          -- Multi-select isn't natively groupable; flatten to comma-joined
          -- text so the value still appears in group-by listings. Reporting
          -- UI can offer a "split rows" mode later.
          v_text := (
            SELECT string_agg(elem #>> '{}', ', ' ORDER BY ord)
            FROM jsonb_array_elements(v_value) WITH ORDINALITY AS t(elem, ord)
          );
        ELSE
          -- text, longText, date (handled above), picklist, file, photo
          v_text := v_value #>> '{}';
      END CASE;
    EXCEPTION WHEN others THEN
      -- Bad cast (e.g. malformed date) — skip this row rather than block
      -- the project save. Validation trigger from the previous migration
      -- already enforces shape; this is belt-and-braces.
      CONTINUE;
    END;

    INSERT INTO project_custom_field_values (
      project_id, definition_id, workspace_id,
      value_text, value_numeric, value_date, value_bool
    ) VALUES (
      NEW.id, def.id, NEW.workspace_id,
      v_text, v_numeric, v_date, v_bool
    );
  END LOOP;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_project_custom_field_values ON projects;
CREATE TRIGGER trg_sync_project_custom_field_values
  AFTER INSERT OR UPDATE OF custom_fields, workspace_id ON projects
  FOR EACH ROW EXECUTE FUNCTION sync_project_custom_field_values();

COMMENT ON TABLE project_custom_field_values IS
  'Typed projection of projects.custom_fields for definitions with '
  'groupable=true. Populated by trigger; clients read-only via RLS.';
