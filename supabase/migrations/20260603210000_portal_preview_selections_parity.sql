-- =============================================================================
-- Bugfix: the 2-arg preview overload of portal_get_project_selections (used by
-- the builder's "preview as customer") had drifted behind the 1-arg client
-- version — missing approved_signature_url, reference_url, attachment_urls, and
-- the options' image_urls / is_client_suggested. Bring it to parity so preview
-- matches the real portal. (Two overloads exist: (uuid) for the live client,
-- (uuid,uuid) for preview — keep both in sync on future column additions.)
-- =============================================================================

DROP FUNCTION IF EXISTS public.portal_get_project_selections(uuid, uuid);

CREATE FUNCTION public.portal_get_project_selections(
  p_project_id uuid, p_preview_customer_id uuid DEFAULT NULL::uuid)
RETURNS TABLE(
  id uuid, project_id uuid, name text, description text, category text, location text,
  status text, allowance_amount numeric, selected_amount numeric, selected_option_id uuid,
  due_date date, client_notes text, approved_at timestamptz, approved_signature_url text,
  reference_url text, attachment_urls text[], options jsonb)
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'pg_temp'
AS $function$
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
            AND LOWER(TRIM(COALESCE(cc.email, ''))) = v_email))
      )
  ) INTO v_allowed;

  IF NOT v_allowed THEN
    RAISE EXCEPTION 'Project not found or access denied';
  END IF;

  RETURN QUERY
  SELECT
    s.id, s.project_id, s.name, s.description, s.category, s.location,
    s.status, s.allowance_amount, s.selected_amount, s.selected_option_id,
    s.due_date, s.client_notes, s.approved_at, s.approved_signature_url,
    s.reference_url, s.attachment_urls,
    COALESCE(
      (SELECT jsonb_agg(jsonb_build_object(
            'id', o.id, 'name', o.name, 'description', o.description,
            'vendor', o.vendor, 'sku', o.sku, 'unit_cost', o.unit_cost,
            'quantity', o.quantity, 'image_url', o.image_url, 'image_urls', o.image_urls,
            'external_url', o.external_url, 'sort_order', o.sort_order,
            'is_client_suggested', o.is_client_suggested)
          ORDER BY o.sort_order, o.created_at)
        FROM selection_options o WHERE o.selection_id = s.id),
      '[]'::jsonb)
  FROM selections s
  WHERE s.project_id = p_project_id
    AND s.status IN ('awaiting_client', 'approved', 'declined')
  ORDER BY CASE s.status WHEN 'awaiting_client' THEN 0 WHEN 'approved' THEN 1 ELSE 2 END,
    s.due_date NULLS LAST, s.created_at;
END;
$function$;

REVOKE ALL ON FUNCTION public.portal_get_project_selections(uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.portal_get_project_selections(uuid, uuid) TO authenticated;
