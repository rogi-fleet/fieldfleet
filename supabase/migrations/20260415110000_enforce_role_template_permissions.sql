-- Enforce workspace role template module permissions at the database boundary.
-- The UI uses the same none/read/write model; RLS must not rely on hidden
-- buttons for authorization.

CREATE OR REPLACE FUNCTION public.permission_level_rank(level TEXT)
RETURNS INTEGER
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE lower(coalesce(level, 'none'))
    WHEN 'write' THEN 2
    WHEN 'read' THEN 1
    ELSE 0
  END;
$$;

CREATE OR REPLACE FUNCTION public.workspace_member_module_level(
  workspace_uuid UUID,
  module_key TEXT
)
RETURNS TEXT
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  resolved_level TEXT;
BEGIN
  SELECT CASE
    WHEN wm.role = 'admin' OR coalesce(wrt.is_admin, FALSE) THEN 'write'
    ELSE coalesce(
      wrt.module_permissions ->> lower(module_key),
      wm.module_permissions ->> lower(module_key),
      CASE lower(module_key)
        WHEN 'projects' THEN CASE wm.role
          WHEN 'admin' THEN 'write'
          WHEN 'project_manager' THEN 'write'
          WHEN 'field_technician' THEN 'read'
          WHEN 'client' THEN 'read'
          ELSE 'none'
        END
        WHEN 'tasks' THEN CASE wm.role
          WHEN 'admin' THEN 'write'
          WHEN 'project_manager' THEN 'write'
          WHEN 'field_technician' THEN 'write'
          ELSE 'none'
        END
        WHEN 'budget' THEN CASE wm.role
          WHEN 'admin' THEN 'write'
          WHEN 'project_manager' THEN 'write'
          ELSE 'none'
        END
        WHEN 'documents' THEN CASE wm.role
          WHEN 'admin' THEN 'write'
          WHEN 'project_manager' THEN 'write'
          WHEN 'field_technician' THEN 'read'
          WHEN 'client' THEN 'read'
          ELSE 'none'
        END
        WHEN 'team' THEN CASE wm.role
          WHEN 'admin' THEN 'write'
          WHEN 'project_manager' THEN 'write'
          WHEN 'field_technician' THEN 'read'
          ELSE 'none'
        END
        WHEN 'settings' THEN CASE wm.role
          WHEN 'admin' THEN 'write'
          WHEN 'project_manager' THEN 'read'
          ELSE 'none'
        END
        ELSE 'none'
      END
    )
  END
  INTO resolved_level
  FROM public.workspace_members wm
  LEFT JOIN public.workspace_role_templates wrt ON wrt.id = wm.role_template_id
  WHERE wm.workspace_id = workspace_uuid
    AND wm.user_id = auth.uid()
  LIMIT 1;

  RETURN coalesce(resolved_level, 'none');
END;
$$;

CREATE OR REPLACE FUNCTION public.has_workspace_module_permission(
  workspace_uuid UUID,
  module_key TEXT,
  required_level TEXT
)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.permission_level_rank(
    public.workspace_member_module_level(workspace_uuid, module_key)
  ) >= public.permission_level_rank(required_level);
$$;

