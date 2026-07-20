-- Automation rules engine foundation
-- Adds workspace-scoped rules/actions/execution logs and extends notifications type checks.

CREATE TABLE IF NOT EXISTS automation_rules (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  description TEXT,
  trigger_type TEXT NOT NULL CHECK (
    trigger_type IN (
      'task_status_changed',
      'task_assigned',
      'task_due_overdue',
      'invoice_status_changed'
    )
  ),
  conditions JSONB NOT NULL DEFAULT '{}'::jsonb,
  is_enabled BOOLEAN NOT NULL DEFAULT true,
  created_by UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
  updated_by UUID REFERENCES users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_automation_rules_workspace
  ON automation_rules(workspace_id);
CREATE INDEX IF NOT EXISTS idx_automation_rules_workspace_enabled_trigger
  ON automation_rules(workspace_id, is_enabled, trigger_type);

CREATE TABLE IF NOT EXISTS automation_actions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  rule_id UUID NOT NULL REFERENCES automation_rules(id) ON DELETE CASCADE,
  workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
  action_type TEXT NOT NULL CHECK (
    action_type IN (
      'create_notification',
      'create_task',
      'update_field',
      'add_tag'
    )
  ),
  payload JSONB NOT NULL DEFAULT '{}'::jsonb,
  sort_order INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT automation_actions_rule_sort_unique UNIQUE (rule_id, sort_order)
);

CREATE INDEX IF NOT EXISTS idx_automation_actions_workspace_rule
  ON automation_actions(workspace_id, rule_id, sort_order);

CREATE TABLE IF NOT EXISTS automation_executions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
  rule_id UUID REFERENCES automation_rules(id) ON DELETE SET NULL,
  trigger_type TEXT NOT NULL,
  event_key TEXT NOT NULL,
  status TEXT NOT NULL CHECK (status IN ('success', 'failed', 'skipped')),
  error_message TEXT,
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  executed_actions JSONB NOT NULL DEFAULT '[]'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_automation_executions_workspace_created
  ON automation_executions(workspace_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_automation_executions_rule_created
  ON automation_executions(rule_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_automation_executions_workspace_event
  ON automation_executions(workspace_id, event_key);

ALTER TABLE automation_rules ENABLE ROW LEVEL SECURITY;
ALTER TABLE automation_actions ENABLE ROW LEVEL SECURITY;
ALTER TABLE automation_executions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS automation_rules_select ON automation_rules;
CREATE POLICY automation_rules_select ON automation_rules
  FOR SELECT USING (is_workspace_member(workspace_id));

DROP POLICY IF EXISTS automation_rules_insert ON automation_rules;
CREATE POLICY automation_rules_insert ON automation_rules
  FOR INSERT WITH CHECK (
    is_pm_or_admin(workspace_id) AND created_by = auth.uid()
  );

DROP POLICY IF EXISTS automation_rules_update ON automation_rules;
CREATE POLICY automation_rules_update ON automation_rules
  FOR UPDATE USING (is_pm_or_admin(workspace_id));

DROP POLICY IF EXISTS automation_rules_delete ON automation_rules;
CREATE POLICY automation_rules_delete ON automation_rules
  FOR DELETE USING (is_pm_or_admin(workspace_id));

DROP POLICY IF EXISTS automation_actions_select ON automation_actions;
CREATE POLICY automation_actions_select ON automation_actions
  FOR SELECT USING (is_workspace_member(workspace_id));

DROP POLICY IF EXISTS automation_actions_insert ON automation_actions;
CREATE POLICY automation_actions_insert ON automation_actions
  FOR INSERT WITH CHECK (is_pm_or_admin(workspace_id));

DROP POLICY IF EXISTS automation_actions_update ON automation_actions;
CREATE POLICY automation_actions_update ON automation_actions
  FOR UPDATE USING (is_pm_or_admin(workspace_id));

DROP POLICY IF EXISTS automation_actions_delete ON automation_actions;
CREATE POLICY automation_actions_delete ON automation_actions
  FOR DELETE USING (is_pm_or_admin(workspace_id));

DROP POLICY IF EXISTS automation_executions_select ON automation_executions;
CREATE POLICY automation_executions_select ON automation_executions
  FOR SELECT USING (is_pm_or_admin(workspace_id));

DROP POLICY IF EXISTS automation_executions_insert ON automation_executions;
CREATE POLICY automation_executions_insert ON automation_executions
  FOR INSERT WITH CHECK (is_workspace_member(workspace_id));

-- Extend notification type check to allow automation-generated in-app notifications.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'notifications_type_check'
      AND conrelid = 'notifications'::regclass
  ) THEN
    ALTER TABLE notifications DROP CONSTRAINT notifications_type_check;
  END IF;
END $$;

ALTER TABLE notifications
  ADD CONSTRAINT notifications_type_check
  CHECK (
    type IN (
      'mention',
      'task_assignment',
      'task_completion',
      'automation'
    )
  );

ALTER PUBLICATION supabase_realtime ADD TABLE automation_rules;
ALTER PUBLICATION supabase_realtime ADD TABLE automation_actions;
ALTER PUBLICATION supabase_realtime ADD TABLE automation_executions;
