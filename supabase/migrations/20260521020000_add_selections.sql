-- =============================================================================
-- Selections & Allowances workflow.
--
--   1. selections          — one decision the client must make on a job
--                            (e.g. "Kitchen faucet", "Bathroom tile"). Each
--                            row carries an allowance and the ultimately
--                            selected cost. Approval feeds the budget rollup.
--   2. selection_options   — the choices the team offers the client. The one
--                            chosen sets `selected_option_id` and price.
--   3. RPCs                — portal-side: list / approve / decline.
-- =============================================================================

CREATE TABLE IF NOT EXISTS selections (
  id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  workspace_id        UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
  project_id          UUID NOT NULL REFERENCES projects(id)   ON DELETE CASCADE,

  name                TEXT NOT NULL,
  description         TEXT,
  category            TEXT,
  location            TEXT,

  status              TEXT NOT NULL DEFAULT 'pending'
                        CHECK (status IN (
                          'pending',
                          'awaiting_client',
                          'approved',
                          'declined',
                          'cancelled'
                        )),

  allowance_amount    NUMERIC(15,2) NOT NULL DEFAULT 0,
  selected_amount     NUMERIC(15,2) NOT NULL DEFAULT 0,
  budget_item_id      UUID REFERENCES budget_items(id) ON DELETE SET NULL,
  selected_option_id  UUID,

  due_date            DATE,
  client_notes        TEXT,
  internal_notes      TEXT,

  approved_at         TIMESTAMPTZ,
  approved_by_name    TEXT,
  approved_by_email   TEXT,
  declined_at         TIMESTAMPTZ,
  declined_by_name    TEXT,
  decline_reason      TEXT,

  created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by          UUID,
  sort_order          INT NOT NULL DEFAULT 0
);

CREATE INDEX IF NOT EXISTS idx_selections_project   ON selections(project_id);
CREATE INDEX IF NOT EXISTS idx_selections_workspace ON selections(workspace_id);
CREATE INDEX IF NOT EXISTS idx_selections_status    ON selections(project_id, status);

