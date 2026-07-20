-- Follow-up fixes:
--   1) Register 'aia_pay_app' in the document_template_type enum so the
--      app can seed a default template row of that type.
--   2) Tighten holdback_release_lines so source_invoice / source_budget_item
--      must belong to the same workspace AND project as the parent release.

-- 1) Enum value --------------------------------------------------------------
ALTER TYPE document_template_type ADD VALUE IF NOT EXISTS 'aia_pay_app';

-- 2) Project-consistency check for holdback_release_lines --------------------
CREATE OR REPLACE FUNCTION holdback_release_line_assert_workspace()
RETURNS TRIGGER LANGUAGE plpgsql SET search_path = public, pg_temp AS $$
DECLARE
  v_parent_ws       UUID;
  v_parent_project  UUID;
  v_inv_ws          UUID;
  v_inv_project     UUID;
  v_bi_ws           UUID;
  v_bi_project      UUID;
BEGIN
  SELECT workspace_id, project_id
    INTO v_parent_ws, v_parent_project
    FROM holdback_releases
   WHERE id = NEW.release_id;

  IF v_parent_ws IS NULL THEN
    RAISE EXCEPTION 'holdback_release_lines: parent release % not found', NEW.release_id;
  END IF;

  IF v_parent_ws IS DISTINCT FROM NEW.workspace_id THEN
    RAISE EXCEPTION 'holdback_release_lines: workspace mismatch (line %, parent %)',
      NEW.workspace_id, v_parent_ws;
  END IF;

  IF NEW.source_invoice_id IS NOT NULL THEN
    SELECT workspace_id, project_id
      INTO v_inv_ws, v_inv_project
      FROM generated_documents
     WHERE id = NEW.source_invoice_id;
    IF v_inv_ws IS NULL THEN
      RAISE EXCEPTION 'holdback_release_lines: source invoice % not found',
        NEW.source_invoice_id;
    END IF;
    IF v_inv_ws IS DISTINCT FROM v_parent_ws THEN
      RAISE EXCEPTION 'holdback_release_lines: source invoice workspace mismatch';
    END IF;
    IF v_parent_project IS NOT NULL
       AND v_inv_project IS DISTINCT FROM v_parent_project THEN
      RAISE EXCEPTION
        'holdback_release_lines: source invoice project mismatch (release project %, invoice project %)',
        v_parent_project, v_inv_project;
    END IF;
  END IF;

  IF NEW.source_budget_item_id IS NOT NULL THEN
    SELECT workspace_id, project_id
      INTO v_bi_ws, v_bi_project
      FROM budget_items
     WHERE id = NEW.source_budget_item_id;
    IF v_bi_ws IS NULL THEN
      RAISE EXCEPTION 'holdback_release_lines: source budget item % not found',
        NEW.source_budget_item_id;
    END IF;
    IF v_bi_ws IS DISTINCT FROM v_parent_ws THEN
      RAISE EXCEPTION 'holdback_release_lines: source budget item workspace mismatch';
    END IF;
    IF v_parent_project IS NOT NULL
       AND v_bi_project IS DISTINCT FROM v_parent_project THEN
      RAISE EXCEPTION
        'holdback_release_lines: source budget item project mismatch (release project %, item project %)',
        v_parent_project, v_bi_project;
    END IF;
  END IF;

  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_holdback_release_line_assert_workspace ON holdback_release_lines;
CREATE TRIGGER trg_holdback_release_line_assert_workspace
  BEFORE INSERT OR UPDATE OF
    workspace_id, release_id, source_invoice_id, source_budget_item_id
  ON holdback_release_lines
  FOR EACH ROW EXECUTE FUNCTION holdback_release_line_assert_workspace();
