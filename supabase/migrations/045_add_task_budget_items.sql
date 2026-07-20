-- Task ↔ Budget Item many-to-many linkage and labor summary view

-- ============================================================================
-- JUNCTION TABLE
-- ============================================================================

CREATE TABLE IF NOT EXISTS task_budget_items (
  task_id UUID NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
  budget_item_id UUID NOT NULL REFERENCES budget_items(id) ON DELETE CASCADE,
  allocation_percentage NUMERIC(5,2) NOT NULL DEFAULT 100,
  workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (task_id, budget_item_id),
  CONSTRAINT task_budget_items_allocation_check
    CHECK (allocation_percentage > 0 AND allocation_percentage <= 100)
);

CREATE INDEX IF NOT EXISTS idx_task_budget_items_budget_item
  ON task_budget_items(budget_item_id);

CREATE INDEX IF NOT EXISTS idx_task_budget_items_task
  ON task_budget_items(task_id);

CREATE INDEX IF NOT EXISTS idx_task_budget_items_workspace
  ON task_budget_items(workspace_id);

-- ============================================================================
-- ROW LEVEL SECURITY
-- ============================================================================

ALTER TABLE task_budget_items ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS task_budget_items_select ON task_budget_items;
CREATE POLICY task_budget_items_select ON task_budget_items
  FOR SELECT USING (is_workspace_member(workspace_id));

DROP POLICY IF EXISTS task_budget_items_insert ON task_budget_items;
CREATE POLICY task_budget_items_insert ON task_budget_items
  FOR INSERT WITH CHECK (is_workspace_member(workspace_id));

DROP POLICY IF EXISTS task_budget_items_update ON task_budget_items;
CREATE POLICY task_budget_items_update ON task_budget_items
  FOR UPDATE USING (is_workspace_member(workspace_id));

DROP POLICY IF EXISTS task_budget_items_delete ON task_budget_items;
CREATE POLICY task_budget_items_delete ON task_budget_items
  FOR DELETE USING (is_workspace_member(workspace_id));

-- ============================================================================
-- REALTIME
-- ============================================================================

ALTER PUBLICATION supabase_realtime ADD TABLE task_budget_items;

-- ============================================================================
-- LABOR SUMMARY VIEW
-- ============================================================================

CREATE OR REPLACE VIEW budget_item_labor_summary AS
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
FROM task_budget_items tbi
JOIN tasks t ON t.id = tbi.task_id
LEFT JOIN time_entries te ON te.task_id = tbi.task_id
GROUP BY tbi.budget_item_id;
