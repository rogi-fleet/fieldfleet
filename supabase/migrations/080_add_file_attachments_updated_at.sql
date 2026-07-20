-- Add updated_at column to file_attachments table
ALTER TABLE public.file_attachments
ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT NOW();

-- Backfill existing rows
UPDATE public.file_attachments
SET updated_at = COALESCE(updated_at, created_at, uploaded_at, NOW())
WHERE updated_at IS NULL;

-- Keep updated_at in sync on row updates
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_trigger
    WHERE tgname = 'set_file_attachments_updated_at'
  ) THEN
    CREATE TRIGGER set_file_attachments_updated_at
    BEFORE UPDATE ON public.file_attachments
    FOR EACH ROW
    EXECUTE FUNCTION public.update_updated_at_column();
  END IF;
END $$;
