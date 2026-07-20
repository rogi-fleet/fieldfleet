-- =============================================================================
-- Add covering indexes for foreign keys on financial tables.
--
-- Surfaced by the Supabase performance advisor (unindexed_foreign_keys).
-- Postgres won't auto-create indexes for FKs, so without these, queries
-- that filter or join on these columns (e.g. "all invoices for project X",
-- "all payments for bank account Y", "drill JE from invoice") fall back to
-- sequential scans. As the workspace grows past a few hundred rows the
-- difference is noticeable on dashboards and reports.
--
-- All indexes are CREATE INDEX IF NOT EXISTS so the migration is idempotent.
-- Applied to the live DB via the supabase MCP `apply_migration` tool.
-- =============================================================================

CREATE INDEX IF NOT EXISTS idx_budget_document_links_created_by ON public.budget_document_links (created_by);
CREATE INDEX IF NOT EXISTS idx_budget_document_links_project_id ON public.budget_document_links (project_id);
CREATE INDEX IF NOT EXISTS idx_budget_items_category_id ON public.budget_items (category_id);
CREATE INDEX IF NOT EXISTS idx_document_sign_links_created_by ON public.document_sign_links (created_by);
CREATE INDEX IF NOT EXISTS idx_generated_documents_created_by ON public.generated_documents (created_by);
CREATE INDEX IF NOT EXISTS idx_generated_documents_customer_id ON public.generated_documents (customer_id);
CREATE INDEX IF NOT EXISTS idx_generated_documents_template_id ON public.generated_documents (template_id);