CREATE OR REPLACE FUNCTION public.is_workspace_admin(workspace_uuid UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1
    FROM public.workspace_members wm
    LEFT JOIN public.workspace_role_templates wrt ON wrt.id = wm.role_template_id
    WHERE wm.workspace_id = workspace_uuid
      AND wm.user_id = auth.uid()
      AND (wm.role = 'admin' OR coalesce(wrt.is_admin, FALSE))
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.is_pm_or_admin(workspace_uuid UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.has_workspace_module_permission(workspace_uuid, 'projects', 'write')
    OR public.is_workspace_admin(workspace_uuid);
$$;

UPDATE public.workspace_role_templates
SET module_permissions = module_permissions || jsonb_build_object(
  'tasks',
  CASE role
    WHEN 'admin' THEN 'write'
    WHEN 'project_manager' THEN 'write'
    WHEN 'field_technician' THEN 'write'
    ELSE 'none'
  END,
  'projects',
  CASE role
    WHEN 'admin' THEN 'write'
    WHEN 'project_manager' THEN 'write'
    WHEN 'field_technician' THEN 'read'
    WHEN 'client' THEN 'read'
    ELSE coalesce(module_permissions ->> 'projects', 'none')
  END
)
WHERE NOT module_permissions ? 'tasks'
   OR role = 'field_technician';

UPDATE public.workspace_members
SET module_permissions = module_permissions || jsonb_build_object(
  'tasks',
  CASE role
    WHEN 'admin' THEN 'write'
    WHEN 'project_manager' THEN 'write'
    WHEN 'field_technician' THEN 'write'
    ELSE 'none'
  END,
  'projects',
  CASE role
    WHEN 'admin' THEN 'write'
    WHEN 'project_manager' THEN 'write'
    WHEN 'field_technician' THEN 'read'
    WHEN 'client' THEN 'read'
    ELSE coalesce(module_permissions ->> 'projects', 'none')
  END
)
WHERE module_permissions IS NOT NULL
  AND (NOT module_permissions ? 'tasks' OR role = 'field_technician');

CREATE OR REPLACE FUNCTION public.seed_default_workspace_role_templates(
  p_workspace_id UUID,
  p_created_by UUID DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
  INSERT INTO public.workspace_role_templates (
    workspace_id,
    name,
    role,
    module_permissions,
    is_system,
    is_admin,
    default_interface_mode,
    description,
    created_by
  )
  VALUES
    (
      p_workspace_id,
      'Admin',
      'admin',
      '{"projects":"write","tasks":"write","budget":"write","documents":"write","team":"write","settings":"write"}'::jsonb,
      TRUE,
      TRUE,
      'manager',
      'Full access to all features and settings',
      p_created_by
    ),
    (
      p_workspace_id,
      'Project Manager',
      'project_manager',
      '{"projects":"write","tasks":"write","budget":"write","documents":"write","team":"write","settings":"read"}'::jsonb,
      TRUE,
      FALSE,
      'manager',
      'Manage projects, budgets, and team members',
      p_created_by
    ),
    (
      p_workspace_id,
      'Field Technician',
      'field_technician',
      '{"projects":"read","tasks":"write","budget":"none","documents":"read","team":"read","settings":"none"}'::jsonb,
      TRUE,
      FALSE,
      'field',
      'Field work, time tracking, and assigned tasks',
      p_created_by
    ),
    (
      p_workspace_id,
      'Client',
      'client',
      '{"projects":"read","tasks":"none","budget":"none","documents":"read","team":"none","settings":"none"}'::jsonb,
      TRUE,
      FALSE,
      'manager',
      'Read-only access to shared project information',
      p_created_by
    )
  ON CONFLICT (workspace_id, name) DO NOTHING;
END;
$$;

-- Workspace member directory: every member can read their own row; team access
-- is required to browse the rest of the workspace directory.
DROP POLICY IF EXISTS workspace_members_select ON public.workspace_members;
CREATE POLICY workspace_members_select ON public.workspace_members
  FOR SELECT USING (
    user_id = auth.uid()
    OR public.has_workspace_module_permission(workspace_id, 'team', 'read')
  );

DROP POLICY IF EXISTS workspace_members_insert ON public.workspace_members;
CREATE POLICY workspace_members_insert ON public.workspace_members
  FOR INSERT WITH CHECK (
    public.is_workspace_admin(workspace_id)
    OR (user_id = auth.uid() AND role = 'admin')
  );

DROP POLICY IF EXISTS workspace_members_update ON public.workspace_members;
CREATE POLICY workspace_members_update ON public.workspace_members
  FOR UPDATE USING (public.is_workspace_admin(workspace_id))
  WITH CHECK (public.is_workspace_admin(workspace_id));

DROP POLICY IF EXISTS workspace_members_delete ON public.workspace_members;
CREATE POLICY workspace_members_delete ON public.workspace_members
  FOR DELETE USING (public.is_workspace_admin(workspace_id));

-- Projects and CRM/customer records.
DROP POLICY IF EXISTS projects_select ON public.projects;
CREATE POLICY projects_select ON public.projects
  FOR SELECT USING (public.has_workspace_module_permission(workspace_id, 'projects', 'read'));
DROP POLICY IF EXISTS projects_insert ON public.projects;
CREATE POLICY projects_insert ON public.projects
  FOR INSERT WITH CHECK (public.has_workspace_module_permission(workspace_id, 'projects', 'write'));
DROP POLICY IF EXISTS projects_update ON public.projects;
CREATE POLICY projects_update ON public.projects
  FOR UPDATE USING (public.has_workspace_module_permission(workspace_id, 'projects', 'write'))
  WITH CHECK (public.has_workspace_module_permission(workspace_id, 'projects', 'write'));
DROP POLICY IF EXISTS projects_delete ON public.projects;
CREATE POLICY projects_delete ON public.projects
  FOR DELETE USING (public.is_workspace_admin(workspace_id));

DROP POLICY IF EXISTS customers_select ON public.customers;
CREATE POLICY customers_select ON public.customers
  FOR SELECT USING (public.has_workspace_module_permission(workspace_id, 'projects', 'read'));
DROP POLICY IF EXISTS customers_insert ON public.customers;
CREATE POLICY customers_insert ON public.customers
  FOR INSERT WITH CHECK (public.has_workspace_module_permission(workspace_id, 'projects', 'write'));
DROP POLICY IF EXISTS customers_update ON public.customers;
CREATE POLICY customers_update ON public.customers
  FOR UPDATE USING (public.has_workspace_module_permission(workspace_id, 'projects', 'write'))
  WITH CHECK (public.has_workspace_module_permission(workspace_id, 'projects', 'write'));
DROP POLICY IF EXISTS customers_delete ON public.customers;
CREATE POLICY customers_delete ON public.customers
  FOR DELETE USING (public.is_workspace_admin(workspace_id));

DROP POLICY IF EXISTS customer_contacts_select ON public.customer_contacts;
CREATE POLICY customer_contacts_select ON public.customer_contacts
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.customers c
      WHERE c.id = customer_id
        AND public.has_workspace_module_permission(c.workspace_id, 'projects', 'read')
    )
  );
DROP POLICY IF EXISTS customer_contacts_insert ON public.customer_contacts;
CREATE POLICY customer_contacts_insert ON public.customer_contacts
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.customers c
      WHERE c.id = customer_id
        AND public.has_workspace_module_permission(c.workspace_id, 'projects', 'write')
    )
  );
