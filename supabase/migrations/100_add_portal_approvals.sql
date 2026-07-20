-- Portal approvals: add denial statuses, activity log, and portal RPCs
-- for document deny/request-changes/approval flows.

-- 1a. Extend document_status enum with denial statuses
ALTER TYPE document_status ADD VALUE IF NOT EXISTS 'denied';
ALTER TYPE document_status ADD VALUE IF NOT EXISTS 'changes_requested';

-- 1b. Add denial columns to generated_documents
ALTER TABLE generated_documents ADD COLUMN IF NOT EXISTS denied_at TIMESTAMPTZ;
ALTER TABLE generated_documents ADD COLUMN IF NOT EXISTS denied_by_name TEXT;
ALTER TABLE generated_documents ADD COLUMN IF NOT EXISTS denied_by_email TEXT;
ALTER TABLE generated_documents ADD COLUMN IF NOT EXISTS denial_reason TEXT;

-- 1c. Create document_activity_log table
CREATE TABLE IF NOT EXISTS document_activity_log (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
  document_id UUID NOT NULL REFERENCES generated_documents(id) ON DELETE CASCADE,
  action TEXT NOT NULL,
  actor_email TEXT,
  actor_name TEXT,
  actor_type TEXT DEFAULT 'portal_user',
  details JSONB DEFAULT '{}',
  ip_address TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_document_activity_log_doc_created
  ON document_activity_log (document_id, created_at);

ALTER TABLE document_activity_log ENABLE ROW LEVEL SECURITY;

-- Deny all direct write access (writes via RPCs / service_role only)
DROP POLICY IF EXISTS document_activity_log_deny_all ON document_activity_log;
CREATE POLICY document_activity_log_deny_all ON document_activity_log
  FOR INSERT WITH CHECK (false);
CREATE POLICY document_activity_log_deny_update ON document_activity_log
  FOR UPDATE USING (false);
CREATE POLICY document_activity_log_deny_delete ON document_activity_log
  FOR DELETE USING (false);

-- Allow workspace members to read activity logs for documents in their workspace
CREATE POLICY document_activity_log_select_workspace_member ON document_activity_log
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM workspace_members wm
      WHERE wm.workspace_id = document_activity_log.workspace_id
        AND wm.user_id = auth.uid()
    )
  );

-- 1i. Create notification helper for document actions
CREATE OR REPLACE FUNCTION public.create_document_action_notifications(
  p_document_id UUID,
  p_action TEXT,
  p_actor_name TEXT DEFAULT NULL,
  p_actor_email TEXT DEFAULT NULL,
  p_reason TEXT DEFAULT NULL
)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  doc_row RECORD;
  project_manager_id UUID;
  actor_label TEXT;
  notif_type TEXT;
  notif_title TEXT;
  notif_body TEXT;
  inserted_count INTEGER := 0;
BEGIN
  SELECT
    gd.id,
    gd.workspace_id,
    gd.project_id,
    gd.created_by,
    COALESCE(NULLIF(TRIM(gd.template_name), ''), 'Document') AS template_name
  INTO doc_row
  FROM public.generated_documents gd
  WHERE gd.id = p_document_id
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN 0;
  END IF;

  IF doc_row.project_id IS NOT NULL THEN
    SELECT p.project_manager_id
    INTO project_manager_id
    FROM public.projects p
    WHERE p.id = doc_row.project_id
    LIMIT 1;
  END IF;

  actor_label := COALESCE(
    NULLIF(TRIM(p_actor_name), ''),
    NULLIF(TRIM(p_actor_email), ''),
    'the customer'
  );

  -- Map action to notification type and message
  CASE p_action
    WHEN 'denied' THEN
      notif_type := 'document_denied';
      notif_title := doc_row.template_name || ' was denied';
      notif_body := 'Denied by ' || actor_label || '.';
      IF p_reason IS NOT NULL AND TRIM(p_reason) <> '' THEN
        notif_body := notif_body || ' Reason: ' || TRIM(p_reason);
      END IF;
    WHEN 'changes_requested' THEN
      notif_type := 'document_changes_requested';
      notif_title := 'Changes requested on ' || doc_row.template_name;
      notif_body := 'Requested by ' || actor_label || '.';
      IF p_reason IS NOT NULL AND TRIM(p_reason) <> '' THEN
        notif_body := notif_body || ' Reason: ' || TRIM(p_reason);
      END IF;
    WHEN 'payment_completed' THEN
      notif_type := 'document_payment_completed';
      notif_title := doc_row.template_name || ' payment received';
      notif_body := 'Payment completed by ' || actor_label || '.';
    ELSE
      RETURN 0;
  END CASE;

  INSERT INTO public.notifications (
    user_id,
    workspace_id,
    type,
    title,
    body,
    metadata
  )
  SELECT
    recipients.user_id,
    doc_row.workspace_id,
    notif_type,
    notif_title,
    notif_body,
    jsonb_build_object(
      'target_type', 'document',
      'document_id', doc_row.id,
      'project_id', doc_row.project_id,
      'action', p_action,
      'reason', NULLIF(TRIM(COALESCE(p_reason, '')), ''),
      'deeplink_path', '/documents/' || doc_row.id::TEXT
    )
  FROM (
    SELECT DISTINCT user_id
    FROM (
      SELECT doc_row.created_by AS user_id
      UNION ALL
      SELECT project_manager_id AS user_id
      UNION ALL
      SELECT wm.user_id
      FROM public.workspace_members wm
      WHERE wm.workspace_id = doc_row.workspace_id
        AND wm.role = 'admin'
    ) candidate_recipients
    WHERE user_id IS NOT NULL
  ) recipients;

  GET DIAGNOSTICS inserted_count = ROW_COUNT;
  RETURN inserted_count;
