-- Architect-driven fixes for 20260521100000_add_opportunities.sql:
--   1. View opportunity_forecast_v defaults to security_definer in PG15+,
--      bypassing RLS. Force security_invoker so it filters by caller.
--   2. opportunity_activities.insert RLS only checks the workspace_id supplied
--      by the caller — they could supply a workspace they belong to but an
--      opportunity_id from a different workspace. Add a trigger that forces
--      workspace_id to match the parent opportunity, blocking spoofed inserts.
--   3. markWonAndCreateProject was two client-side writes (project insert,
--      opp update). On partial failure that leaves an orphan project. Move it
--      into a single SECURITY DEFINER RPC with an authorization check.

-- ---------------------------------------------------------------------------
-- 1. Force view to obey the caller's RLS.
-- ---------------------------------------------------------------------------
ALTER VIEW public.opportunity_forecast_v SET (security_invoker = true);

-- ---------------------------------------------------------------------------
-- 2. Enforce that opportunity_activities.workspace_id matches its opportunity.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.opportunity_activity_enforce_workspace()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  v_ws UUID;
BEGIN
  SELECT workspace_id INTO v_ws
    FROM public.opportunities
   WHERE id = NEW.opportunity_id;
  IF v_ws IS NULL THEN
    RAISE EXCEPTION 'opportunity not found';
  END IF;
  NEW.workspace_id := v_ws;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_opp_activity_enforce_ws
  ON public.opportunity_activities;
CREATE TRIGGER trg_opp_activity_enforce_ws
  BEFORE INSERT OR UPDATE ON public.opportunity_activities
  FOR EACH ROW EXECUTE FUNCTION public.opportunity_activity_enforce_workspace();

-- ---------------------------------------------------------------------------
-- 3. Atomic win-conversion RPC.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.opportunity_mark_won_create_project(
  p_opportunity_id UUID,
  p_project_name TEXT DEFAULT NULL
) RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_opp public.opportunities;
  v_project_id UUID;
BEGIN
  SELECT * INTO v_opp FROM public.opportunities
   WHERE id = p_opportunity_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Opportunity not found';
  END IF;
  IF NOT public.is_workspace_member(v_opp.workspace_id) THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;
  IF v_opp.stage = 'won' AND v_opp.project_id IS NOT NULL THEN
    RETURN v_opp.project_id;
  END IF;

  INSERT INTO public.projects (
    workspace_id, name, client_id, project_manager_id,
    status, is_active, budget
  ) VALUES (
    v_opp.workspace_id,
    COALESCE(p_project_name, v_opp.name),
    v_opp.customer_id,
    v_opp.owner_id,
    'bidding',
    TRUE,
    v_opp.estimated_value
  )
  RETURNING id INTO v_project_id;

  UPDATE public.opportunities
     SET stage = 'won',
         project_id = v_project_id
   WHERE id = p_opportunity_id;

  RETURN v_project_id;
END;
$$;

REVOKE ALL ON FUNCTION public.opportunity_mark_won_create_project(UUID, TEXT)
  FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.opportunity_mark_won_create_project(UUID, TEXT)
  TO authenticated;
