-- Split RLS policies onto their dedicated permission keys so the new module
-- toggles (properties, time_tracking, customer_invoices, vendor_bills,
-- change_orders, bid_requests, customers, vendors) actually enforce.
--
-- Previously every financial table was gated by the single `budget` key and
-- every project-adjacent table by `projects`. That meant a role template
-- with "Vendor Bills: None" didn't actually block vendor bill access — the
-- underlying RLS still asked for `budget: read`.
--
-- This migration rewires each table's SELECT/INSERT/UPDATE/DELETE policies
-- onto the per-module key. Admin still bypasses every check via the
-- is_admin/master_admin branch inside workspace_member_module_level.

-- ==========================================================================
-- PROPERTIES group → `properties` key
-- ==========================================================================
DROP POLICY IF EXISTS properties_select ON public.properties;
CREATE POLICY properties_select ON public.properties
  FOR SELECT USING (public.has_workspace_module_permission(workspace_id, 'properties', 'read'));
DROP POLICY IF EXISTS properties_insert ON public.properties;
CREATE POLICY properties_insert ON public.properties
  FOR INSERT WITH CHECK (public.has_workspace_module_permission(workspace_id, 'properties', 'write'));
DROP POLICY IF EXISTS properties_update ON public.properties;
CREATE POLICY properties_update ON public.properties
  FOR UPDATE USING (public.has_workspace_module_permission(workspace_id, 'properties', 'write'))
  WITH CHECK (public.has_workspace_module_permission(workspace_id, 'properties', 'write'));
DROP POLICY IF EXISTS properties_delete ON public.properties;
CREATE POLICY properties_delete ON public.properties
  FOR DELETE USING (public.has_workspace_module_permission(workspace_id, 'properties', 'write'));

DROP POLICY IF EXISTS areas_select ON public.areas;
CREATE POLICY areas_select ON public.areas
  FOR SELECT USING (public.has_workspace_module_permission(workspace_id, 'properties', 'read'));
DROP POLICY IF EXISTS areas_insert ON public.areas;
CREATE POLICY areas_insert ON public.areas
  FOR INSERT WITH CHECK (public.has_workspace_module_permission(workspace_id, 'properties', 'write'));
DROP POLICY IF EXISTS areas_update ON public.areas;
CREATE POLICY areas_update ON public.areas
  FOR UPDATE USING (public.has_workspace_module_permission(workspace_id, 'properties', 'write'))
  WITH CHECK (public.has_workspace_module_permission(workspace_id, 'properties', 'write'));
DROP POLICY IF EXISTS areas_delete ON public.areas;
CREATE POLICY areas_delete ON public.areas
  FOR DELETE USING (public.has_workspace_module_permission(workspace_id, 'properties', 'write'));

DROP POLICY IF EXISTS property_contents_select ON public.property_contents;
CREATE POLICY property_contents_select ON public.property_contents
  FOR SELECT USING (public.has_workspace_module_permission(workspace_id, 'properties', 'read'));
DROP POLICY IF EXISTS property_contents_insert ON public.property_contents;
CREATE POLICY property_contents_insert ON public.property_contents
  FOR INSERT WITH CHECK (public.has_workspace_module_permission(workspace_id, 'properties', 'write'));
DROP POLICY IF EXISTS property_contents_update ON public.property_contents;
CREATE POLICY property_contents_update ON public.property_contents
  FOR UPDATE USING (public.has_workspace_module_permission(workspace_id, 'properties', 'write'))
  WITH CHECK (public.has_workspace_module_permission(workspace_id, 'properties', 'write'));
DROP POLICY IF EXISTS property_contents_delete ON public.property_contents;
CREATE POLICY property_contents_delete ON public.property_contents
  FOR DELETE USING (public.has_workspace_module_permission(workspace_id, 'properties', 'write'));

-- ==========================================================================
-- CUSTOMERS → `customers` key
-- ==========================================================================
DROP POLICY IF EXISTS customers_select ON public.customers;
CREATE POLICY customers_select ON public.customers
  FOR SELECT USING (public.has_workspace_module_permission(workspace_id, 'customers', 'read'));
