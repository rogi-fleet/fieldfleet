-- Portal "Preview as Customer" mode.
--
-- Adds a sanctioned bypass to the email-match gate on every portal SELECT
-- RPC: workspace members of a customer's workspace can pass
-- p_preview_customer_id and read the portal exactly as that customer would.
-- All write/action RPCs are intentionally left untouched — preview is
-- strictly read-only.

-- ============================================================================
-- 1. Shared helper: is the caller a workspace member for this customer?
-- ============================================================================
CREATE OR REPLACE FUNCTION public._portal_preview_authorized(
  p_customer_id UUID
)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_workspace UUID;
BEGIN
  IF p_customer_id IS NULL OR v_uid IS NULL THEN
    RETURN FALSE;
  END IF;

  SELECT workspace_id
    INTO v_workspace
  FROM customers
  WHERE id = p_customer_id
    AND is_active = TRUE
  LIMIT 1;

  IF v_workspace IS NULL THEN
    RETURN FALSE;
  END IF;

  RETURN EXISTS (
    SELECT 1 FROM workspace_members
    WHERE workspace_id = v_workspace
      AND user_id = v_uid
  );
END;
$$;

REVOKE ALL ON FUNCTION public._portal_preview_authorized(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public._portal_preview_authorized(UUID) TO authenticated;

-- ============================================================================
-- 2. Drop existing SELECT RPCs so we can recreate with an added parameter.
-- ============================================================================
DROP FUNCTION IF EXISTS public.portal_get_projects();
DROP FUNCTION IF EXISTS public.portal_get_project(UUID);
DROP FUNCTION IF EXISTS public.portal_get_invoices(UUID);
DROP FUNCTION IF EXISTS public.portal_get_invoice(UUID);
DROP FUNCTION IF EXISTS public.portal_get_project_documents(UUID);
DROP FUNCTION IF EXISTS public.portal_get_document(UUID);
DROP FUNCTION IF EXISTS public.portal_get_document_activity(UUID);
DROP FUNCTION IF EXISTS public.portal_get_project_selections(UUID);
DROP FUNCTION IF EXISTS public.portal_get_project_activity(UUID, INT);

-- ============================================================================
-- 3. portal_get_projects
-- ============================================================================
CREATE OR REPLACE FUNCTION public.portal_get_projects(
  p_preview_customer_id UUID DEFAULT NULL
)
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
SET search_path = public, pg_temp
AS $$
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
          AND LOWER(TRIM(COALESCE(cc.email, ''))) = v_email
      ))
    )
  ORDER BY p.updated_at DESC;
END;
$$;

REVOKE ALL ON FUNCTION public.portal_get_projects(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.portal_get_projects(UUID) TO authenticated;

-- ============================================================================
-- 4. portal_get_project
-- ============================================================================
CREATE OR REPLACE FUNCTION public.portal_get_project(
  project_id UUID,
  p_preview_customer_id UUID DEFAULT NULL
)
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
SET search_path = public, pg_temp
AS $$
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
          AND LOWER(TRIM(COALESCE(cc.email, ''))) = v_email
      ))
    )
  LIMIT 1;
END;
$$;

REVOKE ALL ON FUNCTION public.portal_get_project(UUID, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.portal_get_project(UUID, UUID) TO authenticated;

-- ============================================================================
-- 5. portal_get_invoices  (note: generated_documents-based after migration 20260517022947)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.portal_get_invoices(
  p_project_id UUID DEFAULT NULL,
  p_preview_customer_id UUID DEFAULT NULL
)
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
  v_email   TEXT    := LOWER(TRIM(COALESCE(auth.jwt() ->> 'email', '')));
  v_preview BOOLEAN := public._portal_preview_authorized(p_preview_customer_id);
BEGIN
  IF NOT v_preview AND v_email = '' THEN RETURN; END IF;

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

-- ============================================================================
-- 6. portal_get_invoice
-- ============================================================================
CREATE OR REPLACE FUNCTION public.portal_get_invoice(
  invoice_id UUID,
  p_preview_customer_id UUID DEFAULT NULL
)
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
  v_email   TEXT    := LOWER(TRIM(COALESCE(auth.jwt() ->> 'email', '')));
  v_preview BOOLEAN := public._portal_preview_authorized(p_preview_customer_id);
BEGIN
  IF invoice_id IS NULL OR (NOT v_preview AND v_email = '') THEN RETURN; END IF;

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

-- ============================================================================
-- 7. portal_get_project_documents
-- ============================================================================
CREATE OR REPLACE FUNCTION public.portal_get_project_documents(
  p_project_id UUID,
  p_preview_customer_id UUID DEFAULT NULL
)
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
          AND LOWER(TRIM(COALESCE(cc.email, ''))) = v_email
      ))
    )
  ORDER BY d.created_at DESC;
