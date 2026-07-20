-- =============================================================================
-- Files & reference link on a selection (JobTread parity: attach files/links to
-- each selection so the client sees specs). Builder-attached, client-visible.
-- =============================================================================

ALTER TABLE public.selections
  ADD COLUMN IF NOT EXISTS reference_url   TEXT,
  ADD COLUMN IF NOT EXISTS attachment_urls TEXT[] NOT NULL DEFAULT '{}';

-- Surface the new fields in the portal read RPC (recreate with extra columns).
-- Return-type change requires a DROP first.
DROP FUNCTION IF EXISTS public.portal_get_project_selections(UUID);
CREATE FUNCTION public.portal_get_project_selections(
  p_project_id UUID
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
  approved_signature_url TEXT,
  reference_url      TEXT,
  attachment_urls    TEXT[],
  options            JSONB
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  normalized_email TEXT := LOWER(TRIM(COALESCE(auth.jwt() ->> 'email', '')));
  v_allowed BOOLEAN;
BEGIN
  IF normalized_email = '' THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM projects p
    JOIN customer_contacts cc ON cc.customer_id = p.client_id
    WHERE p.id = p_project_id
      AND cc.is_active = TRUE
      AND LOWER(TRIM(COALESCE(cc.email, ''))) = normalized_email
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
      (
        SELECT jsonb_agg(
          jsonb_build_object(
            'id', o.id,
            'name', o.name,
            'description', o.description,
            'vendor', o.vendor,
            'sku', o.sku,
            'unit_cost', o.unit_cost,
            'quantity', o.quantity,
            'image_url', o.image_url,
            'image_urls', o.image_urls,
            'external_url', o.external_url,
            'sort_order', o.sort_order
          )
          ORDER BY o.sort_order, o.created_at
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

REVOKE ALL ON FUNCTION public.portal_get_project_selections(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.portal_get_project_selections(UUID) TO authenticated;