DROP POLICY IF EXISTS customers_insert ON public.customers;
CREATE POLICY customers_insert ON public.customers
  FOR INSERT WITH CHECK (public.has_workspace_module_permission(workspace_id, 'customers', 'write'));
DROP POLICY IF EXISTS customers_update ON public.customers;
CREATE POLICY customers_update ON public.customers
  FOR UPDATE USING (public.has_workspace_module_permission(workspace_id, 'customers', 'write'))
  WITH CHECK (public.has_workspace_module_permission(workspace_id, 'customers', 'write'));
-- customers_delete keeps is_workspace_admin — deleting a customer is high-stakes.

DROP POLICY IF EXISTS customer_contacts_select ON public.customer_contacts;
CREATE POLICY customer_contacts_select ON public.customer_contacts
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.customers c
      WHERE c.id = customer_id
        AND public.has_workspace_module_permission(c.workspace_id, 'customers', 'read')
    )
  );
DROP POLICY IF EXISTS customer_contacts_insert ON public.customer_contacts;
CREATE POLICY customer_contacts_insert ON public.customer_contacts
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.customers c
      WHERE c.id = customer_id
        AND public.has_workspace_module_permission(c.workspace_id, 'customers', 'write')
    )
  );
DROP POLICY IF EXISTS customer_contacts_update ON public.customer_contacts;
CREATE POLICY customer_contacts_update ON public.customer_contacts
  FOR UPDATE USING (
    EXISTS (
      SELECT 1 FROM public.customers c
      WHERE c.id = customer_id
        AND public.has_workspace_module_permission(c.workspace_id, 'customers', 'write')
    )
  );
DROP POLICY IF EXISTS customer_contacts_delete ON public.customer_contacts;
CREATE POLICY customer_contacts_delete ON public.customer_contacts
  FOR DELETE USING (
    EXISTS (
      SELECT 1 FROM public.customers c
      WHERE c.id = customer_id
        AND public.has_workspace_module_permission(c.workspace_id, 'customers', 'write')
    )
  );

-- ==========================================================================
-- VENDORS → `vendors` key
-- ==========================================================================
DROP POLICY IF EXISTS vendors_select ON public.vendors;
CREATE POLICY vendors_select ON public.vendors
  FOR SELECT USING (public.has_workspace_module_permission(workspace_id, 'vendors', 'read'));
DROP POLICY IF EXISTS vendors_insert ON public.vendors;
CREATE POLICY vendors_insert ON public.vendors
  FOR INSERT WITH CHECK (public.has_workspace_module_permission(workspace_id, 'vendors', 'write'));
DROP POLICY IF EXISTS vendors_update ON public.vendors;
CREATE POLICY vendors_update ON public.vendors
  FOR UPDATE USING (public.has_workspace_module_permission(workspace_id, 'vendors', 'write'))
  WITH CHECK (public.has_workspace_module_permission(workspace_id, 'vendors', 'write'));

DROP POLICY IF EXISTS vendor_contacts_select ON public.vendor_contacts;
CREATE POLICY vendor_contacts_select ON public.vendor_contacts
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.vendors v
      WHERE v.id = vendor_id
        AND public.has_workspace_module_permission(v.workspace_id, 'vendors', 'read')
    )
  );
DROP POLICY IF EXISTS vendor_contacts_insert ON public.vendor_contacts;
CREATE POLICY vendor_contacts_insert ON public.vendor_contacts
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.vendors v
      WHERE v.id = vendor_id
        AND public.has_workspace_module_permission(v.workspace_id, 'vendors', 'write')
    )
  );
DROP POLICY IF EXISTS vendor_contacts_update ON public.vendor_contacts;
CREATE POLICY vendor_contacts_update ON public.vendor_contacts
  FOR UPDATE USING (
    EXISTS (
      SELECT 1 FROM public.vendors v
      WHERE v.id = vendor_id
        AND public.has_workspace_module_permission(v.workspace_id, 'vendors', 'write')
    )
  );
