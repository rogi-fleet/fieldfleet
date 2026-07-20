-- Defensive repair for local environments where workspaces.timezone is missing.
ALTER TABLE public.workspaces
ADD COLUMN IF NOT EXISTS timezone TEXT;

UPDATE public.workspaces
SET timezone = 'UTC'
WHERE timezone IS NULL OR btrim(timezone) = '';

ALTER TABLE public.workspaces
ALTER COLUMN timezone SET DEFAULT 'UTC';

-- Refresh PostgREST schema cache so the column is visible immediately.
NOTIFY pgrst, 'reload schema';