DROP POLICY IF EXISTS customer_contacts_update ON public.customer_contacts;
CREATE POLICY customer_contacts_update ON public.customer_contacts
  FOR UPDATE USING (
    EXISTS (
      SELECT 1 FROM public.customers c
      WHERE c.id = customer_id
        AND public.has_workspace_module_permission(c.workspace_id, 'projects', 'write')
    )
  );
DROP POLICY IF EXISTS customer_contacts_delete ON public.customer_contacts;
CREATE POLICY customer_contacts_delete ON public.customer_contacts
  FOR DELETE USING (
    EXISTS (
      SELECT 1 FROM public.customers c
      WHERE c.id = customer_id
        AND public.has_workspace_module_permission(c.workspace_id, 'projects', 'write')
    )
  );

-- Tasks and project execution.
DROP POLICY IF EXISTS tasks_select ON public.tasks;
CREATE POLICY tasks_select ON public.tasks
  FOR SELECT USING (public.has_workspace_module_permission(workspace_id, 'tasks', 'read'));
DROP POLICY IF EXISTS tasks_insert ON public.tasks;
CREATE POLICY tasks_insert ON public.tasks
  FOR INSERT WITH CHECK (public.has_workspace_module_permission(workspace_id, 'tasks', 'write'));
DROP POLICY IF EXISTS tasks_update ON public.tasks;
CREATE POLICY tasks_update ON public.tasks
  FOR UPDATE USING (public.has_workspace_module_permission(workspace_id, 'tasks', 'write'))
  WITH CHECK (public.has_workspace_module_permission(workspace_id, 'tasks', 'write'));
DROP POLICY IF EXISTS tasks_delete ON public.tasks;
CREATE POLICY tasks_delete ON public.tasks
  FOR DELETE USING (public.has_workspace_module_permission(workspace_id, 'tasks', 'write'));

DROP POLICY IF EXISTS task_assignees_select ON public.task_assignees;
CREATE POLICY task_assignees_select ON public.task_assignees
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.tasks t
      WHERE t.id = task_id
        AND public.has_workspace_module_permission(t.workspace_id, 'tasks', 'read')
    )
  );
DROP POLICY IF EXISTS task_assignees_insert ON public.task_assignees;
CREATE POLICY task_assignees_insert ON public.task_assignees
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.tasks t
      WHERE t.id = task_id
        AND public.has_workspace_module_permission(t.workspace_id, 'tasks', 'write')
    )
  );
