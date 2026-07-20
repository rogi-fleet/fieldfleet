-- Add thumbnail_url column to file_attachments for image thumbnails
ALTER TABLE file_attachments ADD COLUMN IF NOT EXISTS thumbnail_url TEXT;
