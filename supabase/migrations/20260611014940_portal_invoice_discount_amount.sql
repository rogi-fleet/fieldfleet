-- Follow-up to record_document_payment_rpc: portal invoice RPCs must also
-- expose discount_amount [M004] so the portal can price through the canonical
-- computedGrandTotal instead of re-deriving subtotal+tax and silently
-- ignoring discounts.

DROP FUNCTION IF EXISTS public.portal_get_invoices(UUID, UUID);
CREATE FUNCTION public.portal_get_invoices(
  p_project_id UUID DEFAULT NULL,
  p_preview_customer_id UUID DEFAULT NULL
)
RETURNS TABLE(
  id uuid, project_id uuid, workspace_id uuid, customer_id uuid,
  document_number text, document_type text, status text, line_items jsonb,
  total_amount numeric, amount_paid numeric, discount_amount numeric,
  collect_tax boolean, tax_name text, tax_rate numeric,
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
  total_amount numeric, amount_paid numeric, discount_amount numeric,
  collect_tax boolean, tax_name text, tax_rate numeric,
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
          AND LOWER(TRIM(COALESCE(cc.email, ''))) = v_email
      ))
    )
  LIMIT 1;
END;
$$;

REVOKE ALL ON FUNCTION public.portal_get_invoice(UUID, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.portal_get_invoice(UUID, UUID) TO authenticated;
