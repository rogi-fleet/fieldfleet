-- Regression fix for the role-expansion seed. Restores PM write powers
-- on financials/customers/vendors/team/settings and gives Field Tech
-- customer read access back. Also backfills missing module keys on
-- non-system templates so pre-expansion custom roles don't silently
-- demote.

CREATE OR REPLACE FUNCTION public.seed_default_workspace_role_templates(
  p_workspace_id UUID,
  p_created_by UUID DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
  INSERT INTO public.workspace_role_templates (
    workspace_id, name, role, module_permissions,
    is_system, is_admin, default_interface_mode, description, created_by
  )
  VALUES
    (
      p_workspace_id, 'Master Admin', 'master_admin',
      '{"projects":"write","properties":"write","tasks":"write","time_tracking":"write","estimating":"write","customer_invoices":"write","vendor_bills":"write","change_orders":"write","budget":"write","customers":"write","vendors":"write","documents":"write","bid_requests":"write","team":"write","reports":"write","settings":"write"}'::jsonb,
      TRUE, TRUE, 'manager',
      'Full access. Manages users, billing, and every module.',
      p_created_by
    ),
    (
      p_workspace_id, 'Admin', 'admin',
      '{"projects":"write","properties":"write","tasks":"write","time_tracking":"write","estimating":"write","customer_invoices":"write","vendor_bills":"write","change_orders":"write","budget":"write","customers":"write","vendors":"write","documents":"write","bid_requests":"write","team":"write","reports":"write","settings":"write"}'::jsonb,
      TRUE, TRUE, 'manager',
      'Full admin access across every module.',
      p_created_by
    ),
    (
      p_workspace_id, 'Project Manager', 'project_manager',
      '{"projects":"write","properties":"write","tasks":"write","time_tracking":"write","estimating":"read","customer_invoices":"write","vendor_bills":"write","change_orders":"write","budget":"write","customers":"write","vendors":"write","documents":"write","bid_requests":"write","team":"write","reports":"read","settings":"read"}'::jsonb,
      TRUE, FALSE, 'manager',
      'Manages assigned jobs end to end — financials, customers, vendors, and team coordination.',
      p_created_by
    ),
    (
      p_workspace_id, 'Field Technician', 'field_technician',
      '{"projects":"read","properties":"read","tasks":"write","time_tracking":"write","estimating":"none","customer_invoices":"none","vendor_bills":"none","change_orders":"none","budget":"none","customers":"read","vendors":"none","documents":"read","bid_requests":"none","team":"read","reports":"none","settings":"none"}'::jsonb,
      TRUE, FALSE, 'field',
      'Mobile-first. Assigned tasks, time logging, media upload.',
      p_created_by
    ),
    (
      p_workspace_id, 'Customer', 'client',
      '{"projects":"read","properties":"read","tasks":"none","time_tracking":"none","estimating":"none","customer_invoices":"read","vendor_bills":"none","change_orders":"read","budget":"none","customers":"read","vendors":"none","documents":"read","bid_requests":"none","team":"none","reports":"none","settings":"none"}'::jsonb,
      TRUE, FALSE, 'manager',
      'External portal. Read-only access to their own job and shared docs.',
      p_created_by
    ),
    (
      p_workspace_id, 'Vendor', 'vendor',
      '{"projects":"none","properties":"none","tasks":"none","time_tracking":"none","estimating":"none","customer_invoices":"none","vendor_bills":"read","change_orders":"none","budget":"none","customers":"none","vendors":"read","documents":"read","bid_requests":"write","team":"none","reports":"none","settings":"none"}'::jsonb,
      TRUE, FALSE, 'manager',
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

-- Re-seed every workspace to pick up the restored PM + Field Tech values.
DO $$
DECLARE
  w RECORD;
BEGIN
  FOR w IN SELECT id, owner_id FROM public.workspaces LOOP
    PERFORM public.seed_default_workspace_role_templates(w.id, w.owner_id);
  END LOOP;
END $$;

-- Backfill non-system templates missing new module keys by projecting
-- from the old blanket keys. Uses permission_level_rank for the cap logic
-- on estimating + reports (capped at 'read').
UPDATE public.workspace_role_templates t
SET module_permissions = (
  (COALESCE(t.module_permissions, '{}'::jsonb))
    || (CASE WHEN t.module_permissions ? 'properties' THEN '{}'::jsonb
             ELSE jsonb_build_object('properties', COALESCE(t.module_permissions ->> 'projects', 'none'))
        END)
    || (CASE WHEN t.module_permissions ? 'customers' THEN '{}'::jsonb
             ELSE jsonb_build_object('customers', COALESCE(t.module_permissions ->> 'projects', 'none'))
        END)
    || (CASE WHEN t.module_permissions ? 'customer_invoices' THEN '{}'::jsonb
             ELSE jsonb_build_object('customer_invoices', COALESCE(t.module_permissions ->> 'budget', 'none'))
        END)
    || (CASE WHEN t.module_permissions ? 'vendor_bills' THEN '{}'::jsonb
             ELSE jsonb_build_object('vendor_bills', COALESCE(t.module_permissions ->> 'budget', 'none'))
        END)
    || (CASE WHEN t.module_permissions ? 'change_orders' THEN '{}'::jsonb
             ELSE jsonb_build_object('change_orders', COALESCE(t.module_permissions ->> 'budget', 'none'))
        END)
    || (CASE WHEN t.module_permissions ? 'bid_requests' THEN '{}'::jsonb
             ELSE jsonb_build_object('bid_requests', COALESCE(t.module_permissions ->> 'budget', 'none'))
        END)
    || (CASE WHEN t.module_permissions ? 'vendors' THEN '{}'::jsonb
             ELSE jsonb_build_object('vendors', COALESCE(t.module_permissions ->> 'budget', 'none'))
        END)
    || (CASE WHEN t.module_permissions ? 'time_tracking' THEN '{}'::jsonb
             ELSE jsonb_build_object('time_tracking',
               CASE
                 WHEN public.permission_level_rank(t.module_permissions ->> 'tasks') >=
                      public.permission_level_rank(t.module_permissions ->> 'projects')
                 THEN COALESCE(t.module_permissions ->> 'tasks', 'none')
                 ELSE COALESCE(t.module_permissions ->> 'projects', 'none')
               END)
        END)
    || (CASE WHEN t.module_permissions ? 'estimating' THEN '{}'::jsonb
             ELSE jsonb_build_object('estimating',
               CASE
                 WHEN public.permission_level_rank(t.module_permissions ->> 'budget') >= 1
                 THEN 'read'
                 ELSE 'none'
               END)
        END)
    || (CASE WHEN t.module_permissions ? 'reports' THEN '{}'::jsonb
             ELSE jsonb_build_object('reports',
               CASE
                 WHEN public.permission_level_rank(t.module_permissions ->> 'budget') >= 1
                 THEN 'read'
                 ELSE 'none'
               END)
        END)
),
updated_at = NOW()
WHERE is_system = FALSE;
