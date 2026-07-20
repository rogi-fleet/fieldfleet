-- Migration: Add user_task_expansion_prefs table
-- This table stores per-user expansion state for tasks in the Gantt chart

CREATE TABLE IF NOT EXISTS user_task_expansion_prefs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  expansion_states JSONB DEFAULT '{}'::jsonb,
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(user_id, project_id)
);

-- Enable RLS
-- ALTER TABLE user_task_expansion_prefs ENABLE ROW LEVEL SECURITY;

-- Users can manage their own expansion preferences
DROP POLICY IF EXISTS "Users can manage own expansion prefs" ON user_task_expansion_prefs;
CREATE POLICY "Users can manage own expansion prefs"
  ON user_task_expansion_prefs
  FOR ALL
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- Index for faster lookups
CREATE INDEX IF NOT EXISTS idx_user_task_expansion_prefs_user_project
  ON user_task_expansion_prefs(user_id, project_id);
