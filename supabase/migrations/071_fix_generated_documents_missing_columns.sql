-- Ensure generated_documents has all columns required by the current app code.
-- This is idempotent and safe to run on databases that already have these fields.

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_type
    WHERE typname = 'line_item_source_mode'
      AND typnamespace = 'public'::regnamespace
  ) THEN
    CREATE TYPE public.line_item_source_mode AS ENUM (
      'snapshot',
      'resync_until_signed'
    );
  END IF;
END $$;

ALTER TABLE public.generated_documents
  ADD COLUMN IF NOT EXISTS line_item_source_mode public.line_item_source_mode;

UPDATE public.generated_documents
SET line_item_source_mode = 'snapshot'
WHERE line_item_source_mode IS NULL;

ALTER TABLE public.generated_documents
  ALTER COLUMN line_item_source_mode SET DEFAULT 'snapshot',
  ALTER COLUMN line_item_source_mode SET NOT NULL;

ALTER TABLE public.generated_documents
  ADD COLUMN IF NOT EXISTS collect_tax boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS tax_name text,
  ADD COLUMN IF NOT EXISTS tax_rate double precision NOT NULL DEFAULT 0;

CREATE INDEX IF NOT EXISTS idx_generated_documents_line_item_source_mode
  ON public.generated_documents (workspace_id, line_item_source_mode);