DROP POLICY IF EXISTS vendor_contacts_delete ON public.vendor_contacts;
CREATE POLICY vendor_contacts_delete ON public.vendor_contacts
  FOR DELETE USING (
    EXISTS (
      SELECT 1 FROM public.vendors v
      WHERE v.id = vendor_id
        AND public.has_workspace_module_permission(v.workspace_id, 'vendors', 'write')
    )
  );

-- ==========================================================================
-- INVOICES → `customer_invoices` key
-- ==========================================================================
DROP POLICY IF EXISTS invoices_select ON public.invoices;
CREATE POLICY invoices_select ON public.invoices
  FOR SELECT USING (public.has_workspace_module_permission(workspace_id, 'customer_invoices', 'read'));
DROP POLICY IF EXISTS invoices_insert ON public.invoices;
CREATE POLICY invoices_insert ON public.invoices
  FOR INSERT WITH CHECK (public.has_workspace_module_permission(workspace_id, 'customer_invoices', 'write'));
DROP POLICY IF EXISTS invoices_update ON public.invoices;
CREATE POLICY invoices_update ON public.invoices
  FOR UPDATE USING (public.has_workspace_module_permission(workspace_id, 'customer_invoices', 'write'))
  WITH CHECK (public.has_workspace_module_permission(workspace_id, 'customer_invoices', 'write'));
DROP POLICY IF EXISTS invoices_delete ON public.invoices;
CREATE POLICY invoices_delete ON public.invoices
  FOR DELETE USING (public.has_workspace_module_permission(workspace_id, 'customer_invoices', 'write'));

-- ==========================================================================
-- BILLS + PURCHASE ORDERS → `vendor_bills` key
-- ==========================================================================
DROP POLICY IF EXISTS bills_select ON public.bills;
CREATE POLICY bills_select ON public.bills
  FOR SELECT USING (public.has_workspace_module_permission(workspace_id, 'vendor_bills', 'read'));
DROP POLICY IF EXISTS bills_insert ON public.bills;
CREATE POLICY bills_insert ON public.bills
  FOR INSERT WITH CHECK (public.has_workspace_module_permission(workspace_id, 'vendor_bills', 'write'));
DROP POLICY IF EXISTS bills_update ON public.bills;
CREATE POLICY bills_update ON public.bills
  FOR UPDATE USING (public.has_workspace_module_permission(workspace_id, 'vendor_bills', 'write'))
  WITH CHECK (public.has_workspace_module_permission(workspace_id, 'vendor_bills', 'write'));
DROP POLICY IF EXISTS bills_delete ON public.bills;
CREATE POLICY bills_delete ON public.bills
  FOR DELETE USING (public.has_workspace_module_permission(workspace_id, 'vendor_bills', 'write'));

DROP POLICY IF EXISTS purchase_orders_select ON public.purchase_orders;
CREATE POLICY purchase_orders_select ON public.purchase_orders
  FOR SELECT USING (public.has_workspace_module_permission(workspace_id, 'vendor_bills', 'read'));
DROP POLICY IF EXISTS purchase_orders_insert ON public.purchase_orders;
CREATE POLICY purchase_orders_insert ON public.purchase_orders
  FOR INSERT WITH CHECK (public.has_workspace_module_permission(workspace_id, 'vendor_bills', 'write'));
DROP POLICY IF EXISTS purchase_orders_update ON public.purchase_orders;
CREATE POLICY purchase_orders_update ON public.purchase_orders
  FOR UPDATE USING (public.has_workspace_module_permission(workspace_id, 'vendor_bills', 'write'))
  WITH CHECK (public.has_workspace_module_permission(workspace_id, 'vendor_bills', 'write'));
DROP POLICY IF EXISTS purchase_orders_delete ON public.purchase_orders;
CREATE POLICY purchase_orders_delete ON public.purchase_orders
  FOR DELETE USING (public.has_workspace_module_permission(workspace_id, 'vendor_bills', 'write'));

