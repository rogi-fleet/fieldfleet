-- Portal messaging realtime: open up `messages` SELECT to portal-authed
-- customers for portal-visible threads only, so a Supabase realtime
-- postgres-changes subscription delivers new messages live.
--
-- The default `messages_select` policy gates on workspace membership and
-- participant_ids. Customer contacts are added to participant_ids on first
-- portal load (20260521090000) but are not workspace members, so the
-- EXISTS subquery fails for them under the default policy. We add a
-- second, portal-only policy that uses a SECURITY DEFINER helper to
-- short-circuit on `customer_contacts.email = auth.email()`.
--
-- The two policies are OR'd by Postgres, so the default behavior for
-- staff is unchanged.

CREATE OR REPLACE FUNCTION public._portal_can_read_conversation(p_conversation_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
      FROM public.conversations c
      JOIN public.projects p ON p.id = c.scope_reference_id
      JOIN public.customer_contacts cc ON cc.customer_id = p.client_id
     WHERE c.id = p_conversation_id
       AND c.scope = 'project'
       AND c.portal_visible = TRUE
       AND cc.is_active = TRUE
       AND lower(cc.email) = lower(coalesce(auth.email(), ''))
  );
$$;

REVOKE ALL ON FUNCTION public._portal_can_read_conversation(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public._portal_can_read_conversation(UUID) TO authenticated;

DROP POLICY IF EXISTS messages_select_portal ON public.messages;
CREATE POLICY messages_select_portal ON public.messages
  FOR SELECT
  USING (public._portal_can_read_conversation(conversation_id));

COMMENT ON FUNCTION public._portal_can_read_conversation(UUID) IS
  'Boolean variant of the portal authorization check, used in RLS policies on tables joined to conversations (currently: messages_select_portal).';
COMMENT ON POLICY messages_select_portal ON public.messages IS
  'Lets portal-authenticated customers SELECT messages from portal-visible project threads. OR''d with the default messages_select policy that gates on workspace membership.';