DROP POLICY IF EXISTS task_assignees_delete ON public.task_assignees;
CREATE POLICY task_assignees_delete ON public.task_assignees
  FOR DELETE USING (
    EXISTS (
      SELECT 1 FROM public.tasks t
      WHERE t.id = task_id
        AND public.has_workspace_module_permission(t.workspace_id, 'tasks', 'write')
    )
  );

DROP POLICY IF EXISTS task_comments_select ON public.task_comments;
CREATE POLICY task_comments_select ON public.task_comments
  FOR SELECT USING (public.has_workspace_module_permission(workspace_id, 'tasks', 'read'));
DROP POLICY IF EXISTS task_comments_insert ON public.task_comments;
CREATE POLICY task_comments_insert ON public.task_comments
  FOR INSERT WITH CHECK (
    public.has_workspace_module_permission(workspace_id, 'tasks', 'read')
    AND sender_id = auth.uid()
  );
DROP POLICY IF EXISTS task_comments_update ON public.task_comments;
CREATE POLICY task_comments_update ON public.task_comments
  FOR UPDATE USING (
    sender_id = auth.uid()
    AND public.has_workspace_module_permission(workspace_id, 'tasks', 'read')
  );
DROP POLICY IF EXISTS task_comments_delete ON public.task_comments;
CREATE POLICY task_comments_delete ON public.task_comments
  FOR DELETE USING (
    sender_id = auth.uid()
    OR public.is_workspace_admin(workspace_id)
  );

-- Restoration properties are project execution data.
DROP POLICY IF EXISTS properties_select ON public.properties;
CREATE POLICY properties_select ON public.properties
  FOR SELECT USING (public.has_workspace_module_permission(workspace_id, 'projects', 'read'));
DROP POLICY IF EXISTS properties_insert ON public.properties;
CREATE POLICY properties_insert ON public.properties
  FOR INSERT WITH CHECK (public.has_workspace_module_permission(workspace_id, 'projects', 'write'));
DROP POLICY IF EXISTS properties_update ON public.properties;
CREATE POLICY properties_update ON public.properties
  FOR UPDATE USING (public.has_workspace_module_permission(workspace_id, 'projects', 'write'))
  WITH CHECK (public.has_workspace_module_permission(workspace_id, 'projects', 'write'));
DROP POLICY IF EXISTS properties_delete ON public.properties;
CREATE POLICY properties_delete ON public.properties
  FOR DELETE USING (public.has_workspace_module_permission(workspace_id, 'projects', 'write'));

DROP POLICY IF EXISTS areas_select ON public.areas;
CREATE POLICY areas_select ON public.areas
  FOR SELECT USING (public.has_workspace_module_permission(workspace_id, 'projects', 'read'));
DROP POLICY IF EXISTS areas_insert ON public.areas;
CREATE POLICY areas_insert ON public.areas
  FOR INSERT WITH CHECK (public.has_workspace_module_permission(workspace_id, 'projects', 'write'));
DROP POLICY IF EXISTS areas_update ON public.areas;
CREATE POLICY areas_update ON public.areas
  FOR UPDATE USING (public.has_workspace_module_permission(workspace_id, 'projects', 'write'))
  WITH CHECK (public.has_workspace_module_permission(workspace_id, 'projects', 'write'));
DROP POLICY IF EXISTS areas_delete ON public.areas;
CREATE POLICY areas_delete ON public.areas
  FOR DELETE USING (public.has_workspace_module_permission(workspace_id, 'projects', 'write'));

  FOR SELECT USING (public.has_workspace_module_permission(workspace_id, 'projects', 'read'));
  FOR INSERT WITH CHECK (public.has_workspace_module_permission(workspace_id, 'projects', 'write'));
  FOR UPDATE USING (public.has_workspace_module_permission(workspace_id, 'projects', 'write'))
  WITH CHECK (public.has_workspace_module_permission(workspace_id, 'projects', 'write'));
  FOR DELETE USING (public.has_workspace_module_permission(workspace_id, 'projects', 'write'));

DROP POLICY IF EXISTS property_contents_select ON public.property_contents;
CREATE POLICY property_contents_select ON public.property_contents
  FOR SELECT USING (public.has_workspace_module_permission(workspace_id, 'projects', 'read'));
