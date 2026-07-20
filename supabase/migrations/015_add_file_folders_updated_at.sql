-- Add updated_at column to file_folders table
ALTER TABLE file_folders
ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT NOW();

-- Update existing rows to have updated_at equal to created_at
UPDATE file_folders
SET updated_at = created_at
WHERE updated_at IS NULL;
