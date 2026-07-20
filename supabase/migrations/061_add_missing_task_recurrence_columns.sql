-- Backfill recurring-task columns for environments where they are missing.
ALTER TABLE public.tasks
  ADD COLUMN IF NOT EXISTS is_recurring BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS recurrence_rule JSONB,
  ADD COLUMN IF NOT EXISTS recurring_parent_id UUID,
  ADD COLUMN IF NOT EXISTS occurrence_index INTEGER NOT NULL DEFAULT 0;

UPDATE public.tasks
SET
  is_recurring = COALESCE(is_recurring, FALSE),
  occurrence_index = COALESCE(occurrence_index, 0);

-- Refresh PostgREST schema cache so new columns are visible immediately.
NOTIFY pgrst, 'reload schema';
