-- =============================================================================
-- Revert allowance-line budget impact when an approved selection stops applying.
--
-- Problem found in review (2026-06-01): approve_selection_and_apply_budget writes
-- the chosen cost into the linked budget_items.approved_price. But nothing put
-- that value BACK when the selection later stopped being an approved application
-- of that line — so a declined / cancelled / deleted / re-pointed selection left
-- a stale approved_price (phantom budget impact). The rollup trigger then carried
-- that phantom up to parent groups.
--
-- Fix: a single trigger on `selections` that, whenever a row leaves the
-- "approved + applied to budget_item_id B" state, zeroes B.approved_price —
-- UNLESS some OTHER approved, non-excluded selection still applies to B (so we
-- never clobber a line a sibling selection legitimately owns). Covers every exit
-- path in one place (status change, budget_item_id re-point, exclude toggle,
-- DELETE), at the right altitude — no per-call-site cleanup in Dart.
--
-- Idempotent / additive. Reversible (DROP TRIGGER/FUNCTION).
-- =============================================================================

CREATE OR REPLACE FUNCTION public.selections_revert_budget_impact()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  old_line UUID;
  old_applied BOOLEAN;
  still_applied BOOLEAN;
BEGIN
  -- Was the OLD row an approved, budget-applying selection on a real line?
  old_line := OLD.budget_item_id;
  old_applied := (OLD.status = 'approved'
                  AND OLD.budget_item_id IS NOT NULL
                  AND OLD.exclude_from_budget = FALSE);

  IF NOT old_applied THEN
    RETURN COALESCE(NEW, OLD);  -- nothing was applied; nothing to revert
  END IF;

  -- On UPDATE: if the row STILL applies to the same line in the same way,
  -- the approval RPC already (re)set the correct amount — leave it alone.
  IF TG_OP = 'UPDATE'
     AND NEW.status = 'approved'
     AND NEW.exclude_from_budget = FALSE
     AND NEW.budget_item_id IS NOT DISTINCT FROM old_line THEN
    RETURN NEW;
  END IF;

  -- Does any OTHER approved, non-excluded selection still apply to old_line?
  SELECT EXISTS (
    SELECT 1 FROM selections s
     WHERE s.id <> OLD.id
       AND s.budget_item_id = old_line
       AND s.status = 'approved'
       AND s.exclude_from_budget = FALSE
  ) INTO still_applied;

  IF NOT still_applied THEN
    -- Reset the allowance line back to "budgeted but unselected".
    -- (Keeps is_allowance = TRUE; it's still an allowance bucket.)
    UPDATE budget_items
       SET approved_price = 0,
           approved_at    = NULL,
           updated_at     = now()
     WHERE id = old_line
       AND workspace_id = OLD.workspace_id;  -- tenant guard
  END IF;

  RETURN COALESCE(NEW, OLD);
END;
$$;

DROP TRIGGER IF EXISTS trg_selections_revert_budget ON selections;
CREATE TRIGGER trg_selections_revert_budget
  AFTER UPDATE OF status, budget_item_id, exclude_from_budget OR DELETE
  ON selections
  FOR EACH ROW
  EXECUTE FUNCTION public.selections_revert_budget_impact();
