-- Add new array columns for multi-location support
ALTER TABLE tasks ADD COLUMN IF NOT EXISTS property_ids text[] DEFAULT '{}';
ALTER TABLE tasks ADD COLUMN IF NOT EXISTS area_ids text[] DEFAULT '{}';

-- Migrate existing data from single columns to arrays
UPDATE tasks
SET property_ids = ARRAY[property_id::text]
WHERE property_id IS NOT NULL AND (property_ids IS NULL OR property_ids = '{}');

UPDATE tasks
SET area_ids = ARRAY[area_id::text]
WHERE area_id IS NOT NULL AND (area_ids IS NULL OR area_ids = '{}');

-- Drop old columns and their indexes
DROP INDEX IF EXISTS idx_tasks_property_id;
DROP INDEX IF EXISTS idx_tasks_area_id;
ALTER TABLE tasks DROP COLUMN IF EXISTS property_id;
ALTER TABLE tasks DROP COLUMN IF EXISTS area_id;

-- Add GIN indexes for containment queries on new array columns
CREATE INDEX IF NOT EXISTS idx_tasks_property_ids ON tasks USING GIN (property_ids);
CREATE INDEX IF NOT EXISTS idx_tasks_area_ids ON tasks USING GIN (area_ids);
