-- ===========================================================================
-- Unify purchase orders on documents — Phase 4: data migration + repointing
--
-- Folds the legacy inventory PO system into document POs:
--   1. Promote inventory_suppliers -> vendors (dedupe by name per workspace).
--   2. Carry supplier contacts into vendor_contacts.
--   3. Convert inventory_purchase_orders -> generated_documents (purchase_order).
--   4. Convert inventory_purchase_order_lines -> the document's line_items JSONB
--      (carrying inventoryItemId + quantityReceived so receiving still works).
--   5. Repoint inventory_stock_movements.purchase_order_id at the new documents
--      and swap its FK from inventory_purchase_orders to generated_documents.
--   6. Update the workspace-integrity trigger's stock-movement branch to
--      validate against generated_documents.
--
-- Idempotent: re-running skips suppliers/contacts/POs already migrated. The
-- inventory PO tables are left in place (dormant) as the rollback path; a later
-- migration drops them once the cutover is verified.
-- ===========================================================================

-- 1. Promote suppliers to vendors (only those without a name match already).
INSERT INTO vendors (
  workspace_id, company_name, website, address, notes,
  is_active, business_phone, business_email, created_by
)
SELECT s.workspace_id, s.name, s.website, s.address, s.notes,
       s.is_active, s.phone, s.email, s.created_by
FROM inventory_suppliers s
WHERE NOT EXISTS (
  SELECT 1 FROM vendors v
   WHERE v.workspace_id = s.workspace_id
     AND lower(trim(v.company_name)) = lower(trim(s.name))
);

CREATE TEMP TABLE _supplier_vendor_map ON COMMIT DROP AS
SELECT s.id AS supplier_id,
       (SELECT v.id FROM vendors v
         WHERE v.workspace_id = s.workspace_id
           AND lower(trim(v.company_name)) = lower(trim(s.name))
         ORDER BY v.created_at NULLS LAST
         LIMIT 1) AS vendor_id
FROM inventory_suppliers s;

-- 2. Supplier contacts -> vendor_contacts (when a contact name exists).
INSERT INTO vendor_contacts (vendor_id, name, phone, email, is_primary, is_active)
SELECT m.vendor_id, s.contact_name, s.phone, s.email, true, true
FROM inventory_suppliers s
JOIN _supplier_vendor_map m ON m.supplier_id = s.id
WHERE s.contact_name IS NOT NULL AND trim(s.contact_name) <> ''
  AND NOT EXISTS (
    SELECT 1 FROM vendor_contacts vc
     WHERE vc.vendor_id = m.vendor_id AND vc.name = s.contact_name
  );

-- 3. Inventory POs -> generated_documents.
--    Status: draft -> draft, cancelled -> withdrawn, everything else
--    (ordered/partial/received = a placed order) -> approved (committed).
--    Fulfillment (partial/received) is tracked separately via line-level
--    quantityReceived + received_date, not via document status.
--    Flat inventory tax -> tax_amount_override (no lossy percent conversion).
INSERT INTO generated_documents (
  workspace_id, project_id, document_type, status, vendor_id,
  document_number, expected_date, received_date, shipping_cost,
  tax_amount_override, collect_tax, tax_rate, total_amount,
  template_name, rendered_content, line_items,
  metadata, created_by, created_at
)
SELECT
  po.workspace_id, po.project_id,
  'purchase_order'::document_template_type,
  (CASE po.status
     WHEN 'draft'     THEN 'draft'
     WHEN 'cancelled' THEN 'withdrawn'
     ELSE 'approved'
   END)::document_status,
  m.vendor_id,
  COALESCE(po.po_number, 'PO-' || left(po.id::text, 8)),
  po.expected_date, po.received_date, COALESCE(po.shipping_cost, 0),
  NULLIF(po.tax, 0), (COALESCE(po.tax, 0) > 0), 0,
  COALESCE(po.shipping_cost, 0) + COALESCE(po.tax, 0),
  'Purchase Order', '', '[]'::jsonb,
  jsonb_build_object(
    'migrated_from_inventory_po', po.id::text,
    'legacy_status', po.status,
    'order_date', po.order_date
  ),
  po.created_by, po.created_at
