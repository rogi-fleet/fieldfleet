-- Unit-holder-submitted maintenance/support issues against a single
-- property. Modeled after selection_comments: a plain table with
-- denormalized author info (no FK to users, since portal authors don't
-- have a public.users row), staff-only direct RLS, and all portal
-- reads/writes going through SECURITY DEFINER RPCs (see
-- 20260612120000_add_property_issues_portal_rpcs.sql).

CREATE TABLE IF NOT EXISTS public.property_issues (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id   UUID NOT NULL REFERENCES public.workspaces(id) ON DELETE CASCADE,
  property_id    UUID NOT NULL REFERENCES public.properties(id) ON DELETE CASCADE,
  project_id     UUID NOT NULL REFERENCES public.projects(id) ON DELETE CASCADE,
  title          TEXT NOT NULL,
  description    TEXT,
  status         TEXT NOT NULL DEFAULT 'open'
                   CHECK (status IN ('open', 'in_progress', 'resolved', 'closed')),
  priority       TEXT NOT NULL DEFAULT 'normal'
                   CHECK (priority IN ('low', 'normal', 'high', 'urgent')),
  reported_by_contact_id UUID REFERENCES public.customer_contacts(id) ON DELETE SET NULL,
  reporter_name  TEXT,
  reporter_email TEXT,
  resolved_at    TIMESTAMPTZ,
  resolved_by    UUID REFERENCES public.users(id),
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_property_issues_property_id
  ON public.property_issues (property_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_property_issues_workspace_status
  ON public.property_issues (workspace_id, status);

ALTER TABLE public.property_issues ENABLE ROW LEVEL SECURITY;

-- Staff-only direct table RLS, explicitly excluding external portal users
-- (unlike field_form_submissions' looser "any workspace member" policy,
-- since that table is never touched by any portal codepath). This table
-- *is* written to by portal users too, so the RPC layer must be the only
-- portal entry point — this policy must not let a client-role JWT hit
-- PostgREST directly and read/write rows outside their one property.
DROP POLICY IF EXISTS property_issues_staff_access ON public.property_issues;
CREATE POLICY property_issues_staff_access ON public.property_issues
  FOR ALL USING (
    public.has_workspace_module_permission(workspace_id, 'properties', 'read')
    AND NOT public.is_external_portal_user(workspace_id)
  )
  WITH CHECK (
    public.has_workspace_module_permission(workspace_id, 'properties', 'write')
    AND NOT public.is_external_portal_user(workspace_id)
  );

COMMENT ON TABLE public.property_issues IS
  'Maintenance/support issues raised against a single property. Portal (unit holder) reads/writes exclusively via portal_get_property_issues / portal_create_property_issue RPCs — never direct table access. Staff use normal RLS (this policy) via the property''s Issues tab.';