DROP POLICY IF EXISTS property_contents_insert ON public.property_contents;
CREATE POLICY property_contents_insert ON public.property_contents
  FOR INSERT WITH CHECK (public.has_workspace_module_permission(workspace_id, 'projects', 'write'));
DROP POLICY IF EXISTS property_contents_update ON public.property_contents;
CREATE POLICY property_contents_update ON public.property_contents
  FOR UPDATE USING (public.has_workspace_module_permission(workspace_id, 'projects', 'write'))
  WITH CHECK (public.has_workspace_module_permission(workspace_id, 'projects', 'write'));
DROP POLICY IF EXISTS property_contents_delete ON public.property_contents;
CREATE POLICY property_contents_delete ON public.property_contents
  FOR DELETE USING (public.has_workspace_module_permission(workspace_id, 'projects', 'write'));

-- Financial and vendor records.
DROP POLICY IF EXISTS vendors_select ON public.vendors;
CREATE POLICY vendors_select ON public.vendors
  FOR SELECT USING (public.has_workspace_module_permission(workspace_id, 'budget', 'read'));
DROP POLICY IF EXISTS vendors_insert ON public.vendors;
CREATE POLICY vendors_insert ON public.vendors
  FOR INSERT WITH CHECK (public.has_workspace_module_permission(workspace_id, 'budget', 'write'));
DROP POLICY IF EXISTS vendors_update ON public.vendors;
CREATE POLICY vendors_update ON public.vendors
  FOR UPDATE USING (public.has_workspace_module_permission(workspace_id, 'budget', 'write'))
  WITH CHECK (public.has_workspace_module_permission(workspace_id, 'budget', 'write'));
DROP POLICY IF EXISTS vendors_delete ON public.vendors;
CREATE POLICY vendors_delete ON public.vendors
  FOR DELETE USING (public.is_workspace_admin(workspace_id));

DROP POLICY IF EXISTS vendor_contacts_select ON public.vendor_contacts;
CREATE POLICY vendor_contacts_select ON public.vendor_contacts
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.vendors v
      WHERE v.id = vendor_id
        AND public.has_workspace_module_permission(v.workspace_id, 'budget', 'read')
    )
  );
DROP POLICY IF EXISTS vendor_contacts_insert ON public.vendor_contacts;
CREATE POLICY vendor_contacts_insert ON public.vendor_contacts
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.vendors v
      WHERE v.id = vendor_id
        AND public.has_workspace_module_permission(v.workspace_id, 'budget', 'write')
    )
  );
DROP POLICY IF EXISTS vendor_contacts_update ON public.vendor_contacts;
CREATE POLICY vendor_contacts_update ON public.vendor_contacts
  FOR UPDATE USING (
    EXISTS (
      SELECT 1 FROM public.vendors v
      WHERE v.id = vendor_id
        AND public.has_workspace_module_permission(v.workspace_id, 'budget', 'write')
    )
  );
DROP POLICY IF EXISTS vendor_contacts_delete ON public.vendor_contacts;
CREATE POLICY vendor_contacts_delete ON public.vendor_contacts
  FOR DELETE USING (
    EXISTS (
      SELECT 1 FROM public.vendors v
      WHERE v.id = vendor_id
        AND public.has_workspace_module_permission(v.workspace_id, 'budget', 'write')
    )
  );

DROP POLICY IF EXISTS budget_items_select ON public.budget_items;
CREATE POLICY budget_items_select ON public.budget_items
  FOR SELECT USING (public.has_workspace_module_permission(workspace_id, 'budget', 'read'));
DROP POLICY IF EXISTS budget_items_insert ON public.budget_items;
CREATE POLICY budget_items_insert ON public.budget_items
  FOR INSERT WITH CHECK (public.has_workspace_module_permission(workspace_id, 'budget', 'write'));
DROP POLICY IF EXISTS budget_items_update ON public.budget_items;
CREATE POLICY budget_items_update ON public.budget_items
  FOR UPDATE USING (public.has_workspace_module_permission(workspace_id, 'budget', 'write'))
  WITH CHECK (public.has_workspace_module_permission(workspace_id, 'budget', 'write'));
DROP POLICY IF EXISTS budget_items_delete ON public.budget_items;
CREATE POLICY budget_items_delete ON public.budget_items
  FOR DELETE USING (public.has_workspace_module_permission(workspace_id, 'budget', 'write'));

