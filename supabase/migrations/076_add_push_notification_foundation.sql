-- Push notification foundation: device registration, delivery logs, and
-- notification type extension for priority alerts.

CREATE TABLE IF NOT EXISTS public.push_devices (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  workspace_id UUID REFERENCES public.workspaces(id) ON DELETE CASCADE,
  device_id TEXT NOT NULL,
  platform TEXT NOT NULL CHECK (platform IN ('android', 'ios')),
  transport TEXT NOT NULL DEFAULT 'fcm' CHECK (transport IN ('fcm', 'apns')),
  push_token TEXT NOT NULL,
  app_version TEXT,
  timezone TEXT,
  locale TEXT,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  last_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT push_devices_user_device_unique UNIQUE (user_id, device_id, platform, transport),
  CONSTRAINT push_devices_token_unique UNIQUE (platform, transport, push_token)
);

CREATE INDEX IF NOT EXISTS idx_push_devices_user_active
  ON public.push_devices (user_id, is_active);

CREATE INDEX IF NOT EXISTS idx_push_devices_workspace_active
  ON public.push_devices (workspace_id, is_active);

CREATE TABLE IF NOT EXISTS public.push_delivery_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  notification_id UUID REFERENCES public.notifications(id) ON DELETE SET NULL,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  device_id UUID REFERENCES public.push_devices(id) ON DELETE SET NULL,
  provider TEXT NOT NULL,
  status TEXT NOT NULL CHECK (status IN ('queued', 'sent', 'failed', 'invalid_token', 'skipped')),
  error_code TEXT,
  error_message TEXT,
  payload JSONB,
  attempted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_push_delivery_logs_notification_attempted
  ON public.push_delivery_logs (notification_id, attempted_at DESC);

CREATE INDEX IF NOT EXISTS idx_push_delivery_logs_user_attempted
  ON public.push_delivery_logs (user_id, attempted_at DESC);

ALTER TABLE public.push_devices ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.push_delivery_logs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS push_devices_select_own ON public.push_devices;
CREATE POLICY push_devices_select_own
  ON public.push_devices
  FOR SELECT
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS push_devices_insert_own ON public.push_devices;
CREATE POLICY push_devices_insert_own
  ON public.push_devices
  FOR INSERT
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS push_devices_update_own ON public.push_devices;
CREATE POLICY push_devices_update_own
  ON public.push_devices
  FOR UPDATE
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS push_devices_delete_own ON public.push_devices;
CREATE POLICY push_devices_delete_own
  ON public.push_devices
  FOR DELETE
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS push_delivery_logs_select_own ON public.push_delivery_logs;
CREATE POLICY push_delivery_logs_select_own
  ON public.push_delivery_logs
  FOR SELECT
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS push_delivery_logs_service_role_all ON public.push_delivery_logs;
CREATE POLICY push_delivery_logs_service_role_all
  ON public.push_delivery_logs
  FOR ALL
  USING (auth.role() = 'service_role')
  WITH CHECK (auth.role() = 'service_role');

DROP TRIGGER IF EXISTS set_push_devices_updated_at ON public.push_devices;
CREATE TRIGGER set_push_devices_updated_at
  BEFORE UPDATE ON public.push_devices
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at_column();

ALTER TABLE public.notifications DROP CONSTRAINT IF EXISTS notifications_type_check;
ALTER TABLE public.notifications ADD CONSTRAINT notifications_type_check
  CHECK (
    type IN (
      'mention',
      'task_assignment',
      'task_completion',
      'ai_plan_ready',
      'ai_plan_failed',
      'automation',
      'capacity_alert',
      'priority_alert'
    )
  );

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
      AND c.relname = 'push_devices'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.push_devices;
  END IF;
END $$;
