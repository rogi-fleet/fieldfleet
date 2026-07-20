-- =============================================================================
-- Selections ↔ Budget integration (v1).
--
-- Design (per architect/PM/designer review):
--   * The allowance line IS the budget line. A selection links to one
--     budget_item via selections.budget_item_id. selections.allowance_amount
--     holds the *budgeted* snapshot; on approval the linked budget_item's
--     approved_price is set to the *actual* selected cost. Budgeted-vs-actual
--     variance = selections.allowance_amount vs budget_items.approved_price.
--     No child line is spawned, so there is no double-counting.
--   * Approval is performed by ONE atomic SECURITY DEFINER RPC so a client
--     retry/crash can never leave a selection approved-but-budget-untouched
--     (or apply the budget impact twice).
--   * The existing rollup trigger (20260529120000) cascades the new
--     approved_price up to any parent group automatically.
--
-- Forward-compat columns added now (UI/logic ships later, per PM phasing):
--   * selections.exclude_from_budget       — write-in choices skip budget impact
--   * selections.show_amount_differences   — drive overage display / v2 auto-CO
--   * selections.allow_multiple_selections — v2 multi-select
--   * budget_items.is_allowance            — marks allowance lines; powers the
--                                            v2 "Selections" budget view mode
--
-- Safety: additive only. No DROP/DELETE of data. Backfill is idempotent.
-- =============================================================================

-- ── New columns ─────────────────────────────────────────────────────────────

ALTER TABLE budget_items
  ADD COLUMN IF NOT EXISTS is_allowance BOOLEAN NOT NULL DEFAULT FALSE;

COMMENT ON COLUMN budget_items.is_allowance IS
  'TRUE when this line is a client-selection allowance (a budgeted bucket a '
  'selection resolves into). Used to group allowance lines in the budget view.';

ALTER TABLE selections
  ADD COLUMN IF NOT EXISTS exclude_from_budget       BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS show_amount_differences   BOOLEAN NOT NULL DEFAULT TRUE,
  ADD COLUMN IF NOT EXISTS allow_multiple_selections BOOLEAN NOT NULL DEFAULT FALSE;

COMMENT ON COLUMN selections.exclude_from_budget IS
  'TRUE for write-in selections the client researches themselves; approval '
  'does not touch the budget.';
COMMENT ON COLUMN selections.show_amount_differences IS
  'TRUE to surface overage/underage vs allowance to the client (and, in v2, '
  'to auto-draft a change order for overages).';
COMMENT ON COLUMN selections.allow_multiple_selections IS
  'v2: allow the client to pick more than one option for this selection.';

-- ── Backfill: any budget_item already linked from a selection is an allowance ─

DO $backfill$
DECLARE
  n INTEGER;
BEGIN
  UPDATE budget_items b
     SET is_allowance = TRUE
   WHERE is_allowance = FALSE
     AND EXISTS (
       SELECT 1 FROM selections s
        WHERE s.budget_item_id = b.id
     );
  GET DIAGNOSTICS n = ROW_COUNT;
  RAISE NOTICE 'selections_budget_integration: marked % budget_items as allowances', n;
END;
$backfill$;

