-- Notifications foundation rework:
--   * Replace the per-migration CHECK-constraint expansion with a
--     notification_types lookup table — adding a new type is now a single
--     INSERT, not a constraint rebuild.
--   * Add a unified create_notification RPC that all callers go through.
--     Centralizes authorization (workspace membership) and deduplication.
--   * Tighten notifications RLS: drop the policy that let any authenticated
--     user insert notifications for any other user. Inserts now flow through
--     SECURITY DEFINER RPCs (this one + existing fan-out functions) or the
--     service role. SELECT/UPDATE policies are unchanged.

-- 1. Lookup table for notification types.
CREATE TABLE IF NOT EXISTS public.notification_types (
  code TEXT PRIMARY KEY,
  description TEXT,
  email_pref_key TEXT,
  push_pref_key TEXT,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE public.notification_types IS
  'Allowed notification.type codes. email_pref_key/push_pref_key reference '
  'entries in users.notification_preferences (JSONB) consulted by '
  'send-mention-notification, push-dispatch, etc. before delivery.';

-- Seed with the known type set. Defaults: any type without explicit pref
-- keys falls back to projectUpdatesEmail / projectUpdatesPush, matching the
-- existing push-dispatch fallback (push-dispatch/index.ts:108-123).
INSERT INTO public.notification_types (code, description, email_pref_key, push_pref_key) VALUES
  ('mention',                       'You were mentioned',                       'mentionsEmail',         'mentionsPush'),
  ('task_assignment',               'A task was assigned to you',               'taskAssignmentsEmail',  'taskAssignmentsPush'),
  ('task_completion',               'A task was completed',                     'taskCompletionsEmail',  'taskCompletionsPush'),
  ('message_received',              'New message in conversation',              'messagesEmail',         'messagesPush'),
  ('workspace_member_joined',       'A new member joined the workspace',        'projectUpdatesEmail',   'projectUpdatesPush'),
  ('time_entry_submitted',          'A time entry was submitted for review',    'projectUpdatesEmail',   'projectUpdatesPush'),
  ('time_entry_approved',           'A time entry was approved',                'projectUpdatesEmail',   'projectUpdatesPush'),
  ('time_entry_rejected',           'A time entry was rejected',                'projectUpdatesEmail',   'projectUpdatesPush'),
  ('document_signed',               'A document was signed',                    'projectUpdatesEmail',   'projectUpdatesPush'),
  ('document_denied',               'A document was denied',                    'projectUpdatesEmail',   'projectUpdatesPush'),
  ('document_changes_requested',    'Changes requested on a document',          'projectUpdatesEmail',   'projectUpdatesPush'),
  ('document_payment_completed',    'Payment completed for a document',         'projectUpdatesEmail',   'projectUpdatesPush'),
  ('document_bid_received',         'Vendor bid received on RFP',               'projectUpdatesEmail',   'projectUpdatesPush'),
  ('document_bid_applied',          'Vendor bid applied to budget',             'projectUpdatesEmail',   'projectUpdatesPush'),
  ('agreement_signed',              'An agreement was signed',                  'projectUpdatesEmail',   'projectUpdatesPush'),
  ('project_update',                'Project status update',                    'projectUpdatesEmail',   'projectUpdatesPush'),
  ('priority_alert',                'Priority alert',                           'projectUpdatesEmail',   'projectUpdatesPush'),
  ('capacity_alert',                'Capacity utilization alert',               'projectUpdatesEmail',   'projectUpdatesPush'),
  ('automation',                    'Automation rule fired',                    'projectUpdatesEmail',   'projectUpdatesPush'),
  ('ai_plan_ready',                 'AI plan ready',                            'projectUpdatesEmail',   'projectUpdatesPush'),
  ('ai_plan_failed',                'AI plan generation failed',                'projectUpdatesEmail',   'projectUpdatesPush'),
  ('form_submission',               'Field form submission received',           'projectUpdatesEmail',   'projectUpdatesPush')
ON CONFLICT (code) DO NOTHING;

-- Defensive backstop: import any type values already present in the
-- notifications table that the seed might have missed (e.g. from migrations
-- not visible to this file). Without this, the FK below could fail.
INSERT INTO public.notification_types (code, description)
SELECT DISTINCT type, 'Auto-imported from existing notifications row'
FROM public.notifications
WHERE type IS NOT NULL
ON CONFLICT (code) DO NOTHING;

-- 2. Replace the CHECK constraint with an FK to the lookup table.
ALTER TABLE public.notifications DROP CONSTRAINT IF EXISTS notifications_type_check;
ALTER TABLE public.notifications DROP CONSTRAINT IF EXISTS notifications_type_fkey;
ALTER TABLE public.notifications
  ADD CONSTRAINT notifications_type_fkey
  FOREIGN KEY (type) REFERENCES public.notification_types(code)
  ON UPDATE CASCADE ON DELETE RESTRICT;

-- 3. Add dedupe_key column + supporting index. Stored as a real column
--    rather than a metadata key so dedup lookups are index-backed.
ALTER TABLE public.notifications ADD COLUMN IF NOT EXISTS dedupe_key TEXT;

CREATE INDEX IF NOT EXISTS idx_notifications_dedup_lookup
  ON public.notifications (user_id, workspace_id, type, dedupe_key, created_at DESC)
  WHERE dedupe_key IS NOT NULL;

-- 4. Tighten RLS. The previous "any authenticated user can insert any
--    notification for any user" policy was effectively unauthenticated for
--    cross-user notifications; an attacker could spam any other user's
--    feed. New model: inserts go through SECURITY DEFINER RPCs (which
--    enforce workspace membership) or the service role.
DROP POLICY IF EXISTS "Authenticated users can insert notifications" ON public.notifications;

DROP POLICY IF EXISTS notifications_service_role_insert ON public.notifications;
CREATE POLICY notifications_service_role_insert
  ON public.notifications FOR INSERT TO service_role
  WITH CHECK (TRUE);

-- 5. Unified create_notification RPC.
--
-- Authorization: service role unconditionally; authenticated users only for
-- workspaces they belong to OR for self-notifications. Self-notification is
-- allowed because some flows (e.g. AI plan ready) notify the requesting user.
--
-- Dedup: when p_dedupe_key is provided, returns the existing notification id
-- if one with the same (user_id, workspace_id, type, dedupe_key) was created
-- within p_dedupe_window_seconds. Default window is 5 minutes; pass 0 to
-- disable. Callers that want stricter "one per day" semantics pass a longer
-- window. The dedupe_key shape is caller-defined; recommended pattern:
-- '<scope>:<entity_id>[:<extra>]', e.g. 'mention:<comment_id>'.
CREATE OR REPLACE FUNCTION public.create_notification(
  p_user_id UUID,
  p_workspace_id UUID,
  p_type TEXT,
  p_title TEXT,
  p_body TEXT DEFAULT NULL,
  p_metadata JSONB DEFAULT '{}'::jsonb,
  p_dedupe_key TEXT DEFAULT NULL,
  p_dedupe_window_seconds INTEGER DEFAULT 300
) RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  caller_id UUID := auth.uid();
  is_service_role BOOLEAN := (auth.role() = 'service_role');
  existing_id UUID;
  new_id UUID;
BEGIN
  IF p_user_id IS NULL OR p_workspace_id IS NULL OR p_type IS NULL OR p_title IS NULL THEN
    RAISE EXCEPTION 'p_user_id, p_workspace_id, p_type, and p_title are required';
  END IF;

  IF NOT is_service_role THEN
    IF caller_id IS NULL THEN
      RAISE EXCEPTION 'Authentication required to create a notification';
    END IF;
    IF caller_id <> p_user_id AND NOT public.is_workspace_member(p_workspace_id) THEN
      RAISE EXCEPTION 'Not authorized to create notifications in this workspace';
    END IF;
  END IF;

  IF p_dedupe_key IS NOT NULL AND p_dedupe_window_seconds > 0 THEN
    SELECT id
    INTO existing_id
    FROM public.notifications
    WHERE user_id = p_user_id
      AND workspace_id = p_workspace_id
      AND type = p_type
      AND dedupe_key = p_dedupe_key
      AND created_at >= NOW() - make_interval(secs => p_dedupe_window_seconds)
    ORDER BY created_at DESC
    LIMIT 1;

    IF existing_id IS NOT NULL THEN
      RETURN existing_id;
    END IF;
  END IF;

  INSERT INTO public.notifications (
    user_id, workspace_id, type, title, body, metadata, dedupe_key
  )
  VALUES (
    p_user_id,
    p_workspace_id,
    p_type,
    p_title,
    p_body,
    COALESCE(p_metadata, '{}'::jsonb),
    p_dedupe_key
  )
  RETURNING id INTO new_id;

  RETURN new_id;
END;
$$;

REVOKE ALL ON FUNCTION public.create_notification(UUID, UUID, TEXT, TEXT, TEXT, JSONB, TEXT, INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_notification(UUID, UUID, TEXT, TEXT, TEXT, JSONB, TEXT, INTEGER) TO authenticated, service_role;