CREATE TABLE IF NOT EXISTS selection_options (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  selection_id    UUID NOT NULL REFERENCES selections(id) ON DELETE CASCADE,
  workspace_id    UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,

  name            TEXT NOT NULL,
  description     TEXT,
  vendor          TEXT,
  sku             TEXT,
  unit_cost       NUMERIC(15,2) NOT NULL DEFAULT 0,
  quantity        NUMERIC(15,2) NOT NULL DEFAULT 1,
  image_url       TEXT,
  external_url    TEXT,

  sort_order      INT NOT NULL DEFAULT 0,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_selection_options_selection
  ON selection_options(selection_id);

ALTER TABLE selections DROP CONSTRAINT IF EXISTS selections_selected_option_fk;
ALTER TABLE selections
  ADD CONSTRAINT selections_selected_option_fk
  FOREIGN KEY (selected_option_id) REFERENCES selection_options(id)
  ON DELETE SET NULL;

-- updated_at triggers (project uses `update_updated_at_column`)
DROP TRIGGER IF EXISTS trg_selections_updated_at ON selections;
CREATE TRIGGER trg_selections_updated_at
  BEFORE UPDATE ON selections
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS trg_selection_options_updated_at ON selection_options;
CREATE TRIGGER trg_selection_options_updated_at
  BEFORE UPDATE ON selection_options
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- RLS
ALTER TABLE selections        ENABLE ROW LEVEL SECURITY;
ALTER TABLE selection_options ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS selections_select ON selections;
DROP POLICY IF EXISTS selections_insert ON selections;
DROP POLICY IF EXISTS selections_update ON selections;
DROP POLICY IF EXISTS selections_delete ON selections;
CREATE POLICY selections_select ON selections
  FOR SELECT USING (is_workspace_member(workspace_id));
CREATE POLICY selections_insert ON selections
  FOR INSERT WITH CHECK (is_workspace_member(workspace_id));
CREATE POLICY selections_update ON selections
  FOR UPDATE USING (is_workspace_member(workspace_id));
CREATE POLICY selections_delete ON selections
  FOR DELETE USING (is_workspace_member(workspace_id));

DROP POLICY IF EXISTS selection_options_select ON selection_options;
DROP POLICY IF EXISTS selection_options_insert ON selection_options;
DROP POLICY IF EXISTS selection_options_update ON selection_options;
DROP POLICY IF EXISTS selection_options_delete ON selection_options;
CREATE POLICY selection_options_select ON selection_options
  FOR SELECT USING (is_workspace_member(workspace_id));
CREATE POLICY selection_options_insert ON selection_options
  FOR INSERT WITH CHECK (is_workspace_member(workspace_id));
CREATE POLICY selection_options_update ON selection_options
  FOR UPDATE USING (is_workspace_member(workspace_id));
CREATE POLICY selection_options_delete ON selection_options
  FOR DELETE USING (is_workspace_member(workspace_id));

-- ============================================================================
-- Portal RPCs.  Auth = JWT email matched against an active customer_contact
-- of the project's client (same pattern used by `portal_deny_document`).
-- ============================================================================

CREATE OR REPLACE FUNCTION public.portal_get_project_selections(
  p_project_id UUID
)
RETURNS TABLE (
  id                 UUID,
  project_id         UUID,
  name               TEXT,
  description        TEXT,
  category           TEXT,
  location           TEXT,
  status             TEXT,
  allowance_amount   NUMERIC,
  selected_amount    NUMERIC,
  selected_option_id UUID,
  due_date           DATE,
  client_notes       TEXT,
  approved_at        TIMESTAMPTZ,
  options            JSONB
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  normalized_email TEXT := LOWER(TRIM(COALESCE(auth.jwt() ->> 'email', '')));
  v_allowed BOOLEAN;
BEGIN
  IF normalized_email = '' THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM projects p
    JOIN customer_contacts cc ON cc.customer_id = p.client_id
    WHERE p.id = p_project_id
      AND cc.is_active = TRUE
      AND LOWER(TRIM(COALESCE(cc.email, ''))) = normalized_email
  ) INTO v_allowed;

  IF NOT v_allowed THEN
    RAISE EXCEPTION 'Project not found or access denied';
  END IF;

  RETURN QUERY
  SELECT
    s.id, s.project_id, s.name, s.description, s.category, s.location,
    s.status, s.allowance_amount, s.selected_amount, s.selected_option_id,
    s.due_date, s.client_notes, s.approved_at,
    COALESCE(
      (
        SELECT jsonb_agg(
          jsonb_build_object(
            'id', o.id,
            'name', o.name,
            'description', o.description,
            'vendor', o.vendor,
            'sku', o.sku,
            'unit_cost', o.unit_cost,
            'quantity', o.quantity,
            'image_url', o.image_url,
            'external_url', o.external_url,
            'sort_order', o.sort_order
          )
          ORDER BY o.sort_order, o.created_at
        )
        FROM selection_options o
        WHERE o.selection_id = s.id
      ),
      '[]'::jsonb
    )
  FROM selections s
  WHERE s.project_id = p_project_id
    AND s.status IN ('awaiting_client', 'approved', 'declined')
  ORDER BY
    CASE s.status WHEN 'awaiting_client' THEN 0
                  WHEN 'approved'        THEN 1
                  ELSE 2 END,
    s.due_date NULLS LAST,
    s.created_at;
END;
$$;

REVOKE ALL ON FUNCTION public.portal_get_project_selections(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.portal_get_project_selections(UUID)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.portal_approve_selection(
  p_selection_id UUID,
  p_option_id    UUID,
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
  opt_row RECORD;
BEGIN
  IF normalized_email = '' THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  SELECT s.id, s.project_id, s.status, p.client_id
  INTO sel_row
  FROM selections s
  JOIN projects p ON p.id = s.project_id
  WHERE s.id = p_selection_id
    AND EXISTS (
      SELECT 1 FROM customer_contacts cc
      WHERE cc.customer_id = p.client_id
        AND cc.is_active = TRUE
        AND LOWER(TRIM(COALESCE(cc.email, ''))) = normalized_email
    )
  LIMIT 1;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Selection not found or access denied';
  END IF;
  IF sel_row.status NOT IN ('awaiting_client', 'declined') THEN
    RAISE EXCEPTION 'Selection cannot be approved in status (%)', sel_row.status;
  END IF;

  SELECT id, unit_cost, quantity INTO opt_row
  FROM selection_options
  WHERE id = p_option_id AND selection_id = p_selection_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Option not found for this selection';
  END IF;

  UPDATE selections SET
    status             = 'approved',
    selected_option_id = opt_row.id,
    selected_amount    = COALESCE(opt_row.unit_cost,0) * COALESCE(opt_row.quantity,1),
    approved_at        = now(),
    approved_by_name   = COALESCE(p_actor_name, 'Client'),
    approved_by_email  = normalized_email,
    declined_at        = NULL,
    declined_by_name   = NULL,
    decline_reason     = NULL,
    updated_at         = now()
  WHERE id = p_selection_id;

  RETURN jsonb_build_object('success', true);
END;
$$;

REVOKE ALL ON FUNCTION public.portal_approve_selection(UUID, UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.portal_approve_selection(UUID, UUID, TEXT)
  TO authenticated;

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
  v_allowed BOOLEAN;
BEGIN
  IF normalized_email = '' THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  SELECT EXISTS (
    SELECT 1
    FROM selections s
    JOIN projects p ON p.id = s.project_id
    JOIN customer_contacts cc ON cc.customer_id = p.client_id
    WHERE s.id = p_selection_id
      AND cc.is_active = TRUE
      AND LOWER(TRIM(COALESCE(cc.email, ''))) = normalized_email
  ) INTO v_allowed;

  IF NOT v_allowed THEN
    RAISE EXCEPTION 'Selection not found or access denied';
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
