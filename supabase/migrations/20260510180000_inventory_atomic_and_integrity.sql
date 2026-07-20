-- =============================================================================
-- Inventory Module — Phase 2: atomicity + cross-table workspace integrity
-- =============================================================================
-- 1. Trigger function (SECURITY DEFINER, locked search_path) ensures foreign
--    keys never cross workspaces, since the underlying FKs only point to (id)
--    and not (workspace_id, id). Definer rights avoid RLS false positives
--    when the caller can write inventory rows but does not have direct read
--    access to the referenced project/asset/etc.
-- 2. Two RPCs (`inventory_issue_to_job`, `inventory_close_rental`) so the
--    cost_items insert and the inventory write happen in a single
--    transaction. `inventory_close_rental` locks the rental row, asserts
--    the rental is still open, and computes billing math server-side so
--    the client cannot inflate or duplicate cost_items via concurrent calls.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1. Workspace integrity guards
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION inventory_assert_same_workspace()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_supplier_ws  UUID;
  v_project_ws   UUID;
  v_item_ws      UUID;
  v_po_ws        UUID;
  v_asset_ws     UUID;
BEGIN
  IF TG_TABLE_NAME = 'inventory_purchase_orders' THEN
    SELECT workspace_id INTO v_supplier_ws FROM inventory_suppliers WHERE id = NEW.supplier_id;
    IF v_supplier_ws IS NULL OR v_supplier_ws <> NEW.workspace_id THEN
      RAISE EXCEPTION 'PO supplier % belongs to a different workspace', NEW.supplier_id;
    END IF;
    IF NEW.project_id IS NOT NULL THEN
      SELECT workspace_id INTO v_project_ws FROM projects WHERE id = NEW.project_id;
      IF v_project_ws IS NULL OR v_project_ws <> NEW.workspace_id THEN
        RAISE EXCEPTION 'PO project % belongs to a different workspace', NEW.project_id;
      END IF;
    END IF;

  ELSIF TG_TABLE_NAME = 'inventory_purchase_order_lines' THEN
    SELECT workspace_id INTO v_po_ws FROM inventory_purchase_orders WHERE id = NEW.purchase_order_id;
    IF v_po_ws IS NULL OR v_po_ws <> NEW.workspace_id THEN
      RAISE EXCEPTION 'PO line workspace mismatch with parent PO';
    END IF;
    SELECT workspace_id INTO v_item_ws FROM inventory_items WHERE id = NEW.inventory_item_id;
    IF v_item_ws IS NULL OR v_item_ws <> NEW.workspace_id THEN
      RAISE EXCEPTION 'PO line item % belongs to a different workspace', NEW.inventory_item_id;
    END IF;

  ELSIF TG_TABLE_NAME = 'inventory_stock_movements' THEN
    SELECT workspace_id INTO v_item_ws FROM inventory_items WHERE id = NEW.inventory_item_id;
    IF v_item_ws IS NULL OR v_item_ws <> NEW.workspace_id THEN
      RAISE EXCEPTION 'Stock movement item % belongs to a different workspace', NEW.inventory_item_id;
    END IF;
    IF NEW.project_id IS NOT NULL THEN
      SELECT workspace_id INTO v_project_ws FROM projects WHERE id = NEW.project_id;
      IF v_project_ws IS NULL OR v_project_ws <> NEW.workspace_id THEN
        RAISE EXCEPTION 'Stock movement project % belongs to a different workspace', NEW.project_id;
      END IF;
    END IF;
    IF NEW.purchase_order_id IS NOT NULL THEN
      SELECT workspace_id INTO v_po_ws FROM inventory_purchase_orders WHERE id = NEW.purchase_order_id;
      IF v_po_ws IS NULL OR v_po_ws <> NEW.workspace_id THEN
        RAISE EXCEPTION 'Stock movement PO % belongs to a different workspace', NEW.purchase_order_id;
      END IF;
    END IF;

  ELSIF TG_TABLE_NAME = 'equipment_rentals' THEN
    SELECT workspace_id INTO v_asset_ws FROM assets WHERE id = NEW.asset_id;
    IF v_asset_ws IS NULL OR v_asset_ws <> NEW.workspace_id THEN
      RAISE EXCEPTION 'Rental asset % belongs to a different workspace', NEW.asset_id;
    END IF;
    SELECT workspace_id INTO v_project_ws FROM projects WHERE id = NEW.project_id;
    IF v_project_ws IS NULL OR v_project_ws <> NEW.workspace_id THEN
      RAISE EXCEPTION 'Rental project % belongs to a different workspace', NEW.project_id;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_inv_po_ws_check       ON inventory_purchase_orders;
DROP TRIGGER IF EXISTS trg_inv_pol_ws_check      ON inventory_purchase_order_lines;
DROP TRIGGER IF EXISTS trg_inv_sm_ws_check       ON inventory_stock_movements;
DROP TRIGGER IF EXISTS trg_eqr_ws_check          ON equipment_rentals;

