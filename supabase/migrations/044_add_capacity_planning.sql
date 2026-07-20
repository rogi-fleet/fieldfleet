-- Capacity planning: defaults, per-member overrides, and availability exceptions

ALTER TABLE workspaces
ADD COLUMN IF NOT EXISTS default_weekly_capacity_hours NUMERIC NOT NULL DEFAULT 40;

COMMENT ON COLUMN workspaces.default_weekly_capacity_hours IS
'Default weekly capacity hours used for workload planning when a member override is not set.';

ALTER TABLE workspace_members
ADD COLUMN IF NOT EXISTS weekly_capacity_hours NUMERIC;

COMMENT ON COLUMN workspace_members.weekly_capacity_hours IS
'Optional per-member weekly capacity override for workload planning.';

CREATE TABLE IF NOT EXISTS workspace_member_capacity_exceptions (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  start_date DATE NOT NULL,
  end_date DATE NOT NULL,
  capacity_multiplier NUMERIC NOT NULL DEFAULT 0,
  reason TEXT,
  created_by UUID REFERENCES users(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT workspace_member_capacity_exceptions_date_check CHECK (end_date >= start_date)
);

CREATE INDEX IF NOT EXISTS idx_capacity_exceptions_workspace_user_range
ON workspace_member_capacity_exceptions (workspace_id, user_id, start_date, end_date);

CREATE INDEX IF NOT EXISTS idx_capacity_exceptions_workspace_range
ON workspace_member_capacity_exceptions (workspace_id, start_date, end_date);
