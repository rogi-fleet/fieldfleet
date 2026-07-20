-- =============================================================================
-- Bugfix: overage split must only apply when there's a real allowance.
--
-- A re-approved NON-allowance selection has allowance_amount = 0 but, after its
-- first approval, a non-null budget_item_id (the auto-created line). The over-
-- allowance branch then treated the entire chosen cost as "overage", zeroing the
-- base line and spinning the full amount into a change-order line. Guard the
-- split with allowance_amount > 0; otherwise roll the chosen cost into the line.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.approve_selection_and_apply_budget(
  p_selection_id uuid, p_option_id uuid, p_actor_name text DEFAULT NULL::text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  normalized_email TEXT := LOWER(TRIM(COALESCE(auth.jwt() ->> 'email', '')));
  sel_row RECORD; opt_row RECORD; v_amount NUMERIC(15,2); v_overage NUMERIC(15,2);
  v_is_member BOOLEAN := FALSE; v_is_client BOOLEAN := FALSE;
  v_budget_applied BOOLEAN := FALSE; v_budget_item_id UUID; v_co_id UUID;
BEGIN
  SELECT s.id, s.project_id, s.workspace_id, s.status, s.name, s.budget_item_id,
         s.exclude_from_budget, s.allowance_amount, s.change_order_budget_item_id, p.client_id
    INTO sel_row FROM selections s JOIN projects p ON p.id = s.project_id
   WHERE s.id = p_selection_id LIMIT 1;
  IF NOT FOUND THEN RAISE EXCEPTION 'Selection not found'; END IF;

  v_is_member := is_workspace_member(sel_row.workspace_id);
  IF normalized_email <> '' THEN
    SELECT EXISTS (SELECT 1 FROM customer_contacts cc WHERE cc.customer_id = sel_row.client_id
       AND cc.is_active = TRUE AND LOWER(TRIM(COALESCE(cc.email,''))) = normalized_email) INTO v_is_client;
  END IF;
  IF NOT (v_is_member OR v_is_client) THEN RAISE EXCEPTION 'Access denied'; END IF;
  IF sel_row.status = 'cancelled' THEN
    RAISE EXCEPTION 'Selection cannot be approved in status (%)', sel_row.status; END IF;

  SELECT id, unit_cost, quantity INTO opt_row FROM selection_options
   WHERE id = p_option_id AND selection_id = p_selection_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Option not found for this selection'; END IF;

  v_amount := COALESCE(opt_row.unit_cost,0) * COALESCE(NULLIF(opt_row.quantity,0),1);
  v_budget_item_id := sel_row.budget_item_id;

  UPDATE selections SET status='approved', selected_option_id=opt_row.id, selected_amount=v_amount,
    approved_at=COALESCE(approved_at, now()),
    approved_by_name=COALESCE(p_actor_name, approved_by_name, CASE WHEN v_is_client THEN 'Client' ELSE 'Team' END),
    approved_by_email=CASE WHEN v_is_client THEN normalized_email ELSE approved_by_email END,
    declined_at=NULL, declined_by_name=NULL, decline_reason=NULL, updated_at=now()
  WHERE id = p_selection_id;

  IF sel_row.change_order_budget_item_id IS NOT NULL THEN
    DELETE FROM budget_items WHERE id = sel_row.change_order_budget_item_id;
  END IF;

  IF sel_row.budget_item_id IS NOT NULL AND NOT sel_row.exclude_from_budget THEN
    v_overage := v_amount - COALESCE(sel_row.allowance_amount, 0);
    IF v_overage > 0 AND COALESCE(sel_row.allowance_amount, 0) > 0 THEN
      UPDATE budget_items SET is_allowance=TRUE, approved_price=COALESCE(sel_row.allowance_amount,0),
        approved_at=COALESCE(approved_at, now()), updated_at=now()
      WHERE id = sel_row.budget_item_id AND workspace_id = sel_row.workspace_id;
      INSERT INTO budget_items (workspace_id, project_id, parent_id, name, item_type, hierarchy_level,
        sort_order, quantity, unit, unit_cost, unit_price, markup, is_taxable,
        approved_price, projected_cost, committed_cost, final_cost,
        is_complete, source_type, is_allowance, approved_at, category_id)
      SELECT bi.workspace_id, bi.project_id, bi.parent_id, sel_row.name || ' (overage)', 'item', bi.hierarchy_level,
        COALESCE((SELECT MAX(sort_order)+1 FROM budget_items WHERE project_id=bi.project_id AND parent_id IS NOT DISTINCT FROM bi.parent_id),0),
        1, NULL, v_overage, v_overage, 0, bi.is_taxable, v_overage, v_overage, 0, 0,
        FALSE, 'change_order', FALSE, now(), bi.category_id
        FROM budget_items bi WHERE bi.id = sel_row.budget_item_id
      RETURNING id INTO v_co_id;
      UPDATE selections SET change_order_budget_item_id=v_co_id, updated_at=now() WHERE id=p_selection_id;
      v_budget_applied := TRUE;
    ELSE
      UPDATE budget_items SET is_allowance=TRUE, approved_price=v_amount,
        approved_at=COALESCE(approved_at, now()), updated_at=now()
      WHERE id = sel_row.budget_item_id AND workspace_id = sel_row.workspace_id;
      v_budget_applied := TRUE;
    END IF;
  ELSIF sel_row.budget_item_id IS NULL AND NOT sel_row.exclude_from_budget THEN
    INSERT INTO budget_items (workspace_id, project_id, name, item_type, hierarchy_level, sort_order,
      quantity, unit, unit_cost, unit_price, markup, is_taxable, approved_price, projected_cost,
      committed_cost, final_cost, is_complete, source_type, is_allowance, approved_at, category_id)
    VALUES (sel_row.workspace_id, sel_row.project_id, sel_row.name, 'item', 0,
      COALESCE((SELECT MAX(sort_order)+1 FROM budget_items WHERE project_id=sel_row.project_id AND parent_id IS NULL),0),
      1, NULL, v_amount, v_amount, 0, TRUE, v_amount, v_amount, 0, 0,
      FALSE, 'base', TRUE, now(),
      (SELECT id FROM cost_categories WHERE workspace_id=sel_row.workspace_id AND is_default=TRUE ORDER BY name LIMIT 1))
    RETURNING id INTO v_budget_item_id;
    UPDATE selections SET budget_item_id=v_budget_item_id, updated_at=now() WHERE id=p_selection_id;
    v_budget_applied := TRUE;
  END IF;

  RETURN jsonb_build_object('success', true, 'selection_id', p_selection_id, 'option_id', p_option_id,
    'selected_amount', v_amount, 'budget_item_id', v_budget_item_id,
    'overage', GREATEST(COALESCE(v_overage,0),0), 'budget_applied', v_budget_applied);
END;
$function$;
