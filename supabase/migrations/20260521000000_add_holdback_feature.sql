-- =============================================================================
-- Holdback (retainage) feature
--
--   1. generated_documents       — add retainage_* columns so any invoice doc
--                                  can carry a withheld holdback amount.
--   2. projects                  — add holdback_default_percent + release
--                                  condition so each job has its own defaults.
--   3. holdback_releases         — header rows representing a holdback release
--                                  event (draft → issued → paid).
--   4. holdback_release_lines    — what was released: a slice of a source
--                                  invoice's retainage and/or a budget item.
--   5. RPC issue_holdback_release — atomic: flips status to issued, stamps
--                                  released-date on every linked source invoice,
--                                  marks linked budget items released.
-- =============================================================================

-- 1) Per-document retainage columns ------------------------------------------
ALTER TABLE generated_documents
  ADD COLUMN IF NOT EXISTS retainage_percent       NUMERIC(5,2)  NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS retainage_amount        NUMERIC(15,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS retainage_released      BOOLEAN       NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS retainage_released_date DATE,
  ADD COLUMN IF NOT EXISTS retainage_release_id    UUID;

CREATE INDEX IF NOT EXISTS idx_gen_docs_retainage_outstanding
  ON generated_documents(project_id)
  WHERE retainage_amount > 0 AND retainage_released = FALSE;

-- 2) Project-level holdback defaults -----------------------------------------
ALTER TABLE projects
  ADD COLUMN IF NOT EXISTS holdback_default_percent   NUMERIC(5,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS holdback_release_condition TEXT         NOT NULL DEFAULT 'substantial_completion';

-- 3) Holdback release header --------------------------------------------------
CREATE TABLE IF NOT EXISTS holdback_releases (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  workspace_id    UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
  project_id      UUID NOT NULL REFERENCES projects(id)   ON DELETE CASCADE,

  release_number  INT  NOT NULL,
  release_date    DATE NOT NULL DEFAULT CURRENT_DATE,
  status          TEXT NOT NULL DEFAULT 'draft'
                    CHECK (status IN ('draft','issued','paid')),
  total_amount    NUMERIC(15,2) NOT NULL DEFAULT 0,
  notes           TEXT,

  -- generated_documents row carrying the release PDF/email (nullable until
  -- the release is rendered into a document).
  document_id     UUID REFERENCES generated_documents(id) ON DELETE SET NULL,

  issued_at       TIMESTAMPTZ,
  paid_at         TIMESTAMPTZ,

  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by      UUID,

  CONSTRAINT holdback_releases_unique_number UNIQUE (project_id, release_number)
);

CREATE INDEX IF NOT EXISTS idx_holdback_releases_project
  ON holdback_releases(project_id);
CREATE INDEX IF NOT EXISTS idx_holdback_releases_workspace
  ON holdback_releases(workspace_id);

-- 4) Holdback release lines ---------------------------------------------------
CREATE TABLE IF NOT EXISTS holdback_release_lines (
  id                     UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  release_id             UUID NOT NULL REFERENCES holdback_releases(id) ON DELETE CASCADE,
  workspace_id           UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,

  -- Source — at least one must be set. Source invoice = a generated_document
  -- with a non-zero retainage_amount; budget item = budget-item-level holdback.
  source_invoice_id      UUID REFERENCES generated_documents(id) ON DELETE SET NULL,
  source_budget_item_id  UUID REFERENCES budget_items(id)         ON DELETE SET NULL,

  description            TEXT NOT NULL DEFAULT '',
  amount_held            NUMERIC(15,2) NOT NULL DEFAULT 0,
  amount_released        NUMERIC(15,2) NOT NULL DEFAULT 0,
  sort_order             INT NOT NULL DEFAULT 0,

  created_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at             TIMESTAMPTZ NOT NULL DEFAULT now(),

  CONSTRAINT holdback_release_line_has_source
    CHECK (source_invoice_id IS NOT NULL OR source_budget_item_id IS NOT NULL)
);

CREATE INDEX IF NOT EXISTS idx_holdback_release_lines_release
  ON holdback_release_lines(release_id);
CREATE INDEX IF NOT EXISTS idx_holdback_release_lines_invoice
  ON holdback_release_lines(source_invoice_id);
CREATE INDEX IF NOT EXISTS idx_holdback_release_lines_budget_item
  ON holdback_release_lines(source_budget_item_id);

-- ── RLS ─────────────────────────────────────────────────────────────────────
ALTER TABLE holdback_releases       ENABLE ROW LEVEL SECURITY;
ALTER TABLE holdback_release_lines  ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS holdback_releases_select ON holdback_releases;
DROP POLICY IF EXISTS holdback_releases_insert ON holdback_releases;
DROP POLICY IF EXISTS holdback_releases_update ON holdback_releases;
DROP POLICY IF EXISTS holdback_releases_delete ON holdback_releases;
CREATE POLICY holdback_releases_select ON holdback_releases
  FOR SELECT USING (is_workspace_member(workspace_id));
