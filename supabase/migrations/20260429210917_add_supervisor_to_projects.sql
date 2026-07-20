-- Add supervisor_id to projects. Supervisor sits between Project Manager
-- and Team Members in the team hierarchy. Nullable, references users(id).

ALTER TABLE projects
  ADD COLUMN IF NOT EXISTS supervisor_id UUID REFERENCES users(id);

CREATE INDEX IF NOT EXISTS projects_supervisor_id_idx
  ON projects(supervisor_id)
  WHERE supervisor_id IS NOT NULL;
