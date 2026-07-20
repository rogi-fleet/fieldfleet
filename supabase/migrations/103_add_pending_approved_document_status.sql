-- Add 'pending' and 'approved' to the document_status enum
ALTER TYPE document_status ADD VALUE IF NOT EXISTS 'pending';
ALTER TYPE document_status ADD VALUE IF NOT EXISTS 'approved';

-- Add approval tracking columns to generated_documents
ALTER TABLE generated_documents ADD COLUMN IF NOT EXISTS approved_at TIMESTAMPTZ;
ALTER TABLE generated_documents ADD COLUMN IF NOT EXISTS approved_by TEXT;

-- Filter pending/draft documents from client portal view
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
  FROM generated_documents d
  JOIN projects p ON p.id = d.project_id
  WHERE d.project_id = p_project_id
    AND d.document_type IN ('estimate', 'proposal', 'contract', 'change_order', 'invoice', 'credit_memo', 'refund')
    AND d.status NOT IN ('pending', 'draft')
    AND p.client_id IS NOT NULL
    AND EXISTS (
      SELECT 1
      FROM customer_contacts cc
      WHERE cc.customer_id = p.client_id
        AND cc.is_active = TRUE
        AND LOWER(TRIM(COALESCE(cc.email, ''))) = normalized_email
    )
  ORDER BY d.created_at DESC;
END;
$$;
