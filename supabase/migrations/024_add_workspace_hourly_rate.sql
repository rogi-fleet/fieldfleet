-- Add hourly_rate column to workspaces table
ALTER TABLE workspaces ADD COLUMN IF NOT EXISTS hourly_rate NUMERIC;

-- Comment for documentation
COMMENT ON COLUMN workspaces.hourly_rate IS 'Default hourly rate for all members in the workspace if not specified per-member.';
