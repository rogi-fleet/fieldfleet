-- ===========================================================================
-- F012: server-side payment recording for Stripe portal payments.
--
-- record_document_payment() records a (partial) payment on a
-- generated_documents row in one transaction:
--
--   1. advances amount_paid (capped at the outstanding balance — a stale
--      full-amount Stripe link must not over-pay; the cap is reported
--      back so the caller can flag the overpayment),
--   2. stamps paid_date + payment metadata only when the balance hits 0,
--   3. is idempotent per p_external_ref (Stripe retries webhooks): processed
--      refs accumulate in metadata->'paymentExternalRefs'.
--
-- SECURITY DEFINER, granted to service_role only — staff payments keep going
-- through the Dart service; this exists for trusted server-side callers.
--
-- Also recreates portal_get_invoices / portal_get_invoice to expose
-- amount_paid so the customer portal can show paid-to-date and balance due
-- (RETURNS TABLE signatures can't be altered in place, hence DROP+CREATE).
-- ===========================================================================

CREATE OR REPLACE FUNCTION public.record_document_payment(
  p_document_id uuid,
  p_amount      numeric DEFAULT NULL,  -- NULL = pay the outstanding balance
  p_method      text    DEFAULT 'stripe',
  p_reference   text    DEFAULT NULL,
  p_external_ref text   DEFAULT NULL,
  p_entry_date  date    DEFAULT CURRENT_DATE
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_doc          generated_documents%ROWTYPE;
  v_is_invoice   boolean;
  v_is_bill      boolean;
  v_balance      numeric;
  v_amount       numeric;
  v_new_paid     numeric;
  v_fully_paid   boolean;
  v_refs         jsonb;
  v_metadata     jsonb;
BEGIN
  SELECT * INTO v_doc
  FROM generated_documents
  WHERE id = p_document_id
  FOR UPDATE;

  IF v_doc.id IS NULL THEN
    RAISE EXCEPTION 'Document % not found', p_document_id;
  END IF;

  v_metadata := COALESCE(v_doc.metadata, '{}'::jsonb);
  v_refs := COALESCE(v_metadata->'paymentExternalRefs', '[]'::jsonb);
  IF p_external_ref IS NOT NULL AND v_refs ? p_external_ref THEN
    RETURN jsonb_build_object('skipped', true, 'reason', 'duplicate_external_ref');
  END IF;

  v_is_invoice := v_doc.document_type::text IN
    ('invoice', 'progress_invoice', 'aia_pay_app', 'deposit');
  v_is_bill := v_doc.document_type::text = 'bill';
  IF NOT v_is_invoice AND NOT v_is_bill THEN
    RAISE EXCEPTION 'Only invoices and bills accept payments (got %)',
      v_doc.document_type;
  END IF;
  IF COALESCE(v_doc.total_amount, 0) <= 0 THEN
    RAISE EXCEPTION 'Document total must be greater than zero';
  END IF;

  v_balance := v_doc.total_amount - COALESCE(v_doc.amount_paid, 0);
  v_amount := LEAST(COALESCE(p_amount, v_balance), v_balance);
  IF v_amount <= 0 THEN
    RETURN jsonb_build_object('skipped', true, 'reason', 'no_outstanding_balance');
  END IF;

  v_new_paid := COALESCE(v_doc.amount_paid, 0) + v_amount;
  v_fully_paid := v_new_paid >= v_doc.total_amount - 0.005;

  IF p_external_ref IS NOT NULL THEN
    v_metadata := jsonb_set(
      v_metadata, '{paymentExternalRefs}', v_refs || to_jsonb(p_external_ref));
  END IF;

  UPDATE generated_documents SET
    amount_paid = v_new_paid,
    paid_date = CASE WHEN v_fully_paid THEN p_entry_date::timestamptz
                     ELSE paid_date END,
    payment_method = COALESCE(p_method, payment_method),
    payment_reference = COALESCE(p_reference, payment_reference),
    metadata = v_metadata,
    updated_at = now()
  WHERE id = v_doc.id;

  RETURN jsonb_build_object(
    'recorded_amount', v_amount,
    'requested_amount', COALESCE(p_amount, v_balance),
    'overpayment', GREATEST(COALESCE(p_amount, v_balance) - v_amount, 0),
    'new_amount_paid', v_new_paid,
    'fully_paid', v_fully_paid
  );
END;
$$;

REVOKE ALL ON FUNCTION public.record_document_payment(uuid, numeric, text, text, text, date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.record_document_payment(uuid, numeric, text, text, text, date) TO service_role;

-- ---------------------------------------------------------------------------
-- Portal invoice RPCs: expose amount_paid for paid-to-date / balance display
-- ---------------------------------------------------------------------------

DROP FUNCTION IF EXISTS public.portal_get_invoices(UUID, UUID);
CREATE FUNCTION public.portal_get_invoices(
  p_project_id UUID DEFAULT NULL,
  p_preview_customer_id UUID DEFAULT NULL
)
RETURNS TABLE(
  id uuid, project_id uuid, workspace_id uuid, customer_id uuid,
  document_number text, document_type text, status text, line_items jsonb,
  total_amount numeric, amount_paid numeric, collect_tax boolean,
  tax_name text, tax_rate numeric,
  due_date timestamp with time zone, paid_date timestamp with time zone,
  metadata jsonb, rendered_content text, created_by uuid,
  created_at timestamp with time zone, updated_at timestamp with time zone,
  project_name text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_email   TEXT    := LOWER(TRIM(COALESCE(auth.jwt() ->> 'email', '')));
  v_preview BOOLEAN := public._portal_preview_authorized(p_preview_customer_id);
BEGIN
  IF NOT v_preview AND v_email = '' THEN RETURN; END IF;

  RETURN QUERY
  SELECT
    d.id, d.project_id, d.workspace_id, d.customer_id,
    d.document_number, d.document_type::TEXT, d.status::TEXT, d.line_items,
    d.total_amount, d.amount_paid, d.collect_tax, d.tax_name, d.tax_rate,
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
          AND LOWER(TRIM(COALESCE(cc.email, ''))) = v_email
      ))
    )
  ORDER BY COALESCE(d.due_date, d.created_at) DESC, d.created_at DESC;
END;
$$;

REVOKE ALL ON FUNCTION public.portal_get_invoices(UUID, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.portal_get_invoices(UUID, UUID) TO authenticated;

DROP FUNCTION IF EXISTS public.portal_get_invoice(UUID, UUID);
CREATE FUNCTION public.portal_get_invoice(
  invoice_id UUID,
  p_preview_customer_id UUID DEFAULT NULL
)
RETURNS TABLE(
  id uuid, project_id uuid, workspace_id uuid, customer_id uuid,
  document_number text, document_type text, status text, line_items jsonb,
  total_amount numeric, amount_paid numeric, collect_tax boolean,
  tax_name text, tax_rate numeric,
  due_date timestamp with time zone, paid_date timestamp with time zone,
  metadata jsonb, rendered_content text, created_by uuid,
  created_at timestamp with time zone, updated_at timestamp with time zone,
  project_name text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_email   TEXT    := LOWER(TRIM(COALESCE(auth.jwt() ->> 'email', '')));
  v_preview BOOLEAN := public._portal_preview_authorized(p_preview_customer_id);
BEGIN
  IF invoice_id IS NULL OR (NOT v_preview AND v_email = '') THEN RETURN; END IF;

  RETURN QUERY
  SELECT
    d.id, d.project_id, d.workspace_id, d.customer_id,
    d.document_number, d.document_type::TEXT, d.status::TEXT, d.line_items,
    d.total_amount, d.amount_paid, d.collect_tax, d.tax_name, d.tax_rate,
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
          AND LOWER(TRIM(COALESCE(cc.email, ''))) = v_email
      ))
    )
  LIMIT 1;
END;
$$;

REVOKE ALL ON FUNCTION public.portal_get_invoice(UUID, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.portal_get_invoice(UUID, UUID) TO authenticated;
