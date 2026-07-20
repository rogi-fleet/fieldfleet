-- =============================================================================
-- Harden selections: enforce tenant consistency + tighten portal decline RPC.
--
-- Addresses code-review findings on 20260521020000_add_selections.sql:
--   * selections.workspace_id MUST equal projects.workspace_id
--   * selection_options.workspace_id MUST equal parent selections.workspace_id
--   * portal_decline_selection: only allow awaiting_client -> declined
-- =============================================================================

-- ── Tenant-consistency triggers ─────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.selections_enforce_tenant()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  proj_ws UUID;
BEGIN
  SELECT workspace_id INTO proj_ws FROM projects WHERE id = NEW.project_id;
  IF proj_ws IS NULL THEN
    RAISE EXCEPTION 'Project % does not exist', NEW.project_id;
  END IF;
  IF NEW.workspace_id IS DISTINCT FROM proj_ws THEN
    RAISE EXCEPTION
      'selections.workspace_id (%) does not match project.workspace_id (%)',
      NEW.workspace_id, proj_ws;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_selections_tenant ON selections;
CREATE TRIGGER trg_selections_tenant
  BEFORE INSERT OR UPDATE OF workspace_id, project_id ON selections
  FOR EACH ROW EXECUTE FUNCTION public.selections_enforce_tenant();

CREATE OR REPLACE FUNCTION public.selection_options_enforce_tenant()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  parent_ws UUID;
BEGIN
  SELECT workspace_id INTO parent_ws
  FROM selections WHERE id = NEW.selection_id;
  IF parent_ws IS NULL THEN
    RAISE EXCEPTION 'Selection % does not exist', NEW.selection_id;
  END IF;
  IF NEW.workspace_id IS DISTINCT FROM parent_ws THEN
    RAISE EXCEPTION
      'selection_options.workspace_id (%) does not match parent selection.workspace_id (%)',
      NEW.workspace_id, parent_ws;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_selection_options_tenant ON selection_options;
CREATE TRIGGER trg_selection_options_tenant
  BEFORE INSERT OR UPDATE OF workspace_id, selection_id ON selection_options
  FOR EACH ROW EXECUTE FUNCTION public.selection_options_enforce_tenant();

-- ── Tighten portal_decline_selection: status-transition guard ───────────────

CREATE OR REPLACE FUNCTION public.portal_decline_selection(
  p_selection_id UUID,
  p_reason       TEXT DEFAULT NULL,
  p_actor_name   TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  normalized_email TEXT := LOWER(TRIM(COALESCE(auth.jwt() ->> 'email', '')));
  sel_row RECORD;
BEGIN
  IF normalized_email = '' THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  SELECT s.id, s.status
  INTO sel_row
  FROM selections s
  JOIN projects p ON p.id = s.project_id
  JOIN customer_contacts cc ON cc.customer_id = p.client_id
  WHERE s.id = p_selection_id
    AND cc.is_active = TRUE
    AND LOWER(TRIM(COALESCE(cc.email, ''))) = normalized_email
  LIMIT 1;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Selection not found or access denied';
  END IF;

  IF sel_row.status <> 'awaiting_client' THEN
    RAISE EXCEPTION 'Selection cannot be declined in status (%)', sel_row.status;
  END IF;

  UPDATE selections SET
    status           = 'declined',
    declined_at      = now(),
    declined_by_name = COALESCE(p_actor_name, 'Client'),
    decline_reason   = p_reason,
    updated_at       = now()
  WHERE id = p_selection_id;

  RETURN jsonb_build_object('success', true);
END;
$$;

REVOKE ALL ON FUNCTION public.portal_decline_selection(UUID, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.portal_decline_selection(UUID, TEXT, TEXT)
  TO authenticated;
