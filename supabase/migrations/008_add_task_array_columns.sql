-- Add missing array columns to tasks table for Supabase service compatibility
-- These columns store denormalized arrays for faster queries

-- Add assigned_to_ids array column
ALTER TABLE tasks ADD COLUMN IF NOT EXISTS assigned_to_ids TEXT[] DEFAULT '{}';

-- Add required_asset_ids array column
ALTER TABLE tasks ADD COLUMN IF NOT EXISTS required_asset_ids TEXT[] DEFAULT '{}';

-- Add predecessor_ids array column
ALTER TABLE tasks ADD COLUMN IF NOT EXISTS predecessor_ids TEXT[] DEFAULT '{}';

-- Add required_skill_ids array column
ALTER TABLE tasks ADD COLUMN IF NOT EXISTS required_skill_ids TEXT[] DEFAULT '{}';

-- Update group_color to be integer if it's text (for hex color storage)
-- First check if it exists and its type
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'tasks' AND column_name = 'group_color' AND data_type = 'text'
  ) THEN
    ALTER TABLE tasks ALTER COLUMN group_color TYPE INTEGER USING NULL;
  ELSIF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'tasks' AND column_name = 'group_color'
  ) THEN
    ALTER TABLE tasks ADD COLUMN group_color INTEGER;
  END IF;
END $$;

-- Add assigned_to column for single assignee (legacy compatibility)
ALTER TABLE tasks ADD COLUMN IF NOT EXISTS assigned_to UUID REFERENCES users(id);

-- Create index on array columns for better query performance
CREATE INDEX IF NOT EXISTS idx_tasks_assigned_to_ids ON tasks USING GIN (assigned_to_ids);
CREATE INDEX IF NOT EXISTS idx_tasks_required_skill_ids ON tasks USING GIN (required_skill_ids);
