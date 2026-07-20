-- Batch project-list task metrics into one RPC and add supporting indexes.

CREATE INDEX IF NOT EXISTS idx_projects_workspace_updated_at
ON public.projects(workspace_id, updated_at DESC);

CREATE INDEX IF NOT EXISTS idx_tasks_workspace_project
ON public.tasks(workspace_id, project_id);

CREATE INDEX IF NOT EXISTS idx_tasks_project_due_open
ON public.tasks(project_id, due_date)
WHERE is_complete = FALSE;

CREATE INDEX IF NOT EXISTS idx_assets_assigned_to_project
ON public.assets(assigned_to_project_id);

DROP FUNCTION IF EXISTS public.get_project_list_task_metrics(UUID);

CREATE FUNCTION public.get_project_list_task_metrics(p_workspace_id UUID)
RETURNS TABLE (
  project_id UUID,
  open_count BIGINT,
  overdue_count BIGINT,
  due_today_count BIGINT,
  total_count BIGINT,
  completed_count BIGINT,
  progress_percent DOUBLE PRECISION
)
LANGUAGE sql
STABLE
SET search_path = public
AS $$
  SELECT
    p.id AS project_id,
    COUNT(t.id) FILTER (
      WHERE NOT COALESCE(t.is_complete, FALSE)
    ) AS open_count,
    COUNT(t.id) FILTER (
      WHERE NOT COALESCE(t.is_complete, FALSE)
        AND t.due_date IS NOT NULL
        AND t.due_date < NOW()
    ) AS overdue_count,
    COUNT(t.id) FILTER (
      WHERE NOT COALESCE(t.is_complete, FALSE)
        AND t.due_date IS NOT NULL
        AND t.due_date >= date_trunc('day', NOW())
        AND t.due_date < date_trunc('day', NOW()) + INTERVAL '1 day'
    ) AS due_today_count,
    COUNT(t.id) AS total_count,
    COUNT(t.id) FILTER (
      WHERE COALESCE(t.is_complete, FALSE)
    ) AS completed_count,
    CASE
      WHEN COUNT(t.id) = 0 THEN 0::DOUBLE PRECISION
      ELSE (
        COUNT(t.id) FILTER (WHERE COALESCE(t.is_complete, FALSE))::DOUBLE PRECISION
        / COUNT(t.id)::DOUBLE PRECISION
      ) * 100
    END AS progress_percent
  FROM public.projects p
  LEFT JOIN public.tasks t
    ON t.project_id = p.id
  WHERE p.workspace_id = p_workspace_id
  GROUP BY p.id;
$$;

REVOKE ALL ON FUNCTION public.get_project_list_task_metrics(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_project_list_task_metrics(UUID) TO authenticated;
