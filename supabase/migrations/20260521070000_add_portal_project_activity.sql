-- Portal: chronological project activity timeline.
-- Returns a unified, time-sorted feed of events the customer should see for
-- a single project: documents (sent / viewed / signed / approved / denied /
-- changes-requested / payment-completed), invoices (sent / paid), selections
-- (approved / declined), and change orders (sent / approved / rejected).
--
-- Auth: same pattern as portal_get_project — caller's JWT email must match an
-- active customer_contact for the project's client. SECURITY DEFINER, granted
-- only to authenticated.

CREATE OR REPLACE FUNCTION public.portal_get_project_activity(
  p_project_id UUID,
  p_limit INT DEFAULT 100
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
SET search_path = public
AS $$
DECLARE
  normalized_email TEXT := LOWER(TRIM(COALESCE(auth.jwt() ->> 'email', '')));
  v_workspace_id   UUID;
  v_client_id      UUID;
  v_limit          INT  := LEAST(GREATEST(COALESCE(p_limit, 100), 1), 500);
BEGIN
  IF normalized_email = '' OR p_project_id IS NULL THEN
    RETURN;
  END IF;

  -- Authz: caller must be an active contact of the project's client.
  SELECT p.workspace_id, p.client_id
    INTO v_workspace_id, v_client_id
  FROM projects p
  JOIN customers c ON c.id = p.client_id
  WHERE p.id = p_project_id
    AND p.client_id IS NOT NULL
    AND c.is_active = TRUE
    AND EXISTS (
      SELECT 1
      FROM customer_contacts cc
      WHERE cc.customer_id = p.client_id
        AND cc.is_active = TRUE
        AND LOWER(TRIM(COALESCE(cc.email, ''))) = normalized_email
    )
  LIMIT 1;

  IF v_workspace_id IS NULL THEN
    RETURN;
  END IF;

  RETURN QUERY
  WITH
  -- Documents: emit one row per meaningful state transition we can derive
  -- from the document's timestamps + status. We deliberately exclude drafts.
  doc_sent AS (
    SELECT
      d.sent_at                         AS occurred_at,
      'document_sent'::TEXT             AS event_type,
      COALESCE(NULLIF(TRIM(d.template_name), ''), 'Document')
        || ' was sent to you'           AS title,
      NULL::TEXT                        AS subtitle,
      NULL::TEXT                        AS actor_name,
      'document'::TEXT                  AS ref_type,
      d.id                              AS ref_id,
      d.total_amount                    AS amount,
      jsonb_build_object('status', d.status::TEXT) AS details
    FROM generated_documents d
    WHERE d.project_id = p_project_id
      AND d.sent_at IS NOT NULL
      AND d.status::TEXT <> 'draft'
  ),
  doc_signed AS (
    SELECT
      d.signed_at,
      'document_signed'::TEXT,
      COALESCE(NULLIF(TRIM(d.template_name), ''), 'Document')
        || ' was signed',
      NULL::TEXT,
      COALESCE(NULLIF(TRIM(d.signed_by_name), ''),
               NULLIF(TRIM(d.signed_by_email), '')),
      'document'::TEXT,
      d.id,
      d.total_amount,
      jsonb_build_object('email', d.signed_by_email)
    FROM generated_documents d
    WHERE d.project_id = p_project_id
      AND d.signed_at IS NOT NULL
  ),
  doc_approved AS (
    SELECT
      d.approved_at,
      'document_approved'::TEXT,
      COALESCE(NULLIF(TRIM(d.template_name), ''), 'Document')
        || ' was approved',
      NULL::TEXT,
      NULL::TEXT,
      'document'::TEXT,
      d.id,
      d.total_amount,
      '{}'::JSONB
    FROM generated_documents d
    WHERE d.project_id = p_project_id
      AND d.approved_at IS NOT NULL
  ),
  doc_denied AS (
    SELECT
      d.denied_at,
      'document_denied'::TEXT,
      COALESCE(NULLIF(TRIM(d.template_name), ''), 'Document')
        || ' was denied',
      NULLIF(TRIM(d.denial_reason), ''),
      COALESCE(NULLIF(TRIM(d.denied_by_name), ''),
               NULLIF(TRIM(d.denied_by_email), '')),
      'document'::TEXT,
      d.id,
      d.total_amount,
      jsonb_build_object('reason', d.denial_reason)
    FROM generated_documents d
    WHERE d.project_id = p_project_id
      AND d.denied_at IS NOT NULL
  ),
  -- Pull the richer activity log entries (views, changes-requested,
  -- payment-completed, etc.) for documents that belong to this project.
  doc_activity AS (
    -- IMPORTANT: explicit allowlist of customer-safe actions. Do NOT use a
    -- NOT IN exclusion list here — new internal action types added to
    -- document_activity_log must be opted in explicitly before they reach
    -- the portal feed. Also: we never return raw log.details (it may carry
    -- internal payloads); only the curated reason text is exposed.
    SELECT
      log.created_at                    AS occurred_at,
      ('document_' || log.action)::TEXT AS event_type,
      CASE log.action
        WHEN 'viewed'             THEN COALESCE(NULLIF(TRIM(d.template_name), ''), 'Document') || ' was viewed'
        WHEN 'opened'             THEN COALESCE(NULLIF(TRIM(d.template_name), ''), 'Document') || ' was opened'
        WHEN 'downloaded'         THEN COALESCE(NULLIF(TRIM(d.template_name), ''), 'Document') || ' was downloaded'
        WHEN 'changes_requested'  THEN 'Changes requested on ' || COALESCE(NULLIF(TRIM(d.template_name), ''), 'document')
        WHEN 'payment_completed'  THEN 'Payment received for ' || COALESCE(NULLIF(TRIM(d.template_name), ''), 'document')
        ELSE COALESCE(NULLIF(TRIM(d.template_name), ''), 'Document')
      END                               AS title,
      CASE
        WHEN log.action IN ('changes_requested')
          THEN NULLIF(TRIM(log.details->>'reason'), '')
        ELSE NULL
      END                               AS subtitle,
      COALESCE(NULLIF(TRIM(log.actor_name), ''),
               NULLIF(TRIM(log.actor_email), ''))  AS actor_name,
      'document'::TEXT                  AS ref_type,
      d.id                              AS ref_id,
      d.total_amount                    AS amount,
      CASE
        WHEN log.action = 'changes_requested' AND NULLIF(TRIM(log.details->>'reason'), '') IS NOT NULL
          THEN jsonb_build_object('reason', TRIM(log.details->>'reason'))
        ELSE '{}'::JSONB
      END                               AS details
    FROM document_activity_log log
    JOIN generated_documents d ON d.id = log.document_id
    WHERE d.project_id = p_project_id
      AND log.action IN (
        'viewed',
        'opened',
        'downloaded',
        'changes_requested',
        'payment_completed'
      )
  ),
  -- Invoices: emit at creation (treated as "sent") and on payment.
  inv_sent AS (
    SELECT
      i.created_at,
      'invoice_sent'::TEXT,
      'Invoice ' || i.invoice_number || ' was sent',
      NULL::TEXT,
      NULL::TEXT,
      'invoice'::TEXT,
      i.id,
      i.total,
      jsonb_build_object('status', i.status::TEXT)
    FROM invoices i
    WHERE i.project_id = p_project_id
      AND i.status::TEXT <> 'draft'
  ),
  inv_paid AS (
    SELECT
      (i.paid_date::TIMESTAMPTZ),
      'invoice_paid'::TEXT,
      'Invoice ' || i.invoice_number || ' was paid',
      NULL::TEXT,
      NULL::TEXT,
      'invoice'::TEXT,
      i.id,
      i.total,
      '{}'::JSONB
    FROM invoices i
    WHERE i.project_id = p_project_id
      AND i.paid_date IS NOT NULL
  ),
  -- Selections: approval / decline events. We don't expose creation here to
  -- keep the feed signal-rich.
  sel_approved AS (
    SELECT
      s.approved_at,
      'selection_approved'::TEXT,
      'Selection "' || s.name || '" was approved',
      NULL::TEXT,
      COALESCE(NULLIF(TRIM(s.approved_by_name), ''),
               NULLIF(TRIM(s.approved_by_email), '')),
      'selection'::TEXT,
      s.id,
      s.selected_amount,
      '{}'::JSONB
    FROM selections s
    WHERE s.project_id = p_project_id
      AND s.approved_at IS NOT NULL
  ),
  sel_declined AS (
    SELECT
      s.declined_at,
      'selection_declined'::TEXT,
      'Selection "' || s.name || '" was declined',
      NULLIF(TRIM(s.decline_reason), ''),
      NULLIF(TRIM(s.declined_by_name), ''),
      'selection'::TEXT,
      s.id,
      s.selected_amount,
      jsonb_build_object('reason', s.decline_reason)
    FROM selections s
    WHERE s.project_id = p_project_id
      AND s.declined_at IS NOT NULL
  ),
  -- Change orders: sent and approved are customer-visible events.
  co_sent AS (
    SELECT
      co.sent_date,
      'change_order_sent'::TEXT,
      'Change order ' || co.change_order_number || ' — ' || co.title,
      NULL::TEXT,
      NULL::TEXT,
      'change_order'::TEXT,
      co.id,
      co.total_amount,
      jsonb_build_object('status', co.status::TEXT)
    FROM change_orders co
    WHERE co.project_id = p_project_id
      AND co.sent_date IS NOT NULL
      AND co.status::TEXT <> 'draft'
  ),
  co_approved AS (
    SELECT
      co.approved_date,
      'change_order_approved'::TEXT,
      'Change order ' || co.change_order_number || ' was approved',
      NULL::TEXT,
      NULL::TEXT,
      'change_order'::TEXT,
      co.id,
      co.total_amount,
      '{}'::JSONB
    FROM change_orders co
    WHERE co.project_id = p_project_id
      AND co.approved_date IS NOT NULL
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
  SELECT
    u.occurred_at,
    u.event_type,
    u.title,
    u.subtitle,
    u.actor_name,
    u.ref_type,
    u.ref_id,
    u.amount,
    u.details
  FROM unioned u
  WHERE u.occurred_at IS NOT NULL
  ORDER BY u.occurred_at DESC
  LIMIT v_limit;
END;
$$;

REVOKE ALL ON FUNCTION public.portal_get_project_activity(UUID, INT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.portal_get_project_activity(UUID, INT) TO authenticated;

COMMENT ON FUNCTION public.portal_get_project_activity(UUID, INT) IS
  'Customer portal: chronological activity feed for one project. Combines '
  'document, invoice, selection, and change-order events. Gated by '
  'customer_contacts email match (same authz as portal_get_project).';