-- ==========================================================================
-- CHANGE ORDERS → `change_orders` key
-- ==========================================================================
DROP POLICY IF EXISTS change_orders_select ON public.change_orders;
CREATE POLICY change_orders_select ON public.change_orders
  FOR SELECT USING (public.has_workspace_module_permission(workspace_id, 'change_orders', 'read'));
DROP POLICY IF EXISTS change_orders_insert ON public.change_orders;
CREATE POLICY change_orders_insert ON public.change_orders
  FOR INSERT WITH CHECK (public.has_workspace_module_permission(workspace_id, 'change_orders', 'write'));
DROP POLICY IF EXISTS change_orders_update ON public.change_orders;
CREATE POLICY change_orders_update ON public.change_orders
  FOR UPDATE USING (public.has_workspace_module_permission(workspace_id, 'change_orders', 'write'))
  WITH CHECK (public.has_workspace_module_permission(workspace_id, 'change_orders', 'write'));
DROP POLICY IF EXISTS change_orders_delete ON public.change_orders;
CREATE POLICY change_orders_delete ON public.change_orders
  FOR DELETE USING (public.has_workspace_module_permission(workspace_id, 'change_orders', 'write'));

-- ==========================================================================
-- BID REQUESTS → `bid_requests` key (critical: Vendor role needs write access
-- without touching the budget/financials surface)
-- ==========================================================================
DROP POLICY IF EXISTS bid_requests_select ON public.bid_requests;
CREATE POLICY bid_requests_select ON public.bid_requests
  FOR SELECT USING (public.has_workspace_module_permission(workspace_id, 'bid_requests', 'read'));
DROP POLICY IF EXISTS bid_requests_insert ON public.bid_requests;
CREATE POLICY bid_requests_insert ON public.bid_requests
  FOR INSERT WITH CHECK (public.has_workspace_module_permission(workspace_id, 'bid_requests', 'write'));
DROP POLICY IF EXISTS bid_requests_update ON public.bid_requests;
CREATE POLICY bid_requests_update ON public.bid_requests
  FOR UPDATE USING (public.has_workspace_module_permission(workspace_id, 'bid_requests', 'write'))
  WITH CHECK (public.has_workspace_module_permission(workspace_id, 'bid_requests', 'write'));
DROP POLICY IF EXISTS bid_requests_delete ON public.bid_requests;
CREATE POLICY bid_requests_delete ON public.bid_requests
  FOR DELETE USING (public.has_workspace_module_permission(workspace_id, 'bid_requests', 'write'));

-- ==========================================================================
-- TIME ENTRIES → add `time_tracking` key alongside existing worker-centric
-- policy. Everyone can still read their own rows; PMs and admins with the
-- time_tracking module can read the team. Mutations require time_tracking
-- write OR the owner + draft rule.
-- ==========================================================================
DROP POLICY IF EXISTS time_entries_select ON public.time_entries;
CREATE POLICY time_entries_select ON public.time_entries
  FOR SELECT USING (
    worker_id = auth.uid()
    OR public.has_workspace_module_permission(workspace_id, 'time_tracking', 'read')
  );

DROP POLICY IF EXISTS time_entries_insert ON public.time_entries;
CREATE POLICY time_entries_insert ON public.time_entries
  FOR INSERT WITH CHECK (
    public.is_workspace_member(workspace_id)
    AND (
      worker_id = auth.uid()
      OR public.has_workspace_module_permission(workspace_id, 'time_tracking', 'write')
    )
  );

DROP POLICY IF EXISTS time_entries_update ON public.time_entries;
CREATE POLICY time_entries_update ON public.time_entries
  FOR UPDATE USING (
    (worker_id = auth.uid() AND status = 'draft'::time_entry_status)
    OR public.has_workspace_module_permission(workspace_id, 'time_tracking', 'write')
  );

DROP POLICY IF EXISTS time_entries_delete ON public.time_entries;
CREATE POLICY time_entries_delete ON public.time_entries
  FOR DELETE USING (
    (worker_id = auth.uid() AND status = 'draft'::time_entry_status)
    OR public.has_workspace_module_permission(workspace_id, 'time_tracking', 'write')
  );