DROP POLICY IF EXISTS cost_items_select ON public.cost_items;
CREATE POLICY cost_items_select ON public.cost_items
  FOR SELECT USING (public.has_workspace_module_permission(workspace_id, 'budget', 'read'));
DROP POLICY IF EXISTS cost_items_insert ON public.cost_items;
CREATE POLICY cost_items_insert ON public.cost_items
  FOR INSERT WITH CHECK (public.has_workspace_module_permission(workspace_id, 'budget', 'write'));
DROP POLICY IF EXISTS cost_items_update ON public.cost_items;
CREATE POLICY cost_items_update ON public.cost_items
  FOR UPDATE USING (public.has_workspace_module_permission(workspace_id, 'budget', 'write'))
  WITH CHECK (public.has_workspace_module_permission(workspace_id, 'budget', 'write'));
DROP POLICY IF EXISTS cost_items_delete ON public.cost_items;
CREATE POLICY cost_items_delete ON public.cost_items
  FOR DELETE USING (public.has_workspace_module_permission(workspace_id, 'budget', 'write'));

DROP POLICY IF EXISTS invoices_select ON public.invoices;
CREATE POLICY invoices_select ON public.invoices
  FOR SELECT USING (public.has_workspace_module_permission(workspace_id, 'budget', 'read'));
DROP POLICY IF EXISTS invoices_insert ON public.invoices;
CREATE POLICY invoices_insert ON public.invoices
  FOR INSERT WITH CHECK (public.has_workspace_module_permission(workspace_id, 'budget', 'write'));
DROP POLICY IF EXISTS invoices_update ON public.invoices;
CREATE POLICY invoices_update ON public.invoices
  FOR UPDATE USING (public.has_workspace_module_permission(workspace_id, 'budget', 'write'))
  WITH CHECK (public.has_workspace_module_permission(workspace_id, 'budget', 'write'));
DROP POLICY IF EXISTS invoices_delete ON public.invoices;
CREATE POLICY invoices_delete ON public.invoices
  FOR DELETE USING (public.has_workspace_module_permission(workspace_id, 'budget', 'write'));

DROP POLICY IF EXISTS bills_select ON public.bills;
CREATE POLICY bills_select ON public.bills
  FOR SELECT USING (public.has_workspace_module_permission(workspace_id, 'budget', 'read'));
DROP POLICY IF EXISTS bills_insert ON public.bills;
CREATE POLICY bills_insert ON public.bills
  FOR INSERT WITH CHECK (public.has_workspace_module_permission(workspace_id, 'budget', 'write'));
DROP POLICY IF EXISTS bills_update ON public.bills;
CREATE POLICY bills_update ON public.bills
  FOR UPDATE USING (public.has_workspace_module_permission(workspace_id, 'budget', 'write'))
  WITH CHECK (public.has_workspace_module_permission(workspace_id, 'budget', 'write'));
DROP POLICY IF EXISTS bills_delete ON public.bills;
CREATE POLICY bills_delete ON public.bills
  FOR DELETE USING (public.has_workspace_module_permission(workspace_id, 'budget', 'write'));

DROP POLICY IF EXISTS purchase_orders_select ON public.purchase_orders;
CREATE POLICY purchase_orders_select ON public.purchase_orders
  FOR SELECT USING (public.has_workspace_module_permission(workspace_id, 'budget', 'read'));
DROP POLICY IF EXISTS purchase_orders_insert ON public.purchase_orders;
CREATE POLICY purchase_orders_insert ON public.purchase_orders
  FOR INSERT WITH CHECK (public.has_workspace_module_permission(workspace_id, 'budget', 'write'));
DROP POLICY IF EXISTS purchase_orders_update ON public.purchase_orders;
CREATE POLICY purchase_orders_update ON public.purchase_orders
  FOR UPDATE USING (public.has_workspace_module_permission(workspace_id, 'budget', 'write'))
  WITH CHECK (public.has_workspace_module_permission(workspace_id, 'budget', 'write'));
DROP POLICY IF EXISTS purchase_orders_delete ON public.purchase_orders;
CREATE POLICY purchase_orders_delete ON public.purchase_orders
  FOR DELETE USING (public.has_workspace_module_permission(workspace_id, 'budget', 'write'));

DROP POLICY IF EXISTS change_orders_select ON public.change_orders;
CREATE POLICY change_orders_select ON public.change_orders
  FOR SELECT USING (public.has_workspace_module_permission(workspace_id, 'budget', 'read'));
