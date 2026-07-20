-- Secure RPCs for client portal project and invoice access.
-- These functions use JWT email claims to authorize access via customer_contacts.

CREATE INDEX IF NOT EXISTS idx_customer_contacts_email_lower
  ON customer_contacts (LOWER(email))
  WHERE email IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_customer_contacts_customer_active
  ON customer_contacts(customer_id, is_active);

CREATE OR REPLACE FUNCTION public.portal_can_request_access(portal_email TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  normalized_email TEXT := LOWER(TRIM(COALESCE(portal_email, '')));
BEGIN
  IF normalized_email = '' THEN
    RETURN FALSE;
  END IF;

  RETURN EXISTS (
    SELECT 1
    FROM customer_contacts cc
    JOIN customers c ON c.id = cc.customer_id
    WHERE cc.is_active = TRUE
      AND c.is_active = TRUE
      AND LOWER(TRIM(COALESCE(cc.email, ''))) = normalized_email
  );
END;
$$;

REVOKE ALL ON FUNCTION public.portal_can_request_access(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.portal_can_request_access(TEXT) TO anon, authenticated;

CREATE OR REPLACE FUNCTION public.portal_get_projects()
RETURNS TABLE (
  id UUID,
  workspace_id UUID,
  name TEXT,
  address TEXT,
  status project_status,
  client_id UUID,
  description TEXT,
  start_date DATE,
  target_completion_date DATE,
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
  IF normalized_email = '' THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT
    p.id,
    p.workspace_id,
    p.name,
    p.address,
    p.status,
    p.client_id,
    p.description,
    p.start_date,
    p.target_completion_date,
    p.created_at,
    p.updated_at
  FROM projects p
  WHERE p.client_id IS NOT NULL
    AND EXISTS (
      SELECT 1
      FROM customer_contacts cc
      WHERE cc.customer_id = p.client_id
        AND cc.is_active = TRUE
        AND LOWER(TRIM(COALESCE(cc.email, ''))) = normalized_email
    )
  ORDER BY p.updated_at DESC;
END;
$$;

REVOKE ALL ON FUNCTION public.portal_get_projects() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.portal_get_projects() TO authenticated;

CREATE OR REPLACE FUNCTION public.portal_get_project(project_id UUID)
RETURNS TABLE (
  id UUID,
  workspace_id UUID,
  name TEXT,
  address TEXT,
  status project_status,
  client_id UUID,
  description TEXT,
  start_date DATE,
  target_completion_date DATE,
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
  IF normalized_email = '' OR project_id IS NULL THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT
    p.id,
    p.workspace_id,
    p.name,
    p.address,
    p.status,
    p.client_id,
    p.description,
    p.start_date,
    p.target_completion_date,
    p.created_at,
    p.updated_at
  FROM projects p
  WHERE p.id = project_id
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

REVOKE ALL ON FUNCTION public.portal_get_project(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.portal_get_project(UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.portal_get_invoices(p_project_id UUID DEFAULT NULL)
RETURNS TABLE (
  id UUID,
  project_id UUID,
  workspace_id UUID,
  client_id UUID,
  invoice_number TEXT,
  type invoice_type,
  status invoice_status,
  line_items JSONB,
  subtotal DECIMAL,
  tax_percent DECIMAL,
  tax_amount DECIMAL,
  total DECIMAL,
  retainage_percent DECIMAL,
  retainage_amount DECIMAL,
  retainage_released BOOLEAN,
  retainage_released_date DATE,
  stripe_payment_link_url TEXT,
  due_date DATE,
  paid_date DATE,
  notes TEXT,
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
    i.id,
    i.project_id,
    i.workspace_id,
    i.client_id,
    i.invoice_number,
    i.type,
    i.status,
    i.line_items,
    i.subtotal,
    i.tax_percent,
    i.tax_amount,
    i.total,
    i.retainage_percent,
    i.retainage_amount,
    i.retainage_released,
    i.retainage_released_date,
    i.stripe_payment_link_url,
    i.due_date,
    i.paid_date,
    i.notes,
    i.created_by,
    i.created_at,
    i.updated_at,
    p.name AS project_name
  FROM invoices i
  JOIN projects p ON p.id = i.project_id
  WHERE ($1 IS NULL OR i.project_id = $1)
    AND p.client_id IS NOT NULL
    AND EXISTS (
      SELECT 1
      FROM customer_contacts cc
      WHERE cc.customer_id = p.client_id
        AND cc.is_active = TRUE
        AND LOWER(TRIM(COALESCE(cc.email, ''))) = normalized_email
    )
  ORDER BY COALESCE(i.due_date, i.created_at::date) DESC, i.created_at DESC;
END;
$$;

REVOKE ALL ON FUNCTION public.portal_get_invoices(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.portal_get_invoices(UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.portal_get_invoice(invoice_id UUID)
RETURNS TABLE (
  id UUID,
  project_id UUID,
  workspace_id UUID,
  client_id UUID,
  invoice_number TEXT,
  type invoice_type,
  status invoice_status,
  line_items JSONB,
  subtotal DECIMAL,
  tax_percent DECIMAL,
  tax_amount DECIMAL,
  total DECIMAL,
  retainage_percent DECIMAL,
  retainage_amount DECIMAL,
  retainage_released BOOLEAN,
  retainage_released_date DATE,
  stripe_payment_link_url TEXT,
  due_date DATE,
  paid_date DATE,
  notes TEXT,
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
    i.id,
    i.project_id,
    i.workspace_id,
    i.client_id,
    i.invoice_number,
    i.type,
    i.status,
    i.line_items,
    i.subtotal,
    i.tax_percent,
    i.tax_amount,
    i.total,
    i.retainage_percent,
    i.retainage_amount,
    i.retainage_released,
    i.retainage_released_date,
    i.stripe_payment_link_url,
    i.due_date,
    i.paid_date,
    i.notes,
    i.created_by,
    i.created_at,
    i.updated_at,
    p.name AS project_name
  FROM invoices i
  JOIN projects p ON p.id = i.project_id
  WHERE i.id = invoice_id
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
