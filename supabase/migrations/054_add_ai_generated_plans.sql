-- Create ai_generated_plans table to persist AI-generated project plans
CREATE TABLE IF NOT EXISTS ai_generated_plans (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id TEXT NOT NULL,
    workspace_id UUID NOT NULL,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    status TEXT NOT NULL DEFAULT 'generating' CHECK (status IN ('generating', 'ready', 'failed')),
    plan_json JSONB,
    error_message TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_ai_generated_plans_project ON ai_generated_plans(project_id, status);
CREATE INDEX IF NOT EXISTS idx_ai_generated_plans_user ON ai_generated_plans(user_id, workspace_id, created_at DESC);

ALTER TABLE ai_generated_plans ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'ai_generated_plans'
          AND policyname = 'Users can view own AI plans'
    ) THEN
        CREATE POLICY "Users can view own AI plans"
            ON ai_generated_plans FOR SELECT
            USING (auth.uid() = user_id);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'ai_generated_plans'
          AND policyname = 'Users can insert own AI plans'
    ) THEN
        CREATE POLICY "Users can insert own AI plans"
            ON ai_generated_plans FOR INSERT
            WITH CHECK (auth.uid() = user_id);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'ai_generated_plans'
          AND policyname = 'Users can update own AI plans'
    ) THEN
        CREATE POLICY "Users can update own AI plans"
            ON ai_generated_plans FOR UPDATE
            USING (auth.uid() = user_id);
    END IF;
END $$;

-- Enable realtime so the app can react to status changes
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_publication_rel pr
        JOIN pg_class c ON c.oid = pr.prrelid
        JOIN pg_namespace n ON n.oid = c.relnamespace
        JOIN pg_publication p ON p.oid = pr.prpubid
        WHERE p.pubname = 'supabase_realtime'
          AND n.nspname = 'public'
          AND c.relname = 'ai_generated_plans'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE ai_generated_plans;
    END IF;
END $$;

-- Update notification type check constraint to include AI plan types
ALTER TABLE notifications DROP CONSTRAINT IF EXISTS notifications_type_check;
ALTER TABLE notifications ADD CONSTRAINT notifications_type_check
    CHECK (type IN ('mention', 'task_assignment', 'task_completion', 'ai_plan_ready', 'ai_plan_failed'));
