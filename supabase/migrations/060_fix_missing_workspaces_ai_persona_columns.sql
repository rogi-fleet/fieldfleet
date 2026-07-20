-- Defensive repair for environments where AI persona columns are missing on workspaces.
ALTER TABLE public.workspaces
  ADD COLUMN IF NOT EXISTS ai_persona_name TEXT,
  ADD COLUMN IF NOT EXISTS ai_persona_avatar TEXT,
  ADD COLUMN IF NOT EXISTS ai_persona_style TEXT,
  ADD COLUMN IF NOT EXISTS ai_persona_context TEXT;

UPDATE public.workspaces
SET
  ai_persona_avatar = COALESCE(NULLIF(btrim(ai_persona_avatar), ''), 'hard_hat'),
  ai_persona_style = COALESCE(NULLIF(btrim(ai_persona_style), ''), 'mentor');

ALTER TABLE public.workspaces
  ALTER COLUMN ai_persona_avatar SET DEFAULT 'hard_hat',
  ALTER COLUMN ai_persona_style SET DEFAULT 'mentor';

-- Refresh PostgREST schema cache so new columns are visible immediately.
NOTIFY pgrst, 'reload schema';
