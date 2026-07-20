-- ============================================================================
-- Messaging: Slack-like upgrades
-- Adds per-message pinning, per-user saved/bookmarked messages, thread reply
-- rollups, and first-class channel metadata (name/topic/purpose, public/private).
-- Idempotent.
-- ============================================================================

-- ── conversations: channel metadata ─────────────────────────────────────────
ALTER TABLE conversations
  ADD COLUMN IF NOT EXISTS is_channel BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS channel_name TEXT,
  ADD COLUMN IF NOT EXISTS channel_topic TEXT,
  ADD COLUMN IF NOT EXISTS channel_purpose TEXT,
  ADD COLUMN IF NOT EXISTS is_private BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS created_by UUID;

DO $$ BEGIN
  ALTER TABLE conversations
    ADD CONSTRAINT conversations_channel_name_lowercase
    CHECK (channel_name IS NULL OR channel_name = lower(channel_name));
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS conversations_workspace_channel_name_key
  ON conversations (workspace_id, channel_name)
  WHERE is_channel = TRUE AND channel_name IS NOT NULL;

CREATE INDEX IF NOT EXISTS conversations_workspace_is_channel_idx
  ON conversations (workspace_id, is_channel)
  WHERE is_channel = TRUE;

-- ── messages: pin + thread rollup ───────────────────────────────────────────
ALTER TABLE messages
  ADD COLUMN IF NOT EXISTS pinned_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS pinned_by UUID,
  ADD COLUMN IF NOT EXISTS reply_to_id UUID,
  ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS read_by UUID[] DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS thread_reply_count INT NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS last_reply_at TIMESTAMPTZ;

DO $$ BEGIN
  ALTER TABLE messages
    ADD CONSTRAINT messages_reply_to_fk
    FOREIGN KEY (reply_to_id) REFERENCES messages(id) ON DELETE SET NULL;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE INDEX IF NOT EXISTS messages_conversation_pinned_idx
  ON messages (conversation_id, pinned_at DESC)
  WHERE pinned_at IS NOT NULL AND deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS messages_reply_to_idx
  ON messages (reply_to_id)
  WHERE reply_to_id IS NOT NULL;

-- ── message_bookmarks: per-user saved messages ──────────────────────────────
CREATE TABLE IF NOT EXISTS message_bookmarks (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  message_id UUID NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
  conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
  note TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (user_id, message_id)
);

