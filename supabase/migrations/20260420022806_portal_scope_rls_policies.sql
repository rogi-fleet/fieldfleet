-- Scope read policies for portal-visible tables so Customer and Vendor
-- portal users only see rows tied to their linked entity. Internal users
-- (anyone not in role IN ('client','vendor')) keep their module-permission
-- level of access.
--
-- Pattern per table:
--   has_workspace_module_permission(..., 'read')
--   AND (
--     NOT is_external_portal_user(workspace_id)   -- internal: all rows
--     OR <row-scoped portal predicate>            -- portal: only their rows
--   )
--
-- Write policies are not modified unless a portal flow explicitly needs to
-- mutate (currently: Vendor updating bid_requests to submit responses).

-- ==========================================================================
-- CUSTOMERS → portal customer sees only their own row
-- ==========================================================================
DROP POLICY IF EXISTS customers_select ON public.customers;
CREATE POLICY customers_select ON public.customers
  FOR SELECT USING (
    public.has_workspace_module_permission(workspace_id, 'customers', 'read')
    AND (
      NOT public.is_external_portal_user(workspace_id)
      OR id IN (SELECT public.current_portal_customer_ids(workspace_id))
    )
  );

DROP POLICY IF EXISTS customer_contacts_select ON public.customer_contacts;
CREATE POLICY customer_contacts_select ON public.customer_contacts
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.customers c
      WHERE c.id = customer_id
        AND public.has_workspace_module_permission(c.workspace_id, 'customers', 'read')
        AND (
          NOT public.is_external_portal_user(c.workspace_id)
          OR c.id IN (SELECT public.current_portal_customer_ids(c.workspace_id))
        )
    )
  );

-- ==========================================================================
-- VENDORS → portal vendor sees only their own row
-- ==========================================================================
DROP POLICY IF EXISTS vendors_select ON public.vendors;
CREATE POLICY vendors_select ON public.vendors
  FOR SELECT USING (
    public.has_workspace_module_permission(workspace_id, 'vendors', 'read')
    AND (
      NOT public.is_external_portal_user(workspace_id)
      OR id IN (SELECT public.current_portal_vendor_ids(workspace_id))
    )
  );

DROP POLICY IF EXISTS vendor_contacts_select ON public.vendor_contacts;
CREATE POLICY vendor_contacts_select ON public.vendor_contacts
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.vendors v
      WHERE v.id = vendor_id
        AND public.has_workspace_module_permission(v.workspace_id, 'vendors', 'read')
        AND (
          NOT public.is_external_portal_user(v.workspace_id)
          OR v.id IN (SELECT public.current_portal_vendor_ids(v.workspace_id))
        )
    )
  );

-- ==========================================================================
-- PROJECTS → portal customer sees projects linked to their customer
-- ==========================================================================
DROP POLICY IF EXISTS projects_select ON public.projects;
CREATE POLICY projects_select ON public.projects
  FOR SELECT USING (
    public.has_workspace_module_permission(workspace_id, 'projects', 'read')
    AND (
      NOT public.is_external_portal_user(workspace_id)
      OR client_id IN (SELECT public.current_portal_customer_ids(workspace_id))
    )
  );

-- ==========================================================================
-- INVOICES → portal customer sees invoices for projects linked to them
-- ==========================================================================
DROP POLICY IF EXISTS invoices_select ON public.invoices;
CREATE POLICY invoices_select ON public.invoices
  FOR SELECT USING (
    public.has_workspace_module_permission(workspace_id, 'customer_invoices', 'read')
    AND (
      NOT public.is_external_portal_user(workspace_id)
      OR EXISTS (
        SELECT 1 FROM public.projects p
        WHERE p.id = invoices.project_id
          AND p.client_id IN (SELECT public.current_portal_customer_ids(workspace_id))
      )
    )
  );

-- ==========================================================================
-- CHANGE ORDERS → portal customer sees change orders for their projects
-- ==========================================================================
DROP POLICY IF EXISTS change_orders_select ON public.change_orders;
CREATE POLICY change_orders_select ON public.change_orders
  FOR SELECT USING (
    public.has_workspace_module_permission(workspace_id, 'change_orders', 'read')
    AND (
      NOT public.is_external_portal_user(workspace_id)
      OR EXISTS (
        SELECT 1 FROM public.projects p
        WHERE p.id = change_orders.project_id
          AND p.client_id IN (SELECT public.current_portal_customer_ids(workspace_id))
      )
    )
  );

-- ==========================================================================
-- PROPERTIES / AREAS / DRYING / CONTENTS → customer-scoped through project
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
    )
  );

-- ==========================================================================
-- BID REQUESTS → vendor portal sees requests assigned to them, and can
-- update them (to submit a response). Create/delete remain internal-only.
-- ==========================================================================
DROP POLICY IF EXISTS bid_requests_select ON public.bid_requests;
CREATE POLICY bid_requests_select ON public.bid_requests
  FOR SELECT USING (
    public.has_workspace_module_permission(workspace_id, 'bid_requests', 'read')
    AND (
      NOT public.is_external_portal_user(workspace_id)
      OR vendor_id IN (SELECT public.current_portal_vendor_ids(workspace_id))
    )
  );

DROP POLICY IF EXISTS bid_requests_update ON public.bid_requests;
CREATE POLICY bid_requests_update ON public.bid_requests
  FOR UPDATE USING (
    public.has_workspace_module_permission(workspace_id, 'bid_requests', 'write')
    AND (
      NOT public.is_external_portal_user(workspace_id)
      OR vendor_id IN (SELECT public.current_portal_vendor_ids(workspace_id))
    )
  )
  WITH CHECK (
    public.has_workspace_module_permission(workspace_id, 'bid_requests', 'write')
    AND (
      NOT public.is_external_portal_user(workspace_id)
      OR vendor_id IN (SELECT public.current_portal_vendor_ids(workspace_id))
    )
  );

-- ==========================================================================
-- BILLS → vendor portal sees bills they are the vendor on
-- ==========================================================================
DROP POLICY IF EXISTS bills_select ON public.bills;
CREATE POLICY bills_select ON public.bills
  FOR SELECT USING (
    public.has_workspace_module_permission(workspace_id, 'vendor_bills', 'read')
    AND (
      NOT public.is_external_portal_user(workspace_id)
      OR vendor_id IN (SELECT public.current_portal_vendor_ids(workspace_id))
    )
  );

-- ==========================================================================
-- PURCHASE ORDERS → vendor portal sees POs they are the vendor on
-- ==========================================================================
DROP POLICY IF EXISTS purchase_orders_select ON public.purchase_orders;
CREATE POLICY purchase_orders_select ON public.purchase_orders
  FOR SELECT USING (
    public.has_workspace_module_permission(workspace_id, 'vendor_bills', 'read')
    AND (
      NOT public.is_external_portal_user(workspace_id)
      OR vendor_id IN (SELECT public.current_portal_vendor_ids(workspace_id))
    )
  );
