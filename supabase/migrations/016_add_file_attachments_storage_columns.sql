-- Add storage-related columns to file_attachments table
ALTER TABLE file_attachments
ADD COLUMN IF NOT EXISTS bucket TEXT,
ADD COLUMN IF NOT EXISTS storage_path TEXT,
ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ DEFAULT NOW();

-- Update existing rows to set created_at from uploaded_at if null
UPDATE file_attachments
SET created_at = uploaded_at
WHERE created_at IS NULL;
