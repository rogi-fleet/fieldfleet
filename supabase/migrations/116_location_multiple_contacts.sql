-- Allow multiple contacts per customer location
-- Migrate from single contact_id to contact_ids array

ALTER TABLE customer_locations
  ADD COLUMN contact_ids TEXT[] NOT NULL DEFAULT '{}'::TEXT[];

-- Migrate existing contact_id values
UPDATE customer_locations
SET contact_ids = ARRAY[contact_id::TEXT]
WHERE contact_id IS NOT NULL;

-- Drop the old FK column
ALTER TABLE customer_locations
  DROP COLUMN contact_id;