DROP POLICY IF EXISTS change_orders_insert ON public.change_orders;
CREATE POLICY change_orders_insert ON public.change_orders
  FOR INSERT WITH CHECK (public.has_workspace_module_permission(workspace_id, 'budget', 'write'));
DROP POLICY IF EXISTS change_orders_update ON public.change_orders;
CREATE POLICY change_orders_update ON public.change_orders
  FOR UPDATE USING (public.has_workspace_module_permission(workspace_id, 'budget', 'write'))
  WITH CHECK (public.has_workspace_module_permission(workspace_id, 'budget', 'write'));
DROP POLICY IF EXISTS change_orders_delete ON public.change_orders;
CREATE POLICY change_orders_delete ON public.change_orders
  FOR DELETE USING (public.has_workspace_module_permission(workspace_id, 'budget', 'write'));

DROP POLICY IF EXISTS bid_requests_select ON public.bid_requests;
CREATE POLICY bid_requests_select ON public.bid_requests
  FOR SELECT USING (public.has_workspace_module_permission(workspace_id, 'budget', 'read'));
DROP POLICY IF EXISTS bid_requests_insert ON public.bid_requests;
CREATE POLICY bid_requests_insert ON public.bid_requests
  FOR INSERT WITH CHECK (public.has_workspace_module_permission(workspace_id, 'budget', 'write'));
DROP POLICY IF EXISTS bid_requests_update ON public.bid_requests;
CREATE POLICY bid_requests_update ON public.bid_requests
  FOR UPDATE USING (public.has_workspace_module_permission(workspace_id, 'budget', 'write'))
  WITH CHECK (public.has_workspace_module_permission(workspace_id, 'budget', 'write'));
DROP POLICY IF EXISTS bid_requests_delete ON public.bid_requests;
CREATE POLICY bid_requests_delete ON public.bid_requests
  FOR DELETE USING (public.has_workspace_module_permission(workspace_id, 'budget', 'write'));

DROP POLICY IF EXISTS refunds_select ON public.refunds;
CREATE POLICY refunds_select ON public.refunds
  FOR SELECT USING (public.has_workspace_module_permission(workspace_id, 'budget', 'read'));
DROP POLICY IF EXISTS refunds_insert ON public.refunds;
CREATE POLICY refunds_insert ON public.refunds
  FOR INSERT WITH CHECK (public.has_workspace_module_permission(workspace_id, 'budget', 'write'));
DROP POLICY IF EXISTS refunds_update ON public.refunds;
CREATE POLICY refunds_update ON public.refunds
  FOR UPDATE USING (public.has_workspace_module_permission(workspace_id, 'budget', 'write'))
  WITH CHECK (public.has_workspace_module_permission(workspace_id, 'budget', 'write'));
DROP POLICY IF EXISTS refunds_delete ON public.refunds;
CREATE POLICY refunds_delete ON public.refunds
  FOR DELETE USING (public.is_workspace_admin(workspace_id));

DROP POLICY IF EXISTS service_agreements_select ON public.service_agreements;
CREATE POLICY service_agreements_select ON public.service_agreements
  FOR SELECT USING (public.has_workspace_module_permission(workspace_id, 'budget', 'read'));
DROP POLICY IF EXISTS service_agreements_insert ON public.service_agreements;
CREATE POLICY service_agreements_insert ON public.service_agreements
  FOR INSERT WITH CHECK (public.has_workspace_module_permission(workspace_id, 'budget', 'write'));
DROP POLICY IF EXISTS service_agreements_update ON public.service_agreements;
CREATE POLICY service_agreements_update ON public.service_agreements
  FOR UPDATE USING (public.has_workspace_module_permission(workspace_id, 'budget', 'write'))
  WITH CHECK (public.has_workspace_module_permission(workspace_id, 'budget', 'write'));
DROP POLICY IF EXISTS service_agreements_delete ON public.service_agreements;
CREATE POLICY service_agreements_delete ON public.service_agreements
  FOR DELETE USING (public.has_workspace_module_permission(workspace_id, 'budget', 'write'));

-- Documents and file surfaces. Uploading files intentionally requires read
-- access to the documents module because field roles can contribute photos.
DROP POLICY IF EXISTS document_templates_select ON public.document_templates;
CREATE POLICY document_templates_select ON public.document_templates
  FOR SELECT USING (public.has_workspace_module_permission(workspace_id, 'documents', 'read'));