END;
$$;

REVOKE ALL ON FUNCTION public.create_document_action_notifications(UUID, TEXT, TEXT, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_document_action_notifications(UUID, TEXT, TEXT, TEXT, TEXT) TO service_role;

-- 1d. Portal deny document RPC
CREATE OR REPLACE FUNCTION public.portal_deny_document(
  p_document_id UUID,
  p_reason TEXT DEFAULT NULL,
  p_actor_name TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
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
$$;

REVOKE ALL ON FUNCTION public.portal_deny_document(UUID, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.portal_deny_document(UUID, TEXT, TEXT) TO authenticated;

-- 1e. Portal request changes RPC
CREATE OR REPLACE FUNCTION public.portal_request_document_changes(
  p_document_id UUID,
  p_reason TEXT DEFAULT NULL,
  p_actor_name TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
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
$$;

REVOKE ALL ON FUNCTION public.portal_request_document_changes(UUID, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.portal_request_document_changes(UUID, TEXT, TEXT) TO authenticated;

-- 1f. Portal get document RPC (single document detail)
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
  FROM generated_documents d
  JOIN projects p ON p.id = d.project_id
  WHERE d.id = p_document_id
    AND d.document_type IN ('estimate', 'proposal', 'contract', 'change_order', 'invoice', 'credit_memo', 'refund')
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

REVOKE ALL ON FUNCTION public.portal_get_document(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.portal_get_document(UUID) TO authenticated;

-- 1g. Portal get document activity RPC
CREATE OR REPLACE FUNCTION public.portal_get_document_activity(p_document_id UUID)
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
SET search_path = public
AS $$
DECLARE
  normalized_email TEXT := LOWER(TRIM(COALESCE(auth.jwt() ->> 'email', '')));
BEGIN
  IF normalized_email = '' OR p_document_id IS NULL THEN
    RETURN;
  END IF;

  -- Verify portal access to the document
  IF NOT EXISTS (
    SELECT 1
    FROM generated_documents d
    JOIN projects p ON p.id = d.project_id
    WHERE d.id = p_document_id
      AND p.client_id IS NOT NULL
      AND EXISTS (
        SELECT 1
        FROM customer_contacts cc
        WHERE cc.customer_id = p.client_id
          AND cc.is_active = TRUE
          AND LOWER(TRIM(COALESCE(cc.email, ''))) = normalized_email
      )
  ) THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT
    dal.id,
    dal.document_id,
    dal.action,
    dal.actor_email,
    dal.actor_name,
    dal.actor_type,
    dal.details,
    dal.created_at
  FROM document_activity_log dal
  WHERE dal.document_id = p_document_id
  ORDER BY dal.created_at DESC;
END;
$$;

REVOKE ALL ON FUNCTION public.portal_get_document_activity(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.portal_get_document_activity(UUID) TO authenticated;

-- 1h. Portal get project documents RPC
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

REVOKE ALL ON FUNCTION public.portal_get_project_documents(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.portal_get_project_documents(UUID) TO authenticated;

-- 1k. Portal get or create sign link RPC
CREATE OR REPLACE FUNCTION public.portal_get_or_create_sign_link(p_document_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
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
$$;

REVOKE ALL ON FUNCTION public.portal_get_or_create_sign_link(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.portal_get_or_create_sign_link(UUID) TO authenticated;

-- 1j. Update notifications type constraint to include new types
ALTER TABLE public.notifications DROP CONSTRAINT IF EXISTS notifications_type_check;
ALTER TABLE public.notifications ADD CONSTRAINT notifications_type_check
  CHECK (
    type IN (
      'mention',
      'task_assignment',
      'task_completion',
      'ai_plan_ready',
      'ai_plan_failed',
      'automation',
      'capacity_alert',
      'priority_alert',
      'workspace_member_joined',
      'time_entry_submitted',
      'time_entry_approved',
      'time_entry_rejected',
      'document_signed',
      'agreement_signed',
      'project_update',
      'document_denied',
      'document_changes_requested',
      'document_payment_completed'
    )
  );
