-- ===========================================================================
-- G3: schedule baselines for the project Gantt.
--
-- A baseline is a named snapshot of every task's *effective* schedule dates
-- (groups store their child-derived span) taken at a point in time, so the
-- Gantt can render planned-vs-actual ghost bars and per-task slip. Snapshots
-- are captured client-side (the effective-date rollup for summary tasks lives
-- in Dart), so there is no capture RPC here.
--
-- schedule_baseline_tasks.task_id is deliberately NOT a foreign key: the
-- snapshot is historical and must not mutate when tasks are deleted; rows for
-- since-deleted tasks are simply ignored at render time.
-- ===========================================================================

CREATE TABLE IF NOT EXISTS schedule_baselines (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
  project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  name TEXT NOT NULL DEFAULT 'Baseline',
  created_by UUID REFERENCES users(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_schedule_baselines_project
  ON schedule_baselines(project_id, created_at DESC);

CREATE TABLE IF NOT EXISTS schedule_baseline_tasks (
  baseline_id UUID NOT NULL REFERENCES schedule_baselines(id) ON DELETE CASCADE,
  task_id UUID NOT NULL,
  start_date TIMESTAMPTZ,
  due_date TIMESTAMPTZ,
  estimated_duration DECIMAL(6,2),
  PRIMARY KEY (baseline_id, task_id)
);

ALTER TABLE schedule_baselines ENABLE ROW LEVEL SECURITY;
ALTER TABLE schedule_baseline_tasks ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS schedule_baselines_select ON schedule_baselines;
CREATE POLICY schedule_baselines_select ON schedule_baselines
  FOR SELECT USING (is_workspace_member(workspace_id));
DROP POLICY IF EXISTS schedule_baselines_insert ON schedule_baselines;
CREATE POLICY schedule_baselines_insert ON schedule_baselines
  FOR INSERT WITH CHECK (is_workspace_member(workspace_id));
DROP POLICY IF EXISTS schedule_baselines_delete ON schedule_baselines;
CREATE POLICY schedule_baselines_delete ON schedule_baselines
  FOR DELETE USING (is_workspace_member(workspace_id));

DROP POLICY IF EXISTS schedule_baseline_tasks_select ON schedule_baseline_tasks;
CREATE POLICY schedule_baseline_tasks_select ON schedule_baseline_tasks
  FOR SELECT USING (EXISTS (
    SELECT 1 FROM schedule_baselines b
    WHERE b.id = baseline_id AND is_workspace_member(b.workspace_id)
  ));
DROP POLICY IF EXISTS schedule_baseline_tasks_insert ON schedule_baseline_tasks;
CREATE POLICY schedule_baseline_tasks_insert ON schedule_baseline_tasks
  FOR INSERT WITH CHECK (EXISTS (
    SELECT 1 FROM schedule_baselines b
    WHERE b.id = baseline_id AND is_workspace_member(b.workspace_id)
  ));
DROP POLICY IF EXISTS schedule_baseline_tasks_delete ON schedule_baseline_tasks;
CREATE POLICY schedule_baseline_tasks_delete ON schedule_baseline_tasks
  FOR DELETE USING (EXISTS (
    SELECT 1 FROM schedule_baselines b
    WHERE b.id = baseline_id AND is_workspace_member(b.workspace_id)
  ));
