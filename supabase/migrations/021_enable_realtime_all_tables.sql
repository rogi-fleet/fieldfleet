-- Enable realtime for all remaining tables
-- Made idempotent: only adds tables if not already in publication

DO $$
DECLARE
  tables_to_add text[] := ARRAY[
    -- Tasks
    'tasks', 'task_assignees', 'task_comments', 'task_dependencies', 'task_required_assets', 'task_required_skills', 'task_progress_history',
    -- Skills
    'skills',
    -- Vendors
    'vendors', 'vendor_contacts',
    -- Customers
    'customers', 'customer_contacts', 'customer_tags', 'customer_tag_assignments',
    -- Time tracking
    'time_entries',
    -- Finance
    'bills', 'bid_requests', 'invoices', 'purchase_orders', 'change_orders', 'refunds', 'cost_items', 'cost_categories', 'service_agreements',
    -- Documents
    'generated_documents', 'document_templates',
    -- Files
    'file_folders', 'file_attachments',
    -- Catalog
    'catalog_items',
    -- Conversations
    'conversations', 'messages',
    -- Workspaces
    'workspaces', 'workspace_members', 'workspace_invitations',
    -- Users
    'users'
  ];
  tbl text;
BEGIN
  FOREACH tbl IN ARRAY tables_to_add LOOP
    IF NOT EXISTS (
      SELECT 1 FROM pg_publication_tables 
      WHERE pubname = 'supabase_realtime' AND tablename = tbl
    ) THEN
      -- Only add if table exists
      IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = tbl) THEN
        EXECUTE format('ALTER PUBLICATION supabase_realtime ADD TABLE %I', tbl);
      END IF;
    END IF;
  END LOOP;
END $$;
