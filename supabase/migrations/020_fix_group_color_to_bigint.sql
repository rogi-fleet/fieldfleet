-- Fix group_color column type from INTEGER to BIGINT
-- Flutter color values with alpha channel (like 0xFF2196F3) can exceed INTEGER max value
-- PostgreSQL INTEGER max is 2,147,483,647 but Flutter colors can be up to 4,294,967,295

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'tasks' AND column_name = 'group_color' AND data_type = 'integer'
  ) THEN
    ALTER TABLE tasks ALTER COLUMN group_color TYPE BIGINT;
  END IF;
END $$;
