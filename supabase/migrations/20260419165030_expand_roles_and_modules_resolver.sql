-- Teach the permission resolver about the new modules and the master_admin
-- role. Extends the fallback path in workspace_member_module_level so legacy
-- workspace_member rows (which only carry a 6-key module_permissions blob)
-- still produce sensible answers for Properties, Time Tracking, Estimating,
-- Customer Invoices, Vendor Bills, Change Orders, Customers, Vendors, Bid
-- Requests, and Reports.

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
    WHEN wm.role::TEXT IN ('admin', 'master_admin') OR coalesce(wrt.is_admin, FALSE) THEN 'write'
    ELSE coalesce(
      wrt.module_permissions ->> lower(module_key),
      wm.module_permissions ->> lower(module_key),
      CASE lower(module_key)
        WHEN 'projects' THEN CASE wm.role::TEXT
          WHEN 'project_manager' THEN 'write'
          WHEN 'field_technician' THEN 'read'
          WHEN 'client' THEN 'read'
          ELSE 'none'
        END
        WHEN 'tasks' THEN CASE wm.role::TEXT
          WHEN 'project_manager' THEN 'write'
          WHEN 'field_technician' THEN 'write'
          ELSE 'none'
        END
        WHEN 'budget' THEN CASE wm.role::TEXT
          WHEN 'project_manager' THEN 'write'
          ELSE 'none'
        END
        WHEN 'documents' THEN CASE wm.role::TEXT
          WHEN 'project_manager' THEN 'write'
          WHEN 'field_technician' THEN 'read'
          WHEN 'client' THEN 'read'
          WHEN 'vendor' THEN 'read'
          ELSE 'none'
        END
        WHEN 'team' THEN CASE wm.role::TEXT
          WHEN 'project_manager' THEN 'write'
          WHEN 'field_technician' THEN 'read'
          ELSE 'none'
        END
        WHEN 'settings' THEN CASE wm.role::TEXT
          WHEN 'project_manager' THEN 'read'
          ELSE 'none'
        END
        WHEN 'properties' THEN CASE wm.role::TEXT
          WHEN 'project_manager' THEN 'write'
          WHEN 'field_technician' THEN 'read'
          WHEN 'client' THEN 'read'
          ELSE 'none'
        END
        WHEN 'time_tracking' THEN CASE wm.role::TEXT
          WHEN 'project_manager' THEN 'write'
          WHEN 'field_technician' THEN 'write'
          ELSE 'none'
        END
        WHEN 'estimating' THEN CASE wm.role::TEXT
          WHEN 'project_manager' THEN 'read'
          ELSE 'none'
        END
        WHEN 'customer_invoices' THEN CASE wm.role::TEXT
          WHEN 'project_manager' THEN 'read'
          WHEN 'client' THEN 'read'
          ELSE 'none'
        END
        WHEN 'vendor_bills' THEN CASE wm.role::TEXT
          WHEN 'project_manager' THEN 'read'
          WHEN 'vendor' THEN 'read'
          ELSE 'none'
        END
        WHEN 'change_orders' THEN CASE wm.role::TEXT
          WHEN 'project_manager' THEN 'write'
          WHEN 'client' THEN 'read'
          ELSE 'none'
        END
        WHEN 'customers' THEN CASE wm.role::TEXT
          WHEN 'project_manager' THEN 'read'
          WHEN 'client' THEN 'read'
          ELSE 'none'
        END
        WHEN 'vendors' THEN CASE wm.role::TEXT
          WHEN 'project_manager' THEN 'read'
          WHEN 'vendor' THEN 'read'
          ELSE 'none'
        END
        WHEN 'bid_requests' THEN CASE wm.role::TEXT
          WHEN 'project_manager' THEN 'write'
          WHEN 'vendor' THEN 'write'
          ELSE 'none'
        END
        WHEN 'reports' THEN CASE wm.role::TEXT
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

-- Admin helper must recognise master_admin too.
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
      AND (
        wm.role::TEXT IN ('admin', 'master_admin')
        OR coalesce(wrt.is_admin, FALSE)
      )
  );
END;
$$;
