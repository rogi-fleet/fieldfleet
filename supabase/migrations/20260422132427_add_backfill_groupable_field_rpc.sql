-- backfill_groupable_field — populate project_custom_field_values for an
-- existing definition that was just promoted to groupable=true.
--
-- Without this, the sync trigger only catches future project saves, so
-- existing projects' values stay invisible to reports/group-by until each
-- project is touched. Called from the settings UI immediately after the
-- groupable flag is flipped on.
--
-- Idempotent: re-running for the same definition just rewrites the rows.

CREATE OR REPLACE FUNCTION public.backfill_groupable_field(
  p_definition_id UUID
) RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_def RECORD;
  v_project RECORD;
  v_value JSONB;
  v_text TEXT;
  v_numeric NUMERIC;
  v_date DATE;
  v_bool BOOLEAN;
  v_count INT := 0;
BEGIN
  SELECT id, workspace_id, entity_type, key, type, groupable, archived_at
  INTO v_def
  FROM custom_field_definitions
  WHERE id = p_definition_id;

  IF v_def.id IS NULL THEN
    RAISE EXCEPTION 'definition % not found', p_definition_id
      USING ERRCODE = 'no_data_found';
  END IF;

  IF NOT public.is_pm_or_admin(v_def.workspace_id) THEN
    RAISE EXCEPTION 'not authorized to backfill custom field values'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF v_def.entity_type <> 'project' THEN
    RAISE EXCEPTION 'backfill only supports entity_type = project (got %)',
      v_def.entity_type;
  END IF;

  IF v_def.groupable IS NOT TRUE OR v_def.archived_at IS NOT NULL THEN
    RAISE EXCEPTION
      'definition must be active and groupable to backfill (groupable=%, archived=%)',
      v_def.groupable, v_def.archived_at IS NOT NULL;
  END IF;

  DELETE FROM project_custom_field_values
  WHERE definition_id = v_def.id;

  FOR v_project IN
    SELECT id, workspace_id, custom_fields
    FROM projects
    WHERE workspace_id = v_def.workspace_id
      AND custom_fields ? v_def.key
  LOOP
    v_value := v_project.custom_fields -> v_def.key;
    IF v_value IS NULL OR jsonb_typeof(v_value) = 'null' THEN
      CONTINUE;
    END IF;

    v_text := NULL;
    v_numeric := NULL;
    v_date := NULL;
    v_bool := NULL;

    BEGIN
      CASE v_def.type
        WHEN 'number' THEN
          v_numeric := (v_value #>> '{}')::numeric;
        WHEN 'checkbox' THEN
          v_bool := (v_value #>> '{}')::boolean;
        WHEN 'date' THEN
          v_date := (v_value #>> '{}')::date;
        WHEN 'multiSelect' THEN
          v_text := (
            SELECT string_agg(elem #>> '{}', ', ' ORDER BY ord)
            FROM jsonb_array_elements(v_value)
              WITH ORDINALITY AS t(elem, ord)
          );
        ELSE
          v_text := v_value #>> '{}';
      END CASE;
    EXCEPTION WHEN others THEN
      CONTINUE;
    END;

    INSERT INTO project_custom_field_values (
      project_id, definition_id, workspace_id,
      value_text, value_numeric, value_date, value_bool
    ) VALUES (
      v_project.id, v_def.id, v_project.workspace_id,
      v_text, v_numeric, v_date, v_bool
    );
    v_count := v_count + 1;
  END LOOP;

  RETURN v_count;
END;
$$;

REVOKE ALL ON FUNCTION public.backfill_groupable_field(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.backfill_groupable_field(UUID) TO authenticated;

COMMENT ON FUNCTION public.backfill_groupable_field(UUID) IS
  'Populate project_custom_field_values for an existing groupable custom '
  'field definition. Call from the settings UI immediately after toggling '
  'groupable=true so existing projects show up in reports.';
