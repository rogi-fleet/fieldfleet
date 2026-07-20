-- Include direct time_entries.budget_item_id assignments in labor summary
-- without double counting entries that also have task links.

CREATE OR REPLACE VIEW public.budget_item_labor_summary AS
WITH task_estimates AS (
  SELECT
    tbi.budget_item_id,
    COUNT(DISTINCT tbi.task_id) AS task_count,
    COALESCE(
      SUM(t.estimated_duration * tbi.allocation_percentage / 100),
      0
    ) AS estimated_hours
  FROM public.task_budget_items tbi
  JOIN public.tasks t ON t.id = tbi.task_id
  GROUP BY tbi.budget_item_id
),
task_allocated_time AS (
  SELECT
    tbi.budget_item_id,
    COALESCE(
      SUM(
        (te.regular_hours + te.overtime_hours + te.double_time_hours)
        * tbi.allocation_percentage / 100
      ),
      0
    ) AS tracked_hours,
    COALESCE(
      SUM(te.total_cost * tbi.allocation_percentage / 100),
      0
    ) AS labor_cost
  FROM public.task_budget_items tbi
  JOIN public.time_entries te ON te.task_id = tbi.task_id
  WHERE te.status = 'approved'
    AND te.budget_item_id IS NULL
  GROUP BY tbi.budget_item_id
),
direct_time AS (
  SELECT
    te.budget_item_id,
    COALESCE(
      SUM(te.regular_hours + te.overtime_hours + te.double_time_hours),
      0
    ) AS tracked_hours,
    COALESCE(SUM(te.total_cost), 0) AS labor_cost
  FROM public.time_entries te
  WHERE te.status = 'approved'
    AND te.budget_item_id IS NOT NULL
  GROUP BY te.budget_item_id
)
SELECT
  COALESCE(
    task_estimates.budget_item_id,
    task_allocated_time.budget_item_id,
    direct_time.budget_item_id
  ) AS budget_item_id,
  COALESCE(task_estimates.task_count, 0) AS task_count,
  COALESCE(task_estimates.estimated_hours, 0) AS estimated_hours,
  COALESCE(task_allocated_time.tracked_hours, 0) +
      COALESCE(direct_time.tracked_hours, 0) AS tracked_hours,
  COALESCE(task_allocated_time.labor_cost, 0) +
      COALESCE(direct_time.labor_cost, 0) AS labor_cost
FROM task_estimates
FULL OUTER JOIN task_allocated_time
  ON task_allocated_time.budget_item_id = task_estimates.budget_item_id
FULL OUTER JOIN direct_time
  ON direct_time.budget_item_id = COALESCE(
    task_estimates.budget_item_id,
    task_allocated_time.budget_item_id
  );
