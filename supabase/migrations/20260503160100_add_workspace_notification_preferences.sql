-- Per-workspace notification preferences. Lets a user mute a noisy
-- workspace (or override per-type prefs for it) without affecting other
-- workspaces they belong to.
--
-- Resolution order, expressed by effective_notification_pref():
--   1. Workspace-level muted_until in the future ⇒ FALSE for everything.
--   2. Workspace-level preferences[key] if present.
--   3. User-global users.notification_preferences[key] if present.
--   4. Default TRUE.
--
-- Both push-dispatch and the email-sending edge functions read through the
-- helper instead of reading user prefs directly, so adding new dispatch
-- channels later only needs to update the helper.

CREATE TABLE IF NOT EXISTS public.workspace_notification_preferences (
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  workspace_id UUID NOT NULL REFERENCES public.workspaces(id) ON DELETE CASCADE,
  preferences JSONB NOT NULL DEFAULT '{}'::jsonb,
  muted_until TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (user_id, workspace_id)
);

CREATE INDEX IF NOT EXISTS idx_wnp_workspace ON public.workspace_notification_preferences (workspace_id);

ALTER TABLE public.workspace_notification_preferences ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS wnp_select_own ON public.workspace_notification_preferences;
CREATE POLICY wnp_select_own
  ON public.workspace_notification_preferences FOR SELECT
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS wnp_insert_own ON public.workspace_notification_preferences;
CREATE POLICY wnp_insert_own
  ON public.workspace_notification_preferences FOR INSERT
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS wnp_update_own ON public.workspace_notification_preferences;
CREATE POLICY wnp_update_own
  ON public.workspace_notification_preferences FOR UPDATE
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS wnp_delete_own ON public.workspace_notification_preferences;
CREATE POLICY wnp_delete_own
  ON public.workspace_notification_preferences FOR DELETE
  USING (auth.uid() = user_id);

DROP TRIGGER IF EXISTS set_wnp_updated_at ON public.workspace_notification_preferences;
CREATE TRIGGER set_wnp_updated_at
  BEFORE UPDATE ON public.workspace_notification_preferences
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at_column();

-- Resolution helper. STABLE so callers can use it in WHERE clauses
-- without per-row re-evaluation surprises. SECURITY DEFINER so callers
-- (push-dispatch using service role, email functions using service role)
-- can read both tables uniformly without RLS gymnastics.
CREATE OR REPLACE FUNCTION public.effective_notification_pref(
  p_user_id UUID,
  p_workspace_id UUID,
  p_pref_key TEXT
) RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  ws_prefs JSONB;
  ws_muted_until TIMESTAMPTZ;
  user_prefs JSONB;
  raw_value TEXT;
BEGIN
  IF p_user_id IS NULL OR p_pref_key IS NULL THEN
    RETURN TRUE;
  END IF;

  IF p_workspace_id IS NOT NULL THEN
    SELECT preferences, muted_until
    INTO ws_prefs, ws_muted_until
    FROM public.workspace_notification_preferences
    WHERE user_id = p_user_id AND workspace_id = p_workspace_id;

    IF ws_muted_until IS NOT NULL AND ws_muted_until > NOW() THEN
      RETURN FALSE;
    END IF;

    IF ws_prefs IS NOT NULL AND ws_prefs ? p_pref_key THEN
      raw_value := ws_prefs ->> p_pref_key;
      IF raw_value IS NOT NULL THEN
        RETURN raw_value::BOOLEAN;
      END IF;
    END IF;
  END IF;

  SELECT notification_preferences INTO user_prefs FROM public.users WHERE id = p_user_id;
  IF user_prefs IS NOT NULL AND user_prefs ? p_pref_key THEN
    raw_value := user_prefs ->> p_pref_key;
    IF raw_value IS NOT NULL THEN
      RETURN raw_value::BOOLEAN;
    END IF;
  END IF;

  RETURN TRUE;
EXCEPTION
  WHEN invalid_text_representation THEN
    -- Pref value wasn't a parseable boolean — fall back to default ON.
    RETURN TRUE;
END;
$$;

REVOKE ALL ON FUNCTION public.effective_notification_pref(UUID, UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.effective_notification_pref(UUID, UUID, TEXT) TO authenticated, service_role;
