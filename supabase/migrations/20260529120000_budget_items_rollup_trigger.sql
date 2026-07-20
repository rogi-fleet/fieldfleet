-- Budget rollup: keep parent budget_items' denormalized totals
-- (approved_price, projected_cost, committed_cost) in sync with their direct
-- children's sums, no matter which code path inserts/updates/deletes a child.
--
-- Until now the rollup lived only in `SupabaseBudgetService._recalculateParentTotals`,
-- so any write that bypassed that service (REST API, raw SQL, future Edge
-- functions, etc.) left parent totals stale. Production audit on 2026-05-28
-- showed 2 parents with approved_price=0 while children summed > 0.
--
-- Approach: trigger-driven recompute that fires only when the child's
-- rollup-relevant fields actually change. The Dart service path continues
-- to call `_recalculateParentTotals` as before — the trigger is additive
-- belt-and-suspenders, not a replacement. The math is identical (pure SUM),
-- so the two paths converge to the same result.
--
-- Hierarchy depth is capped at 3 levels (0..2), so the propagation is
-- bounded: recomputing a parent UPDATEs that row, which re-fires the trigger
-- against its own parent, etc., terminating naturally when parent_id IS NULL.
--
-- Safety:
--  • No DELETE / DROP of existing data.
--  • Backfill at the bottom of this file is idempotent (re-running the
--    same SUM produces the same result).
--  • The function is SECURITY DEFINER so RLS doesn't block the implicit
--    parent update when a child insert is performed by a non-owner role,
--    but the WHERE clause only matches the explicit parent id — no cross-
--    workspace bleed possible.

CREATE OR REPLACE FUNCTION recompute_budget_parent_totals(p_parent_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE budget_items
     SET approved_price = COALESCE((
            SELECT SUM(approved_price)
              FROM budget_items
             WHERE parent_id = p_parent_id), 0),
         projected_cost = COALESCE((
            SELECT SUM(projected_cost)
              FROM budget_items
             WHERE parent_id = p_parent_id), 0),
         committed_cost = COALESCE((
            SELECT SUM(committed_cost)
              FROM budget_items
             WHERE parent_id = p_parent_id), 0),
         updated_at      = now()
   WHERE id = p_parent_id;
END;
$$;

CREATE OR REPLACE FUNCTION trg_budget_items_recompute_parent()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- INSERT: recompute the new parent.
  IF TG_OP = 'INSERT' THEN
    IF NEW.parent_id IS NOT NULL THEN
      PERFORM recompute_budget_parent_totals(NEW.parent_id);
    END IF;
    RETURN NEW;
  END IF;

  -- DELETE: recompute the old parent.
  IF TG_OP = 'DELETE' THEN
    IF OLD.parent_id IS NOT NULL THEN
      PERFORM recompute_budget_parent_totals(OLD.parent_id);
    END IF;
    RETURN OLD;
  END IF;

  -- UPDATE: recompute new parent always; recompute old parent too if the
  -- child was re-parented.
  IF NEW.parent_id IS NOT NULL THEN
    PERFORM recompute_budget_parent_totals(NEW.parent_id);
  END IF;
  IF OLD.parent_id IS NOT NULL
     AND OLD.parent_id IS DISTINCT FROM NEW.parent_id THEN
    PERFORM recompute_budget_parent_totals(OLD.parent_id);
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS budget_items_rollup_insert_delete ON budget_items;
CREATE TRIGGER budget_items_rollup_insert_delete
  AFTER INSERT OR DELETE ON budget_items
  FOR EACH ROW
  EXECUTE FUNCTION trg_budget_items_recompute_parent();

-- For UPDATE we use a column-list + WHEN clause so a rollup-irrelevant
-- UPDATE (e.g. renaming, changing description) doesn't trigger a parent
-- recompute, and so the parent's own UPDATE (which sets approved_price /
-- projected_cost / committed_cost) only re-fires upward when *its* values
-- actually changed — terminating the recursion at the top of the tree
-- without an explicit base case in the function.
DROP TRIGGER IF EXISTS budget_items_rollup_update ON budget_items;
CREATE TRIGGER budget_items_rollup_update
  AFTER UPDATE OF approved_price, projected_cost, committed_cost, parent_id
  ON budget_items
  FOR EACH ROW
  WHEN (
    OLD.approved_price IS DISTINCT FROM NEW.approved_price OR
    OLD.projected_cost IS DISTINCT FROM NEW.projected_cost OR
    OLD.committed_cost IS DISTINCT FROM NEW.committed_cost OR
    OLD.parent_id      IS DISTINCT FROM NEW.parent_id
  )
  EXECUTE FUNCTION trg_budget_items_recompute_parent();

-- One-shot backfill: walk every distinct parent_id and recompute its
-- totals from the children's current sums. Idempotent, safe to re-run.
-- Processes deeper hierarchy levels last so that level-1 rollups see the
-- already-corrected level-2 totals (Dart hierarchy_level: 0=group,
-- 1=section, 2=item).
DO $backfill$
DECLARE
  r RECORD;
BEGIN
  FOR r IN
    SELECT id
      FROM budget_items
     WHERE id IN (SELECT DISTINCT parent_id FROM budget_items WHERE parent_id IS NOT NULL)
     ORDER BY hierarchy_level DESC
  LOOP
    PERFORM recompute_budget_parent_totals(r.id);
  END LOOP;
END;
$backfill$;
