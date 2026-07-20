-- Migration: AI copilot foundation (feature flags, events, weekly digests)

CREATE TABLE IF NOT EXISTS workspace_feature_flags (
  workspace_id UUID PRIMARY KEY REFERENCES workspaces(id) ON DELETE CASCADE,
  flags JSONB NOT NULL DEFAULT '{}'::jsonb,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS ai_copilot_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  project_id UUID REFERENCES projects(id) ON DELETE SET NULL,
  operation TEXT NOT NULL,
  status TEXT NOT NULL,
  request_payload JSONB,
  response_payload JSONB,
  provider TEXT,
  model TEXT,
  latency_ms INTEGER,
  error TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_ai_copilot_events_workspace_created
  ON ai_copilot_events(workspace_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_ai_copilot_events_operation_created
  ON ai_copilot_events(operation, created_at DESC);

CREATE TABLE IF NOT EXISTS weekly_ai_project_digests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  week_start_date DATE NOT NULL,
  week_end_date DATE NOT NULL,
  timezone TEXT NOT NULL DEFAULT 'UTC',
  digest_markdown TEXT NOT NULL DEFAULT '',
  source_data JSONB,
  provider TEXT NOT NULL DEFAULT 'rule_based',
  model TEXT,
  prompt_version TEXT NOT NULL DEFAULT 'v1',
  status TEXT NOT NULL DEFAULT 'success',
  error TEXT,
  generated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT weekly_ai_project_digests_unique
    UNIQUE (workspace_id, user_id, project_id, week_start_date)
);

CREATE INDEX IF NOT EXISTS idx_weekly_ai_project_digests_workspace_week
  ON weekly_ai_project_digests(workspace_id, week_start_date DESC);

ALTER TABLE workspace_feature_flags ENABLE ROW LEVEL SECURITY;
ALTER TABLE ai_copilot_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE weekly_ai_project_digests ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS workspace_feature_flags_select ON workspace_feature_flags;
CREATE POLICY workspace_feature_flags_select ON workspace_feature_flags
  FOR SELECT USING (is_workspace_member(workspace_id));

DROP POLICY IF EXISTS workspace_feature_flags_upsert ON workspace_feature_flags;
CREATE POLICY workspace_feature_flags_upsert ON workspace_feature_flags
  FOR ALL USING (is_workspace_admin(workspace_id))
  WITH CHECK (is_workspace_admin(workspace_id));

DROP POLICY IF EXISTS ai_copilot_events_select ON ai_copilot_events;
CREATE POLICY ai_copilot_events_select ON ai_copilot_events
  FOR SELECT USING (is_workspace_member(workspace_id));

DROP POLICY IF EXISTS ai_copilot_events_insert ON ai_copilot_events;
CREATE POLICY ai_copilot_events_insert ON ai_copilot_events
  FOR INSERT WITH CHECK (
    is_workspace_member(workspace_id)
    AND user_id = auth.uid()
  );

DROP POLICY IF EXISTS weekly_ai_project_digests_select ON weekly_ai_project_digests;
CREATE POLICY weekly_ai_project_digests_select ON weekly_ai_project_digests
  FOR SELECT USING (is_workspace_member(workspace_id));

DROP POLICY IF EXISTS weekly_ai_project_digests_insert ON weekly_ai_project_digests;
CREATE POLICY weekly_ai_project_digests_insert ON weekly_ai_project_digests
  FOR INSERT WITH CHECK (
    is_workspace_member(workspace_id)
    AND user_id = auth.uid()
  );

DROP POLICY IF EXISTS weekly_ai_project_digests_update ON weekly_ai_project_digests;
CREATE POLICY weekly_ai_project_digests_update ON weekly_ai_project_digests
  FOR UPDATE USING (
    is_workspace_member(workspace_id)
    AND user_id = auth.uid()
  )
  WITH CHECK (
    is_workspace_member(workspace_id)
    AND user_id = auth.uid()
  );

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = 'set_weekly_ai_project_digests_updated_at'
  ) THEN
    CREATE TRIGGER set_weekly_ai_project_digests_updated_at
    BEFORE UPDATE ON weekly_ai_project_digests
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();
  END IF;
END $$;
