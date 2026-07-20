-- =============================================================================
-- Follow-up fixes for AIA payment applications:
--   1. Add header snapshots so list views don't need line rows.
--   2. Add prior-certified rollover column (correct G702 line 7).
--   3. Trigger: enforce line.workspace_id == parent header.workspace_id.
--   4. RPC: atomic replace-all-lines (single transaction).
--   5. Better composite index for the primary line read path.
-- =============================================================================

-- 1 & 2: header snapshot columns
ALTER TABLE aia_payment_applications
  ADD COLUMN IF NOT EXISTS previous_certificates_total NUMERIC(15,2) NOT NULL DEFAULT 0;

ALTER TABLE aia_payment_applications
  ADD COLUMN IF NOT EXISTS current_payment_due_snapshot NUMERIC(15,2);

ALTER TABLE aia_payment_applications
  ADD COLUMN IF NOT EXISTS total_completed_stored_snapshot NUMERIC(15,2);

ALTER TABLE aia_payment_applications
  ADD COLUMN IF NOT EXISTS total_retainage_snapshot NUMERIC(15,2);

-- 3: enforce workspace consistency between line and parent header.
CREATE OR REPLACE FUNCTION aia_pay_app_line_assert_workspace()
RETURNS TRIGGER LANGUAGE plpgsql SET search_path = public, pg_temp AS $$
DECLARE
  v_parent_ws UUID;
BEGIN
  SELECT workspace_id INTO v_parent_ws
    FROM aia_payment_applications
    WHERE id = NEW.pay_application_id;
  IF v_parent_ws IS NULL THEN
    RAISE EXCEPTION 'aia_pay_app_lines: parent application % not found', NEW.pay_application_id;
  END IF;
  IF v_parent_ws IS DISTINCT FROM NEW.workspace_id THEN
    RAISE EXCEPTION 'aia_pay_app_lines: workspace mismatch (line %, parent %)',
      NEW.workspace_id, v_parent_ws;
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_aia_pay_app_line_assert_workspace ON aia_pay_app_lines;
CREATE TRIGGER trg_aia_pay_app_line_assert_workspace
  BEFORE INSERT OR UPDATE OF workspace_id, pay_application_id ON aia_pay_app_lines
  FOR EACH ROW EXECUTE FUNCTION aia_pay_app_line_assert_workspace();

-- 4: atomic replace lines. Caller passes a JSON array of line objects;
-- function deletes all existing lines for the app and inserts the new set
-- inside a single transaction. RLS still applies (SECURITY INVOKER).
CREATE OR REPLACE FUNCTION replace_aia_pay_app_lines(
  p_app_id UUID,
  p_lines JSONB
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
BEGIN
  DELETE FROM aia_pay_app_lines WHERE pay_application_id = p_app_id;

  IF jsonb_array_length(p_lines) = 0 THEN
    RETURN;
  END IF;

  INSERT INTO aia_pay_app_lines (
    pay_application_id,
    workspace_id,
    budget_item_id,
    item_no,
    description,
    scheduled_value,
    work_completed_previous,
    work_completed_this_period,
    materials_stored,
    retainage_amount,
    sort_order
  )
  SELECT
    p_app_id,
    (elem->>'workspace_id')::UUID,
    NULLIF(elem->>'budget_item_id','')::UUID,
    elem->>'item_no',
    COALESCE(elem->>'description',''),
    COALESCE((elem->>'scheduled_value')::NUMERIC, 0),
    COALESCE((elem->>'work_completed_previous')::NUMERIC, 0),
    COALESCE((elem->>'work_completed_this_period')::NUMERIC, 0),
    COALESCE((elem->>'materials_stored')::NUMERIC, 0),
    NULLIF(elem->>'retainage_amount','')::NUMERIC,
    COALESCE((elem->>'sort_order')::INT, 0)
  FROM jsonb_array_elements(p_lines) AS elem;
END $$;

-- 5: composite index on primary read path
CREATE INDEX IF NOT EXISTS idx_aia_pay_app_lines_app_sort
  ON aia_pay_app_lines(pay_application_id, sort_order);
