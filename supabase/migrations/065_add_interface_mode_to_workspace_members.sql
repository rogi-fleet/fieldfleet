ALTER TABLE workspace_members
  ADD COLUMN IF NOT EXISTS interface_mode TEXT NOT NULL DEFAULT 'manager'
  CHECK (interface_mode IN ('manager', 'field'));
