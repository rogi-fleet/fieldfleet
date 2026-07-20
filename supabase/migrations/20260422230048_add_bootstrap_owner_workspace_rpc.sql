-- Atomic workspace bootstrap for new signups.
--
-- Replaces the non-transactional sequence in auth_service.dart:
--   INSERT workspaces; INSERT workspace_members; UPDATE users
-- which could orphan a workspace if step 2 or 3 failed. This wraps all three
-- in a single transaction so a failure rolls the workspace back with it.
--
-- The existing AFTER INSERT trigger on workspaces seeds system role templates
-- before this function continues, so the admin template lookup is reliable.

CREATE OR REPLACE FUNCTION public.bootstrap_owner_workspace(
  p_name TEXT,
  p_company_type TEXT,
  p_project_terminology TEXT,
  p_enabled_project_tabs TEXT[],
  p_timezone TEXT,
  p_trial_days INTEGER DEFAULT 14
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  now_ts TIMESTAMPTZ := NOW();
  trial_end TIMESTAMPTZ := now_ts + (p_trial_days || ' days')::INTERVAL;
  v_owner_id UUID := auth.uid();
  v_workspace_id UUID;
  v_admin_template_id UUID;
BEGIN
  IF v_owner_id IS NULL THEN
    RAISE EXCEPTION 'You must be signed in to create a workspace';
  END IF;

  IF p_name IS NULL OR length(trim(p_name)) = 0 THEN
    RAISE EXCEPTION 'Workspace name is required';
  END IF;

  INSERT INTO workspaces (
    name,
    owner_id,
    company_type,
    project_terminology,
    enabled_project_tabs,
    timezone,
    subscription_tier,
    subscription_status,
    trial_start_date,
    trial_end_date,
    created_at,
    updated_at
  ) VALUES (
    p_name,
    v_owner_id,
    COALESCE(p_company_type, 'other')::company_type,
    p_project_terminology,
    COALESCE(p_enabled_project_tabs, ARRAY[]::TEXT[]),
    COALESCE(p_timezone, 'UTC'),
    'pro',
    'trialing',
    now_ts,
    trial_end,
    now_ts,
    now_ts
  )
  RETURNING id INTO v_workspace_id;

  SELECT id
  INTO v_admin_template_id
  FROM workspace_role_templates
  WHERE workspace_id = v_workspace_id
    AND role = 'admin'
    AND is_system = TRUE
  LIMIT 1;

  INSERT INTO workspace_members (
    workspace_id,
    user_id,
    role,
    role_template_id,
    interface_mode,
    created_at,
    updated_at
  ) VALUES (
    v_workspace_id,
    v_owner_id,
    'admin',
    v_admin_template_id,
    'manager',
    now_ts,
    now_ts
  );

  UPDATE users
  SET active_workspace_id = v_workspace_id,
      default_workspace_id = v_workspace_id,
      updated_at = now_ts
  WHERE id = v_owner_id;

  RETURN jsonb_build_object(
    'workspaceId', v_workspace_id,
    'roleTemplateId', v_admin_template_id
  );
END;
$$;

REVOKE ALL ON FUNCTION public.bootstrap_owner_workspace(TEXT, TEXT, TEXT, TEXT[], TEXT, INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.bootstrap_owner_workspace(TEXT, TEXT, TEXT, TEXT[], TEXT, INTEGER) TO authenticated;
