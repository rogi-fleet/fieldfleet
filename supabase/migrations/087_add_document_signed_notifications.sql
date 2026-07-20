CREATE OR REPLACE FUNCTION public.create_document_signed_notifications(
  p_document_id UUID,
  p_signed_by_name TEXT DEFAULT NULL,
  p_signed_by_email TEXT DEFAULT NULL
)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  current_user_id UUID := auth.uid();
  current_auth_role TEXT := auth.role();
  doc_row RECORD;
  project_manager_id UUID;
  signer_label TEXT;
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
    RAISE EXCEPTION 'Document not found';
  END IF;

  IF current_auth_role <> 'service_role' THEN
    IF current_user_id IS NULL THEN
      RAISE EXCEPTION 'You must be signed in to create document signed notifications';
    END IF;

    IF NOT public.is_workspace_member(doc_row.workspace_id) THEN
      RAISE EXCEPTION 'You do not have access to this workspace';
    END IF;
  END IF;

  IF doc_row.project_id IS NOT NULL THEN
    SELECT p.project_manager_id
    INTO project_manager_id
    FROM public.projects p
    WHERE p.id = doc_row.project_id
    LIMIT 1;
  END IF;

  signer_label := COALESCE(
    NULLIF(TRIM(p_signed_by_name), ''),
    NULLIF(TRIM(p_signed_by_email), ''),
    'the recipient'
  );

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
    'document_signed',
    doc_row.template_name || ' was signed',
    'Signed by ' || signer_label || '.',
    jsonb_build_object(
      'target_type', 'document',
      'document_id', doc_row.id,
      'project_id', doc_row.project_id,
      'signed_by_name', NULLIF(TRIM(p_signed_by_name), ''),
      'signed_by_email', NULLIF(TRIM(p_signed_by_email), ''),
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
      AND (current_user_id IS NULL OR user_id <> current_user_id)
  ) recipients;

  GET DIAGNOSTICS inserted_count = ROW_COUNT;
  RETURN inserted_count;
END;
$$;

REVOKE ALL ON FUNCTION public.create_document_signed_notifications(UUID, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_document_signed_notifications(UUID, TEXT, TEXT) TO authenticated;

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
      'document_signed'
    )
  );
