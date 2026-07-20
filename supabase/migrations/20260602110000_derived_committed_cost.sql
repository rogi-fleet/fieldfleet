-- ===========================================================================
-- Unify purchase orders on documents — Phase 2: automatic committed cost
--
-- Makes budget_items.committed_cost a DERIVED value instead of a hand-written
-- one. Previously committed_cost was only ever set by a manual "Update Budget"
-- dialog, so the budget's "PO Commitments" never reflected a PO until a user
-- clicked through that dialog. Now a leaf budget item's committed_cost is the
-- SUM of amounts on its budget_document_links whose linked document is a vendor
-- commitment (purchase_order / request_for_bid) in a firm-commitment status
-- (signed / approved). It recomputes automatically whenever a PO is
-- approved/withdrawn or its budget links change.
--
-- Coexistence with the parent rollup (20260529120000):
--   • This function writes ONLY leaf items (items with no children). Parent
--     committed_cost stays owned by recompute_budget_parent_totals, which sums
--     children. The two never write the same row, so no double counting and no
--     mutual recursion.
--   • Setting a leaf's committed_cost fires budget_items_rollup_update, which
--     propagates the new total up the tree. The `IS DISTINCT FROM` guard below
--     suppresses no-op updates so the rollup only re-fires on real changes.
-- ===========================================================================

-- Recompute a single LEAF budget item's committed_cost from its document links.
CREATE OR REPLACE FUNCTION recompute_budget_item_committed(p_item_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_is_parent boolean;
  v_new       numeric;
BEGIN
  -- Parents are owned by recompute_budget_parent_totals (SUM of children).
  SELECT EXISTS (SELECT 1 FROM budget_items WHERE parent_id = p_item_id)
    INTO v_is_parent;
  IF v_is_parent THEN
    RETURN;
  END IF;

  v_new := COALESCE((
    SELECT SUM(bdl.amount)
      FROM budget_document_links bdl
      JOIN generated_documents g ON g.id = bdl.generated_document_id
     WHERE bdl.budget_item_id = p_item_id
       AND g.document_type IN ('purchase_order', 'request_for_bid')
       AND g.status IN ('signed', 'approved')
  ), 0);

  UPDATE budget_items
     SET committed_cost = v_new,
         updated_at     = now()
   WHERE id = p_item_id
     AND committed_cost IS DISTINCT FROM v_new;
END;
$$;

-- Fire when a document's budget links change (insert / amount edit / delete).
CREATE OR REPLACE FUNCTION trg_bdl_recompute_committed()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    PERFORM recompute_budget_item_committed(OLD.budget_item_id);
    RETURN OLD;
  END IF;

  PERFORM recompute_budget_item_committed(NEW.budget_item_id);
  IF TG_OP = 'UPDATE'
     AND OLD.budget_item_id IS DISTINCT FROM NEW.budget_item_id THEN
    PERFORM recompute_budget_item_committed(OLD.budget_item_id);
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS budget_document_links_committed ON budget_document_links;
CREATE TRIGGER budget_document_links_committed
  AFTER INSERT OR DELETE OR UPDATE OF amount, budget_item_id, generated_document_id
  ON budget_document_links
  FOR EACH ROW
  EXECUTE FUNCTION trg_bdl_recompute_committed();

-- Fire when a vendor-commitment document crosses a status boundary
-- (e.g. pending → approved, approved → withdrawn).
CREATE OR REPLACE FUNCTION trg_doc_status_recompute_committed()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  r RECORD;
BEGIN
  IF NEW.document_type NOT IN ('purchase_order', 'request_for_bid') THEN
    RETURN NEW;
  END IF;
  FOR r IN
    SELECT budget_item_id
      FROM budget_document_links
     WHERE generated_document_id = NEW.id
  LOOP
    PERFORM recompute_budget_item_committed(r.budget_item_id);
  END LOOP;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS generated_documents_committed ON generated_documents;
CREATE TRIGGER generated_documents_committed
  AFTER UPDATE OF status ON generated_documents
  FOR EACH ROW
  WHEN (OLD.status IS DISTINCT FROM NEW.status)
  EXECUTE FUNCTION trg_doc_status_recompute_committed();

-- One-shot backfill: recompute committed_cost for every leaf item that either
-- has a document link or carries a stale non-zero committed_cost from the old
-- manual flow. Leaves with no qualifying links reset to 0; the rollup trigger
-- then corrects their parents. Idempotent.
DO $backfill$
DECLARE
  r RECORD;
BEGIN
  FOR r IN
    SELECT bi.id
      FROM budget_items bi
     WHERE NOT EXISTS (SELECT 1 FROM budget_items c WHERE c.parent_id = bi.id)
       AND (
         EXISTS (SELECT 1 FROM budget_document_links l WHERE l.budget_item_id = bi.id)
         OR bi.committed_cost <> 0
       )
  LOOP
    PERFORM recompute_budget_item_committed(r.id);
  END LOOP;
END;
$backfill$;