CREATE TRIGGER trg_inv_po_ws_check
  BEFORE INSERT OR UPDATE ON inventory_purchase_orders
  FOR EACH ROW EXECUTE FUNCTION inventory_assert_same_workspace();

CREATE TRIGGER trg_inv_pol_ws_check
  BEFORE INSERT OR UPDATE ON inventory_purchase_order_lines
  FOR EACH ROW EXECUTE FUNCTION inventory_assert_same_workspace();

CREATE TRIGGER trg_inv_sm_ws_check
  BEFORE INSERT OR UPDATE ON inventory_stock_movements
  FOR EACH ROW EXECUTE FUNCTION inventory_assert_same_workspace();

CREATE TRIGGER trg_eqr_ws_check
  BEFORE INSERT OR UPDATE ON equipment_rentals
  FOR EACH ROW EXECUTE FUNCTION inventory_assert_same_workspace();

-- ---------------------------------------------------------------------------
-- 2. Atomic RPC: issue stock to a job
--    Inserts a cost_items row and an inventory_stock_movements row in the
--    same transaction; either both succeed or both roll back.
--    SECURITY INVOKER so RLS still applies — the caller must be a workspace
--    member of `p_workspace_id`.
-- ---------------------------------------------------------------------------
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
  p_occurred_at     TIMESTAMPTZ
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
    description, quantity, unit_price, date,
    created_by, created_at, updated_at
  ) VALUES (
    p_workspace_id, p_project_id, p_category_id, 'material',
    p_description, p_quantity, p_billed_unit, v_now,
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

-- ---------------------------------------------------------------------------
-- 3. Atomic RPC: close (return) an equipment rental and bill it to the job
--    Concurrency-safe: locks the rental row with FOR UPDATE and refuses to
--    re-close an already-closed rental (idempotent — returns the existing
--    cost_item_id instead of inserting a duplicate). All billing math is
--    derived server-side from the stored rental rates so the client cannot
--    inflate or duplicate the financial record.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION inventory_close_rental(
  p_rental_id   UUID,
  p_end_date    DATE,
  p_description TEXT
) RETURNS UUID
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid       UUID := auth.uid();
  v_rental    equipment_rentals%ROWTYPE;
  v_cost_id   UUID;
  v_days      INTEGER;
  v_billed    NUMERIC;
  v_qty       NUMERIC;
  v_unit      NUMERIC;
  v_end       DATE := COALESCE(p_end_date, CURRENT_DATE);
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  -- Lock the row so two concurrent calls cannot both decide to insert a
  -- cost_items line for the same rental.
  SELECT * INTO v_rental FROM equipment_rentals WHERE id = p_rental_id FOR UPDATE;
  IF v_rental.id IS NULL THEN
    RAISE EXCEPTION 'Rental % not found', p_rental_id;
  END IF;

  -- Idempotent close: if already returned, surface the existing backlink
  -- without writing anything new. Lets retries from the client be safe.
  IF v_rental.end_date IS NOT NULL THEN
    RETURN v_rental.cost_item_id;
  END IF;

  IF v_end < v_rental.start_date THEN
    RAISE EXCEPTION 'End date % is before rental start %', v_end, v_rental.start_date;
  END IF;

  -- Server-side billing math. Mirrors EquipmentRental.billedAmount in Dart:
  -- monthly preferred at >=28 days, weekly at >=7, daily otherwise. At least
  -- one billable day so a same-day return still bills.
  v_days := GREATEST((v_end - v_rental.start_date), 1);

  IF v_rental.is_billable THEN
    IF v_rental.monthly_rate IS NOT NULL AND v_days >= 28 THEN
      v_billed := (v_days / 30.0) * v_rental.monthly_rate;
    ELSIF v_rental.weekly_rate IS NOT NULL AND v_days >= 7 THEN
      v_billed := (v_days / 7.0) * v_rental.weekly_rate;
    ELSE
      v_billed := v_days * v_rental.daily_rate;
    END IF;

    IF v_billed > 0 THEN
      v_qty  := v_days;
      v_unit := v_billed / v_days;

      INSERT INTO cost_items (
        workspace_id, project_id, category_id, type,
        description, quantity, unit_price, date,
        created_by, created_at, updated_at
      ) VALUES (
        v_rental.workspace_id, v_rental.project_id, NULL, 'material',
        p_description, v_qty, v_unit, v_end,
        v_uid, NOW(), NOW()
      ) RETURNING id INTO v_cost_id;
    END IF;
  END IF;

  UPDATE equipment_rentals
     SET end_date     = v_end,
         cost_item_id = COALESCE(v_cost_id, cost_item_id),
         updated_at   = NOW()
   WHERE id = p_rental_id;

  RETURN v_cost_id;
END;
$$;

GRANT EXECUTE ON FUNCTION inventory_issue_to_job(
  UUID, UUID, UUID, NUMERIC, NUMERIC, NUMERIC, TEXT, UUID, TEXT, TIMESTAMPTZ
) TO authenticated;
GRANT EXECUTE ON FUNCTION inventory_close_rental(
  UUID, DATE, TEXT
) TO authenticated;
