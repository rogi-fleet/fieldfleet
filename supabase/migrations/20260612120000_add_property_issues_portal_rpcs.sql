-- Portal RPCs for the property-scoped ("unit holder") view: fetching the
-- single property a unit holder is restricted to, and listing/creating
-- issues against it. Follows the portal_get_project / portal_add_selection_
-- comment conventions already established in this codebase: SECURITY
-- DEFINER, auth.jwt() ->> 'email' for the real-portal-user check,
-- _portal_preview_authorized() for the staff-preview check, REVOKE ALL FROM
-- PUBLIC + GRANT EXECUTE TO authenticated.

-- ============================================================================
-- 1. Authorization helper. The "real portal user" branch supports BOTH
--    valid paths: a customer-wide contact whose customer owns the
--    property's project, or a unit holder restricted to this exact
--    property. Preview only ever impersonates the customer-wide view
--    (there is no "preview as unit holder" — staff already see the
--    property directly).
-- ============================================================================
CREATE OR REPLACE FUNCTION public._portal_property_authorized(
  p_property_id UUID,
  p_preview_customer_id UUID DEFAULT NULL
) RETURNS public.properties
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_property public.properties;
  v_project  public.projects;
  v_email    TEXT := LOWER(TRIM(COALESCE(auth.jwt() ->> 'email', '')));
  v_preview  BOOLEAN := public._portal_preview_authorized(p_preview_customer_id);
  v_none     public.properties;
BEGIN
  IF p_property_id IS NULL THEN
    RETURN v_none;
  END IF;

  SELECT * INTO v_property FROM public.properties WHERE id = p_property_id;
  IF NOT FOUND THEN
    RETURN v_none;
  END IF;

  SELECT * INTO v_project FROM public.projects WHERE id = v_property.project_id;
  IF NOT FOUND THEN
    RETURN v_none;
  END IF;

  IF v_preview THEN
    IF v_project.client_id = p_preview_customer_id THEN
      RETURN v_property;
    END IF;
    RETURN v_none;
  END IF;

  IF v_email = '' THEN
    RETURN v_none;
  END IF;

  -- Path 1: customer-wide contact whose customer owns this property's project.
  IF v_project.client_id IS NOT NULL AND EXISTS (
    SELECT 1 FROM public.customer_contacts cc
    WHERE cc.customer_id = v_project.client_id
      AND cc.restricted_property_id IS NULL
      AND cc.is_active = TRUE
      AND LOWER(TRIM(COALESCE(cc.email, ''))) = v_email
  ) THEN
    RETURN v_property;
  END IF;

  -- Path 2: unit holder restricted to exactly this property.
  IF EXISTS (
    SELECT 1 FROM public.customer_contacts cc
    WHERE cc.restricted_property_id = p_property_id
      AND cc.is_active = TRUE
      AND LOWER(TRIM(COALESCE(cc.email, ''))) = v_email
  ) THEN
    RETURN v_property;
  END IF;

  RETURN v_none;
END;
$$;