CREATE INDEX IF NOT EXISTS message_bookmarks_user_idx
  ON message_bookmarks (user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS message_bookmarks_workspace_idx
  ON message_bookmarks (workspace_id, user_id);

ALTER TABLE message_bookmarks ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  CREATE POLICY message_bookmarks_owner ON message_bookmarks
    FOR ALL USING (user_id = auth.uid())
    WITH CHECK (user_id = auth.uid());
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- ── thread reply rollup trigger ─────────────────────────────────────────────
CREATE OR REPLACE FUNCTION fn_messages_thread_rollup()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
  parent_id UUID;
  reply_ts  TIMESTAMPTZ;
BEGIN
  IF TG_OP = 'INSERT' THEN
    parent_id := NEW.reply_to_id;
    reply_ts  := COALESCE(NEW."timestamp", NOW());
    IF parent_id IS NOT NULL THEN
      UPDATE messages
        SET thread_reply_count = thread_reply_count + 1,
            last_reply_at = GREATEST(COALESCE(last_reply_at, reply_ts), reply_ts)
        WHERE id = parent_id;
    END IF;
    RETURN NEW;
  ELSIF TG_OP = 'UPDATE' THEN
    reply_ts := COALESCE(NEW."timestamp", NOW());
    -- soft-delete on a reply: decrement parent
    IF OLD.reply_to_id IS NOT NULL
       AND OLD.deleted_at IS NULL
       AND NEW.deleted_at IS NOT NULL THEN
      UPDATE messages
        SET thread_reply_count = GREATEST(thread_reply_count - 1, 0)
        WHERE id = OLD.reply_to_id;
    ELSIF OLD.reply_to_id IS NOT NULL
       AND OLD.deleted_at IS NOT NULL
       AND NEW.deleted_at IS NULL THEN
      UPDATE messages
        SET thread_reply_count = thread_reply_count + 1,
            last_reply_at = GREATEST(COALESCE(last_reply_at, reply_ts), reply_ts)
        WHERE id = OLD.reply_to_id;
    END IF;
    RETURN NEW;
  ELSIF TG_OP = 'DELETE' THEN
    IF OLD.reply_to_id IS NOT NULL AND OLD.deleted_at IS NULL THEN
      UPDATE messages
        SET thread_reply_count = GREATEST(thread_reply_count - 1, 0)
        WHERE id = OLD.reply_to_id;
    END IF;
    RETURN OLD;
  END IF;
  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_messages_thread_rollup ON messages;
CREATE TRIGGER trg_messages_thread_rollup
  AFTER INSERT OR UPDATE OR DELETE ON messages
  FOR EACH ROW EXECUTE FUNCTION fn_messages_thread_rollup();

-- ── SECURITY DEFINER RPCs for actions blocked by base RLS ──────────────────
-- The existing messages_update policy only allows sender_id = auth.uid().
-- To let any conversation participant pin/unpin a shared message we expose
-- SECURITY DEFINER functions that perform the participant check themselves.

CREATE OR REPLACE FUNCTION pin_message(p_message_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_conv UUID;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  SELECT conversation_id INTO v_conv FROM messages WHERE id = p_message_id;
  IF v_conv IS NULL THEN
    RAISE EXCEPTION 'Message not found';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM conversations
     WHERE id = v_conv AND v_uid = ANY(participant_ids)
  ) THEN
    RAISE EXCEPTION 'Not a participant of this conversation';
  END IF;
  UPDATE messages
     SET pinned_at = NOW(), pinned_by = v_uid
   WHERE id = p_message_id;
END;
$$;

CREATE OR REPLACE FUNCTION unpin_message(p_message_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_conv UUID;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  SELECT conversation_id INTO v_conv FROM messages WHERE id = p_message_id;
  IF v_conv IS NULL THEN RETURN; END IF;
  IF NOT EXISTS (
    SELECT 1 FROM conversations
     WHERE id = v_conv AND v_uid = ANY(participant_ids)
  ) THEN
    RAISE EXCEPTION 'Not a participant of this conversation';
  END IF;
  UPDATE messages SET pinned_at = NULL, pinned_by = NULL WHERE id = p_message_id;
END;
$$;

REVOKE ALL ON FUNCTION pin_message(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION unpin_message(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION pin_message(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION unpin_message(UUID) TO authenticated;

-- Public channel discovery + join: base RLS only exposes conversations the
-- caller is already a participant of. Use SECURITY DEFINER for both.

CREATE OR REPLACE FUNCTION list_public_channels(p_workspace UUID)
RETURNS SETOF conversations
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  IF NOT is_workspace_member(p_workspace) THEN
    RAISE EXCEPTION 'Not a workspace member';
  END IF;
  RETURN QUERY
    SELECT * FROM conversations
     WHERE workspace_id = p_workspace
       AND is_channel = TRUE
       AND COALESCE(is_private, FALSE) = FALSE
     ORDER BY channel_name NULLS LAST;
END;
$$;

CREATE OR REPLACE FUNCTION join_channel(
  p_conversation UUID,
  p_user_name TEXT
) RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_workspace UUID;
  v_is_channel BOOLEAN;
  v_is_private BOOLEAN;
  v_ids UUID[];
  v_names JSONB;
  v_unread JSONB;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  SELECT workspace_id, is_channel, COALESCE(is_private, FALSE),
         participant_ids, COALESCE(participant_names, '{}'::jsonb),
         COALESCE(unread_counts, '{}'::jsonb)
    INTO v_workspace, v_is_channel, v_is_private, v_ids, v_names, v_unread
    FROM conversations WHERE id = p_conversation;
  IF v_workspace IS NULL THEN RAISE EXCEPTION 'Channel not found'; END IF;
  IF NOT v_is_channel OR v_is_private THEN
    RAISE EXCEPTION 'Channel is not joinable';
  END IF;
  IF NOT is_workspace_member(v_workspace) THEN
    RAISE EXCEPTION 'Not a workspace member';
  END IF;
  IF v_uid = ANY(v_ids) THEN RETURN; END IF;
  v_ids := array_append(v_ids, v_uid);
  v_names := v_names || jsonb_build_object(v_uid::text, p_user_name);
  v_unread := v_unread || jsonb_build_object(v_uid::text, 0);
  UPDATE conversations
     SET participant_ids = v_ids,
         participant_names = v_names,
         unread_counts = v_unread
   WHERE id = p_conversation;
END;
$$;

CREATE OR REPLACE FUNCTION leave_channel(p_conversation UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_ids UUID[];
  v_names JSONB;
  v_unread JSONB;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  SELECT participant_ids, COALESCE(participant_names, '{}'::jsonb),
         COALESCE(unread_counts, '{}'::jsonb)
    INTO v_ids, v_names, v_unread
    FROM conversations WHERE id = p_conversation AND is_channel = TRUE;
  IF v_ids IS NULL THEN RETURN; END IF;
  v_ids := array_remove(v_ids, v_uid);
  v_names := v_names - v_uid::text;
  v_unread := v_unread - v_uid::text;
  UPDATE conversations
     SET participant_ids = v_ids,
         participant_names = v_names,
         unread_counts = v_unread
   WHERE id = p_conversation;
END;
$$;

REVOKE ALL ON FUNCTION list_public_channels(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION join_channel(UUID, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION leave_channel(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION list_public_channels(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION join_channel(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION leave_channel(UUID) TO authenticated;

-- ── realtime publication ────────────────────────────────────────────────────
DO $$ BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE message_bookmarks;
EXCEPTION WHEN duplicate_object THEN NULL;
WHEN undefined_object THEN NULL;
END $$;
