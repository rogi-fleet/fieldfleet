-- Add end_date column to tasks table
-- end_date tracks when a task was actually completed (distinct from due_date which is the deadline)
-- Automatically set to NOW() when a task is marked as done

ALTER TABLE tasks
  ADD COLUMN IF NOT EXISTS end_date TIMESTAMPTZ;
