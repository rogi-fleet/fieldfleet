-- asset_events — append-only audit trail per asset.
--
-- Mirrors the file_events shape: every meaningful action on an asset
-- (created, renamed, status changed, assigned, unassigned, photos
-- added/removed, tags added/removed, retired, deleted) lands here. The
-- detail screen renders this as an Activity timeline so workspace
-- owners can answer "who moved this and when" without trawling
-- backups.
--
-- Writes are forgery-proof: clients have no INSERT grant. The only
-- write path is the SECURITY DEFINER RPC `record_asset_event`, which
-- verifies workspace membership and stamps the actor from auth.uid().
-- A simple membership check matches the existing assets RLS — anyone
-- who can read/write an asset can record events for it.

CREATE TABLE IF NOT EXISTS public.asset_events (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  workspace_id UUID NOT NULL REFERENCES public.workspaces(id) ON DELETE CASCADE,
  asset_id UUID NOT NULL REFERENCES public.assets(id) ON DELETE CASCADE,
  actor_id UUID REFERENCES public.users(id),
  action TEXT NOT NULL,
  payload JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_asset_events_asset
  ON public.asset_events (asset_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_asset_events_workspace
  ON public.asset_events (workspace_id, created_at DESC);

COMMENT ON TABLE public.asset_events IS
  'Append-only audit trail for assets. Populated only via '
  'record_asset_event(). Rendered as the Activity timeline in the '
  'asset detail screen.';

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------
ALTER TABLE public.asset_events ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS asset_events_select ON public.asset_events;
CREATE POLICY asset_events_select ON public.asset_events
  FOR SELECT USING (public.is_workspace_member(workspace_id));

-- No insert/update/delete policies: clients never write directly.
REVOKE INSERT, UPDATE, DELETE ON public.asset_events FROM authenticated;

-- ---------------------------------------------------------------------------
-- record_asset_event — the only client-callable write path
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.record_asset_event(
  p_asset_id UUID,
  p_action TEXT,
  p_payload JSONB DEFAULT '{}'::jsonb
) RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_workspace_id UUID;
  v_event_id UUID;
BEGIN
  -- Resolve the asset's workspace and verify the caller is a member.
  -- Membership matches the existing assets_select / assets_update RLS,
  -- so anyone allowed to mutate the asset can record events for it.
  SELECT a.workspace_id INTO v_workspace_id
  FROM public.assets a
  WHERE a.id = p_asset_id;

  IF v_workspace_id IS NULL THEN
    RAISE EXCEPTION 'asset % not found', p_asset_id
      USING ERRCODE = 'no_data_found';
  END IF;

  IF NOT public.is_workspace_member(v_workspace_id) THEN
    RAISE EXCEPTION 'not authorized to record events for this asset'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- Validate action against the known set. Extend as new event types
  -- ship; unknown actions are rejected to keep the timeline clean.
  IF p_action NOT IN (
    'created',
    'updated',
    'renamed',
    'status_changed',
    'category_changed',
    'location_changed',
    'assigned_project',
    'assigned_user',
    'unassigned',
    'photo_added',
    'photo_removed',
    'tag_added',
    'tag_removed',
    'retired',
    'restored',
    'deleted'
  ) THEN
    RAISE EXCEPTION 'unknown asset event action: %', p_action
      USING ERRCODE = 'invalid_parameter_value';
  END IF;

  INSERT INTO public.asset_events (
    workspace_id, asset_id, actor_id, action, payload
  ) VALUES (
    v_workspace_id, p_asset_id, auth.uid(), p_action, p_payload
  )
  RETURNING id INTO v_event_id;

  RETURN v_event_id;
END;
$$;

REVOKE ALL ON FUNCTION public.record_asset_event(UUID, TEXT, JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.record_asset_event(UUID, TEXT, JSONB)
  TO authenticated;

COMMENT ON FUNCTION public.record_asset_event(UUID, TEXT, JSONB) IS
  'Append a row to asset_events. Validates the action name, resolves '
  'the asset''s workspace, checks workspace membership, and stamps '
  'actor from auth.uid(). Only legitimate path for clients to write '
  'events.';

-- ---------------------------------------------------------------------------
-- Realtime
-- ---------------------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'asset_events'
  ) THEN
    EXECUTE 'ALTER PUBLICATION supabase_realtime ADD TABLE asset_events';
  END IF;
END $$;
