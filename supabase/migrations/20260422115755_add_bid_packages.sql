-- Multi-vendor bidding: a "bid package" groups N per-vendor request-for-bid
-- documents that all quote the same scope. Each vendor sees only their
-- own child RFB; the GC works at the package level to compare bids and
-- pick a winner.

CREATE TABLE IF NOT EXISTS public.bid_packages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL REFERENCES public.workspaces(id) ON DELETE CASCADE,
  project_id uuid REFERENCES public.projects(id) ON DELETE SET NULL,
  name text NOT NULL,
  scope_description text,
  due_date timestamptz,
  status text NOT NULL DEFAULT 'draft'
    CHECK (status IN ('draft','sent','awarded','expired','cancelled')),
  awarded_document_id uuid REFERENCES public.generated_documents(id)
    ON DELETE SET NULL,
  created_by uuid,
  created_at timestamptz DEFAULT NOW() NOT NULL,
  updated_at timestamptz DEFAULT NOW() NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_bid_packages_workspace
  ON public.bid_packages(workspace_id);
CREATE INDEX IF NOT EXISTS idx_bid_packages_project
  ON public.bid_packages(project_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_bid_packages_status
  ON public.bid_packages(status) WHERE status IN ('draft', 'sent');

-- Each child RFB document points back to its parent package.
ALTER TABLE public.generated_documents
  ADD COLUMN IF NOT EXISTS bid_package_id uuid
  REFERENCES public.bid_packages(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_generated_documents_bid_package
  ON public.generated_documents(bid_package_id)
  WHERE bid_package_id IS NOT NULL;

-- New document_status values ('not_selected', 'withdrawn') are added in
-- a separate migration: ALTER TYPE ADD VALUE can't share a transaction
-- with other DDL that references the type.

-- updated_at trigger.
CREATE OR REPLACE FUNCTION public.touch_bid_packages_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at := NOW();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS bid_packages_touch_updated_at ON public.bid_packages;
CREATE TRIGGER bid_packages_touch_updated_at
  BEFORE UPDATE ON public.bid_packages
  FOR EACH ROW EXECUTE FUNCTION public.touch_bid_packages_updated_at();

-- RLS. Packages are internal-only — vendors never see them directly.
ALTER TABLE public.bid_packages ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS bid_packages_select ON public.bid_packages;
CREATE POLICY bid_packages_select ON public.bid_packages
  FOR SELECT USING (
    has_workspace_module_permission(workspace_id, 'bid_requests', 'read')
    AND NOT is_external_portal_user(workspace_id)
  );

DROP POLICY IF EXISTS bid_packages_insert ON public.bid_packages;
CREATE POLICY bid_packages_insert ON public.bid_packages
  FOR INSERT WITH CHECK (
    has_workspace_module_permission(workspace_id, 'bid_requests', 'write')
    AND NOT is_external_portal_user(workspace_id)
  );

DROP POLICY IF EXISTS bid_packages_update ON public.bid_packages;
CREATE POLICY bid_packages_update ON public.bid_packages
  FOR UPDATE USING (
    has_workspace_module_permission(workspace_id, 'bid_requests', 'write')
    AND NOT is_external_portal_user(workspace_id)
  );

DROP POLICY IF EXISTS bid_packages_delete ON public.bid_packages;
CREATE POLICY bid_packages_delete ON public.bid_packages
  FOR DELETE USING (
    has_workspace_module_permission(workspace_id, 'bid_requests', 'write')
    AND NOT is_external_portal_user(workspace_id)
  );
