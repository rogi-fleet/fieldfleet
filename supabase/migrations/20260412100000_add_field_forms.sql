-- Field Forms System
-- Operational forms filled by field technicians and supervisors.
-- Supports multi-party signing (technician, supervisor, customer) and task integration.

-- =========================================================
-- 1. field_form_templates
-- =========================================================
CREATE TABLE IF NOT EXISTS field_form_templates (
  id                            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id                  UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
  name                          TEXT NOT NULL,
  description                   TEXT,
  -- category: inspection | completion | safety | assessment | custom
  category                      TEXT NOT NULL DEFAULT 'custom',
  fields                        JSONB NOT NULL DEFAULT '[]',
  requires_tech_signature       BOOLEAN NOT NULL DEFAULT FALSE,
  requires_supervisor_signature BOOLEAN NOT NULL DEFAULT FALSE,
  requires_customer_signature   BOOLEAN NOT NULL DEFAULT FALSE,
  -- ships with the system as a built-in template
  is_default                    BOOLEAN NOT NULL DEFAULT FALSE,
  -- task categories that auto-attach this template (e.g. ["electrical","plumbing"])
  default_task_categories       TEXT[] NOT NULL DEFAULT '{}',
  created_by                    UUID REFERENCES users(id),
  created_at                    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at                    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- =========================================================
-- 2. field_form_submissions
-- =========================================================
CREATE TABLE IF NOT EXISTS field_form_submissions (
  id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id                UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
  template_id                 UUID NOT NULL REFERENCES field_form_templates(id) ON DELETE RESTRICT,
  template_name               TEXT NOT NULL,        -- snapshot at fill time
  project_id                  UUID REFERENCES projects(id) ON DELETE SET NULL,
  task_id                     UUID REFERENCES tasks(id) ON DELETE SET NULL,
  title                       TEXT,
  -- status: draft | submitted | approved | rejected
  status                      TEXT NOT NULL DEFAULT 'draft',
  data                        JSONB NOT NULL DEFAULT '{}',
  filled_by_id                UUID REFERENCES users(id),
  filled_by_name              TEXT,
  filled_at                   TIMESTAMPTZ,
  submitted_at                TIMESTAMPTZ,
  notes                       TEXT,
  attached_photo_ids          UUID[] NOT NULL DEFAULT '{}',

  -- Technician signature (internal — signs while filling the form)
  tech_signature_url          TEXT,
  tech_signed_by_name         TEXT,
  tech_signed_by_email        TEXT,
  tech_signed_at              TIMESTAMPTZ,
  tech_signature_ip           TEXT,

  -- Supervisor signature (internal — reviews after submission)
  supervisor_signature_url    TEXT,
  supervisor_signed_by_name   TEXT,
  supervisor_signed_by_email  TEXT,
  supervisor_signed_at        TIMESTAMPTZ,
  supervisor_signature_ip     TEXT,

  -- Customer signature (external — via public sign link)
  customer_signature_url      TEXT,
  customer_signed_by_name     TEXT,
  customer_signed_by_email    TEXT,
  customer_signed_at          TIMESTAMPTZ,
  customer_signature_ip       TEXT,

  created_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- =========================================================
-- 3. field_form_sign_links  (mirrors document_sign_links)
-- Only the edge function has access — no direct client RLS.
-- =========================================================
CREATE TABLE IF NOT EXISTS field_form_sign_links (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id    UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
  submission_id   UUID NOT NULL REFERENCES field_form_submissions(id) ON DELETE CASCADE,
  token           TEXT UNIQUE NOT NULL,
  recipient_email TEXT,
  created_by      UUID REFERENCES users(id),
  expires_at      TIMESTAMPTZ NOT NULL,
  revoked_at      TIMESTAMPTZ,
  used_at         TIMESTAMPTZ,
  last_accessed_at TIMESTAMPTZ,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- =========================================================
-- 4. task_required_forms
-- =========================================================
CREATE TABLE IF NOT EXISTS task_required_forms (
  task_id             UUID NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
  template_id         UUID NOT NULL REFERENCES field_form_templates(id) ON DELETE CASCADE,
  -- null until a submission is linked
  submission_id       UUID REFERENCES field_form_submissions(id) ON DELETE SET NULL,
  blocks_completion   BOOLEAN NOT NULL DEFAULT FALSE,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (task_id, template_id)
);

-- =========================================================
-- Indexes
-- =========================================================
CREATE INDEX IF NOT EXISTS idx_fft_workspace_id
  ON field_form_templates(workspace_id);

CREATE INDEX IF NOT EXISTS idx_fft_is_default
  ON field_form_templates(workspace_id, is_default)
  WHERE is_default = TRUE;

CREATE INDEX IF NOT EXISTS idx_ffs_workspace_id
  ON field_form_submissions(workspace_id);

CREATE INDEX IF NOT EXISTS idx_ffs_template_id
  ON field_form_submissions(template_id);

CREATE INDEX IF NOT EXISTS idx_ffs_task_id
  ON field_form_submissions(task_id);

CREATE INDEX IF NOT EXISTS idx_ffs_project_id
  ON field_form_submissions(project_id);

CREATE INDEX IF NOT EXISTS idx_ffs_status
  ON field_form_submissions(workspace_id, status);

CREATE INDEX IF NOT EXISTS idx_ffsl_submission_id
  ON field_form_sign_links(submission_id);

CREATE INDEX IF NOT EXISTS idx_ffsl_token
  ON field_form_sign_links(token);

CREATE INDEX IF NOT EXISTS idx_trf_task_id
  ON task_required_forms(task_id);

-- =========================================================
-- updated_at triggers
-- =========================================================
DROP TRIGGER IF EXISTS set_field_form_templates_updated_at ON field_form_templates;
CREATE TRIGGER set_field_form_templates_updated_at
  BEFORE UPDATE ON field_form_templates
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS set_field_form_submissions_updated_at ON field_form_submissions;
CREATE TRIGGER set_field_form_submissions_updated_at
  BEFORE UPDATE ON field_form_submissions
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS set_field_form_sign_links_updated_at ON field_form_sign_links;
CREATE TRIGGER set_field_form_sign_links_updated_at
  BEFORE UPDATE ON field_form_sign_links
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- =========================================================
-- Row Level Security
-- =========================================================
ALTER TABLE field_form_templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE field_form_submissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE field_form_sign_links ENABLE ROW LEVEL SECURITY;
ALTER TABLE task_required_forms ENABLE ROW LEVEL SECURITY;

-- Templates: full access for workspace members
DROP POLICY IF EXISTS field_form_templates_workspace_access ON field_form_templates;
CREATE POLICY field_form_templates_workspace_access ON field_form_templates
  FOR ALL
  USING (
    workspace_id IN (
      SELECT workspace_id FROM workspace_members WHERE user_id = auth.uid()
    )
  )
  WITH CHECK (
    workspace_id IN (
      SELECT workspace_id FROM workspace_members WHERE user_id = auth.uid()
    )
  );

-- Submissions: full access for workspace members
DROP POLICY IF EXISTS field_form_submissions_workspace_access ON field_form_submissions;
CREATE POLICY field_form_submissions_workspace_access ON field_form_submissions
  FOR ALL
  USING (
    workspace_id IN (
      SELECT workspace_id FROM workspace_members WHERE user_id = auth.uid()
    )
  )
  WITH CHECK (
    workspace_id IN (
      SELECT workspace_id FROM workspace_members WHERE user_id = auth.uid()
    )
  );

-- Sign links: no direct client access (edge function only, same as document_sign_links)
DROP POLICY IF EXISTS field_form_sign_links_no_direct_access ON field_form_sign_links;
CREATE POLICY field_form_sign_links_no_direct_access ON field_form_sign_links
  FOR ALL
  USING (FALSE)
  WITH CHECK (FALSE);

-- Task required forms: access via workspace membership on the parent task
DROP POLICY IF EXISTS task_required_forms_workspace_access ON task_required_forms;
CREATE POLICY task_required_forms_workspace_access ON task_required_forms
  FOR ALL
  USING (
    task_id IN (
      SELECT t.id FROM tasks t
      JOIN workspace_members wm ON wm.workspace_id = t.workspace_id
      WHERE wm.user_id = auth.uid()
    )
  )
  WITH CHECK (
    task_id IN (
      SELECT t.id FROM tasks t
      JOIN workspace_members wm ON wm.workspace_id = t.workspace_id
      WHERE wm.user_id = auth.uid()
    )
  );
