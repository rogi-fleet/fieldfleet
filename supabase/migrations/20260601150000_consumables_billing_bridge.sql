-- =============================================================================
-- Consumables / cost-items → client invoice bridge
-- =============================================================================
-- Gives project costs (created when consumables are issued to a job, when an
-- equipment rental is closed, or entered by hand) a path onto a client
-- invoice document:
--   1. `cost_items.billable`              — is this cost chargeable to the client?
--   2. `cost_items.invoiced_document_id`  — which invoice document has claimed
--                                            it (NULL = unbilled). Doubles as the
--                                            anti-double-bill guard.
--   3. `inventory_issue_to_job` learns a `p_billable` flag so the issue dialog
--      can mark stock as internal-use vs. billable at issue time.
--   4. `bill_cost_items_to_document`      — atomically appends the selected
--      unbilled, billable costs as line items on an invoice document, recomputes
--      the document total (mirrors DocumentService._calculateDocumentTotal), and
--      stamps the costs as invoiced. Lives in one transaction so a cost can never
--      be stamped without its line landing, nor billed onto two invoices at once.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1. Billability + invoiced backlink on cost_items
-- ---------------------------------------------------------------------------
ALTER TABLE cost_items
  ADD COLUMN IF NOT EXISTS billable BOOLEAN NOT NULL DEFAULT TRUE;

ALTER TABLE cost_items
  ADD COLUMN IF NOT EXISTS invoiced_document_id UUID
    REFERENCES generated_documents(id) ON DELETE SET NULL;

-- Fast lookup of a project's unbilled, billable costs (the candidate list the
-- "Bill to client" picker shows).
CREATE INDEX IF NOT EXISTS idx_cost_items_unbilled
  ON cost_items (project_id)
  WHERE billable = TRUE AND invoiced_document_id IS NULL;

-- ---------------------------------------------------------------------------
-- 2. inventory_issue_to_job — carry the billable flag through to the cost row
--    Drop the old 10-arg signature first so we can append p_billable with a
--    default; existing callers that omit it keep working unchanged.
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS inventory_issue_to_job(
  UUID, UUID, UUID, NUMERIC, NUMERIC, NUMERIC, TEXT, UUID, TEXT, TIMESTAMPTZ
);

CREATE OR REPLACE FUNCTION inventory_issue_to_job(
  p_workspace_id    UUID,
  p_inventory_item  UUID,
  p_project_id      UUID,
  p_quantity        NUMERIC,
  p_unit_cost       NUMERIC,
  p_billed_unit     NUMERIC,
  p_description     TEXT,
  p_category_id     UUID,
  p_notes           TEXT,
  p_occurred_at     TIMESTAMPTZ,
  p_billable        BOOLEAN DEFAULT TRUE
) RETURNS UUID
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid          UUID := auth.uid();
  v_now          TIMESTAMPTZ := COALESCE(p_occurred_at, NOW());
  v_cost_id      UUID;
  v_movement_id  UUID;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  INSERT INTO cost_items (
    workspace_id, project_id, category_id, type,
    description, quantity, unit_price, date, billable,
    created_by, created_at, updated_at
  ) VALUES (
    p_workspace_id, p_project_id, p_category_id, 'material',
    p_description, p_quantity, p_billed_unit, v_now, COALESCE(p_billable, TRUE),
    v_uid, v_now, v_now
  ) RETURNING id INTO v_cost_id;

  INSERT INTO inventory_stock_movements (
    workspace_id, inventory_item_id, movement_type, quantity,
    unit_cost, project_id, cost_item_id, notes, occurred_at, created_by
  ) VALUES (
    p_workspace_id, p_inventory_item, 'issue', p_quantity,
    p_unit_cost, p_project_id, v_cost_id, p_notes, v_now, v_uid
  ) RETURNING id INTO v_movement_id;

  RETURN v_movement_id;
END;
$$;

GRANT EXECUTE ON FUNCTION inventory_issue_to_job(
  UUID, UUID, UUID, NUMERIC, NUMERIC, NUMERIC, TEXT, UUID, TEXT, TIMESTAMPTZ, BOOLEAN
) TO authenticated;