-- ============================================================================
-- Atomic approval RPC.
--
-- Marks the selection approved to the chosen option AND, unless excluded,
-- applies the selected cost to the linked allowance budget_item — in one
-- transaction. SECURITY DEFINER; auth = JWT email matched against an active
-- customer_contact of the project's client (same gate as portal_approve_selection),
-- OR an internal workspace member (covers the team "pick for client" path and
-- document-signing approval driven by staff).
--
-- Idempotent: re-invoking with the same option is a no-op re-apply; invoking
-- with a different option re-points the selection and re-applies the budget.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.approve_selection_and_apply_budget(
  p_selection_id UUID,
  p_option_id    UUID,
  p_actor_name   TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  normalized_email TEXT := LOWER(TRIM(COALESCE(auth.jwt() ->> 'email', '')));
  sel_row   RECORD;
  opt_row   RECORD;
  v_amount  NUMERIC(15,2);
  v_is_member BOOLEAN := FALSE;
  v_is_client BOOLEAN := FALSE;
  v_budget_applied BOOLEAN := FALSE;
BEGIN
  -- Load the selection + its project's workspace/client.
  SELECT s.id, s.project_id, s.workspace_id, s.status,
         s.budget_item_id, s.exclude_from_budget, p.client_id
    INTO sel_row
    FROM selections s
    JOIN projects p ON p.id = s.project_id
   WHERE s.id = p_selection_id
   LIMIT 1;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Selection not found';
  END IF;

  -- Authorize: internal workspace member OR the project's active client contact.
  v_is_member := is_workspace_member(sel_row.workspace_id);
  IF normalized_email <> '' THEN
    SELECT EXISTS (
      SELECT 1 FROM customer_contacts cc
       WHERE cc.customer_id = sel_row.client_id
         AND cc.is_active = TRUE
         AND LOWER(TRIM(COALESCE(cc.email, ''))) = normalized_email
    ) INTO v_is_client;
  END IF;

  IF NOT (v_is_member OR v_is_client) THEN
    RAISE EXCEPTION 'Access denied';
  END IF;

  -- Approvable from any pre-cancellation state: 'pending' covers the internal
  -- "team picks the option for the client" path (before the selection is ever
  -- sent out); 'awaiting_client' is the normal client path; 'approved'/
  -- 'declined' allow idempotent re-approval / change-of-mind. Only a cancelled
  -- selection is rejected.
  IF sel_row.status = 'cancelled' THEN
    RAISE EXCEPTION 'Selection cannot be approved in status (%)', sel_row.status;
  END IF;

  -- Validate the chosen option belongs to this selection.
  SELECT id, unit_cost, quantity
    INTO opt_row
    FROM selection_options
   WHERE id = p_option_id AND selection_id = p_selection_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Option not found for this selection';
  END IF;

  v_amount := COALESCE(opt_row.unit_cost, 0) * COALESCE(NULLIF(opt_row.quantity, 0), 1);

  -- Mark the selection approved to the chosen option.
  UPDATE selections SET
    status             = 'approved',
    selected_option_id = opt_row.id,
    selected_amount    = v_amount,
    approved_at        = COALESCE(approved_at, now()),
    approved_by_name   = COALESCE(p_actor_name, approved_by_name,
                                  CASE WHEN v_is_client THEN 'Client' ELSE 'Team' END),
    approved_by_email  = CASE WHEN v_is_client THEN normalized_email ELSE approved_by_email END,
    declined_at        = NULL,
    declined_by_name   = NULL,
    decline_reason     = NULL,
    updated_at         = now()
  WHERE id = p_selection_id;

  -- Apply the actual selected cost to the linked allowance budget line.
  -- The rollup trigger (20260529120000) cascades this up to any parent group.
  IF sel_row.budget_item_id IS NOT NULL AND NOT sel_row.exclude_from_budget THEN
    UPDATE budget_items SET
      is_allowance   = TRUE,
      approved_price = v_amount,
      approved_at    = COALESCE(approved_at, now()),
      updated_at     = now()
    WHERE id = sel_row.budget_item_id
      AND workspace_id = sel_row.workspace_id;  -- tenant guard
    v_budget_applied := FOUND;
  END IF;

  RETURN jsonb_build_object(
    'success',       true,
    'selection_id',  p_selection_id,
    'option_id',     p_option_id,
    'selected_amount', v_amount,
    'budget_item_id',  sel_row.budget_item_id,
    'budget_applied',  v_budget_applied
  );
END;
$$;

REVOKE ALL ON FUNCTION public.approve_selection_and_apply_budget(UUID, UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.approve_selection_and_apply_budget(UUID, UUID, TEXT)
  TO authenticated;

-- ============================================================================
-- Re-point portal_approve_selection at the atomic RPC so the customer-facing
-- approve path also applies the budget impact. Signature unchanged → no Dart
-- change required for the portal call site.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.portal_approve_selection(
  p_selection_id UUID,
  p_option_id    UUID,
  p_actor_name   TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Delegates to the atomic approval+budget RPC (which enforces the same
  -- client-contact / workspace-member authorization).
  RETURN public.approve_selection_and_apply_budget(
    p_selection_id, p_option_id, COALESCE(p_actor_name, 'Client')
  );
END;
$$;

REVOKE ALL ON FUNCTION public.portal_approve_selection(UUID, UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.portal_approve_selection(UUID, UUID, TEXT)
  TO authenticated;
