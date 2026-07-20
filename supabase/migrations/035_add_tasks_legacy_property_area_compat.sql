-- Migration: Add compatibility columns for legacy task property/area fields
-- Purpose:
--   Older clients still read/write tasks.property_id and tasks.area_id.
--   Current schema uses tasks.property_ids/tasks.area_ids arrays.
--   This migration restores legacy columns and keeps both schemas in sync.

-- Add legacy columns back (nullable)
ALTER TABLE tasks
ADD COLUMN IF NOT EXISTS property_id UUID,
ADD COLUMN IF NOT EXISTS area_id UUID;

-- Recreate foreign keys if missing
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'tasks_property_id_fkey'
      AND conrelid = 'tasks'::regclass
  ) THEN
    ALTER TABLE tasks
      ADD CONSTRAINT tasks_property_id_fkey
      FOREIGN KEY (property_id) REFERENCES properties(id) ON DELETE SET NULL;
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'tasks_area_id_fkey'
      AND conrelid = 'tasks'::regclass
  ) THEN
    ALTER TABLE tasks
      ADD CONSTRAINT tasks_area_id_fkey
      FOREIGN KEY (area_id) REFERENCES areas(id) ON DELETE SET NULL;
  END IF;
END $$;

-- Indexes for legacy lookup patterns
CREATE INDEX IF NOT EXISTS idx_tasks_property_id ON tasks(property_id)
WHERE property_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_tasks_area_id ON tasks(area_id)
WHERE area_id IS NOT NULL;

-- Backfill legacy scalar columns from array columns
UPDATE tasks
SET property_id = NULLIF(property_ids[1], '')::uuid
WHERE property_id IS NULL
  AND COALESCE(array_length(property_ids, 1), 0) > 0
  AND property_ids[1] ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$';

UPDATE tasks
SET area_id = NULLIF(area_ids[1], '')::uuid
WHERE area_id IS NULL
  AND COALESCE(array_length(area_ids, 1), 0) > 0
  AND area_ids[1] ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$';

-- Backfill array columns from legacy scalar columns
UPDATE tasks
SET property_ids = ARRAY[property_id::text]
WHERE property_id IS NOT NULL
  AND COALESCE(array_length(property_ids, 1), 0) = 0;

UPDATE tasks
SET area_ids = ARRAY[area_id::text]
WHERE area_id IS NOT NULL
  AND COALESCE(array_length(area_ids, 1), 0) = 0;

-- Keep legacy scalar and array columns synchronized for mixed client versions
CREATE OR REPLACE FUNCTION sync_tasks_property_area_legacy()
RETURNS TRIGGER AS $$
BEGIN
  -- property sync
  IF NEW.property_id IS NOT NULL
     AND COALESCE(array_length(NEW.property_ids, 1), 0) = 0 THEN
    NEW.property_ids := ARRAY[NEW.property_id::text];
  ELSIF NEW.property_id IS NULL
        AND COALESCE(array_length(NEW.property_ids, 1), 0) > 0 THEN
    BEGIN
      NEW.property_id := NULLIF(NEW.property_ids[1], '')::uuid;
    EXCEPTION WHEN OTHERS THEN
      NEW.property_id := NULL;
    END;
  END IF;

  -- area sync
  IF NEW.area_id IS NOT NULL
     AND COALESCE(array_length(NEW.area_ids, 1), 0) = 0 THEN
    NEW.area_ids := ARRAY[NEW.area_id::text];
  ELSIF NEW.area_id IS NULL
        AND COALESCE(array_length(NEW.area_ids, 1), 0) > 0 THEN
    BEGIN
      NEW.area_id := NULLIF(NEW.area_ids[1], '')::uuid;
    EXCEPTION WHEN OTHERS THEN
      NEW.area_id := NULL;
    END;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_sync_tasks_property_area_legacy ON tasks;
CREATE TRIGGER trg_sync_tasks_property_area_legacy
BEFORE INSERT OR UPDATE ON tasks
FOR EACH ROW
EXECUTE FUNCTION sync_tasks_property_area_legacy();
