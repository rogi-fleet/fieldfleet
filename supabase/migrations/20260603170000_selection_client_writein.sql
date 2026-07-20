-- =============================================================================
-- Client write-in options (JobTread parity). The client can propose their own
-- option from the portal; it's stored flagged is_client_suggested so the
-- builder can see and price it. Also surfaces the flag in the portal read RPC.
-- =============================================================================

ALTER TABLE public.selection_options
  ADD COLUMN IF NOT EXISTS is_client_suggested BOOLEAN NOT NULL DEFAULT FALSE;

CREATE OR REPLACE FUNCTION public.portal_suggest_selection_option(
  p_selection_id UUID,
  p_name TEXT,
  p_note TEXT DEFAULT NULL,
  p_unit_cost NUMERIC DEFAULT 0
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  normalized_email TEXT := LOWER(TRIM(COALESCE(auth.jwt() ->> 'email', '')));
  v_workspace UUID;
  v_sort INT;
BEGIN
  IF normalized_email = '' THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;
  IF COALESCE(TRIM(p_name), '') = '' THEN
    RAISE EXCEPTION 'Name required';
  END IF;

  SELECT s.workspace_id INTO v_workspace
    FROM selections s
    JOIN projects p ON p.id = s.project_id
    JOIN customer_contacts cc ON cc.customer_id = p.client_id
   WHERE s.id = p_selection_id
     AND cc.is_active = TRUE
     AND LOWER(TRIM(COALESCE(cc.email, ''))) = normalized_email
   LIMIT 1;
  IF v_workspace IS NULL THEN
    RAISE EXCEPTION 'Selection not found or access denied';
  END IF;

  SELECT COALESCE(MAX(sort_order) + 1, 0) INTO v_sort
    FROM selection_options WHERE selection_id = p_selection_id;

  INSERT INTO selection_options
    (selection_id, workspace_id, name, description, unit_cost, quantity,
     sort_order, is_client_suggested)
  VALUES
    (p_selection_id, v_workspace, TRIM(p_name),
     NULLIF(TRIM(COALESCE(p_note,'')),''), COALESCE(p_unit_cost, 0), 1, v_sort, TRUE);

  RETURN jsonb_build_object('success', true);
END;
$$;

REVOKE ALL ON FUNCTION public.portal_suggest_selection_option(UUID, TEXT, TEXT, NUMERIC) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.portal_suggest_selection_option(UUID, TEXT, TEXT, NUMERIC) TO authenticated;

-- portal_get_project_selections also returns is_client_suggested per option
-- (recreated in the same release; see the consolidated function definition).
