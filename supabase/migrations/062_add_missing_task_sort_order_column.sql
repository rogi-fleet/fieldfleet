-- Backfill task ordering column for environments where it is missing.
ALTER TABLE public.tasks
  ADD COLUMN IF NOT EXISTS sort_order DOUBLE PRECISION NOT NULL DEFAULT 0;

UPDATE public.tasks
SET sort_order = 0
WHERE sort_order IS NULL;

-- Refresh PostgREST schema cache so the column is visible immediately.
NOTIFY pgrst, 'reload schema';