FROM inventory_purchase_orders po
JOIN _supplier_vendor_map m ON m.supplier_id = po.supplier_id
WHERE NOT EXISTS (
  SELECT 1 FROM generated_documents g
   WHERE g.metadata->>'migrated_from_inventory_po' = po.id::text
);

CREATE TEMP TABLE _po_doc_map ON COMMIT DROP AS
SELECT (g.metadata->>'migrated_from_inventory_po')::uuid AS old_po_id,
       g.id AS new_doc_id
FROM generated_documents g
WHERE g.metadata ? 'migrated_from_inventory_po';

-- 4. Lines -> line_items JSONB. Recompute total = subtotal + shipping + tax.
UPDATE generated_documents g
SET line_items   = sub.items,
    total_amount = COALESCE(sub.subtotal, 0)
                   + COALESCE(g.shipping_cost, 0)
                   + COALESCE(g.tax_amount_override, 0)
FROM (
  SELECT x.new_doc_id,
         jsonb_agg(x.elem ORDER BY x.ord) AS items,
         SUM(x.lt) AS subtotal
  FROM (
    SELECT map.new_doc_id AS new_doc_id,
           l.line_total   AS lt,
           (row_number() OVER (PARTITION BY l.purchase_order_id
                               ORDER BY l.created_at))::int - 1 AS ord,
           jsonb_build_object(
             'id', gen_random_uuid()::text,
             'type', 'item',
             'sortOrder',
               (row_number() OVER (PARTITION BY l.purchase_order_id
                                   ORDER BY l.created_at))::int - 1,
             'name', COALESCE(ii.name, 'Item'),
             'inventoryItemId', l.inventory_item_id::text,
             'quantity', l.quantity_ordered,
             'quantityReceived', l.quantity_received,
             'unitPrice', l.unit_cost,
             'totalPrice', l.line_total,
             'isVisible', true,
             'customizedFields', '[]'::jsonb
           ) AS elem
    FROM inventory_purchase_order_lines l
    JOIN _po_doc_map map ON map.old_po_id = l.purchase_order_id
    LEFT JOIN inventory_items ii ON ii.id = l.inventory_item_id
  ) x
  GROUP BY x.new_doc_id
) sub
WHERE g.id = sub.new_doc_id;

-- 5. Repoint stock movements, then swap the FK to generated_documents.
UPDATE inventory_stock_movements sm
SET purchase_order_id = map.new_doc_id
FROM _po_doc_map map
WHERE sm.purchase_order_id = map.old_po_id;

-- Safety: NULL out any stock movement still pointing at a non-document id
-- (e.g. a PO that failed to migrate). With suppliers fully promoted this set
-- is empty, but the guard keeps the FK swap below from failing.
UPDATE inventory_stock_movements sm
SET purchase_order_id = NULL
WHERE sm.purchase_order_id IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM generated_documents g WHERE g.id = sm.purchase_order_id);

ALTER TABLE inventory_stock_movements
  DROP CONSTRAINT IF EXISTS inventory_stock_movements_purchase_order_id_fkey;
ALTER TABLE inventory_stock_movements
  ADD CONSTRAINT inventory_stock_movements_purchase_order_id_fkey
  FOREIGN KEY (purchase_order_id) REFERENCES generated_documents(id) ON DELETE SET NULL;

-- 6. Re-point the workspace-integrity trigger's stock-movement branch at
--    generated_documents. Other branches are unchanged (the inventory PO
--    tables remain until the Phase 6 drop).
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
    -- purchase_order_id now references a document PO (generated_documents).
    IF NEW.purchase_order_id IS NOT NULL THEN
      SELECT workspace_id INTO v_po_ws FROM generated_documents WHERE id = NEW.purchase_order_id;
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
