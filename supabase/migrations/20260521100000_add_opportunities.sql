-- P2-1 Lead Pipeline: opportunities + activities + forecast helpers.
-- Workspace-scoped; RLS gates on is_workspace_member().

-- ---------------------------------------------------------------------------
-- Enums
-- ---------------------------------------------------------------------------
DO $$ BEGIN
  CREATE TYPE opportunity_stage AS ENUM
    ('new','qualified','proposal','negotiation','won','lost');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE opportunity_activity_kind AS ENUM
    ('note','call','email','meeting','follow_up','stage_change','won','lost');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ---------------------------------------------------------------------------
-- opportunities
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.opportunities (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  workspace_id UUID NOT NULL REFERENCES public.workspaces(id) ON DELETE CASCADE,
  customer_id UUID REFERENCES public.customers(id) ON DELETE SET NULL,
  project_id UUID REFERENCES public.projects(id) ON DELETE SET NULL,
  owner_id UUID REFERENCES public.users(id) ON DELETE SET NULL,
  name TEXT NOT NULL,
  description TEXT,
  stage opportunity_stage NOT NULL DEFAULT 'new',
  source customer_source,
  estimated_value NUMERIC(14,2) NOT NULL DEFAULT 0,
  probability INTEGER NOT NULL DEFAULT 50 CHECK (probability BETWEEN 0 AND 100),
  expected_close_date DATE,
  actual_close_date DATE,
  lost_reason TEXT,
  next_action TEXT,
  next_action_at TIMESTAMPTZ,
  tags TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_by UUID REFERENCES public.users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS opportunities_workspace_idx
  ON public.opportunities (workspace_id, is_active);
CREATE INDEX IF NOT EXISTS opportunities_stage_idx
  ON public.opportunities (workspace_id, stage)
  WHERE is_active = TRUE;
CREATE INDEX IF NOT EXISTS opportunities_owner_idx
  ON public.opportunities (workspace_id, owner_id);
CREATE INDEX IF NOT EXISTS opportunities_customer_idx
  ON public.opportunities (customer_id);
CREATE INDEX IF NOT EXISTS opportunities_close_idx
  ON public.opportunities (workspace_id, expected_close_date);

ALTER TABLE public.opportunities ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  DROP POLICY IF EXISTS opportunities_select ON public.opportunities;
  DROP POLICY IF EXISTS opportunities_insert ON public.opportunities;
  DROP POLICY IF EXISTS opportunities_update ON public.opportunities;
  DROP POLICY IF EXISTS opportunities_delete ON public.opportunities;
END $$;

CREATE POLICY opportunities_select ON public.opportunities
  FOR SELECT USING (public.is_workspace_member(workspace_id));
CREATE POLICY opportunities_insert ON public.opportunities
  FOR INSERT WITH CHECK (public.is_workspace_member(workspace_id));
CREATE POLICY opportunities_update ON public.opportunities
  FOR UPDATE USING (public.is_workspace_member(workspace_id))
  WITH CHECK (public.is_workspace_member(workspace_id));
CREATE POLICY opportunities_delete ON public.opportunities
  FOR DELETE USING (public.is_workspace_member(workspace_id));

-- ---------------------------------------------------------------------------
-- opportunity_activities (timeline + tasks)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.opportunity_activities (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  opportunity_id UUID NOT NULL REFERENCES public.opportunities(id) ON DELETE CASCADE,
  workspace_id UUID NOT NULL REFERENCES public.workspaces(id) ON DELETE CASCADE,
  kind opportunity_activity_kind NOT NULL DEFAULT 'note',
  subject TEXT,
  body TEXT,
  due_at TIMESTAMPTZ,
  completed_at TIMESTAMPTZ,
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_by UUID REFERENCES public.users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS opportunity_activities_opp_idx
  ON public.opportunity_activities (opportunity_id, created_at DESC);
CREATE INDEX IF NOT EXISTS opportunity_activities_due_idx
  ON public.opportunity_activities (workspace_id, due_at)
  WHERE completed_at IS NULL;

ALTER TABLE public.opportunity_activities ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  DROP POLICY IF EXISTS opp_activities_select ON public.opportunity_activities;
  DROP POLICY IF EXISTS opp_activities_insert ON public.opportunity_activities;
  DROP POLICY IF EXISTS opp_activities_update ON public.opportunity_activities;
  DROP POLICY IF EXISTS opp_activities_delete ON public.opportunity_activities;
END $$;

CREATE POLICY opp_activities_select ON public.opportunity_activities
  FOR SELECT USING (public.is_workspace_member(workspace_id));
CREATE POLICY opp_activities_insert ON public.opportunity_activities
  FOR INSERT WITH CHECK (public.is_workspace_member(workspace_id));
CREATE POLICY opp_activities_update ON public.opportunity_activities
  FOR UPDATE USING (public.is_workspace_member(workspace_id))
  WITH CHECK (public.is_workspace_member(workspace_id));
CREATE POLICY opp_activities_delete ON public.opportunity_activities
  FOR DELETE USING (public.is_workspace_member(workspace_id));

-- ---------------------------------------------------------------------------
-- Stage-change audit trigger: writes a stage_change activity on transition.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.opportunity_log_stage_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'UPDATE' AND NEW.stage IS DISTINCT FROM OLD.stage THEN
    INSERT INTO public.opportunity_activities (
      opportunity_id, workspace_id, kind, subject, body,
      created_by, metadata
    ) VALUES (
      NEW.id, NEW.workspace_id,
      CASE WHEN NEW.stage = 'won' THEN 'won'::opportunity_activity_kind
           WHEN NEW.stage = 'lost' THEN 'lost'::opportunity_activity_kind
           ELSE 'stage_change'::opportunity_activity_kind END,
      'Stage changed',
      OLD.stage::text || ' → ' || NEW.stage::text,
      auth.uid(),
      jsonb_build_object('from', OLD.stage, 'to', NEW.stage)
    );
    IF NEW.stage IN ('won','lost') AND NEW.actual_close_date IS NULL THEN
      NEW.actual_close_date := CURRENT_DATE;
    END IF;
  END IF;
  NEW.updated_at := NOW();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_opportunity_stage_change ON public.opportunities;
CREATE TRIGGER trg_opportunity_stage_change
  BEFORE UPDATE ON public.opportunities
  FOR EACH ROW EXECUTE FUNCTION public.opportunity_log_stage_change();

-- ---------------------------------------------------------------------------
-- Forecast roll-up view: weighted pipeline per workspace by stage and owner.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW public.opportunity_forecast_v AS
SELECT
  o.workspace_id,
  o.owner_id,
  o.stage,
  COUNT(*)::INT                                        AS opportunity_count,
  COALESCE(SUM(o.estimated_value), 0)                  AS total_value,
  COALESCE(SUM(o.estimated_value * o.probability / 100.0), 0)
                                                       AS weighted_value
FROM public.opportunities o
WHERE o.is_active = TRUE
  AND o.stage NOT IN ('won','lost')
GROUP BY o.workspace_id, o.owner_id, o.stage;

GRANT SELECT ON public.opportunity_forecast_v TO authenticated;

COMMENT ON TABLE public.opportunities IS
  'Lead pipeline opportunities (P2-1). Linked to customers and (post-win) projects.';
COMMENT ON TABLE public.opportunity_activities IS
  'Timeline of calls/notes/follow-ups + auto stage-change audit entries.';