END;
$$;

REVOKE ALL ON FUNCTION public.portal_get_project_documents(UUID, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.portal_get_project_documents(UUID, UUID) TO authenticated;

-- ============================================================================
-- 8. portal_get_document
-- ============================================================================
CREATE OR REPLACE FUNCTION public.portal_get_document(
  p_document_id UUID,
  p_preview_customer_id UUID DEFAULT NULL
)
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
          AND LOWER(TRIM(COALESCE(cc.email, ''))) = v_email
      ))
    )
  LIMIT 1;
END;
$$;

REVOKE ALL ON FUNCTION public.portal_get_document(UUID, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.portal_get_document(UUID, UUID) TO authenticated;

-- ============================================================================
-- 9. portal_get_document_activity
-- ============================================================================
CREATE OR REPLACE FUNCTION public.portal_get_document_activity(
  p_document_id UUID,
  p_preview_customer_id UUID DEFAULT NULL
)
RETURNS TABLE (
  id UUID,
  document_id UUID,
  action TEXT,
  actor_email TEXT,
  actor_name TEXT,
  actor_type TEXT,
  details JSONB,
  created_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
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
$$;

REVOKE ALL ON FUNCTION public.portal_get_document_activity(UUID, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.portal_get_document_activity(UUID, UUID) TO authenticated;

-- ============================================================================
-- 10. portal_get_project_selections
-- ============================================================================
CREATE OR REPLACE FUNCTION public.portal_get_project_selections(
  p_project_id UUID,
  p_preview_customer_id UUID DEFAULT NULL
)
RETURNS TABLE (
  id                 UUID,
  project_id         UUID,
  name               TEXT,
  description        TEXT,
  category           TEXT,
  location           TEXT,
  status             TEXT,
  allowance_amount   NUMERIC,
  selected_amount    NUMERIC,
  selected_option_id UUID,
  due_date           DATE,
  client_notes       TEXT,
  approved_at        TIMESTAMPTZ,
  options            JSONB
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
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
            AND LOWER(TRIM(COALESCE(cc.email, ''))) = v_email
        ))
      )
  ) INTO v_allowed;

  IF NOT v_allowed THEN
    RAISE EXCEPTION 'Project not found or access denied';
  END IF;

  RETURN QUERY
  SELECT
    s.id, s.project_id, s.name, s.description, s.category, s.location,
    s.status, s.allowance_amount, s.selected_amount, s.selected_option_id,
    s.due_date, s.client_notes, s.approved_at,
    COALESCE(
      (
        SELECT jsonb_agg(
          jsonb_build_object(
            'id', o.id, 'name', o.name, 'description', o.description,
            'vendor', o.vendor, 'sku', o.sku, 'unit_cost', o.unit_cost,
            'quantity', o.quantity, 'image_url', o.image_url,
            'external_url', o.external_url, 'sort_order', o.sort_order
          ) ORDER BY o.sort_order, o.created_at
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
$$;

REVOKE ALL ON FUNCTION public.portal_get_project_selections(UUID, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.portal_get_project_selections(UUID, UUID) TO authenticated;

-- ============================================================================
-- 11. portal_get_project_activity
-- ============================================================================
CREATE OR REPLACE FUNCTION public.portal_get_project_activity(
  p_project_id UUID,
  p_limit INT DEFAULT 100,
  p_preview_customer_id UUID DEFAULT NULL
)
RETURNS TABLE (
  occurred_at   TIMESTAMPTZ,
  event_type    TEXT,
  title         TEXT,
  subtitle      TEXT,
  actor_name    TEXT,
  ref_type      TEXT,
  ref_id        UUID,
  amount        NUMERIC,
  details       JSONB
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
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
$$;

REVOKE ALL ON FUNCTION public.portal_get_project_activity(UUID, INT, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.portal_get_project_activity(UUID, INT, UUID) TO authenticated;

COMMENT ON FUNCTION public._portal_preview_authorized(UUID) IS
  'Returns TRUE when caller is an active workspace member of the customer''s '
  'workspace. Used by portal SELECT RPCs to enable a sanctioned read-only '
  '"Preview as Customer" mode for staff.';
