-- Portal messaging notifications: when a customer posts to a portal-visible
-- thread, fan out staff notifications (in-app + email + push) so the team
-- isn't left polling the portal tab for new messages.
--
-- Architecture mirrors `invoke_email_digest_runner` from
-- 20260503160300_schedule_email_digest_runner.sql: the SECURITY DEFINER
-- portal_send_message RPC POSTs via pg_net to an edge function that owns
-- the create_notification → enqueue_digest_email → push-dispatch fanout.
-- Keeping HTML email + push routing out of plpgsql is intentional.
--
-- Failures here are non-fatal — the message has already been inserted by
-- the time we call out. We log a WARNING and move on.

CREATE EXTENSION IF NOT EXISTS pg_net;

-- ---------------------------------------------------------------------------
-- Helper: fire-and-forget HTTP POST to portal-message-notify edge function.
-- Returns the pg_net request id (or NULL if app settings aren't configured).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.invoke_portal_message_notify(p_message_id UUID)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  base_url    TEXT;
  service_key TEXT;
  request_id  BIGINT;
BEGIN
  IF p_message_id IS NULL THEN
    RETURN NULL;
  END IF;

  base_url    := NULLIF(current_setting('app.settings.supabase_url',     true), '');
  service_key := NULLIF(current_setting('app.settings.service_role_key', true), '');

  IF base_url IS NULL OR service_key IS NULL THEN
    RAISE WARNING 'invoke_portal_message_notify: app.settings.supabase_url / service_role_key not configured; skipping fanout for message %', p_message_id;
    RETURN NULL;
  END IF;

  SELECT net.http_post(
    url     := base_url || '/functions/v1/portal-message-notify',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || service_key,
      'Content-Type',  'application/json'
    ),
    body    := jsonb_build_object('message_id', p_message_id)
  )
  INTO request_id;

  RETURN request_id;
END;
$$;

REVOKE ALL ON FUNCTION public.invoke_portal_message_notify(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.invoke_portal_message_notify(UUID) TO authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Re-create portal_send_message to fire the fanout after a successful insert.
-- Body matches 20260521090000_add_portal_messaging.sql with one added block
-- after the conversation-bump UPDATE.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.portal_send_message(
  p_conversation_id UUID,
  p_content TEXT,
  p_attachments JSONB DEFAULT '[]'::jsonb
) RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_conv        public.conversations;
  v_caller_id   UUID := auth.uid();
  v_sender_name TEXT;
  v_message_id  UUID;
  v_unread      JSONB;
  v_id          UUID;
BEGIN
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  -- Allow attachment-only messages: empty content is OK as long as at
  -- least one attachment is present. The previous (text-only) guard was
  -- a strict non-empty check.
  IF p_content IS NULL OR length(trim(p_content)) = 0 THEN
    IF p_attachments IS NULL
       OR jsonb_typeof(p_attachments) <> 'array'
       OR jsonb_array_length(p_attachments) = 0 THEN
      RAISE EXCEPTION 'Empty content';
    END IF;
  END IF;

  -- Authorize for real portal user only (preview is read-only).
  v_conv := public._portal_conversation_authorized(p_conversation_id, NULL);
  IF v_conv.id IS NULL THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;

  -- Resolve sender_name from customer_contacts.
  SELECT cc.name INTO v_sender_name
    FROM public.customer_contacts cc
    JOIN public.projects p ON p.client_id = cc.customer_id
   WHERE p.id = v_conv.scope_reference_id
     AND cc.is_active = TRUE
     AND lower(cc.email) = lower(coalesce(auth.email(), ''))
   LIMIT 1;

  IF v_sender_name IS NULL THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;

  -- Ensure caller is in participant_ids (idempotent).
  IF NOT (v_caller_id = ANY(v_conv.participant_ids)) THEN
    UPDATE public.conversations
       SET participant_ids = array_append(participant_ids, v_caller_id),
           participant_names = COALESCE(participant_names, '{}'::jsonb)
                                || jsonb_build_object(v_caller_id::text, v_sender_name),
           unread_counts = COALESCE(unread_counts, '{}'::jsonb)
                            || jsonb_build_object(v_caller_id::text, 0)
     WHERE id = v_conv.id
     RETURNING * INTO v_conv;
  END IF;

  INSERT INTO public.messages (
    conversation_id, workspace_id, sender_id, sender_name,
    content, attachments
  ) VALUES (
    p_conversation_id, v_conv.workspace_id, v_caller_id, v_sender_name,
    p_content, COALESCE(p_attachments, '[]'::jsonb)
  )
  RETURNING id INTO v_message_id;

  -- Bump unread counts for everyone except sender.
  v_unread := COALESCE(v_conv.unread_counts, '{}'::jsonb);
  FOREACH v_id IN ARRAY v_conv.participant_ids LOOP
    IF v_id <> v_caller_id THEN
      v_unread := v_unread || jsonb_build_object(
        v_id::text,
        COALESCE((v_unread ->> v_id::text)::int, 0) + 1
      );
    END IF;
  END LOOP;
  v_unread := v_unread || jsonb_build_object(v_caller_id::text, 0);

  UPDATE public.conversations
     SET last_message    = LEFT(p_content, 500),
         last_message_at = NOW(),
         unread_counts   = v_unread,
         updated_at      = NOW()
   WHERE id = p_conversation_id;

  -- Best-effort staff fanout. Edge function owns recipient resolution
  -- (staff != sender), notification creation, email enqueue, and push
  -- dispatch. Failures are non-fatal — the message is already saved.
  BEGIN
    PERFORM public.invoke_portal_message_notify(v_message_id);
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'portal_send_message: fanout failed for message %: %', v_message_id, SQLERRM;
  END;

  RETURN v_message_id;
END;
$$;

REVOKE ALL ON FUNCTION public.portal_send_message(UUID, TEXT, JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.portal_send_message(UUID, TEXT, JSONB) TO authenticated;

COMMENT ON FUNCTION public.invoke_portal_message_notify(UUID) IS
  'Fire-and-forget HTTP POST via pg_net to portal-message-notify edge function. Skips silently when app.settings.supabase_url / service_role_key are not configured.';
