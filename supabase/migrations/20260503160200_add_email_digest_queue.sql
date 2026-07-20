-- Email digest pipeline.
--
-- Today every email goes out immediately, which is fine for a quiet user
-- but quickly becomes noise for someone watching a busy workspace. This
-- migration introduces a small queue + per-user digest preference so a
-- noisy day collapses into one rolled-up email per hour or per day.
--
-- Pieces:
--   * `email_notification_queue` — outbox of pending digestable emails.
--     Frozen at enqueue time (subject/html/cta) so the runner doesn't
--     have to re-derive content if state has moved on.
--   * `enqueue_digest_email()` — single insert RPC the edge functions
--     call once they've decided not to send immediately.
--   * `email_digest_pending_for_user()` — set-returning helper the
--     runner uses to pull a user's outstanding rows.
--   * `mark_digest_emails_delivered()` — single-statement bulk update.
--
-- The runner edge function (email-digest-runner) is scheduled by a
-- separate migration so this one can land even before pg_cron+pg_net are
-- proven to be available in the target environment.

CREATE TABLE IF NOT EXISTS public.email_notification_queue (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  workspace_id UUID NOT NULL REFERENCES public.workspaces(id) ON DELETE CASCADE,
  notification_id UUID REFERENCES public.notifications(id) ON DELETE SET NULL,
  type TEXT NOT NULL REFERENCES public.notification_types(code) ON UPDATE CASCADE,
  subject TEXT NOT NULL,
  body_html TEXT NOT NULL,
  cta_label TEXT,
  cta_url TEXT,
  preview_text TEXT,
  digest_mode TEXT NOT NULL CHECK (digest_mode IN ('hourly', 'daily')),
  enqueued_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  delivered_at TIMESTAMPTZ,
  delivery_attempts INTEGER NOT NULL DEFAULT 0,
  last_error TEXT
);

CREATE INDEX IF NOT EXISTS idx_email_queue_pending
  ON public.email_notification_queue (digest_mode, user_id, enqueued_at)
  WHERE delivered_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_email_queue_user_workspace
  ON public.email_notification_queue (user_id, workspace_id, enqueued_at DESC);

ALTER TABLE public.email_notification_queue ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS email_queue_select_own ON public.email_notification_queue;
CREATE POLICY email_queue_select_own
  ON public.email_notification_queue FOR SELECT
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS email_queue_service_role ON public.email_notification_queue;
CREATE POLICY email_queue_service_role
  ON public.email_notification_queue FOR ALL TO service_role
  USING (TRUE) WITH CHECK (TRUE);

-- Resolution helper: read digestMode from users.notification_preferences,
-- default 'immediate'. Centralized so callers can't drift.
CREATE OR REPLACE FUNCTION public.user_digest_mode(p_user_id UUID)
RETURNS TEXT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(
    NULLIF(notification_preferences ->> 'digestMode', ''),
    'immediate'
  )
  FROM public.users
  WHERE id = p_user_id;
$$;

REVOKE ALL ON FUNCTION public.user_digest_mode(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.user_digest_mode(UUID) TO authenticated, service_role;

-- Enqueue a digestable email. Returns the row id, or NULL if the user is
-- in immediate mode (caller should send right away in that case).
CREATE OR REPLACE FUNCTION public.enqueue_digest_email(
  p_user_id UUID,
  p_workspace_id UUID,
  p_notification_id UUID,
  p_type TEXT,
  p_subject TEXT,
  p_body_html TEXT,
  p_cta_label TEXT DEFAULT NULL,
  p_cta_url TEXT DEFAULT NULL,
  p_preview_text TEXT DEFAULT NULL
) RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  mode TEXT;
  new_id UUID;
BEGIN
  mode := public.user_digest_mode(p_user_id);
  IF mode = 'immediate' OR mode IS NULL THEN
    RETURN NULL;
  END IF;
  IF mode NOT IN ('hourly', 'daily') THEN
    -- Unknown mode — degrade safely to immediate (caller will send).
    RETURN NULL;
  END IF;

  INSERT INTO public.email_notification_queue (
    user_id, workspace_id, notification_id, type,
    subject, body_html, cta_label, cta_url, preview_text, digest_mode
  ) VALUES (
    p_user_id, p_workspace_id, p_notification_id, p_type,
    p_subject, p_body_html, p_cta_label, p_cta_url, p_preview_text, mode
  )
  RETURNING id INTO new_id;

  RETURN new_id;
END;
$$;

REVOKE ALL ON FUNCTION public.enqueue_digest_email(UUID, UUID, UUID, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.enqueue_digest_email(UUID, UUID, UUID, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT) TO authenticated, service_role;

-- Helper for the runner: list user_ids with pending rows for a given mode,
-- newest-pending first. Used so the runner can iterate users.
CREATE OR REPLACE FUNCTION public.email_digest_users_pending(p_mode TEXT)
RETURNS TABLE (user_id UUID, pending_count BIGINT)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT user_id, COUNT(*) AS pending_count
  FROM public.email_notification_queue
  WHERE delivered_at IS NULL
    AND digest_mode = p_mode
  GROUP BY user_id
  ORDER BY MAX(enqueued_at) DESC;
$$;

REVOKE ALL ON FUNCTION public.email_digest_users_pending(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.email_digest_users_pending(TEXT) TO service_role;

-- Bulk-mark rows delivered. Caller passes the ids it actually handled.
CREATE OR REPLACE FUNCTION public.mark_digest_emails_delivered(p_ids UUID[])
RETURNS INTEGER
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  WITH updated AS (
    UPDATE public.email_notification_queue
    SET delivered_at = NOW()
    WHERE id = ANY(p_ids)
      AND delivered_at IS NULL
    RETURNING id
  )
  SELECT COUNT(*)::INTEGER FROM updated;
$$;

REVOKE ALL ON FUNCTION public.mark_digest_emails_delivered(UUID[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.mark_digest_emails_delivered(UUID[]) TO service_role;

-- Bulk-record failures. Mirrors mark_delivered for retries / surfacing.
CREATE OR REPLACE FUNCTION public.mark_digest_emails_failed(p_ids UUID[], p_error TEXT)
RETURNS INTEGER
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  WITH updated AS (
    UPDATE public.email_notification_queue
    SET delivery_attempts = delivery_attempts + 1,
        last_error = p_error
    WHERE id = ANY(p_ids)
      AND delivered_at IS NULL
    RETURNING id
  )
  SELECT COUNT(*)::INTEGER FROM updated;
$$;

REVOKE ALL ON FUNCTION public.mark_digest_emails_failed(UUID[], TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.mark_digest_emails_failed(UUID[], TEXT) TO service_role;
