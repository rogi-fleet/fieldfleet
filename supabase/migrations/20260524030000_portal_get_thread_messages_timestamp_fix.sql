-- Fix portal_get_thread_messages to read from the actual column.
--
-- The RPC introduced in 20260521090000 selects `m.created_at` from
-- public.messages, but that table's timestamp column is named `timestamp`
-- (a reserved-word column name dating back to migration 002). The RPC
-- has been silently broken since its addition — any attempt to call it
-- raises `column messages.created_at does not exist` at runtime, because
-- plpgsql validates column references lazily (function creation succeeds
-- even with bad column names).
--
-- This migration keeps the RETURNS TABLE shape stable (callers still see
-- `created_at` in the response) and aliases the underlying `timestamp`
-- column to it. Filter + sort are switched to the real column.

CREATE OR REPLACE FUNCTION public.portal_get_thread_messages(
  p_conversation_id UUID,
  p_preview_customer_id UUID DEFAULT NULL,
  p_limit INT DEFAULT 100,
  p_before TIMESTAMPTZ DEFAULT NULL
) RETURNS TABLE (
  id UUID,
  conversation_id UUID,
  sender_id UUID,
  sender_name TEXT,
  content TEXT,
  attachments JSONB,
  created_at TIMESTAMPTZ,
  edited_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
DECLARE
  v_conv public.conversations;
BEGIN
  v_conv := public._portal_conversation_authorized(p_conversation_id, p_preview_customer_id);
  IF v_conv.id IS NULL THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;

  RETURN QUERY
    SELECT m.id, m.conversation_id, m.sender_id, m.sender_name,
           m.content, m.attachments,
           m."timestamp" AS created_at,
           m.edited_at
      FROM public.messages m
     WHERE m.conversation_id = p_conversation_id
       AND (p_before IS NULL OR m."timestamp" < p_before)
     ORDER BY m."timestamp" DESC
     LIMIT GREATEST(1, LEAST(p_limit, 200));
END;
$$;

REVOKE ALL ON FUNCTION public.portal_get_thread_messages(UUID, UUID, INT, TIMESTAMPTZ) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.portal_get_thread_messages(UUID, UUID, INT, TIMESTAMPTZ) TO authenticated;