-- ---------------------------------------------------------------------------
-- 3. bill_cost_items_to_document — pull unbilled costs onto an invoice
--    Atomic: locks the document, appends a line item per eligible cost, marks
--    each cost invoiced, and recomputes the document total. SECURITY INVOKER so
--    RLS still gates which documents/costs the caller can touch.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION bill_cost_items_to_document(
  p_document_id   UUID,
  p_cost_item_ids UUID[]
) RETURNS INTEGER
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid        UUID := auth.uid();
  v_doc        generated_documents%ROWTYPE;
  v_lines      JSONB;
  v_next_sort  INTEGER;
  v_count      INTEGER := 0;
  v_cost       RECORD;
  v_subtotal   NUMERIC := 0;
  v_total      NUMERIC;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  -- Lock the document so two concurrent pulls cannot both rewrite line_items.
  SELECT * INTO v_doc FROM generated_documents WHERE id = p_document_id FOR UPDATE;
  IF v_doc.id IS NULL THEN
    RAISE EXCEPTION 'Document % not found', p_document_id;
  END IF;
  IF v_doc.project_id IS NULL THEN
    RAISE EXCEPTION 'Document has no project, so project costs cannot be matched to it';
  END IF;

  v_lines := COALESCE(v_doc.line_items, '[]'::jsonb);

  SELECT COALESCE(MAX((elem->>'sortOrder')::int), -1) + 1
    INTO v_next_sort
  FROM jsonb_array_elements(v_lines) elem;

  -- Only costs in the same workspace + project, billable and not yet invoiced
  -- are eligible. Row locks prevent a parallel call from claiming the same one.
  FOR v_cost IN
    SELECT * FROM cost_items
     WHERE id = ANY(p_cost_item_ids)
       AND workspace_id = v_doc.workspace_id
       AND project_id   = v_doc.project_id
       AND billable     = TRUE
       AND invoiced_document_id IS NULL
     FOR UPDATE
  LOOP
    v_lines := v_lines || jsonb_build_object(
      'id', gen_random_uuid()::text,
      'budgetItemId', NULL,
      'costItemId', v_cost.id::text,
      'type', 'item',
      'parentId', NULL,
      'sortOrder', v_next_sort,
      'name', v_cost.description,
      'description', NULL,
      'quantity', v_cost.quantity,
      'unit', NULL,
      'unitPrice', v_cost.unit_price,
      'totalPrice', v_cost.quantity * v_cost.unit_price,
      'isVisible', TRUE,
      'customizedFields', '[]'::jsonb
    );
    v_next_sort := v_next_sort + 1;
    v_count := v_count + 1;

    UPDATE cost_items
       SET invoiced_document_id = p_document_id,
           updated_at = NOW()
     WHERE id = v_cost.id;
  END LOOP;

  IF v_count = 0 THEN
    RETURN 0;
  END IF;

  -- Subtotal mirrors DocumentService._calculateDocumentSubtotal: visible,
  -- leaf (non-group) line items only.
  SELECT COALESCE(
           SUM((elem->>'quantity')::numeric * (elem->>'unitPrice')::numeric), 0)
    INTO v_subtotal
  FROM jsonb_array_elements(v_lines) elem
  WHERE COALESCE((elem->>'isVisible')::boolean, TRUE) = TRUE
    AND COALESCE(elem->>'type', 'item') = 'item';

  IF v_doc.collect_tax AND COALESCE(v_doc.tax_rate, 0) > 0 THEN
    v_total := v_subtotal + (v_subtotal * (v_doc.tax_rate / 100.0));
  ELSE
    v_total := v_subtotal;
  END IF;

  UPDATE generated_documents
     SET line_items   = v_lines,
         total_amount = v_total
   WHERE id = p_document_id;

  RETURN v_count;
END;
$$;

GRANT EXECUTE ON FUNCTION bill_cost_items_to_document(UUID, UUID[]) TO authenticated;
