-- Property-scoped ("unit holder") customer contacts.
--
-- A customer_contacts row with restricted_property_id set represents a
-- contact who should see exactly one properties row (and post issues
-- against it, see 20260612110000/20260612120000) instead of the whole
-- customer's projects/invoices. NULL (the default, all existing rows)
-- preserves today's customer-wide behavior unchanged.

ALTER TABLE public.customer_contacts
  ADD COLUMN IF NOT EXISTS restricted_property_id UUID
    REFERENCES public.properties(id) ON DELETE CASCADE;

CREATE INDEX IF NOT EXISTS idx_customer_contacts_restricted_property_id
  ON public.customer_contacts (restricted_property_id)
  WHERE restricted_property_id IS NOT NULL;

COMMENT ON COLUMN public.customer_contacts.restricted_property_id IS
  'When set, this contact is a "unit holder" scoped to exactly one property instead of the whole customer. NULL = customer-wide (default, unchanged behavior).';

-- ==========================================================================
-- 1. Narrow current_portal_customer_ids: a property-restricted contact must
--    NOT also get customer-wide visibility through the pre-existing
--    customer_id-based RLS branches (customers, customer_contacts, projects,
--    invoices, change_orders, generated_documents all key off this
--    function). Excluding them here is sufficient — no changes needed to
--    those policies themselves.
-- ==========================================================================
CREATE OR REPLACE FUNCTION public.current_portal_customer_ids(workspace_uuid UUID)
RETURNS SETOF UUID
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT cc.customer_id
  FROM public.customer_contacts cc
  JOIN public.customers c ON c.id = cc.customer_id
  WHERE cc.user_id = auth.uid()
    AND c.workspace_id = workspace_uuid
    AND cc.restricted_property_id IS NULL;
$$;

-- ==========================================================================
-- 2. New scope helper, mirrors current_portal_customer_ids but for the
--    property path.
-- ==========================================================================
CREATE OR REPLACE FUNCTION public.current_portal_property_ids(workspace_uuid UUID)
RETURNS SETOF UUID
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT cc.restricted_property_id
  FROM public.customer_contacts cc
  JOIN public.properties p ON p.id = cc.restricted_property_id
  WHERE cc.user_id = auth.uid()
    AND cc.restricted_property_id IS NOT NULL
    AND p.workspace_id = workspace_uuid;
$$;

REVOKE ALL ON FUNCTION public.current_portal_property_ids(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.current_portal_property_ids(UUID) TO authenticated;

COMMENT ON FUNCTION public.current_portal_property_ids(UUID) IS
  'Returns the property id(s) the current auth user is restricted to as a unit holder, in the given workspace.';

-- ==========================================================================
-- 3. OR-in property-restricted access on the three tables a unit holder is
--    actually allowed to see. (No changes needed to customers, projects,
--    invoices, change_orders, generated_documents, customer_contacts — those
--    stay customer-wide-only and are now correctly closed to a
--    property-restricted contact by change #1 above, since
--    is_external_portal_user() is still TRUE for them.)
-- ==========================================================================
DROP POLICY IF EXISTS properties_select ON public.properties;
CREATE POLICY properties_select ON public.properties
  FOR SELECT USING (
    public.has_workspace_module_permission(workspace_id, 'properties', 'read')
    AND (
      NOT public.is_external_portal_user(workspace_id)
      OR EXISTS (
        SELECT 1 FROM public.projects p
        WHERE p.id = properties.project_id
          AND p.client_id IN (SELECT public.current_portal_customer_ids(workspace_id))
      )
      OR properties.id IN (SELECT public.current_portal_property_ids(workspace_id))
    )
  );

DO $$
BEGIN
  EXECUTE 'DROP POLICY IF EXISTS areas_select ON public.areas';
  EXECUTE $policy$
    CREATE POLICY areas_select ON public.areas
      FOR SELECT USING (
        public.has_workspace_module_permission(workspace_id, 'properties', 'read')
        AND (
          NOT public.is_external_portal_user(workspace_id)
          OR EXISTS (
            SELECT 1 FROM public.projects p
            WHERE p.id = areas.project_id
              AND p.client_id IN (SELECT public.current_portal_customer_ids(workspace_id))
          )
          OR areas.property_id IN (SELECT public.current_portal_property_ids(workspace_id))
        )
      )
  $policy$;
END $$;

DROP POLICY IF EXISTS property_contents_select ON public.property_contents;
CREATE POLICY property_contents_select ON public.property_contents
  FOR SELECT USING (
    public.has_workspace_module_permission(workspace_id, 'properties', 'read')
    AND (
      NOT public.is_external_portal_user(workspace_id)
      OR EXISTS (
        SELECT 1 FROM public.projects p
        WHERE p.id = property_contents.project_id
          AND p.client_id IN (SELECT public.current_portal_customer_ids(workspace_id))
      )
      OR property_contents.property_id IN (SELECT public.current_portal_property_ids(workspace_id))
    )
  );

-- property_notes is intentionally NOT exposed to the portal here.
-- property_notes.author_id is NOT NULL REFERENCES users(id), which would
-- need loosening to support external (portal) authorship — unnecessary
-- scope for this feature. Unit-holder-authored content lives in its own
-- property_issues table instead (see 20260612110000_add_property_issues.sql).
