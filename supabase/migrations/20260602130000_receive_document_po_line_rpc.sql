-- ===========================================================================
-- Unify purchase orders on documents — Phase 3: receiving RPC
--
-- Receives quantity against a single inventory-tracked line of a document
-- purchase order. Because document line items live in the generated_documents
-- .line_items JSONB array, the read-modify-write must be atomic (FOR UPDATE)
-- to avoid two concurrent receives clobbering each other. The function:
--   1. bumps the target line's quantityReceived,
--   2. stamps received_date when every inventory line is fully received,
--   3. records an inventory_stock_movements 'receive' row pointing at the
--      document, which fires inventory_apply_stock_movement to bump on_hand_qty.
--
-- SECURITY INVOKER: RLS still applies, so the caller must be a member of the
-- document's workspace and able to insert stock movements.
-- ===========================================================================

CREATE OR REPLACE FUNCTION receive_document_po_line(
  p_document_id uuid,
  p_line_id     text,
  p_quantity    numeric
) RETURNS void
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_ws            uuid;
  v_items         jsonb;
  v_idx           int;
  v_line          jsonb;
  v_item_id       uuid;
  v_unit_cost     numeric;
  v_new_received  numeric;
  v_all_received  boolean;
BEGIN
  IF p_quantity IS NULL OR p_quantity <= 0 THEN
    RAISE EXCEPTION 'Receive quantity must be positive';
  END IF;

  SELECT workspace_id, line_items
    INTO v_ws, v_items
  FROM generated_documents
  WHERE id = p_document_id
  FOR UPDATE;

  IF v_ws IS NULL THEN
    RAISE EXCEPTION 'Document % not found', p_document_id;
  END IF;

  -- Locate the target line within the JSONB array (0-based index for jsonb_set).
  SELECT (ord - 1)
    INTO v_idx
  FROM jsonb_array_elements(v_items) WITH ORDINALITY AS a(elem, ord)
  WHERE elem->>'id' = p_line_id;

  IF v_idx IS NULL THEN
    RAISE EXCEPTION 'Line % not found on document %', p_line_id, p_document_id;
  END IF;

  v_line      := v_items -> v_idx;
  v_item_id   := NULLIF(v_line->>'inventoryItemId', '')::uuid;
  IF v_item_id IS NULL THEN
    RAISE EXCEPTION 'Line % is not an inventory-tracked line', p_line_id;
  END IF;
  v_unit_cost    := COALESCE((v_line->>'unitPrice')::numeric, 0);
  v_new_received := COALESCE((v_line->>'quantityReceived')::numeric, 0) + p_quantity;

  -- Write back the updated received quantity.
  v_items := jsonb_set(
    v_items,
    ARRAY[v_idx::text, 'quantityReceived'],
    to_jsonb(v_new_received),
    true
  );

  -- All inventory-tracked lines fully received?
  SELECT bool_and(
           COALESCE((e->>'quantityReceived')::numeric, 0)
             >= COALESCE((e->>'quantity')::numeric, 0)
         )
    INTO v_all_received
  FROM jsonb_array_elements(v_items) AS e
  WHERE COALESCE(e->>'inventoryItemId', '') <> '';

  UPDATE generated_documents
     SET line_items    = v_items,
         received_date = CASE WHEN v_all_received THEN now()::date ELSE received_date END,
         updated_at    = now()
   WHERE id = p_document_id;

  -- Record the stock movement; the trigger updates inventory_items.on_hand_qty.
  INSERT INTO inventory_stock_movements
    (workspace_id, inventory_item_id, movement_type, quantity, unit_cost,
     purchase_order_id, occurred_at, created_by)
  VALUES
    (v_ws, v_item_id, 'receive', p_quantity, v_unit_cost,
     p_document_id, now(), auth.uid());
END;
$$;

GRANT EXECUTE ON FUNCTION receive_document_po_line(uuid, text, numeric) TO authenticated;
