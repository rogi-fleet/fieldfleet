-- Repair generated_documents.updated_at and align portal document RPCs
-- with the current document_template_type values.

ALTER TABLE public.generated_documents
ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ;

UPDATE public.generated_documents
SET updated_at = COALESCE(updated_at, created_at, now())
WHERE updated_at IS NULL;

ALTER TABLE public.generated_documents
ALTER COLUMN updated_at SET DEFAULT now();

ALTER TABLE public.generated_documents
ALTER COLUMN updated_at SET NOT NULL;

DROP TRIGGER IF EXISTS update_generated_documents_updated_at ON public.generated_documents;

CREATE TRIGGER update_generated_documents_updated_at
BEFORE UPDATE ON public.generated_documents
FOR EACH ROW
EXECUTE FUNCTION public.update_updated_at_column();

CREATE OR REPLACE FUNCTION public.portal_get_document(p_document_id UUID)
RETURNS TABLE (
  id UUID,
  project_id UUID,
  workspace_id UUID,
  customer_id UUID,
  template_name TEXT,
  document_number TEXT,
  document_type TEXT,
  status TEXT,
  rendered_content TEXT,
  line_items JSONB,
  line_item_visibility TEXT,
  total_amount DECIMAL,
  collect_tax BOOLEAN,
  tax_name TEXT,
  tax_rate DECIMAL,
  due_date DATE,
  paid_date DATE,
  metadata JSONB,
  prepared_by JSONB,
  prepared_for JSONB,
  footer_content TEXT,
  signed_by_name TEXT,
  signed_by_email TEXT,
  signed_at TIMESTAMPTZ,
  signature_url TEXT,
  denied_at TIMESTAMPTZ,
  denied_by_name TEXT,
  denied_by_email TEXT,
  denial_reason TEXT,
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
  IF normalized_email = '' OR p_document_id IS NULL THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT
    d.id,
    d.project_id,
    d.workspace_id,
    d.customer_id,
    d.template_name,
    d.document_number,
    d.document_type::TEXT,
    d.status::TEXT,
    d.rendered_content,
    d.line_items,
    d.line_item_visibility::TEXT,
    d.total_amount,
    d.collect_tax,
    d.tax_name,
    d.tax_rate,
    d.due_date,
    d.paid_date,
    d.metadata,
    d.prepared_by,
    d.prepared_for,
    d.footer_content,
    d.signed_by_name,
    d.signed_by_email,
    d.signed_at,
    d.signature_url,
    d.denied_at,
    d.denied_by_name,
    d.denied_by_email,
    d.denial_reason,
    d.created_by,
    d.created_at,
    d.updated_at,
    p.name AS project_name
  FROM public.generated_documents d
  JOIN public.projects p ON p.id = d.project_id
  WHERE d.id = p_document_id
    AND d.document_type IN (
      'quotation',
      'change_order',
      'work_auth_emergency',
      'work_auth_restoration',
      'work_auth_services',
      'selections',
      'service_agreement',
      'invoice',
      'progress_invoice',
      'credit',
      'deposit',
      'refund',
      'work_order',
      'work_order_emergency',
      'work_order_maintenance'
    )
    AND p.client_id IS NOT NULL
    AND EXISTS (
      SELECT 1
      FROM public.customer_contacts cc
      WHERE cc.customer_id = p.client_id
        AND cc.is_active = TRUE
        AND LOWER(TRIM(COALESCE(cc.email, ''))) = normalized_email
    )
  LIMIT 1;
END;
$$;

CREATE OR REPLACE FUNCTION public.portal_get_project_documents(p_project_id UUID)
RETURNS TABLE (
  id UUID,
  project_id UUID,
  workspace_id UUID,
  customer_id UUID,
  template_name TEXT,
  document_number TEXT,
  document_type TEXT,
  status TEXT,
  total_amount DECIMAL,
  due_date DATE,
  paid_date DATE,
  metadata JSONB,
  denied_at TIMESTAMPTZ,
  denied_by_name TEXT,
  denial_reason TEXT,
  signed_by_name TEXT,
  signed_at TIMESTAMPTZ,
  created_by UUID,
  created_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  normalized_email TEXT := LOWER(TRIM(COALESCE(auth.jwt() ->> 'email', '')));
BEGIN
  IF normalized_email = '' OR p_project_id IS NULL THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT
    d.id,
    d.project_id,
    d.workspace_id,
    d.customer_id,
    d.template_name,
    d.document_number,
    d.document_type::TEXT,
    d.status::TEXT,
    d.total_amount,
    d.due_date,
    d.paid_date,
    d.metadata,
    d.denied_at,
    d.denied_by_name,
    d.denial_reason,
    d.signed_by_name,
    d.signed_at,
    d.created_by,
    d.created_at,
    d.updated_at
  FROM public.generated_documents d
  JOIN public.projects p ON p.id = d.project_id
  WHERE d.project_id = p_project_id
    AND d.document_type IN (
      'quotation',
      'change_order',
      'work_auth_emergency',
      'work_auth_restoration',
      'work_auth_services',
      'selections',
      'service_agreement',
      'invoice',
      'progress_invoice',
      'credit',
      'deposit',
      'refund',
      'work_order',
      'work_order_emergency',
      'work_order_maintenance'
    )
    AND d.status NOT IN ('pending', 'draft')
    AND p.client_id IS NOT NULL
    AND EXISTS (
      SELECT 1
      FROM public.customer_contacts cc
      WHERE cc.customer_id = p.client_id
        AND cc.is_active = TRUE
        AND LOWER(TRIM(COALESCE(cc.email, ''))) = normalized_email
    )
  ORDER BY d.created_at DESC;
END;
$$;