CREATE POLICY holdback_releases_insert ON holdback_releases
  FOR INSERT WITH CHECK (is_workspace_member(workspace_id));
CREATE POLICY holdback_releases_update ON holdback_releases
  FOR UPDATE USING (is_workspace_member(workspace_id));
CREATE POLICY holdback_releases_delete ON holdback_releases
  FOR DELETE USING (is_workspace_member(workspace_id));

DROP POLICY IF EXISTS holdback_release_lines_select ON holdback_release_lines;
DROP POLICY IF EXISTS holdback_release_lines_insert ON holdback_release_lines;
DROP POLICY IF EXISTS holdback_release_lines_update ON holdback_release_lines;
DROP POLICY IF EXISTS holdback_release_lines_delete ON holdback_release_lines;
CREATE POLICY holdback_release_lines_select ON holdback_release_lines
  FOR SELECT USING (is_workspace_member(workspace_id));
CREATE POLICY holdback_release_lines_insert ON holdback_release_lines
  FOR INSERT WITH CHECK (is_workspace_member(workspace_id));
CREATE POLICY holdback_release_lines_update ON holdback_release_lines
  FOR UPDATE USING (is_workspace_member(workspace_id));
CREATE POLICY holdback_release_lines_delete ON holdback_release_lines
  FOR DELETE USING (is_workspace_member(workspace_id));

-- ── updated_at + workspace-consistency triggers ─────────────────────────────
CREATE OR REPLACE FUNCTION holdback_set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql SET search_path = public, pg_temp AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END $$;

DROP TRIGGER IF EXISTS trg_holdback_releases_updated ON holdback_releases;
CREATE TRIGGER trg_holdback_releases_updated BEFORE UPDATE ON holdback_releases
  FOR EACH ROW EXECUTE FUNCTION holdback_set_updated_at();

DROP TRIGGER IF EXISTS trg_holdback_release_lines_updated ON holdback_release_lines;
CREATE TRIGGER trg_holdback_release_lines_updated BEFORE UPDATE ON holdback_release_lines
  FOR EACH ROW EXECUTE FUNCTION holdback_set_updated_at();

CREATE OR REPLACE FUNCTION holdback_release_line_assert_workspace()
RETURNS TRIGGER LANGUAGE plpgsql SET search_path = public, pg_temp AS $$
DECLARE
  v_parent_ws UUID;
BEGIN
  SELECT workspace_id INTO v_parent_ws
    FROM holdback_releases
    WHERE id = NEW.release_id;
  IF v_parent_ws IS NULL THEN
    RAISE EXCEPTION 'holdback_release_lines: parent release % not found', NEW.release_id;
  END IF;
  IF v_parent_ws IS DISTINCT FROM NEW.workspace_id THEN
    RAISE EXCEPTION 'holdback_release_lines: workspace mismatch (line %, parent %)',
      NEW.workspace_id, v_parent_ws;
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_holdback_release_line_assert_workspace ON holdback_release_lines;
CREATE TRIGGER trg_holdback_release_line_assert_workspace
  BEFORE INSERT OR UPDATE OF workspace_id, release_id ON holdback_release_lines
  FOR EACH ROW EXECUTE FUNCTION holdback_release_line_assert_workspace();

-- 5) Atomic issue: flip status + stamp sources ------------------------------
CREATE OR REPLACE FUNCTION issue_holdback_release(p_release_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_release_date DATE;
BEGIN
  UPDATE holdback_releases
     SET status = 'issued',
         issued_at = now(),
         release_date = COALESCE(release_date, CURRENT_DATE)
   WHERE id = p_release_id
     AND status = 'draft'
   RETURNING release_date INTO v_release_date;

  IF v_release_date IS NULL THEN
    RAISE EXCEPTION 'issue_holdback_release: release % is not in draft or does not exist',
      p_release_id;
  END IF;

  -- Stamp the source invoices.
  UPDATE generated_documents AS gd
     SET retainage_released = TRUE,
         retainage_released_date = COALESCE(retainage_released_date, v_release_date),
         retainage_release_id = p_release_id
   WHERE gd.id IN (
     SELECT source_invoice_id FROM holdback_release_lines
      WHERE release_id = p_release_id AND source_invoice_id IS NOT NULL
   );

  -- Stamp the source budget items.
  UPDATE budget_items AS bi
     SET holdback_released = TRUE,
         holdback_released_date = COALESCE(holdback_released_date, v_release_date)
   WHERE bi.id IN (
     SELECT source_budget_item_id FROM holdback_release_lines
      WHERE release_id = p_release_id AND source_budget_item_id IS NOT NULL
   );
END $$;

-- 6) Helper: next release number per project --------------------------------
CREATE OR REPLACE FUNCTION next_holdback_release_number(p_project_id UUID)
RETURNS INT
LANGUAGE sql
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
  SELECT COALESCE(MAX(release_number), 0) + 1
    FROM holdback_releases
   WHERE project_id = p_project_id;
$$;
