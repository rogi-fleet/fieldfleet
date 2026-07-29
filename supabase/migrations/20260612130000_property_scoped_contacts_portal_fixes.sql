-- Fix: every pre-existing portal RPC that authorizes via
-- "customer_contacts.customer_id = <project's client_id> AND email match"
-- was written before unit holders (property-restricted contacts) existed,
-- so none of them exclude cc.restricted_property_id. A unit holder's
-- contact row still has a valid customer_id (the same customer, just also
-- scoped to one property), so every one of these RPCs still granted full
-- customer-wide access — defeating the whole point of the restriction.
--
-- This migration re-defines each affected function, unchanged except for
-- adding "AND cc.restricted_property_id IS NULL" alongside the existing
-- "AND cc.is_active = TRUE" check. This mirrors the same exclusion already
-- applied to current_portal_customer_ids() in
-- 20260612100000_add_property_scoped_portal_contacts.sql.
--
-- portal_can_request_access() is deliberately NOT touched: it only checks
-- "does any customer_contacts row exist for this email" to gate whether a
-- magic-link can be requested at all — it does not expose customer-wide
-- data, and a unit holder must still be able to request a login link.

CREATE OR REPLACE FUNCTION public._portal_can_read_conversation(p_conversation_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT EXISTS (
    SELECT 1
      FROM public.conversations c
      JOIN public.projects p ON p.id = c.scope_reference_id
      JOIN public.customer_contacts cc ON cc.customer_id = p.client_id
     WHERE c.id = p_conversation_id
       AND c.scope = 'project'
       AND c.portal_visible = TRUE
       AND cc.is_active = TRUE
       AND cc.restricted_property_id IS NULL
       AND lower(cc.email) = lower(coalesce(auth.email(), ''))
  );
$function$;

CREATE OR REPLACE FUNCTION public._portal_conversation_authorized(p_conversation_id uuid, p_preview_customer_id uuid DEFAULT NULL::uuid)
 RETURNS conversations
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_conv      public.conversations;
  v_project   public.projects;
  v_preview   BOOLEAN := public._portal_preview_authorized(p_preview_customer_id);
  v_caller_id UUID := auth.uid();
BEGIN
  SELECT * INTO v_conv FROM public.conversations WHERE id = p_conversation_id;
  IF NOT FOUND THEN
    RETURN NULL;
  END IF;

  -- Only project-scoped, portal-visible threads are exposed.
  IF v_conv.scope <> 'project'
     OR v_conv.scope_reference_id IS NULL
     OR v_conv.portal_visible IS NOT TRUE THEN
    RETURN NULL;
  END IF;

  SELECT * INTO v_project FROM public.projects WHERE id = v_conv.scope_reference_id;
  IF NOT FOUND THEN
    RETURN NULL;
  END IF;

  IF v_preview THEN
    -- Preview: caller is a workspace_member of the project's workspace AND
    -- the project belongs to the preview customer.
    IF v_project.client_id = p_preview_customer_id
       AND EXISTS (
         SELECT 1 FROM public.workspace_members wm
         WHERE wm.user_id = v_caller_id
           AND wm.workspace_id = v_project.workspace_id
       ) THEN
      RETURN v_conv;
    END IF;
    RETURN NULL;
  END IF;

  -- Real portal user: email match on the project's client.
  IF v_project.client_id IS NOT NULL
     AND EXISTS (
       SELECT 1 FROM public.customer_contacts cc
       WHERE cc.customer_id = v_project.client_id
         AND cc.is_active = TRUE
         AND cc.restricted_property_id IS NULL
         AND lower(cc.email) = lower(coalesce(auth.email(), ''))
     ) THEN
    RETURN v_conv;
  END IF;

  RETURN NULL;
END;
$function$;

CREATE OR REPLACE FUNCTION public.portal_add_selection_comment(p_selection_id uuid, p_body text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  normalized_email TEXT := LOWER(TRIM(COALESCE(auth.jwt() ->> 'email', '')));
  v_workspace UUID;
  v_name TEXT;
BEGIN
  IF normalized_email = '' THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;
  IF COALESCE(TRIM(p_body), '') = '' THEN
    RAISE EXCEPTION 'Message cannot be empty';
  END IF;

  SELECT s.workspace_id, cc.name
    INTO v_workspace, v_name
    FROM selections s
    JOIN projects p ON p.id = s.project_id
    JOIN customer_contacts cc ON cc.customer_id = p.client_id
   WHERE s.id = p_selection_id
     AND cc.is_active = TRUE
     AND cc.restricted_property_id IS NULL
     AND LOWER(TRIM(COALESCE(cc.email, ''))) = normalized_email
   LIMIT 1;

  IF v_workspace IS NULL THEN
    RAISE EXCEPTION 'Selection not found or access denied';
  END IF;

  INSERT INTO selection_comments
    (selection_id, workspace_id, body, author_name, author_email, is_from_client)
  VALUES
    (p_selection_id, v_workspace, TRIM(p_body),
     COALESCE(NULLIF(TRIM(v_name), ''), 'Client'), normalized_email, TRUE);

  RETURN jsonb_build_object('success', true);
END;
$function$;

CREATE OR REPLACE FUNCTION public.portal_add_selection_signature(p_selection_id uuid, p_signer_name text, p_signer_email text, p_signature_url text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  normalized_email TEXT := LOWER(TRIM(COALESCE(auth.jwt() ->> 'email', '')));
  v_workspace UUID;
BEGIN
  IF normalized_email = '' THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;
  IF COALESCE(TRIM(p_signature_url), '') = '' THEN
    RAISE EXCEPTION 'Signature required';
  END IF;

  SELECT s.workspace_id INTO v_workspace
    FROM selections s
    JOIN projects p ON p.id = s.project_id
    JOIN customer_contacts cc ON cc.customer_id = p.client_id
   WHERE s.id = p_selection_id
     AND cc.is_active = TRUE
     AND cc.restricted_property_id IS NULL
     AND LOWER(TRIM(COALESCE(cc.email, ''))) = normalized_email
   LIMIT 1;
  IF v_workspace IS NULL THEN
    RAISE EXCEPTION 'Selection not found or access denied';
  END IF;

  INSERT INTO selection_signatures
    (selection_id, workspace_id, signer_name, signer_email, signature_url)
  VALUES
    (p_selection_id, v_workspace, NULLIF(TRIM(COALESCE(p_signer_name,'')),''),
     COALESCE(NULLIF(TRIM(COALESCE(p_signer_email,'')),''), normalized_email),
     p_signature_url);

  RETURN jsonb_build_object('success', true);
END;
$function$;

CREATE OR REPLACE FUNCTION public.approve_selection_and_apply_budget(p_selection_id uuid, p_option_id uuid, p_actor_name text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
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
       AND cc.is_active = TRUE AND cc.restricted_property_id IS NULL
       AND LOWER(TRIM(COALESCE(cc.email,''))) = normalized_email) INTO v_is_client;
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

CREATE OR REPLACE FUNCTION public.portal_decline_selection(p_selection_id uuid, p_reason text DEFAULT NULL::text, p_actor_name text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  normalized_email TEXT := LOWER(TRIM(COALESCE(auth.jwt() ->> 'email', '')));
  sel_row RECORD;
BEGIN
  IF normalized_email = '' THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  SELECT s.id, s.status
  INTO sel_row
  FROM selections s
  JOIN projects p ON p.id = s.project_id
  JOIN customer_contacts cc ON cc.customer_id = p.client_id
  WHERE s.id = p_selection_id
    AND cc.is_active = TRUE
    AND cc.restricted_property_id IS NULL
    AND LOWER(TRIM(COALESCE(cc.email, ''))) = normalized_email
  LIMIT 1;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Selection not found or access denied';
  END IF;

  IF sel_row.status <> 'awaiting_client' THEN
    RAISE EXCEPTION 'Selection cannot be declined in status (%)', sel_row.status;
  END IF;

  UPDATE selections SET
    status           = 'declined',
    declined_at      = now(),
    declined_by_name = COALESCE(p_actor_name, 'Client'),
    decline_reason   = p_reason,
    updated_at       = now()
  WHERE id = p_selection_id;

  RETURN jsonb_build_object('success', true);
END;
$function$;

CREATE OR REPLACE FUNCTION public.portal_deny_document(p_document_id uuid, p_reason text DEFAULT NULL::text, p_actor_name text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  normalized_email TEXT := LOWER(TRIM(COALESCE(auth.jwt() ->> 'email', '')));
  doc_row RECORD;
  now_ts TIMESTAMPTZ := NOW();
BEGIN
  IF normalized_email = '' THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  -- Fetch document and verify portal access
  SELECT gd.id, gd.workspace_id, gd.project_id, gd.status::TEXT AS status
  INTO doc_row
  FROM generated_documents gd
  JOIN projects p ON p.id = gd.project_id
  WHERE gd.id = p_document_id
    AND p.client_id IS NOT NULL
    AND EXISTS (
      SELECT 1
      FROM customer_contacts cc
      WHERE cc.customer_id = p.client_id
        AND cc.is_active = TRUE
        AND cc.restricted_property_id IS NULL
        AND LOWER(TRIM(COALESCE(cc.email, ''))) = normalized_email
    )
  LIMIT 1;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Document not found or access denied';
  END IF;

  IF doc_row.status NOT IN ('sent', 'viewed') THEN
    RAISE EXCEPTION 'Document cannot be denied in its current status (%)', doc_row.status;
  END IF;

  UPDATE generated_documents
  SET status = 'denied',
      denied_at = now_ts,
      denied_by_name = p_actor_name,
      denied_by_email = normalized_email,
      denial_reason = p_reason,
      updated_at = now_ts
  WHERE id = p_document_id;

  INSERT INTO document_activity_log (workspace_id, document_id, action, actor_email, actor_name, actor_type, details)
  VALUES (doc_row.workspace_id, p_document_id, 'denied', normalized_email, p_actor_name, 'portal_user',
    jsonb_build_object('reason', COALESCE(p_reason, '')));

  PERFORM create_document_action_notifications(p_document_id, 'denied', p_actor_name, normalized_email, p_reason);

  RETURN jsonb_build_object('success', true);
END;
$function$;

CREATE OR REPLACE FUNCTION public.portal_get_document(p_document_id uuid, p_preview_customer_id uuid DEFAULT NULL::uuid)
 RETURNS TABLE(id uuid, project_id uuid, workspace_id uuid, customer_id uuid, template_name text, document_number text, document_type text, status text, rendered_content text, line_items jsonb, line_item_visibility text, total_amount numeric, collect_tax boolean, tax_name text, tax_rate numeric, due_date timestamp with time zone, paid_date timestamp with time zone, metadata jsonb, prepared_by jsonb, prepared_for jsonb, footer_content text, signed_by_name text, signed_by_email text, signed_at timestamp with time zone, signature_url text, denied_at timestamp with time zone, denied_by_name text, denied_by_email text, denial_reason text, created_by uuid, created_at timestamp with time zone, updated_at timestamp with time zone, project_name text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_email   TEXT    := LOWER(TRIM(COALESCE(auth.jwt() ->> 'email', '')));
  v_preview BOOLEAN := public._portal_preview_authorized(p_preview_customer_id);
BEGIN
  IF p_document_id IS NULL OR (NOT v_preview AND v_email = '') THEN RETURN; END IF;

  RETURN QUERY
  SELECT
    d.id, d.project_id, d.workspace_id, d.customer_id,
    d.template_name, d.document_number, d.document_type::TEXT, d.status::TEXT,
    d.rendered_content, d.line_items, d.line_item_visibility::TEXT,
    d.total_amount, d.collect_tax, d.tax_name, d.tax_rate,
    d.due_date, d.paid_date, d.metadata,
    d.prepared_by, d.prepared_for, d.footer_content,
    d.signed_by_name, d.signed_by_email, d.signed_at, d.signature_url,
    d.denied_at, d.denied_by_name, d.denied_by_email, d.denial_reason,
    d.created_by, d.created_at, d.updated_at, p.name AS project_name
  FROM public.generated_documents d
  JOIN public.projects p ON p.id = d.project_id
  WHERE d.id = p_document_id
    AND d.document_type IN (
      'quotation','change_order','work_auth','work_auth_emergency',
      'work_auth_restoration','work_auth_services','selections',
      'service_agreement','invoice','progress_invoice','credit','deposit',
      'refund','work_order','work_order_emergency','work_order_maintenance'
    )
    AND p.client_id IS NOT NULL
    AND (
      (v_preview AND p.client_id = p_preview_customer_id)
      OR (NOT v_preview AND EXISTS (
        SELECT 1 FROM public.customer_contacts cc
        WHERE cc.customer_id = p.client_id
          AND cc.is_active = TRUE
          AND cc.restricted_property_id IS NULL
          AND LOWER(TRIM(COALESCE(cc.email, ''))) = v_email
      ))
    )
  LIMIT 1;
END;
$function$;

CREATE OR REPLACE FUNCTION public.portal_get_document_activity(p_document_id uuid, p_preview_customer_id uuid DEFAULT NULL::uuid)
 RETURNS TABLE(id uuid, document_id uuid, action text, actor_email text, actor_name text, actor_type text, details jsonb, created_at timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_email   TEXT    := LOWER(TRIM(COALESCE(auth.jwt() ->> 'email', '')));
  v_preview BOOLEAN := public._portal_preview_authorized(p_preview_customer_id);
BEGIN
  IF p_document_id IS NULL OR (NOT v_preview AND v_email = '') THEN
    RETURN;
  END IF;

  -- Verify the document belongs to a project owned by the right customer.
  IF NOT EXISTS (
    SELECT 1
    FROM generated_documents d
    JOIN projects p ON p.id = d.project_id
    WHERE d.id = p_document_id
      AND p.client_id IS NOT NULL
      AND (
        (v_preview AND p.client_id = p_preview_customer_id)
        OR (NOT v_preview AND EXISTS (
          SELECT 1 FROM customer_contacts cc
          WHERE cc.customer_id = p.client_id
            AND cc.is_active = TRUE
            AND cc.restricted_property_id IS NULL
            AND LOWER(TRIM(COALESCE(cc.email, ''))) = v_email
        ))
      )
  ) THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT dal.id, dal.document_id, dal.action, dal.actor_email,
         dal.actor_name, dal.actor_type, dal.details, dal.created_at
  FROM document_activity_log dal
  WHERE dal.document_id = p_document_id
  ORDER BY dal.created_at DESC;
END;
$function$;

CREATE OR REPLACE FUNCTION public.portal_get_invoice(invoice_id uuid, p_preview_customer_id uuid DEFAULT NULL::uuid)
 RETURNS TABLE(id uuid, project_id uuid, workspace_id uuid, customer_id uuid, document_number text, document_type text, status text, line_items jsonb, total_amount numeric, amount_paid numeric, discount_amount numeric, collect_tax boolean, tax_name text, tax_rate numeric, due_date timestamp with time zone, paid_date timestamp with time zone, metadata jsonb, rendered_content text, created_by uuid, created_at timestamp with time zone, updated_at timestamp with time zone, project_name text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_email   TEXT    := LOWER(TRIM(COALESCE(auth.jwt() ->> 'email', '')));
  v_preview BOOLEAN := public._portal_preview_authorized(p_preview_customer_id);
BEGIN
  IF invoice_id IS NULL OR (NOT v_preview AND v_email = '') THEN RETURN; END IF;

  RETURN QUERY
  SELECT
    d.id, d.project_id, d.workspace_id, d.customer_id,
    d.document_number, d.document_type::TEXT, d.status::TEXT, d.line_items,
    d.total_amount, d.amount_paid, d.discount_amount,
    d.collect_tax, d.tax_name, d.tax_rate,
    d.due_date, d.paid_date, d.metadata, d.rendered_content,
    d.created_by, d.created_at, d.updated_at, p.name AS project_name
  FROM generated_documents d
  JOIN projects p ON p.id = d.project_id
  WHERE d.id = invoice_id
    AND d.document_type = 'invoice'
    AND p.client_id IS NOT NULL
    AND (
      (v_preview AND p.client_id = p_preview_customer_id)
      OR (NOT v_preview AND EXISTS (
        SELECT 1 FROM customer_contacts cc
        WHERE cc.customer_id = p.client_id
          AND cc.is_active = TRUE
          AND cc.restricted_property_id IS NULL
          AND LOWER(TRIM(COALESCE(cc.email, ''))) = v_email
      ))
    )
  LIMIT 1;
END;
$function$;

CREATE OR REPLACE FUNCTION public.portal_get_invoices(p_project_id uuid DEFAULT NULL::uuid, p_preview_customer_id uuid DEFAULT NULL::uuid)
 RETURNS TABLE(id uuid, project_id uuid, workspace_id uuid, customer_id uuid, document_number text, document_type text, status text, line_items jsonb, total_amount numeric, amount_paid numeric, discount_amount numeric, collect_tax boolean, tax_name text, tax_rate numeric, due_date timestamp with time zone, paid_date timestamp with time zone, metadata jsonb, rendered_content text, created_by uuid, created_at timestamp with time zone, updated_at timestamp with time zone, project_name text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_email   TEXT    := LOWER(TRIM(COALESCE(auth.jwt() ->> 'email', '')));
  v_preview BOOLEAN := public._portal_preview_authorized(p_preview_customer_id);
BEGIN
  IF NOT v_preview AND v_email = '' THEN RETURN; END IF;

  RETURN QUERY
  SELECT
    d.id, d.project_id, d.workspace_id, d.customer_id,
    d.document_number, d.document_type::TEXT, d.status::TEXT, d.line_items,
    d.total_amount, d.amount_paid, d.discount_amount,
    d.collect_tax, d.tax_name, d.tax_rate,
    d.due_date, d.paid_date, d.metadata, d.rendered_content,
    d.created_by, d.created_at, d.updated_at, p.name AS project_name
  FROM generated_documents d
  JOIN projects p ON p.id = d.project_id
  WHERE d.document_type = 'invoice'
    AND (p_project_id IS NULL OR d.project_id = p_project_id)
    AND p.client_id IS NOT NULL
    AND (
      (v_preview AND p.client_id = p_preview_customer_id)
      OR (NOT v_preview AND EXISTS (
        SELECT 1 FROM customer_contacts cc
        WHERE cc.customer_id = p.client_id
          AND cc.is_active = TRUE
          AND cc.restricted_property_id IS NULL
          AND LOWER(TRIM(COALESCE(cc.email, ''))) = v_email
      ))
    )
  ORDER BY COALESCE(d.due_date, d.created_at) DESC, d.created_at DESC;
END;
$function$;

CREATE OR REPLACE FUNCTION public.portal_get_or_create_project_thread(p_project_id uuid, p_preview_customer_id uuid DEFAULT NULL::uuid)
 RETURNS conversations
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_project   public.projects;
  v_conv      public.conversations;
  v_preview   BOOLEAN := public._portal_preview_authorized(p_preview_customer_id);
  v_caller_id UUID := auth.uid();
  v_participants UUID[] := ARRAY[]::UUID[];
  v_names     JSONB := '{}'::jsonb;
  v_unread    JSONB := '{}'::jsonb;
  v_subject   TEXT;
  v_staff     RECORD;
BEGIN
  SELECT * INTO v_project FROM public.projects WHERE id = p_project_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Project not found';
  END IF;

  -- Authorize (same rules as portal_get_project).
  IF v_preview THEN
    IF v_project.client_id <> p_preview_customer_id
       OR NOT EXISTS (
         SELECT 1 FROM public.workspace_members wm
         WHERE wm.user_id = v_caller_id
           AND wm.workspace_id = v_project.workspace_id
       ) THEN
      RAISE EXCEPTION 'Not authorized';
    END IF;
  ELSE
    IF v_project.client_id IS NULL
       OR NOT EXISTS (
         SELECT 1 FROM public.customer_contacts cc
         WHERE cc.customer_id = v_project.client_id
           AND cc.is_active = TRUE
           AND cc.restricted_property_id IS NULL
           AND lower(cc.email) = lower(coalesce(auth.email(), ''))
       ) THEN
      RAISE EXCEPTION 'Not authorized';
    END IF;
  END IF;

  -- Return existing thread if any.
  SELECT * INTO v_conv FROM public.conversations
   WHERE scope = 'project'
     AND scope_reference_id = p_project_id
     AND portal_visible = TRUE
   ORDER BY created_at ASC
   LIMIT 1;

  IF FOUND THEN
    IF NOT v_preview AND NOT (v_caller_id = ANY(v_conv.participant_ids)) THEN
      UPDATE public.conversations
         SET participant_ids = array_append(participant_ids, v_caller_id),
             unread_counts = COALESCE(unread_counts, '{}'::jsonb)
                              || jsonb_build_object(v_caller_id::text, 0)
       WHERE id = v_conv.id
       RETURNING * INTO v_conv;
    END IF;
    RETURN v_conv;
  END IF;

  -- Seed staff: every admin + project_manager in the workspace, plus the
  -- project's project_manager_id (if not already covered).
  FOR v_staff IN
    SELECT DISTINCT wm.user_id, COALESCE(u.display_name, u.email) AS name
      FROM public.workspace_members wm
      JOIN public.users u ON u.id = wm.user_id
     WHERE wm.workspace_id = v_project.workspace_id
       AND wm.role IN ('admin', 'project_manager')
  LOOP
    v_participants := array_append(v_participants, v_staff.user_id);
    v_names := v_names || jsonb_build_object(v_staff.user_id::text,
                            COALESCE(v_staff.name, 'Team member'));
    v_unread := v_unread || jsonb_build_object(v_staff.user_id::text, 0);
  END LOOP;

  IF v_project.project_manager_id IS NOT NULL
     AND NOT (v_project.project_manager_id = ANY(v_participants)) THEN
    v_participants := array_append(v_participants, v_project.project_manager_id);
    v_names := v_names || jsonb_build_object(
      v_project.project_manager_id::text,
      COALESCE((SELECT COALESCE(display_name, email) FROM public.users
                  WHERE id = v_project.project_manager_id), 'Project Manager'));
    v_unread := v_unread || jsonb_build_object(
      v_project.project_manager_id::text, 0);
  END IF;

  IF NOT v_preview AND NOT (v_caller_id = ANY(v_participants)) THEN
    v_participants := array_append(v_participants, v_caller_id);
    v_unread := v_unread || jsonb_build_object(v_caller_id::text, 0);
    v_names := v_names || jsonb_build_object(
      v_caller_id::text,
      COALESCE(
        (SELECT cc.name FROM public.customer_contacts cc
          WHERE cc.customer_id = v_project.client_id
            AND cc.is_active = TRUE
            AND cc.restricted_property_id IS NULL
            AND lower(cc.email) = lower(coalesce(auth.email(), ''))
          LIMIT 1),
        'Customer'));
  END IF;

  IF array_length(v_participants, 1) IS NULL THEN
    -- Fall back to a workspace owner.
    SELECT user_id INTO v_caller_id FROM public.workspace_members
     WHERE workspace_id = v_project.workspace_id LIMIT 1;
    IF v_caller_id IS NOT NULL THEN
      v_participants := ARRAY[v_caller_id]::UUID[];
      v_unread := v_unread || jsonb_build_object(v_caller_id::text, 0);
    END IF;
  END IF;

  v_subject := COALESCE(v_project.name, 'Project') || ' — Customer thread';

  BEGIN
    INSERT INTO public.conversations (
      workspace_id, participant_ids, participant_names, subject,
      type, scope, scope_reference_id, scope_reference_name,
      unread_counts, portal_visible
    ) VALUES (
      v_project.workspace_id, v_participants, v_names, v_subject,
      'group', 'project', p_project_id, v_project.name,
      v_unread, TRUE
    )
    RETURNING * INTO v_conv;
  EXCEPTION
    WHEN unique_violation THEN
      -- Lost the race; fetch the thread the other caller just created.
      SELECT * INTO v_conv FROM public.conversations
       WHERE scope = 'project'
         AND scope_reference_id = p_project_id
         AND portal_visible = TRUE
       ORDER BY created_at ASC
       LIMIT 1;
      IF NOT v_preview AND NOT (v_caller_id = ANY(v_conv.participant_ids)) THEN
        UPDATE public.conversations
           SET participant_ids = array_append(participant_ids, v_caller_id),
               unread_counts = COALESCE(unread_counts, '{}'::jsonb)
                                || jsonb_build_object(v_caller_id::text, 0)
         WHERE id = v_conv.id
         RETURNING * INTO v_conv;
      END IF;
  END;

  RETURN v_conv;
END;
$function$;

CREATE OR REPLACE FUNCTION public.portal_get_or_create_sign_link(p_document_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  normalized_email TEXT := LOWER(TRIM(COALESCE(auth.jwt() ->> 'email', '')));
  doc_row RECORD;
  existing_link RECORD;
  new_token TEXT;
  new_expires TIMESTAMPTZ;
  link_id UUID;
BEGIN
  IF normalized_email = '' THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  -- Verify portal access
  SELECT gd.id, gd.workspace_id, gd.status::TEXT AS status
  INTO doc_row
  FROM generated_documents gd
  JOIN projects p ON p.id = gd.project_id
  WHERE gd.id = p_document_id
    AND p.client_id IS NOT NULL
    AND EXISTS (
      SELECT 1
      FROM customer_contacts cc
      WHERE cc.customer_id = p.client_id
        AND cc.is_active = TRUE
        AND cc.restricted_property_id IS NULL
        AND LOWER(TRIM(COALESCE(cc.email, ''))) = normalized_email
    )
  LIMIT 1;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Document not found or access denied';
  END IF;

  IF doc_row.status NOT IN ('sent', 'viewed') THEN
    RAISE EXCEPTION 'Document cannot be signed in its current status (%)', doc_row.status;
  END IF;

  -- Check for existing valid link
  SELECT dsl.id, dsl.token, dsl.expires_at
  INTO existing_link
  FROM document_sign_links dsl
  WHERE dsl.document_id = p_document_id
    AND dsl.recipient_email = normalized_email
    AND dsl.used_at IS NULL
    AND dsl.revoked_at IS NULL
    AND dsl.expires_at > NOW()
  ORDER BY dsl.created_at DESC
  LIMIT 1;

  IF FOUND THEN
    RETURN jsonb_build_object('token', existing_link.token, 'expires_at', existing_link.expires_at);
  END IF;

  -- Create new link
  new_token := encode(gen_random_bytes(32), 'hex');
  new_expires := NOW() + INTERVAL '14 days';
  link_id := gen_random_uuid();

  INSERT INTO document_sign_links (id, workspace_id, document_id, token, recipient_email, expires_at)
  VALUES (link_id, doc_row.workspace_id, p_document_id, new_token, normalized_email, new_expires);

  RETURN jsonb_build_object('token', new_token, 'expires_at', new_expires);
END;
$function$;

CREATE OR REPLACE FUNCTION public.portal_get_project(project_id uuid, p_preview_customer_id uuid DEFAULT NULL::uuid)
 RETURNS TABLE(id uuid, workspace_id uuid, name text, address text, status project_status, client_id uuid, description text, start_date date, target_completion_date date, created_at timestamp with time zone, updated_at timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_email   TEXT    := LOWER(TRIM(COALESCE(auth.jwt() ->> 'email', '')));
  v_preview BOOLEAN := public._portal_preview_authorized(p_preview_customer_id);
BEGIN
  IF project_id IS NULL OR (NOT v_preview AND v_email = '') THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT
    p.id, p.workspace_id, p.name, p.address, p.status, p.client_id,
    p.description, p.start_date, p.target_completion_date,
    p.created_at, p.updated_at
  FROM projects p
  JOIN customers c ON c.id = p.client_id
  WHERE p.id = project_id
    AND p.client_id IS NOT NULL
    AND c.is_active = TRUE
    AND (
      (v_preview AND p.client_id = p_preview_customer_id)
      OR (NOT v_preview AND EXISTS (
        SELECT 1 FROM customer_contacts cc
        WHERE cc.customer_id = p.client_id
          AND cc.is_active = TRUE
          AND cc.restricted_property_id IS NULL
          AND LOWER(TRIM(COALESCE(cc.email, ''))) = v_email
      ))
    )
  LIMIT 1;
END;
$function$;

CREATE OR REPLACE FUNCTION public.portal_get_project_activity(p_project_id uuid, p_limit integer DEFAULT 100, p_preview_customer_id uuid DEFAULT NULL::uuid)
 RETURNS TABLE(occurred_at timestamp with time zone, event_type text, title text, subtitle text, actor_name text, ref_type text, ref_id uuid, amount numeric, details jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_email   TEXT    := LOWER(TRIM(COALESCE(auth.jwt() ->> 'email', '')));
  v_preview BOOLEAN := public._portal_preview_authorized(p_preview_customer_id);
  v_workspace_id   UUID;
  v_client_id      UUID;
  v_limit          INT  := LEAST(GREATEST(COALESCE(p_limit, 100), 1), 500);
BEGIN
  IF p_project_id IS NULL OR (NOT v_preview AND v_email = '') THEN
    RETURN;
  END IF;

  SELECT p.workspace_id, p.client_id
    INTO v_workspace_id, v_client_id
  FROM projects p
  JOIN customers c ON c.id = p.client_id
  WHERE p.id = p_project_id
    AND p.client_id IS NOT NULL
    AND c.is_active = TRUE
    AND (
      (v_preview AND p.client_id = p_preview_customer_id)
      OR (NOT v_preview AND EXISTS (
        SELECT 1 FROM customer_contacts cc
        WHERE cc.customer_id = p.client_id
          AND cc.is_active = TRUE
          AND cc.restricted_property_id IS NULL
          AND LOWER(TRIM(COALESCE(cc.email, ''))) = v_email
      ))
    )
  LIMIT 1;

  IF v_workspace_id IS NULL THEN
    RETURN;
  END IF;

  RETURN QUERY
  WITH
  doc_sent AS (
    SELECT
      d.sent_at AS occurred_at, 'document_sent'::TEXT AS event_type,
      COALESCE(NULLIF(TRIM(d.template_name), ''), 'Document') || ' was sent to you' AS title,
      NULL::TEXT AS subtitle, NULL::TEXT AS actor_name,
      'document'::TEXT AS ref_type, d.id AS ref_id, d.total_amount AS amount,
      jsonb_build_object('status', d.status::TEXT) AS details
    FROM generated_documents d
    WHERE d.project_id = p_project_id AND d.sent_at IS NOT NULL AND d.status::TEXT <> 'draft'
  ),
  doc_signed AS (
    SELECT d.signed_at, 'document_signed'::TEXT,
      COALESCE(NULLIF(TRIM(d.template_name), ''), 'Document') || ' was signed',
      NULL::TEXT,
      COALESCE(NULLIF(TRIM(d.signed_by_name), ''), NULLIF(TRIM(d.signed_by_email), '')),
      'document'::TEXT, d.id, d.total_amount,
      jsonb_build_object('email', d.signed_by_email)
    FROM generated_documents d WHERE d.project_id = p_project_id AND d.signed_at IS NOT NULL
  ),
  doc_approved AS (
    SELECT d.approved_at, 'document_approved'::TEXT,
      COALESCE(NULLIF(TRIM(d.template_name), ''), 'Document') || ' was approved',
      NULL::TEXT, NULL::TEXT, 'document'::TEXT, d.id, d.total_amount, '{}'::JSONB
    FROM generated_documents d WHERE d.project_id = p_project_id AND d.approved_at IS NOT NULL
  ),
  doc_denied AS (
    SELECT d.denied_at, 'document_denied'::TEXT,
      COALESCE(NULLIF(TRIM(d.template_name), ''), 'Document') || ' was denied',
      NULLIF(TRIM(d.denial_reason), ''),
      COALESCE(NULLIF(TRIM(d.denied_by_name), ''), NULLIF(TRIM(d.denied_by_email), '')),
      'document'::TEXT, d.id, d.total_amount,
      jsonb_build_object('reason', d.denial_reason)
    FROM generated_documents d WHERE d.project_id = p_project_id AND d.denied_at IS NOT NULL
  ),
  doc_activity AS (
    SELECT
      log.created_at AS occurred_at,
      ('document_' || log.action)::TEXT AS event_type,
      CASE log.action
        WHEN 'viewed'             THEN COALESCE(NULLIF(TRIM(d.template_name), ''), 'Document') || ' was viewed'
        WHEN 'opened'             THEN COALESCE(NULLIF(TRIM(d.template_name), ''), 'Document') || ' was opened'
        WHEN 'downloaded'         THEN COALESCE(NULLIF(TRIM(d.template_name), ''), 'Document') || ' was downloaded'
        WHEN 'changes_requested'  THEN 'Changes requested on ' || COALESCE(NULLIF(TRIM(d.template_name), ''), 'document')
        WHEN 'payment_completed'  THEN 'Payment received for ' || COALESCE(NULLIF(TRIM(d.template_name), ''), 'document')
        ELSE COALESCE(NULLIF(TRIM(d.template_name), ''), 'Document')
      END AS title,
      CASE WHEN log.action IN ('changes_requested') THEN NULLIF(TRIM(log.details->>'reason'), '') ELSE NULL END AS subtitle,
      COALESCE(NULLIF(TRIM(log.actor_name), ''), NULLIF(TRIM(log.actor_email), '')) AS actor_name,
      'document'::TEXT AS ref_type, d.id AS ref_id, d.total_amount AS amount,
      CASE WHEN log.action = 'changes_requested' AND NULLIF(TRIM(log.details->>'reason'), '') IS NOT NULL
           THEN jsonb_build_object('reason', TRIM(log.details->>'reason'))
           ELSE '{}'::JSONB END AS details
    FROM document_activity_log log
    JOIN generated_documents d ON d.id = log.document_id
    WHERE d.project_id = p_project_id
      AND log.action IN ('viewed','opened','downloaded','changes_requested','payment_completed')
  ),
  inv_sent AS (
    SELECT i.created_at, 'invoice_sent'::TEXT,
      'Invoice ' || i.invoice_number || ' was sent', NULL::TEXT, NULL::TEXT,
      'invoice'::TEXT, i.id, i.total, jsonb_build_object('status', i.status::TEXT)
    FROM invoices i WHERE i.project_id = p_project_id AND i.status::TEXT <> 'draft'
  ),
  inv_paid AS (
    SELECT (i.paid_date::TIMESTAMPTZ), 'invoice_paid'::TEXT,
      'Invoice ' || i.invoice_number || ' was paid', NULL::TEXT, NULL::TEXT,
      'invoice'::TEXT, i.id, i.total, '{}'::JSONB
    FROM invoices i WHERE i.project_id = p_project_id AND i.paid_date IS NOT NULL
  ),
  sel_approved AS (
    SELECT s.approved_at, 'selection_approved'::TEXT,
      'Selection "' || s.name || '" was approved', NULL::TEXT,
      COALESCE(NULLIF(TRIM(s.approved_by_name), ''), NULLIF(TRIM(s.approved_by_email), '')),
      'selection'::TEXT, s.id, s.selected_amount, '{}'::JSONB
    FROM selections s WHERE s.project_id = p_project_id AND s.approved_at IS NOT NULL
  ),
  sel_declined AS (
    SELECT s.declined_at, 'selection_declined'::TEXT,
      'Selection "' || s.name || '" was declined',
      NULLIF(TRIM(s.decline_reason), ''), NULLIF(TRIM(s.declined_by_name), ''),
      'selection'::TEXT, s.id, s.selected_amount,
      jsonb_build_object('reason', s.decline_reason)
    FROM selections s WHERE s.project_id = p_project_id AND s.declined_at IS NOT NULL
  ),
  co_sent AS (
    SELECT co.sent_date, 'change_order_sent'::TEXT,
      'Change order ' || co.change_order_number || ' — ' || co.title,
      NULL::TEXT, NULL::TEXT, 'change_order'::TEXT, co.id, co.total_amount,
      jsonb_build_object('status', co.status::TEXT)
    FROM change_orders co WHERE co.project_id = p_project_id
      AND co.sent_date IS NOT NULL AND co.status::TEXT <> 'draft'
  ),
  co_approved AS (
    SELECT co.approved_date, 'change_order_approved'::TEXT,
      'Change order ' || co.change_order_number || ' was approved',
      NULL::TEXT, NULL::TEXT, 'change_order'::TEXT, co.id, co.total_amount, '{}'::JSONB
    FROM change_orders co WHERE co.project_id = p_project_id AND co.approved_date IS NOT NULL
  ),
  unioned AS (
    SELECT * FROM doc_sent
    UNION ALL SELECT * FROM doc_signed
    UNION ALL SELECT * FROM doc_approved
    UNION ALL SELECT * FROM doc_denied
    UNION ALL SELECT * FROM doc_activity
    UNION ALL SELECT * FROM inv_sent
    UNION ALL SELECT * FROM inv_paid
    UNION ALL SELECT * FROM sel_approved
    UNION ALL SELECT * FROM sel_declined
    UNION ALL SELECT * FROM co_sent
    UNION ALL SELECT * FROM co_approved
  )
  SELECT u.occurred_at, u.event_type, u.title, u.subtitle, u.actor_name,
         u.ref_type, u.ref_id, u.amount, u.details
  FROM unioned u
  WHERE u.occurred_at IS NOT NULL
  ORDER BY u.occurred_at DESC
  LIMIT v_limit;
END;
$function$;

CREATE OR REPLACE FUNCTION public.portal_get_project_documents(p_project_id uuid, p_preview_customer_id uuid DEFAULT NULL::uuid)
 RETURNS TABLE(id uuid, project_id uuid, workspace_id uuid, customer_id uuid, template_name text, document_number text, document_type text, status text, total_amount numeric, due_date timestamp with time zone, paid_date timestamp with time zone, metadata jsonb, denied_at timestamp with time zone, denied_by_name text, denial_reason text, signed_by_name text, signed_at timestamp with time zone, created_by uuid, created_at timestamp with time zone, updated_at timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_email   TEXT    := LOWER(TRIM(COALESCE(auth.jwt() ->> 'email', '')));
  v_preview BOOLEAN := public._portal_preview_authorized(p_preview_customer_id);
BEGIN
  IF p_project_id IS NULL OR (NOT v_preview AND v_email = '') THEN RETURN; END IF;

  RETURN QUERY
  SELECT
    d.id, d.project_id, d.workspace_id, d.customer_id,
    d.template_name, d.document_number, d.document_type::TEXT, d.status::TEXT,
    d.total_amount, d.due_date, d.paid_date, d.metadata,
    d.denied_at, d.denied_by_name, d.denial_reason,
    d.signed_by_name, d.signed_at,
    d.created_by, d.created_at, d.updated_at
  FROM public.generated_documents d
  JOIN public.projects p ON p.id = d.project_id
  WHERE d.project_id = p_project_id
    AND d.document_type IN (
      'quotation','change_order','work_auth','work_auth_emergency',
      'work_auth_restoration','work_auth_services','selections',
      'service_agreement','invoice','progress_invoice','credit','deposit',
      'refund','work_order','work_order_emergency','work_order_maintenance'
    )
    AND d.status NOT IN ('pending', 'draft')
    AND p.client_id IS NOT NULL
    AND (
      (v_preview AND p.client_id = p_preview_customer_id)
      OR (NOT v_preview AND EXISTS (
        SELECT 1 FROM public.customer_contacts cc
        WHERE cc.customer_id = p.client_id
          AND cc.is_active = TRUE
          AND cc.restricted_property_id IS NULL
          AND LOWER(TRIM(COALESCE(cc.email, ''))) = v_email
      ))
    )
  ORDER BY d.created_at DESC;
END;
$function$;

CREATE OR REPLACE FUNCTION public.portal_get_project_selections(p_project_id uuid)
 RETURNS TABLE(id uuid, project_id uuid, name text, description text, category text, location text, status text, allowance_amount numeric, selected_amount numeric, selected_option_id uuid, due_date date, client_notes text, approved_at timestamp with time zone, approved_signature_url text, reference_url text, attachment_urls text[], options jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  normalized_email TEXT := LOWER(TRIM(COALESCE(auth.jwt() ->> 'email', '')));
  v_allowed BOOLEAN;
BEGIN
  IF normalized_email = '' THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM projects p
    JOIN customer_contacts cc ON cc.customer_id = p.client_id
    WHERE p.id = p_project_id
      AND cc.is_active = TRUE
      AND cc.restricted_property_id IS NULL
      AND LOWER(TRIM(COALESCE(cc.email, ''))) = normalized_email
  ) INTO v_allowed;

  IF NOT v_allowed THEN
    RAISE EXCEPTION 'Project not found or access denied';
  END IF;

  RETURN QUERY
  SELECT
    s.id, s.project_id, s.name, s.description, s.category, s.location,
    s.status, s.allowance_amount, s.selected_amount, s.selected_option_id,
    s.due_date, s.client_notes, s.approved_at, s.approved_signature_url,
    s.reference_url, s.attachment_urls,
    COALESCE(
      (
        SELECT jsonb_agg(
          jsonb_build_object(
            'id', o.id,
            'name', o.name,
            'description', o.description,
            'vendor', o.vendor,
            'sku', o.sku,
            'unit_cost', o.unit_cost,
            'quantity', o.quantity,
            'image_url', o.image_url,
            'image_urls', o.image_urls,
            'external_url', o.external_url,
            'sort_order', o.sort_order
          )
          ORDER BY o.sort_order, o.created_at
        )
        FROM selection_options o
        WHERE o.selection_id = s.id
      ),
      '[]'::jsonb
    )
  FROM selections s
  WHERE s.project_id = p_project_id
    AND s.status IN ('awaiting_client', 'approved', 'declined')
  ORDER BY
    CASE s.status WHEN 'awaiting_client' THEN 0
                  WHEN 'approved'        THEN 1
                  ELSE 2 END,
    s.due_date NULLS LAST,
    s.created_at;
END;
$function$;

CREATE OR REPLACE FUNCTION public.portal_get_project_selections(p_project_id uuid, p_preview_customer_id uuid DEFAULT NULL::uuid)
 RETURNS TABLE(id uuid, project_id uuid, name text, description text, category text, location text, status text, allowance_amount numeric, selected_amount numeric, selected_option_id uuid, due_date date, client_notes text, approved_at timestamp with time zone, approved_signature_url text, reference_url text, attachment_urls text[], options jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_email   TEXT    := LOWER(TRIM(COALESCE(auth.jwt() ->> 'email', '')));
  v_preview BOOLEAN := public._portal_preview_authorized(p_preview_customer_id);
  v_allowed BOOLEAN;
BEGIN
  IF NOT v_preview AND v_email = '' THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM projects p
    WHERE p.id = p_project_id
      AND p.client_id IS NOT NULL
      AND (
        (v_preview AND p.client_id = p_preview_customer_id)
        OR (NOT v_preview AND EXISTS (
          SELECT 1 FROM customer_contacts cc
          WHERE cc.customer_id = p.client_id
            AND cc.is_active = TRUE
            AND cc.restricted_property_id IS NULL
            AND LOWER(TRIM(COALESCE(cc.email, ''))) = v_email))
      )
  ) INTO v_allowed;

  IF NOT v_allowed THEN
    RAISE EXCEPTION 'Project not found or access denied';
  END IF;

  RETURN QUERY
  SELECT
    s.id, s.project_id, s.name, s.description, s.category, s.location,
    s.status, s.allowance_amount, s.selected_amount, s.selected_option_id,
    s.due_date, s.client_notes, s.approved_at, s.approved_signature_url,
    s.reference_url, s.attachment_urls,
    COALESCE(
      (SELECT jsonb_agg(jsonb_build_object(
            'id', o.id, 'name', o.name, 'description', o.description,
            'vendor', o.vendor, 'sku', o.sku, 'unit_cost', o.unit_cost,
            'quantity', o.quantity, 'image_url', o.image_url, 'image_urls', o.image_urls,
            'external_url', o.external_url, 'sort_order', o.sort_order,
            'is_client_suggested', o.is_client_suggested)
          ORDER BY o.sort_order, o.created_at)
        FROM selection_options o WHERE o.selection_id = s.id),
      '[]'::jsonb)
  FROM selections s
  WHERE s.project_id = p_project_id
    AND s.status IN ('awaiting_client', 'approved', 'declined')
  ORDER BY CASE s.status WHEN 'awaiting_client' THEN 0 WHEN 'approved' THEN 1 ELSE 2 END,
    s.due_date NULLS LAST, s.created_at;
END;
$function$;

CREATE OR REPLACE FUNCTION public.portal_get_projects(p_preview_customer_id uuid DEFAULT NULL::uuid)
 RETURNS TABLE(id uuid, workspace_id uuid, name text, address text, status project_status, client_id uuid, description text, start_date date, target_completion_date date, created_at timestamp with time zone, updated_at timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_email     TEXT    := LOWER(TRIM(COALESCE(auth.jwt() ->> 'email', '')));
  v_preview   BOOLEAN := public._portal_preview_authorized(p_preview_customer_id);
BEGIN
  IF NOT v_preview AND v_email = '' THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT
    p.id, p.workspace_id, p.name, p.address, p.status, p.client_id,
    p.description, p.start_date, p.target_completion_date,
    p.created_at, p.updated_at
  FROM projects p
  JOIN customers c ON c.id = p.client_id
  WHERE p.client_id IS NOT NULL
    AND c.is_active = TRUE
    AND (
      (v_preview AND p.client_id = p_preview_customer_id)
      OR (NOT v_preview AND EXISTS (
        SELECT 1 FROM customer_contacts cc
        WHERE cc.customer_id = p.client_id
          AND cc.is_active = TRUE
          AND cc.restricted_property_id IS NULL
          AND LOWER(TRIM(COALESCE(cc.email, ''))) = v_email
      ))
    )
  ORDER BY p.updated_at DESC;
END;
$function$;

CREATE OR REPLACE FUNCTION public.portal_list_selection_comments(p_selection_id uuid)
 RETURNS TABLE(id uuid, body text, author_name text, is_from_client boolean, created_at timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  normalized_email TEXT := LOWER(TRIM(COALESCE(auth.jwt() ->> 'email', '')));
  v_allowed BOOLEAN;
BEGIN
  IF normalized_email = '' THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;
  SELECT EXISTS (
    SELECT 1 FROM selections s
    JOIN projects p ON p.id = s.project_id
    JOIN customer_contacts cc ON cc.customer_id = p.client_id
    WHERE s.id = p_selection_id
      AND cc.is_active = TRUE
      AND cc.restricted_property_id IS NULL
      AND LOWER(TRIM(COALESCE(cc.email, ''))) = normalized_email
  ) INTO v_allowed;
  IF NOT v_allowed THEN
    RAISE EXCEPTION 'Selection not found or access denied';
  END IF;

  RETURN QUERY
    SELECT c.id, c.body, c.author_name, c.is_from_client, c.created_at
      FROM selection_comments c
     WHERE c.selection_id = p_selection_id
     ORDER BY c.created_at;
END;
$function$;

CREATE OR REPLACE FUNCTION public.portal_request_document_changes(p_document_id uuid, p_reason text DEFAULT NULL::text, p_actor_name text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  normalized_email TEXT := LOWER(TRIM(COALESCE(auth.jwt() ->> 'email', '')));
  doc_row RECORD;
  now_ts TIMESTAMPTZ := NOW();
BEGIN
  IF normalized_email = '' THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  SELECT gd.id, gd.workspace_id, gd.project_id, gd.status::TEXT AS status
  INTO doc_row
  FROM generated_documents gd
  JOIN projects p ON p.id = gd.project_id
  WHERE gd.id = p_document_id
    AND p.client_id IS NOT NULL
    AND EXISTS (
      SELECT 1
      FROM customer_contacts cc
      WHERE cc.customer_id = p.client_id
        AND cc.is_active = TRUE
        AND cc.restricted_property_id IS NULL
        AND LOWER(TRIM(COALESCE(cc.email, ''))) = normalized_email
    )
  LIMIT 1;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Document not found or access denied';
  END IF;

  IF doc_row.status NOT IN ('sent', 'viewed') THEN
    RAISE EXCEPTION 'Cannot request changes for document in status (%)', doc_row.status;
  END IF;

  UPDATE generated_documents
  SET status = 'changes_requested',
      denied_by_name = p_actor_name,
      denied_by_email = normalized_email,
      denial_reason = p_reason,
      updated_at = now_ts
  WHERE id = p_document_id;

  INSERT INTO document_activity_log (workspace_id, document_id, action, actor_email, actor_name, actor_type, details)
  VALUES (doc_row.workspace_id, p_document_id, 'changes_requested', normalized_email, p_actor_name, 'portal_user',
    jsonb_build_object('reason', COALESCE(p_reason, '')));

  PERFORM create_document_action_notifications(p_document_id, 'changes_requested', p_actor_name, normalized_email, p_reason);

  RETURN jsonb_build_object('success', true);
END;
$function$;

CREATE OR REPLACE FUNCTION public.portal_set_selection_signature(p_selection_id uuid, p_signature_url text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  normalized_email TEXT := LOWER(TRIM(COALESCE(auth.jwt() ->> 'email', '')));
  v_allowed BOOLEAN;
BEGIN
  IF normalized_email = '' THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  SELECT EXISTS (
    SELECT 1
    FROM selections s
    JOIN projects p ON p.id = s.project_id
    JOIN customer_contacts cc ON cc.customer_id = p.client_id
    WHERE s.id = p_selection_id
      AND cc.is_active = TRUE
      AND cc.restricted_property_id IS NULL
      AND LOWER(TRIM(COALESCE(cc.email, ''))) = normalized_email
  ) INTO v_allowed;

  IF NOT v_allowed THEN
    RAISE EXCEPTION 'Selection not found or access denied';
  END IF;

  UPDATE selections
     SET approved_signature_url = p_signature_url,
         updated_at = now()
   WHERE id = p_selection_id;

  RETURN jsonb_build_object('success', true);
END;
$function$;

CREATE OR REPLACE FUNCTION public.portal_suggest_selection_option(p_selection_id uuid, p_name text, p_note text DEFAULT NULL::text, p_unit_cost numeric DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  normalized_email TEXT := LOWER(TRIM(COALESCE(auth.jwt() ->> 'email', '')));
  v_workspace UUID;
  v_sort INT;
BEGIN
  IF normalized_email = '' THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;
  IF COALESCE(TRIM(p_name), '') = '' THEN
    RAISE EXCEPTION 'Name required';
  END IF;

  SELECT s.workspace_id INTO v_workspace
    FROM selections s
    JOIN projects p ON p.id = s.project_id
    JOIN customer_contacts cc ON cc.customer_id = p.client_id
   WHERE s.id = p_selection_id
     AND cc.is_active = TRUE
     AND cc.restricted_property_id IS NULL
     AND LOWER(TRIM(COALESCE(cc.email, ''))) = normalized_email
   LIMIT 1;
  IF v_workspace IS NULL THEN
    RAISE EXCEPTION 'Selection not found or access denied';
  END IF;

  SELECT COALESCE(MAX(sort_order) + 1, 0) INTO v_sort
    FROM selection_options WHERE selection_id = p_selection_id;

  INSERT INTO selection_options
    (selection_id, workspace_id, name, description, unit_cost, quantity,
     sort_order, is_client_suggested)
  VALUES
    (p_selection_id, v_workspace, TRIM(p_name),
     NULLIF(TRIM(COALESCE(p_note,'')),''), COALESCE(p_unit_cost, 0), 1, v_sort, TRUE);

  RETURN jsonb_build_object('success', true);
END;
$function$;