DROP POLICY IF EXISTS document_templates_insert ON public.document_templates;
CREATE POLICY document_templates_insert ON public.document_templates
  FOR INSERT WITH CHECK (public.has_workspace_module_permission(workspace_id, 'documents', 'write'));
DROP POLICY IF EXISTS document_templates_update ON public.document_templates;
CREATE POLICY document_templates_update ON public.document_templates
  FOR UPDATE USING (public.has_workspace_module_permission(workspace_id, 'documents', 'write'))
  WITH CHECK (public.has_workspace_module_permission(workspace_id, 'documents', 'write'));
DROP POLICY IF EXISTS document_templates_delete ON public.document_templates;
CREATE POLICY document_templates_delete ON public.document_templates
  FOR DELETE USING (public.is_workspace_admin(workspace_id));

DROP POLICY IF EXISTS generated_documents_select ON public.generated_documents;
CREATE POLICY generated_documents_select ON public.generated_documents
  FOR SELECT USING (public.has_workspace_module_permission(workspace_id, 'documents', 'read'));
DROP POLICY IF EXISTS generated_documents_insert ON public.generated_documents;
CREATE POLICY generated_documents_insert ON public.generated_documents
  FOR INSERT WITH CHECK (public.has_workspace_module_permission(workspace_id, 'documents', 'write'));
DROP POLICY IF EXISTS generated_documents_update ON public.generated_documents;
CREATE POLICY generated_documents_update ON public.generated_documents
  FOR UPDATE USING (public.has_workspace_module_permission(workspace_id, 'documents', 'write'))
  WITH CHECK (public.has_workspace_module_permission(workspace_id, 'documents', 'write'));
DROP POLICY IF EXISTS generated_documents_delete ON public.generated_documents;
CREATE POLICY generated_documents_delete ON public.generated_documents
  FOR DELETE USING (public.has_workspace_module_permission(workspace_id, 'documents', 'write'));

DROP POLICY IF EXISTS file_folders_select ON public.file_folders;
CREATE POLICY file_folders_select ON public.file_folders
  FOR SELECT USING (public.has_workspace_module_permission(workspace_id, 'documents', 'read'));
DROP POLICY IF EXISTS file_folders_insert ON public.file_folders;
CREATE POLICY file_folders_insert ON public.file_folders
  FOR INSERT WITH CHECK (public.has_workspace_module_permission(workspace_id, 'documents', 'write'));
DROP POLICY IF EXISTS file_folders_update ON public.file_folders;
CREATE POLICY file_folders_update ON public.file_folders
  FOR UPDATE USING (public.has_workspace_module_permission(workspace_id, 'documents', 'write'))
  WITH CHECK (public.has_workspace_module_permission(workspace_id, 'documents', 'write'));
DROP POLICY IF EXISTS file_folders_delete ON public.file_folders;
CREATE POLICY file_folders_delete ON public.file_folders
  FOR DELETE USING (public.has_workspace_module_permission(workspace_id, 'documents', 'write'));

DROP POLICY IF EXISTS file_attachments_select ON public.file_attachments;
CREATE POLICY file_attachments_select ON public.file_attachments
  FOR SELECT USING (public.has_workspace_module_permission(workspace_id, 'documents', 'read'));
DROP POLICY IF EXISTS file_attachments_insert ON public.file_attachments;
CREATE POLICY file_attachments_insert ON public.file_attachments
  FOR INSERT WITH CHECK (public.has_workspace_module_permission(workspace_id, 'documents', 'read'));
DROP POLICY IF EXISTS file_attachments_update ON public.file_attachments;
CREATE POLICY file_attachments_update ON public.file_attachments
  FOR UPDATE USING (
    uploaded_by = auth.uid()
    OR public.has_workspace_module_permission(workspace_id, 'documents', 'write')
  )
  WITH CHECK (
    uploaded_by = auth.uid()
    OR public.has_workspace_module_permission(workspace_id, 'documents', 'write')
  );
DROP POLICY IF EXISTS file_attachments_delete ON public.file_attachments;
CREATE POLICY file_attachments_delete ON public.file_attachments
  FOR DELETE USING (
    uploaded_by = auth.uid()
    OR public.has_workspace_module_permission(workspace_id, 'documents', 'write')
  );