REVOKE ALL ON FUNCTION public._portal_property_authorized(UUID, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public._portal_property_authorized(UUID, UUID) TO authenticated;

-- ============================================================================
-- 2. portal_get_property — single-property fetch for the scoped dashboard.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.portal_get_property(
  p_property_id UUID,
  p_preview_customer_id UUID DEFAULT NULL
) RETURNS TABLE (
  id UUID,
  workspace_id UUID,
  project_id UUID,
  project_name TEXT,
  name TEXT,
  identifier TEXT,
  floor TEXT,
  occupant TEXT,
  status property_status,
  notes TEXT,
  created_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_property public.properties;
BEGIN
  v_property := public._portal_property_authorized(p_property_id, p_preview_customer_id);
  IF v_property.id IS NULL THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT p.id, p.workspace_id, p.project_id, pr.name, p.name, p.identifier,
         p.floor, p.occupant, p.status, p.notes, p.created_at, p.updated_at
    FROM public.properties p
    JOIN public.projects pr ON pr.id = p.project_id
   WHERE p.id = p_property_id;
END;
$$;

REVOKE ALL ON FUNCTION public.portal_get_property(UUID, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.portal_get_property(UUID, UUID) TO authenticated;

-- ============================================================================
-- 3. portal_get_my_property_scope — used once at login to decide whether to
--    route to the scoped single-property view instead of the multi-project
--    dashboard.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.portal_get_my_property_scope()
RETURNS TABLE (restricted_property_id UUID)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT cc.restricted_property_id
    FROM public.customer_contacts cc
   WHERE cc.is_active = TRUE
     AND cc.restricted_property_id IS NOT NULL
     AND LOWER(TRIM(COALESCE(cc.email, ''))) = LOWER(TRIM(COALESCE(auth.jwt() ->> 'email', '')))
   LIMIT 1;
$$;

REVOKE ALL ON FUNCTION public.portal_get_my_property_scope() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.portal_get_my_property_scope() TO authenticated;

-- ============================================================================
-- 4. portal_get_property_issues / portal_create_property_issue — list and
--    create, following the portal_add_selection_comment simple-create
--    precedent (no thread/participant bookkeeping).
-- ============================================================================
CREATE OR REPLACE FUNCTION public.portal_get_property_issues(
  p_property_id UUID,
  p_preview_customer_id UUID DEFAULT NULL
) RETURNS TABLE (
  id UUID,
  title TEXT,
  description TEXT,
  status TEXT,
  priority TEXT,
  reporter_name TEXT,
  created_at TIMESTAMPTZ,
  resolved_at TIMESTAMPTZ
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_property public.properties;
BEGIN
  v_property := public._portal_property_authorized(p_property_id, p_preview_customer_id);
  IF v_property.id IS NULL THEN
    RAISE EXCEPTION 'Property not found or access denied';
  END IF;

  RETURN QUERY
    SELECT i.id, i.title, i.description, i.status, i.priority,
           i.reporter_name, i.created_at, i.resolved_at
      FROM public.property_issues i
     WHERE i.property_id = p_property_id
     ORDER BY i.created_at DESC;
END;
$$;

REVOKE ALL ON FUNCTION public.portal_get_property_issues(UUID, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.portal_get_property_issues(UUID, UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.portal_create_property_issue(
  p_property_id UUID,
  p_title TEXT,
  p_description TEXT DEFAULT NULL,
  p_priority TEXT DEFAULT 'normal'
) RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_property public.properties;
  v_email    TEXT := LOWER(TRIM(COALESCE(auth.jwt() ->> 'email', '')));
  v_contact  public.customer_contacts;
  v_issue_id UUID;
BEGIN
  IF COALESCE(TRIM(p_title), '') = '' THEN
    RAISE EXCEPTION 'Title cannot be empty';
  END IF;
  IF p_priority NOT IN ('low', 'normal', 'high', 'urgent') THEN
    RAISE EXCEPTION 'Invalid priority';
  END IF;

  -- No preview: preview is read-only, matching every other portal write RPC.
  v_property := public._portal_property_authorized(p_property_id, NULL);
  IF v_property.id IS NULL THEN
    RAISE EXCEPTION 'Property not found or access denied';
  END IF;

  SELECT * INTO v_contact
    FROM public.customer_contacts cc
   WHERE cc.is_active = TRUE
     AND LOWER(TRIM(COALESCE(cc.email, ''))) = v_email
     AND (
       cc.restricted_property_id = p_property_id
       OR (
         cc.restricted_property_id IS NULL
         AND EXISTS (
           SELECT 1 FROM public.projects p
           WHERE p.id = v_property.project_id
             AND p.client_id = cc.customer_id
         )
       )
     )
   LIMIT 1;

  INSERT INTO public.property_issues (
    workspace_id, property_id, project_id, title, description, priority,
    reported_by_contact_id, reporter_name, reporter_email
  ) VALUES (
    v_property.workspace_id, p_property_id, v_property.project_id,
    TRIM(p_title), NULLIF(TRIM(COALESCE(p_description, '')), ''), p_priority,
    v_contact.id, NULLIF(TRIM(COALESCE(v_contact.name, '')), ''), v_email
  )
  RETURNING id INTO v_issue_id;

  RETURN v_issue_id;
END;
$$;

REVOKE ALL ON FUNCTION public.portal_create_property_issue(UUID, TEXT, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.portal_create_property_issue(UUID, TEXT, TEXT, TEXT) TO authenticated;
