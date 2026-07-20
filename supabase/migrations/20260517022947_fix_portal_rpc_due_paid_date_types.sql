-- =============================================================================
-- Fix portal RPC return-type mismatches on due_date / paid_date.
--
-- generated_documents.due_date and paid_date were promoted from `date` to
-- `timestamp with time zone` in an earlier migration, but the four portal
-- RPCs that surface those columns kept their original `date` declarations
-- in RETURNS TABLE. Postgres raises 42804 ("structure of query does not
-- match function result type") on every call, so the entire customer
-- portal dashboard was throwing the moment a portal user signed in.
--
-- Drops + recreates the four affected RPCs with the correct return types.
-- Body logic is unchanged. Applied via supabase MCP apply_migration.
-- =============================================================================

DROP FUNCTION IF EXISTS public.portal_get_invoices(uuid);
DROP FUNCTION IF EXISTS public.portal_get_invoice(uuid);
DROP FUNCTION IF EXISTS public.portal_get_project_documents(uuid);
DROP FUNCTION IF EXISTS public.portal_get_document(uuid);

CREATE OR REPLACE FUNCTION public.portal_get_invoices(p_project_id uuid DEFAULT NULL::uuid)
RETURNS TABLE(
  id uuid, project_id uuid, workspace_id uuid, customer_id uuid,
  document_number text, document_type text, status text, line_items jsonb,
  total_amount numeric, collect_tax boolean, tax_name text, tax_rate numeric,
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
  normalized_email TEXT := LOWER(TRIM(COALESCE(auth.jwt() ->> 'email', '')));
BEGIN
  IF normalized_email = '' THEN RETURN; END IF;

  RETURN QUERY
  SELECT
    d.id, d.project_id, d.workspace_id, d.customer_id,
    d.document_number, d.document_type::TEXT, d.status::TEXT, d.line_items,
    d.total_amount, d.collect_tax, d.tax_name, d.tax_rate,
    d.due_date, d.paid_date, d.metadata, d.rendered_content,
    d.created_by, d.created_at, d.updated_at, p.name AS project_name
  FROM generated_documents d
  JOIN projects p ON p.id = d.project_id
  WHERE d.document_type = 'invoice'
    AND (p_project_id IS NULL OR d.project_id = p_project_id)
    AND p.client_id IS NOT NULL
    AND EXISTS (
      SELECT 1 FROM customer_contacts cc
      WHERE cc.customer_id = p.client_id
        AND cc.is_active = TRUE
        AND LOWER(TRIM(COALESCE(cc.email, ''))) = normalized_email
    )
  ORDER BY COALESCE(d.due_date, d.created_at) DESC, d.created_at DESC;
END;
$$;

CREATE OR REPLACE FUNCTION public.portal_get_invoice(invoice_id uuid)
RETURNS TABLE(
  id uuid, project_id uuid, workspace_id uuid, customer_id uuid,
  document_number text, document_type text, status text, line_items jsonb,
  total_amount numeric, collect_tax boolean, tax_name text, tax_rate numeric,
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
  normalized_email TEXT := LOWER(TRIM(COALESCE(auth.jwt() ->> 'email', '')));
BEGIN
  IF normalized_email = '' OR invoice_id IS NULL THEN RETURN; END IF;

  RETURN QUERY
  SELECT
    d.id, d.project_id, d.workspace_id, d.customer_id,
    d.document_number, d.document_type::TEXT, d.status::TEXT, d.line_items,
    d.total_amount, d.collect_tax, d.tax_name, d.tax_rate,
    d.due_date, d.paid_date, d.metadata, d.rendered_content,
    d.created_by, d.created_at, d.updated_at, p.name AS project_name
  FROM generated_documents d
  JOIN projects p ON p.id = d.project_id
  WHERE d.id = invoice_id
    AND d.document_type = 'invoice'
    AND p.client_id IS NOT NULL
    AND EXISTS (
      SELECT 1 FROM customer_contacts cc
      WHERE cc.customer_id = p.client_id
        AND cc.is_active = TRUE
        AND LOWER(TRIM(COALESCE(cc.email, ''))) = normalized_email
    )
  LIMIT 1;
END;
$$;

CREATE OR REPLACE FUNCTION public.portal_get_project_documents(p_project_id uuid)
RETURNS TABLE(
  id uuid, project_id uuid, workspace_id uuid, customer_id uuid,
  template_name text, document_number text, document_type text, status text,
  total_amount numeric,
  due_date timestamp with time zone, paid_date timestamp with time zone,
  metadata jsonb,
  denied_at timestamp with time zone, denied_by_name text, denial_reason text,
  signed_by_name text, signed_at timestamp with time zone,
  created_by uuid,
  created_at timestamp with time zone, updated_at timestamp with time zone
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  normalized_email TEXT := LOWER(TRIM(COALESCE(auth.jwt() ->> 'email', '')));
BEGIN
  IF normalized_email = '' OR p_project_id IS NULL THEN RETURN; END IF;

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
    AND EXISTS (
      SELECT 1 FROM public.customer_contacts cc
      WHERE cc.customer_id = p.client_id
        AND cc.is_active = TRUE
        AND LOWER(TRIM(COALESCE(cc.email, ''))) = normalized_email
    )
  ORDER BY d.created_at DESC;
END;
$$;

CREATE OR REPLACE FUNCTION public.portal_get_document(p_document_id uuid)
RETURNS TABLE(
  id uuid, project_id uuid, workspace_id uuid, customer_id uuid,
  template_name text, document_number text, document_type text, status text,
  rendered_content text, line_items jsonb, line_item_visibility text,
  total_amount numeric, collect_tax boolean, tax_name text, tax_rate numeric,
  due_date timestamp with time zone, paid_date timestamp with time zone,
  metadata jsonb, prepared_by jsonb, prepared_for jsonb, footer_content text,
  signed_by_name text, signed_by_email text,
  signed_at timestamp with time zone, signature_url text,
  denied_at timestamp with time zone, denied_by_name text,
  denied_by_email text, denial_reason text,
  created_by uuid,
  created_at timestamp with time zone, updated_at timestamp with time zone,
  project_name text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  normalized_email TEXT := LOWER(TRIM(COALESCE(auth.jwt() ->> 'email', '')));
BEGIN
  IF normalized_email = '' OR p_document_id IS NULL THEN RETURN; END IF;

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
    AND EXISTS (
      SELECT 1 FROM public.customer_contacts cc
      WHERE cc.customer_id = p.client_id
        AND cc.is_active = TRUE
        AND LOWER(TRIM(COALESCE(cc.email, ''))) = normalized_email
    )
  LIMIT 1;
END;
$$;
