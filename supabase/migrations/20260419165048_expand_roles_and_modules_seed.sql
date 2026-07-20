-- Refresh the system role-template seed with the full 15-module permission
-- map and the two new roles (Master Admin, Vendor). Re-seeds every existing
-- workspace so the matrix has values to display immediately.
--
-- NOTE: Admin.is_admin is FALSE here on purpose — per the schematic, only
-- Master Admin holds the user/billing management tier. Existing admin
-- members are still treated as admins via the `wm.role = 'admin'` branch
-- in is_workspace_admin(), so this is not a downgrade for current users.

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
      'Master Admin',
      'master_admin',
      '{"projects":"write","properties":"write","tasks":"write","time_tracking":"write","estimating":"write","customer_invoices":"write","vendor_bills":"write","change_orders":"write","budget":"write","customers":"write","vendors":"write","documents":"write","bid_requests":"write","team":"write","reports":"write","settings":"write"}'::jsonb,
      TRUE,
      TRUE,
      'manager',
      'Full access. Only role that can manage users and billing.',
      p_created_by
    ),
    (
      p_workspace_id,
      'Admin',
      'admin',
      '{"projects":"write","properties":"write","tasks":"write","time_tracking":"write","estimating":"write","customer_invoices":"write","vendor_bills":"write","change_orders":"write","budget":"write","customers":"write","vendors":"write","documents":"write","bid_requests":"write","team":"write","reports":"write","settings":"read"}'::jsonb,
      TRUE,
      FALSE,
      'manager',
      'Full operational access. Cannot manage users or billing.',
      p_created_by
    ),
    (
      p_workspace_id,
      'Project Manager',
      'project_manager',
      '{"projects":"write","properties":"write","tasks":"write","time_tracking":"write","estimating":"read","customer_invoices":"read","vendor_bills":"read","change_orders":"write","budget":"read","customers":"read","vendors":"read","documents":"write","bid_requests":"write","team":"read","reports":"read","settings":"none"}'::jsonb,
      TRUE,
      FALSE,
      'manager',
      'Assigned jobs. View financials, manage tasks, coordinate team.',
      p_created_by
    ),
    (
      p_workspace_id,
      'Field Technician',
      'field_technician',
      '{"projects":"read","properties":"read","tasks":"write","time_tracking":"write","estimating":"none","customer_invoices":"none","vendor_bills":"none","change_orders":"none","budget":"none","customers":"none","vendors":"none","documents":"read","bid_requests":"none","team":"read","reports":"none","settings":"none"}'::jsonb,
      TRUE,
      FALSE,
      'field',
      'Mobile-first. Assigned tasks, time logging, media upload.',
      p_created_by
    ),
    (
      p_workspace_id,
      'Customer',
      'client',
      '{"projects":"read","properties":"read","tasks":"none","time_tracking":"none","estimating":"none","customer_invoices":"read","vendor_bills":"none","change_orders":"read","budget":"none","customers":"read","vendors":"none","documents":"read","bid_requests":"none","team":"none","reports":"none","settings":"none"}'::jsonb,
      TRUE,
      FALSE,
      'manager',
      'External portal. Read-only access to their own job and shared docs.',
      p_created_by
    ),
    (
      p_workspace_id,
      'Vendor',
      'vendor',
      '{"projects":"none","properties":"none","tasks":"none","time_tracking":"none","estimating":"none","customer_invoices":"none","vendor_bills":"read","change_orders":"none","budget":"none","customers":"none","vendors":"read","documents":"read","bid_requests":"write","team":"none","reports":"none","settings":"none"}'::jsonb,
      TRUE,
      FALSE,
      'manager',
      'External portal. Bid requests, purchase orders, own bills.',
      p_created_by
    )
  ON CONFLICT (workspace_id, name) DO UPDATE
    SET module_permissions = EXCLUDED.module_permissions,
        description = EXCLUDED.description,
        default_interface_mode = EXCLUDED.default_interface_mode,
        is_admin = EXCLUDED.is_admin,
        updated_at = NOW()
    WHERE public.workspace_role_templates.is_system = TRUE;
END;
$$;

DO $$
DECLARE
  w RECORD;
BEGIN
  FOR w IN SELECT id, owner_id FROM public.workspaces LOOP
    PERFORM public.seed_default_workspace_role_templates(w.id, w.owner_id);
  END LOOP;
END $$;
