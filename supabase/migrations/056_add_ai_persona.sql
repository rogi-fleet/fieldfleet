ALTER TABLE workspaces
  ADD COLUMN IF NOT EXISTS ai_persona_name    TEXT,
  ADD COLUMN IF NOT EXISTS ai_persona_avatar  TEXT DEFAULT 'hard_hat',
  ADD COLUMN IF NOT EXISTS ai_persona_style   TEXT DEFAULT 'mentor',
  ADD COLUMN IF NOT EXISTS ai_persona_context TEXT;
