-- Migrate portal invoice RPC functions from `invoices` table to `generated_documents`.
-- The invoices are now stored as generated_documents with document_type = 'invoice'.
-- Invoice-specific fields (retainage, stripe URL, etc.) live in the `metadata` JSONB column.

-- Drop old function signatures that reference invoice_type/invoice_status enums
DROP FUNCTION IF EXISTS public.portal_get_invoices(UUID);
DROP FUNCTION IF EXISTS public.portal_get_invoice(UUID);

CREATE OR REPLACE FUNCTION public.portal_get_invoices(p_project_id UUID DEFAULT NULL)
RETURNS TABLE (
  id UUID,
  project_id UUID,
  workspace_id UUID,
  customer_id UUID,
  document_number TEXT,
  document_type TEXT,
  status TEXT,
  line_items JSONB,
  total_amount DECIMAL,
  collect_tax BOOLEAN,
  tax_name TEXT,
  tax_rate DECIMAL,
  due_date DATE,
  paid_date DATE,
  metadata JSONB,
  rendered_content TEXT,
  created_by UUID,
  created_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ,
  project_name TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  normalized_email TEXT := LOWER(TRIM(COALESCE(auth.jwt() ->> 'email', '')));
BEGIN
  IF normalized_email = '' THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT
    d.id,
    d.project_id,
    d.workspace_id,
    d.customer_id,
    d.document_number,
    d.document_type::TEXT,
    d.status::TEXT,
    d.line_items,
    d.total_amount,
    d.collect_tax,
    d.tax_name,
    d.tax_rate,
    d.due_date,
    d.paid_date,
    d.metadata,
    d.rendered_content,
    d.created_by,
    d.created_at,
    d.updated_at,
    p.name AS project_name
  FROM generated_documents d
  JOIN projects p ON p.id = d.project_id
  WHERE d.document_type = 'invoice'
    AND ($1 IS NULL OR d.project_id = $1)
    AND p.client_id IS NOT NULL
    AND EXISTS (
      SELECT 1
      FROM customer_contacts cc
      WHERE cc.customer_id = p.client_id
        AND cc.is_active = TRUE
        AND LOWER(TRIM(COALESCE(cc.email, ''))) = normalized_email
    )
  ORDER BY COALESCE(d.due_date, d.created_at::date) DESC, d.created_at DESC;
END;
$$;

REVOKE ALL ON FUNCTION public.portal_get_invoices(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.portal_get_invoices(UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.portal_get_invoice(invoice_id UUID)
RETURNS TABLE (
  id UUID,
  project_id UUID,
  workspace_id UUID,
  customer_id UUID,
  document_number TEXT,
  document_type TEXT,
  status TEXT,
  line_items JSONB,
  total_amount DECIMAL,
  collect_tax BOOLEAN,
  tax_name TEXT,
  tax_rate DECIMAL,
  due_date DATE,
  paid_date DATE,
  metadata JSONB,
  rendered_content TEXT,
  created_by UUID,
  created_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ,
  project_name TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  normalized_email TEXT := LOWER(TRIM(COALESCE(auth.jwt() ->> 'email', '')));
BEGIN
  IF normalized_email = '' OR invoice_id IS NULL THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT
    d.id,
    d.project_id,
    d.workspace_id,
    d.customer_id,
    d.document_number,
    d.document_type::TEXT,
    d.status::TEXT,
    d.line_items,
    d.total_amount,
    d.collect_tax,
    d.tax_name,
    d.tax_rate,
    d.due_date,
    d.paid_date,
    d.metadata,
    d.rendered_content,
    d.created_by,
    d.created_at,
    d.updated_at,
    p.name AS project_name
  FROM generated_documents d
  JOIN projects p ON p.id = d.project_id
  WHERE d.id = invoice_id
    AND d.document_type = 'invoice'
    AND p.client_id IS NOT NULL
    AND EXISTS (
      SELECT 1
      FROM customer_contacts cc
      WHERE cc.customer_id = p.client_id
        AND cc.is_active = TRUE
        AND LOWER(TRIM(COALESCE(cc.email, ''))) = normalized_email
    )
  LIMIT 1;
END;
$$;

REVOKE ALL ON FUNCTION public.portal_get_invoice(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.portal_get_invoice(UUID) TO authenticated;
