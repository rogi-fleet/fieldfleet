-- Add weekly_wage columns for workspace and members
ALTER TABLE workspaces
  ADD COLUMN IF NOT EXISTS weekly_wage NUMERIC;

COMMENT ON COLUMN workspaces.weekly_wage IS 'Default weekly wage for members in the workspace if not specified per-member.';

ALTER TABLE workspace_members
  ADD COLUMN IF NOT EXISTS weekly_wage NUMERIC;

COMMENT ON COLUMN workspace_members.weekly_wage IS 'Weekly wage for a specific workspace member.';
