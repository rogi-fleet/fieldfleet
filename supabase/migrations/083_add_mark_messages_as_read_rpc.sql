-- Mark all messages in a conversation as read for the authenticated user.
-- This runs as SECURITY DEFINER because message recipients cannot update
-- other users' message rows directly under the current RLS policies.
DROP FUNCTION IF EXISTS public.mark_messages_as_read(UUID, UUID);

CREATE FUNCTION public.mark_messages_as_read(
  p_conversation_id UUID,
  p_user_id UUID DEFAULT auth.uid()
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  conversation_workspace_id UUID;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  IF p_conversation_id IS NULL THEN
    RAISE EXCEPTION 'Conversation id is required';
  END IF;

  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'User id is required';
  END IF;

  IF p_user_id <> auth.uid() THEN
    RAISE EXCEPTION 'Cannot mark messages as read for another user';
  END IF;

  SELECT c.workspace_id
  INTO conversation_workspace_id
  FROM conversations c
  WHERE c.id = p_conversation_id
    AND is_workspace_member(c.workspace_id)
    AND auth.uid() = ANY(c.participant_ids)
  LIMIT 1;

  IF NOT FOUND OR conversation_workspace_id IS NULL THEN
    RAISE EXCEPTION 'Conversation not found or access denied';
  END IF;

  UPDATE conversations
  SET unread_counts = jsonb_set(
        COALESCE(unread_counts, '{}'::jsonb),
        ARRAY[p_user_id::text],
        to_jsonb(0),
        true
      ),
      updated_at = NOW()
  WHERE id = p_conversation_id;

  UPDATE messages
  SET read_by = array_append(COALESCE(read_by, ARRAY[]::UUID[]), p_user_id)
  WHERE conversation_id = p_conversation_id
    AND NOT (p_user_id = ANY(COALESCE(read_by, ARRAY[]::UUID[])));
END;
$$;

REVOKE ALL ON FUNCTION public.mark_messages_as_read(UUID, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.mark_messages_as_read(UUID, UUID) TO authenticated;
