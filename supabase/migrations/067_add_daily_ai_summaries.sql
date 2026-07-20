-- Daily AI summaries for dashboard
CREATE TABLE IF NOT EXISTS daily_ai_summaries (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  summary_date DATE NOT NULL,
  timezone TEXT NOT NULL,
  summary_markdown TEXT NOT NULL,
  source_data JSONB NOT NULL,
  provider TEXT,
  model TEXT,
  prompt_version TEXT,
  generated_at TIMESTAMPTZ DEFAULT NOW(),
  status TEXT DEFAULT 'success',
  error TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS daily_ai_summaries_unique
  ON daily_ai_summaries (workspace_id, user_id, summary_date);

CREATE INDEX IF NOT EXISTS daily_ai_summaries_user_date
  ON daily_ai_summaries (user_id, summary_date);

ALTER TABLE daily_ai_summaries ENABLE ROW LEVEL SECURITY;

-- Users can read their own summaries
DROP POLICY IF EXISTS "Users can read their own daily summaries" ON daily_ai_summaries;
CREATE POLICY "Users can read their own daily summaries"
  ON daily_ai_summaries
  FOR SELECT
  USING (user_id = auth.uid());

-- Service role only for writes
DROP POLICY IF EXISTS "Service role can write daily summaries" ON daily_ai_summaries;
CREATE POLICY "Service role can write daily summaries"
  ON daily_ai_summaries
  FOR ALL
  USING (auth.role() = 'service_role')
  WITH CHECK (auth.role() = 'service_role');

-- Trigger to update updated_at
CREATE OR REPLACE FUNCTION set_daily_ai_summaries_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER daily_ai_summaries_updated_at
  BEFORE UPDATE ON daily_ai_summaries
  FOR EACH ROW
  EXECUTE FUNCTION set_daily_ai_summaries_updated_at();
