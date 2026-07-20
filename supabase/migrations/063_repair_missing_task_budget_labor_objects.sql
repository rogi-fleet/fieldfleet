-- Repair migration: recreate task-budget linkage objects when migration history is out of sync

CREATE TABLE IF NOT EXISTS public.task_budget_items (
  task_id UUID NOT NULL REFERENCES public.tasks(id) ON DELETE CASCADE,
  budget_item_id UUID NOT NULL REFERENCES public.budget_items(id) ON DELETE CASCADE,
  allocation_percentage NUMERIC(5,2) NOT NULL DEFAULT 100,
  workspace_id UUID NOT NULL REFERENCES public.workspaces(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (task_id, budget_item_id),
  CONSTRAINT task_budget_items_allocation_check
    CHECK (allocation_percentage > 0 AND allocation_percentage <= 100)
);

CREATE INDEX IF NOT EXISTS idx_task_budget_items_budget_item
  ON public.task_budget_items(budget_item_id);

CREATE INDEX IF NOT EXISTS idx_task_budget_items_task
  ON public.task_budget_items(task_id);

CREATE INDEX IF NOT EXISTS idx_task_budget_items_workspace
  ON public.task_budget_items(workspace_id);

ALTER TABLE public.task_budget_items ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS task_budget_items_select ON public.task_budget_items;
CREATE POLICY task_budget_items_select ON public.task_budget_items
  FOR SELECT USING (is_workspace_member(workspace_id));

DROP POLICY IF EXISTS task_budget_items_insert ON public.task_budget_items;
CREATE POLICY task_budget_items_insert ON public.task_budget_items
  FOR INSERT WITH CHECK (is_workspace_member(workspace_id));

DROP POLICY IF EXISTS task_budget_items_update ON public.task_budget_items;
CREATE POLICY task_budget_items_update ON public.task_budget_items
  FOR UPDATE USING (is_workspace_member(workspace_id));

DROP POLICY IF EXISTS task_budget_items_delete ON public.task_budget_items;
CREATE POLICY task_budget_items_delete ON public.task_budget_items
  FOR DELETE USING (is_workspace_member(workspace_id));

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'task_budget_items'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.task_budget_items;
  END IF;
END
$$;

CREATE OR REPLACE VIEW public.budget_item_labor_summary AS
SELECT
  tbi.budget_item_id,
  COUNT(DISTINCT tbi.task_id) AS task_count,
  COALESCE(SUM(t.estimated_duration * tbi.allocation_percentage / 100), 0) AS estimated_hours,
  COALESCE(SUM(
    CASE WHEN te.status = 'approved' THEN
      (te.regular_hours + te.overtime_hours + te.double_time_hours)
      * tbi.allocation_percentage / 100
    ELSE 0 END
  ), 0) AS tracked_hours,
  COALESCE(SUM(
    CASE WHEN te.status = 'approved' THEN
      te.total_cost * tbi.allocation_percentage / 100
    ELSE 0 END
  ), 0) AS labor_cost
FROM public.task_budget_items tbi
JOIN public.tasks t ON t.id = tbi.task_id
LEFT JOIN public.time_entries te ON te.task_id = tbi.task_id
GROUP BY tbi.budget_item_id;
