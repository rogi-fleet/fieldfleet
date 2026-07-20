-- Migration: Add timezone to workspaces for schedule and settings defaults

ALTER TABLE workspaces
ADD COLUMN IF NOT EXISTS timezone TEXT DEFAULT 'UTC';

UPDATE workspaces
SET timezone = 'UTC'
WHERE timezone IS NULL OR timezone = '';

ALTER TABLE workspaces
ALTER COLUMN timezone SET DEFAULT 'UTC';
