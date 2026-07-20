-- =============================================================================
-- Inventory Module — editable / reversible job issues
-- =============================================================================
-- Issuing stock to a job (`inventory_issue_to_job`) writes two linked rows in
-- one transaction: an `inventory_stock_movements` row (drives on_hand_qty via
-- the apply-movement trigger) and a `cost_items` row (rolls into Financials,
-- carries the `billable` flag). Until now that pair was write-once.
--
-- These two RPCs make an issue editable and reversible while preserving the
-- same atomic coupling — either both rows change or neither does — and refuse
-- to touch a cost that has already been pulled onto an invoice
-- (`invoiced_document_id IS NOT NULL`), so an issued material can never drift
-- out of sync with a posted bill.
--
--   1. `inventory_update_issue`  — edit qty / unit cost / bill rate /
--                                  description / notes / billable on an issue.
--   2. `inventory_reverse_issue` — delete the issue and its cost line; the
--                                  apply-movement trigger restores on_hand_qty.
--
-- Both are SECURITY INVOKER so RLS still applies (caller must be a workspace
-- member). The inventory item the movement points to is intentionally NOT
-- editable here — to move stock to a different item, reverse and re-issue.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1. Edit an existing job issue (movement + linked cost item together).
--    p_billed_unit is what the client is charged per unit (the cost item's
--    unit_price); p_unit_cost is the internal cost snapshot on the movement.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION inventory_update_issue(
  p_movement_id   UUID,
  p_quantity      NUMERIC,
  p_unit_cost     NUMERIC,
  p_billed_unit   NUMERIC,
  p_description   TEXT,
  p_notes         TEXT,
  p_billable      BOOLEAN DEFAULT TRUE
) RETURNS VOID
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid       UUID := auth.uid();
  v_movement  inventory_stock_movements%ROWTYPE;
  v_cost      cost_items%ROWTYPE;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  IF p_quantity IS NULL OR p_quantity <= 0 THEN
    RAISE EXCEPTION 'Quantity must be greater than zero';
  END IF;

  -- Lock the movement so a concurrent edit/reverse can't race this one.
  SELECT * INTO v_movement
    FROM inventory_stock_movements
   WHERE id = p_movement_id
   FOR UPDATE;
  IF v_movement.id IS NULL THEN
    RAISE EXCEPTION 'Stock movement % not found', p_movement_id;
  END IF;
  IF v_movement.movement_type <> 'issue' THEN
    RAISE EXCEPTION 'Only job issues can be edited (movement is %)',
      v_movement.movement_type;
  END IF;

  -- Lock and validate the linked cost line before touching either row.
  IF v_movement.cost_item_id IS NOT NULL THEN
    SELECT * INTO v_cost
      FROM cost_items
     WHERE id = v_movement.cost_item_id
     FOR UPDATE;
    IF v_cost.id IS NOT NULL AND v_cost.invoiced_document_id IS NOT NULL THEN
      RAISE EXCEPTION
        'This material is already billed to an invoice and can no longer be edited';
    END IF;

    UPDATE cost_items
       SET quantity    = p_quantity,
           unit_price  = p_billed_unit,
           description = p_description,
           notes       = p_notes,
           billable    = COALESCE(p_billable, TRUE),
           updated_at  = NOW()
     WHERE id = v_movement.cost_item_id;
  END IF;

  -- Trigger inventory_apply_stock_movement re-balances on_hand_qty from the
  -- old vs. new quantity automatically.
  UPDATE inventory_stock_movements
     SET quantity  = p_quantity,
         unit_cost = p_unit_cost,
         notes     = p_notes
   WHERE id = p_movement_id;
END;
$$;

-- ---------------------------------------------------------------------------
-- 2. Reverse (delete) a job issue and its cost line.
--    Deleting the movement fires the apply-movement trigger, which adds the
--    issued quantity back to on_hand_qty.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION inventory_reverse_issue(
  p_movement_id UUID
) RETURNS VOID
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid       UUID := auth.uid();
  v_movement  inventory_stock_movements%ROWTYPE;
  v_cost      cost_items%ROWTYPE;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  SELECT * INTO v_movement
    FROM inventory_stock_movements
   WHERE id = p_movement_id
   FOR UPDATE;
  IF v_movement.id IS NULL THEN
    RAISE EXCEPTION 'Stock movement % not found', p_movement_id;
  END IF;
  IF v_movement.movement_type <> 'issue' THEN
    RAISE EXCEPTION 'Only job issues can be reversed (movement is %)',
      v_movement.movement_type;
  END IF;

  IF v_movement.cost_item_id IS NOT NULL THEN
    SELECT * INTO v_cost
      FROM cost_items
     WHERE id = v_movement.cost_item_id
     FOR UPDATE;
    IF v_cost.id IS NOT NULL AND v_cost.invoiced_document_id IS NOT NULL THEN
      RAISE EXCEPTION
        'This material is already billed to an invoice and can no longer be removed';
    END IF;

    -- Delete the movement first so the apply trigger restores stock, then the
    -- now-orphaned cost line.
    DELETE FROM inventory_stock_movements WHERE id = p_movement_id;
    DELETE FROM cost_items WHERE id = v_movement.cost_item_id;
  ELSE
    DELETE FROM inventory_stock_movements WHERE id = p_movement_id;
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION inventory_update_issue(
  UUID, NUMERIC, NUMERIC, NUMERIC, TEXT, TEXT, BOOLEAN
) TO authenticated;
GRANT EXECUTE ON FUNCTION inventory_reverse_issue(UUID) TO authenticated;
