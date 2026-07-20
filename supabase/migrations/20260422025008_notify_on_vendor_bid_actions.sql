-- Wire the Request-for-Bid flow into the existing document notification
-- infrastructure, and snapshot the prior bid on re-submission so history
-- is preserved.
--
-- Three functions are rewritten:
--   * create_document_action_notifications — add 'bid_received' and
--     'bid_applied' actions alongside the existing denied /
--     changes_requested / payment_completed branches.
--   * submit_vendor_bid — snapshot current line_items into
--     metadata.previousBids (capped at 5) before merging the new bid, then
--     emit a 'bid_received' notification with the vendor company name.
--   * apply_vendor_bid_to_budget — emit a 'bid_applied' notification with
--     the current user as the actor.

CREATE OR REPLACE FUNCTION public.create_document_action_notifications(
  p_document_id uuid,
  p_action text,
  p_actor_name text DEFAULT NULL,
  p_actor_email text DEFAULT NULL,
  p_reason text DEFAULT NULL
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  doc_row RECORD;
  project_manager_id UUID;
  actor_label TEXT;
  notif_type TEXT;
  notif_title TEXT;
  notif_body TEXT;
  inserted_count INTEGER := 0;
BEGIN
  SELECT
    gd.id,
    gd.workspace_id,
    gd.project_id,
    gd.created_by,
    COALESCE(NULLIF(TRIM(gd.template_name), ''), 'Document') AS template_name
  INTO doc_row
  FROM public.generated_documents gd
  WHERE gd.id = p_document_id
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN 0;
  END IF;

  IF doc_row.project_id IS NOT NULL THEN
    SELECT p.project_manager_id
    INTO project_manager_id
    FROM public.projects p
    WHERE p.id = doc_row.project_id
    LIMIT 1;
  END IF;

  actor_label := COALESCE(
    NULLIF(TRIM(p_actor_name), ''),
    NULLIF(TRIM(p_actor_email), ''),
    'the customer'
  );

  CASE p_action
    WHEN 'denied' THEN
      notif_type := 'document_denied';
      notif_title := doc_row.template_name || ' was denied';
      notif_body := 'Denied by ' || actor_label || '.';
      IF p_reason IS NOT NULL AND TRIM(p_reason) <> '' THEN
        notif_body := notif_body || ' Reason: ' || TRIM(p_reason);
      END IF;
    WHEN 'changes_requested' THEN
      notif_type := 'document_changes_requested';
      notif_title := 'Changes requested on ' || doc_row.template_name;
      notif_body := 'Requested by ' || actor_label || '.';
      IF p_reason IS NOT NULL AND TRIM(p_reason) <> '' THEN
        notif_body := notif_body || ' Reason: ' || TRIM(p_reason);
      END IF;
    WHEN 'payment_completed' THEN
      notif_type := 'document_payment_completed';
      notif_title := doc_row.template_name || ' payment received';
      notif_body := 'Payment completed by ' || actor_label || '.';
    WHEN 'bid_received' THEN
      notif_type := 'document_bid_received';
      notif_title := 'Bid received on ' || doc_row.template_name;
      notif_body := actor_label || ' has submitted their bid. Review and apply to budget.';
    WHEN 'bid_applied' THEN
      notif_type := 'document_bid_applied';
      notif_title := doc_row.template_name || ' bid applied to budget';
      notif_body := actor_label || ' applied the vendor bid to the project budget.';
    ELSE
      RETURN 0;
  END CASE;

  INSERT INTO public.notifications (
    user_id,
    workspace_id,
    type,
    title,
    body,
    metadata
  )
  SELECT
    recipients.user_id,
    doc_row.workspace_id,
    notif_type,
    notif_title,
    notif_body,
    jsonb_build_object(
      'target_type', 'document',
      'document_id', doc_row.id,
      'project_id', doc_row.project_id,
      'action', p_action,
      'reason', NULLIF(TRIM(COALESCE(p_reason, '')), ''),
      'deeplink_path', '/documents/' || doc_row.id::TEXT
    )
  FROM (
    SELECT DISTINCT user_id
    FROM (
      SELECT doc_row.created_by AS user_id
      UNION ALL
      SELECT project_manager_id AS user_id
      UNION ALL
      SELECT wm.user_id
      FROM public.workspace_members wm
      WHERE wm.workspace_id = doc_row.workspace_id
        AND wm.role = 'admin'
    ) candidate_recipients
    WHERE user_id IS NOT NULL
  ) recipients;

  GET DIAGNOSTICS inserted_count = ROW_COUNT;
  RETURN inserted_count;
END;
$function$;


CREATE OR REPLACE FUNCTION public.submit_vendor_bid(
  p_document_id uuid,
  p_line_item_bids jsonb,
  p_overall_note text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_doc generated_documents%ROWTYPE;
  v_bid_request bid_requests%ROWTYPE;
  v_line_items jsonb;
  v_new_line_items jsonb;
  v_li jsonb;
  v_bid jsonb;
  v_total numeric := 0;
  v_qty numeric;
  v_bid_price numeric;
  v_vendor_name text;
  v_prev_bids jsonb;
  v_snapshot jsonb;
  v_metadata jsonb;
BEGIN
  IF p_line_item_bids IS NULL OR jsonb_typeof(p_line_item_bids) <> 'array' THEN
    RAISE EXCEPTION 'p_line_item_bids must be a jsonb array'
      USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_doc FROM generated_documents WHERE id = p_document_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Document % not found', p_document_id
      USING ERRCODE = 'P0002';
  END IF;

  IF v_doc.document_type::text <> 'request_for_bid' THEN
    RAISE EXCEPTION 'Document % is not a request for bid', p_document_id
      USING ERRCODE = 'P0001';
  END IF;

  IF v_doc.status::text = 'applied' THEN
    RAISE EXCEPTION 'Bid has already been applied to budget and is locked'
      USING ERRCODE = 'P0001';
  END IF;

  IF NOT (
    (v_doc.vendor_id IS NOT NULL
      AND v_doc.vendor_id IN (
        SELECT current_portal_vendor_ids(v_doc.workspace_id)
      ))
    OR has_workspace_module_permission(
      v_doc.workspace_id, 'bid_requests', 'write'
    )
  ) THEN
    RAISE EXCEPTION 'Not authorized to submit a bid on document %',
      p_document_id USING ERRCODE = '42501';
  END IF;

  v_line_items := COALESCE(v_doc.line_items, '[]'::jsonb);

  -- If this is a re-submission (status already 'responded'), preserve the
  -- prior bid as a snapshot in metadata.previousBids (capped at 5).
  IF v_doc.status::text = 'responded' THEN
    v_snapshot := jsonb_build_object(
      'submittedAt', to_jsonb(NOW()),
      'lineItems', v_line_items
    );
    v_metadata := COALESCE(v_doc.metadata, '{}'::jsonb);
    v_prev_bids := COALESCE(v_metadata->'previousBids', '[]'::jsonb);
    -- Prepend the snapshot, keep only the 5 most recent.
    v_prev_bids := jsonb_build_array(v_snapshot) || v_prev_bids;
    IF jsonb_array_length(v_prev_bids) > 5 THEN
      v_prev_bids := (
        SELECT jsonb_agg(elem)
        FROM (
          SELECT elem, ordinality
          FROM jsonb_array_elements(v_prev_bids) WITH ORDINALITY AS t(elem, ordinality)
          WHERE ordinality <= 5
          ORDER BY ordinality
        ) capped
      );
    END IF;
    v_metadata := jsonb_set(v_metadata, '{previousBids}', v_prev_bids, true);
  ELSE
    v_metadata := v_doc.metadata;
  END IF;

  v_new_line_items := '[]'::jsonb;

  FOR v_li IN SELECT * FROM jsonb_array_elements(v_line_items)
  LOOP
    FOR v_bid IN SELECT * FROM jsonb_array_elements(p_line_item_bids)
    LOOP
      IF v_bid->>'id' = v_li->>'id' THEN
        IF v_bid ? 'vendorBidPrice' THEN
          IF v_bid->>'vendorBidPrice' IS NULL THEN
            v_li := v_li - 'vendorBidPrice';
          ELSE
            v_bid_price := (v_bid->>'vendorBidPrice')::numeric;
            v_li := jsonb_set(
              v_li, '{vendorBidPrice}', to_jsonb(v_bid_price), true
            );
          END IF;
        END IF;
        IF v_bid ? 'vendorBidNote' THEN
          IF v_bid->>'vendorBidNote' IS NULL THEN
            v_li := v_li - 'vendorBidNote';
          ELSE
            v_li := jsonb_set(
              v_li, '{vendorBidNote}', v_bid->'vendorBidNote', true
            );
          END IF;
        END IF;
        EXIT;
      END IF;
    END LOOP;

    IF COALESCE(v_li->>'type', 'item') = 'item'
      AND v_li->>'vendorBidPrice' IS NOT NULL
    THEN
      v_qty := COALESCE((v_li->>'quantity')::numeric, 1);
      v_total := v_total + (v_qty * (v_li->>'vendorBidPrice')::numeric);
    END IF;

    v_new_line_items := v_new_line_items || v_li;
  END LOOP;

  UPDATE generated_documents
  SET line_items = v_new_line_items,
      status = 'responded',
      metadata = v_metadata,
      updated_at = NOW()
  WHERE id = p_document_id;

  SELECT * INTO v_bid_request FROM bid_requests
    WHERE project_id = v_doc.project_id
      AND vendor_id = v_doc.vendor_id
    ORDER BY created_at DESC
    LIMIT 1;

  IF v_bid_request.id IS NOT NULL THEN
    UPDATE bid_requests
    SET vendor_bid_amount = v_total,
        vendor_notes = p_overall_note,
        status = 'responded',
        response_date = NOW(),
        updated_at = NOW()
    WHERE id = v_bid_request.id;
  END IF;

  -- Notify GC-side creators / PMs / admins that a bid has landed.
  IF v_doc.vendor_id IS NOT NULL THEN
    SELECT COALESCE(NULLIF(TRIM(company_name), ''), 'The vendor')
    INTO v_vendor_name
    FROM vendors
    WHERE id = v_doc.vendor_id
    LIMIT 1;
  END IF;

  PERFORM create_document_action_notifications(
    p_document_id,
    'bid_received',
    COALESCE(v_vendor_name, 'The vendor'),
    NULL,
    NULL
  );
END;
$$;


CREATE OR REPLACE FUNCTION public.apply_vendor_bid_to_budget(
  p_document_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_doc generated_documents%ROWTYPE;
  v_li jsonb;
  v_budget_item_id uuid;
  v_bid_price numeric;
  v_qty numeric;
  v_new_projected numeric;
  v_bi budget_items%ROWTYPE;
  v_actor uuid := auth.uid();
  v_actor_name text;
  v_actor_email text;
BEGIN
  SELECT * INTO v_doc FROM generated_documents WHERE id = p_document_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Document % not found', p_document_id
      USING ERRCODE = 'P0002';
  END IF;

  IF v_doc.document_type::text <> 'request_for_bid' THEN
    RAISE EXCEPTION 'Document % is not a request for bid', p_document_id
      USING ERRCODE = 'P0001';
  END IF;

  IF v_doc.status::text <> 'responded' THEN
    RAISE EXCEPTION
      'Document must be in responded status to apply to budget (current: %)',
      v_doc.status USING ERRCODE = 'P0001';
  END IF;

  IF NOT has_workspace_module_permission(
    v_doc.workspace_id, 'budget', 'write'
  ) THEN
    RAISE EXCEPTION 'Not authorized to modify budget'
      USING ERRCODE = '42501';
  END IF;

  IF NOT has_workspace_module_permission(
    v_doc.workspace_id, 'documents', 'write'
  ) THEN
    RAISE EXCEPTION 'Not authorized to modify this document'
      USING ERRCODE = '42501';
  END IF;

  FOR v_li IN SELECT * FROM jsonb_array_elements(
    COALESCE(v_doc.line_items, '[]'::jsonb)
  )
  LOOP
    v_budget_item_id := NULLIF(v_li->>'budgetItemId', '')::uuid;
    v_bid_price := NULLIF(v_li->>'vendorBidPrice', '')::numeric;
    IF v_budget_item_id IS NULL OR v_bid_price IS NULL THEN
      CONTINUE;
    END IF;

    SELECT * INTO v_bi FROM budget_items WHERE id = v_budget_item_id;
    IF NOT FOUND OR v_bi.workspace_id <> v_doc.workspace_id THEN
      CONTINUE;
    END IF;

    v_qty := COALESCE((v_li->>'quantity')::numeric, 1);
    v_new_projected := v_bid_price * v_qty;

    INSERT INTO budget_item_events (
      workspace_id, budget_item_id, source_document_id, actor_id,
      event_type, previous_values, new_values
    ) VALUES (
      v_bi.workspace_id, v_bi.id, v_doc.id, v_actor,
      'vendor_bid_applied',
      jsonb_build_object(
        'projectedCost', v_bi.projected_cost,
        'unitCost', v_bi.unit_cost
      ),
      jsonb_build_object(
        'projectedCost', v_new_projected,
        'unitCost', v_bid_price
      )
    );

    UPDATE budget_items
    SET projected_cost = v_new_projected,
        unit_cost = v_bid_price,
        updated_at = NOW()
    WHERE id = v_bi.id;
  END LOOP;

  UPDATE generated_documents
  SET status = 'applied',
      line_items = (
        SELECT jsonb_agg(
          CASE
            WHEN elem->>'vendorBidPrice' IS NOT NULL
              THEN jsonb_set(elem, '{unitPrice}', elem->'vendorBidPrice')
            ELSE elem
          END
        )
        FROM jsonb_array_elements(COALESCE(line_items, '[]'::jsonb)) elem
      ),
      updated_at = NOW()
  WHERE id = p_document_id;

  -- Emit bid_applied notification with the current user as the actor.
  IF v_actor IS NOT NULL THEN
    SELECT display_name, email
    INTO v_actor_name, v_actor_email
    FROM users
    WHERE id = v_actor
    LIMIT 1;
  END IF;

  PERFORM create_document_action_notifications(
    p_document_id,
    'bid_applied',
    v_actor_name,
    v_actor_email,
    NULL
  );
END;
$$;
