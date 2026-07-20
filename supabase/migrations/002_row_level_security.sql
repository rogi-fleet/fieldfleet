-- ============================================================================
-- ROW LEVEL SECURITY POLICIES
-- Replaces Firebase Security Rules with PostgreSQL RLS
-- ============================================================================

-- Helper function: Check if user is a workspace member
CREATE OR REPLACE FUNCTION is_workspace_member(workspace_uuid UUID)
RETURNS BOOLEAN AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM workspace_members
    WHERE workspace_id = workspace_uuid
    AND user_id = auth.uid()
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Helper function: Check if user is workspace admin
CREATE OR REPLACE FUNCTION is_workspace_admin(workspace_uuid UUID)
RETURNS BOOLEAN AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM workspace_members
    WHERE workspace_id = workspace_uuid
    AND user_id = auth.uid()
    AND role = 'admin'
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Helper function: Check if user is PM or admin
CREATE OR REPLACE FUNCTION is_pm_or_admin(workspace_uuid UUID)
RETURNS BOOLEAN AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM workspace_members
    WHERE workspace_id = workspace_uuid
    AND user_id = auth.uid()
    AND role IN ('admin', 'project_manager')
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Helper function: Get user's workspace IDs
CREATE OR REPLACE FUNCTION get_user_workspace_ids()
RETURNS UUID[] AS $$
BEGIN
  RETURN ARRAY(
    SELECT workspace_id FROM workspace_members
    WHERE user_id = auth.uid()
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- WORKSPACES
-- ============================================================================

ALTER TABLE workspaces ENABLE ROW LEVEL SECURITY;

-- Users can view workspaces they're members of
DROP POLICY IF EXISTS workspaces_select ON workspaces;
CREATE POLICY workspaces_select ON workspaces
  FOR SELECT USING (is_workspace_member(id));

-- Only admins can update workspace settings
DROP POLICY IF EXISTS workspaces_update ON workspaces;
CREATE POLICY workspaces_update ON workspaces
  FOR UPDATE USING (is_workspace_admin(id));

-- Any authenticated user can create a workspace (they become owner)
DROP POLICY IF EXISTS workspaces_insert ON workspaces;
CREATE POLICY workspaces_insert ON workspaces
  FOR INSERT WITH CHECK (auth.uid() IS NOT NULL);

-- Only owner can delete workspace
DROP POLICY IF EXISTS workspaces_delete ON workspaces;
CREATE POLICY workspaces_delete ON workspaces
  FOR DELETE USING (owner_id = auth.uid());

-- ============================================================================
-- USERS
-- ============================================================================

ALTER TABLE users ENABLE ROW LEVEL SECURITY;

-- Users can view other users in their workspaces
DROP POLICY IF EXISTS users_select ON users;
CREATE POLICY users_select ON users
  FOR SELECT USING (
    id = auth.uid() OR
    id IN (
      SELECT wm.user_id FROM workspace_members wm
      WHERE wm.workspace_id = ANY(get_user_workspace_ids())
    )
  );

-- Users can update their own profile
DROP POLICY IF EXISTS users_update ON users;
CREATE POLICY users_update ON users
  FOR UPDATE USING (id = auth.uid());

-- Users can insert their own record
DROP POLICY IF EXISTS users_insert ON users;
CREATE POLICY users_insert ON users
  FOR INSERT WITH CHECK (id = auth.uid());

-- ============================================================================
-- WORKSPACE MEMBERS
-- ============================================================================

ALTER TABLE workspace_members ENABLE ROW LEVEL SECURITY;

-- Members can view other members in their workspaces
DROP POLICY IF EXISTS workspace_members_select ON workspace_members;
CREATE POLICY workspace_members_select ON workspace_members
  FOR SELECT USING (is_workspace_member(workspace_id));

-- Only admins can add/update/remove members
DROP POLICY IF EXISTS workspace_members_insert ON workspace_members;
CREATE POLICY workspace_members_insert ON workspace_members
  FOR INSERT WITH CHECK (is_workspace_admin(workspace_id) OR (
    -- Allow users to add themselves as owner when creating workspace
    user_id = auth.uid() AND role = 'admin'
  ));

DROP POLICY IF EXISTS workspace_members_update ON workspace_members;
CREATE POLICY workspace_members_update ON workspace_members
  FOR UPDATE USING (is_workspace_admin(workspace_id));

DROP POLICY IF EXISTS workspace_members_delete ON workspace_members;
CREATE POLICY workspace_members_delete ON workspace_members
  FOR DELETE USING (is_workspace_admin(workspace_id));

-- ============================================================================
-- WORKSPACE INVITATIONS
-- ============================================================================

ALTER TABLE workspace_invitations ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS invitations_select ON workspace_invitations;
CREATE POLICY invitations_select ON workspace_invitations
  FOR SELECT USING (is_workspace_admin(workspace_id));

DROP POLICY IF EXISTS invitations_insert ON workspace_invitations;
CREATE POLICY invitations_insert ON workspace_invitations
  FOR INSERT WITH CHECK (is_workspace_admin(workspace_id));

DROP POLICY IF EXISTS invitations_delete ON workspace_invitations;
CREATE POLICY invitations_delete ON workspace_invitations
  FOR DELETE USING (is_workspace_admin(workspace_id));

-- ============================================================================
-- PROJECTS
-- ============================================================================

ALTER TABLE projects ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS projects_select ON projects;
CREATE POLICY projects_select ON projects
  FOR SELECT USING (is_workspace_member(workspace_id));

DROP POLICY IF EXISTS projects_insert ON projects;
CREATE POLICY projects_insert ON projects
  FOR INSERT WITH CHECK (is_workspace_member(workspace_id));

DROP POLICY IF EXISTS projects_update ON projects;
CREATE POLICY projects_update ON projects
  FOR UPDATE USING (is_workspace_member(workspace_id));

DROP POLICY IF EXISTS projects_delete ON projects;
CREATE POLICY projects_delete ON projects
  FOR DELETE USING (is_pm_or_admin(workspace_id));

-- ============================================================================
-- PROJECT TEAM MEMBERS
-- ============================================================================

ALTER TABLE project_team_members ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS project_team_select ON project_team_members;
CREATE POLICY project_team_select ON project_team_members
  FOR SELECT USING (
    EXISTS (SELECT 1 FROM projects p WHERE p.id = project_id AND is_workspace_member(p.workspace_id))
  );

DROP POLICY IF EXISTS project_team_insert ON project_team_members;
CREATE POLICY project_team_insert ON project_team_members
  FOR INSERT WITH CHECK (
    EXISTS (SELECT 1 FROM projects p WHERE p.id = project_id AND is_pm_or_admin(p.workspace_id))
  );

DROP POLICY IF EXISTS project_team_delete ON project_team_members;
CREATE POLICY project_team_delete ON project_team_members
  FOR DELETE USING (
    EXISTS (SELECT 1 FROM projects p WHERE p.id = project_id AND is_pm_or_admin(p.workspace_id))
  );

-- ============================================================================
-- TASKS
-- ============================================================================

ALTER TABLE tasks ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS tasks_select ON tasks;
CREATE POLICY tasks_select ON tasks
  FOR SELECT USING (is_workspace_member(workspace_id));

DROP POLICY IF EXISTS tasks_insert ON tasks;
CREATE POLICY tasks_insert ON tasks
  FOR INSERT WITH CHECK (is_workspace_member(workspace_id));

DROP POLICY IF EXISTS tasks_update ON tasks;
CREATE POLICY tasks_update ON tasks
  FOR UPDATE USING (is_workspace_member(workspace_id));

DROP POLICY IF EXISTS tasks_delete ON tasks;
CREATE POLICY tasks_delete ON tasks
  FOR DELETE USING (is_workspace_member(workspace_id));

-- ============================================================================
-- TASK ASSIGNEES
-- ============================================================================

ALTER TABLE task_assignees ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS task_assignees_select ON task_assignees;
CREATE POLICY task_assignees_select ON task_assignees
  FOR SELECT USING (
    EXISTS (SELECT 1 FROM tasks t WHERE t.id = task_id AND is_workspace_member(t.workspace_id))
  );

DROP POLICY IF EXISTS task_assignees_insert ON task_assignees;
CREATE POLICY task_assignees_insert ON task_assignees
  FOR INSERT WITH CHECK (
    EXISTS (SELECT 1 FROM tasks t WHERE t.id = task_id AND is_workspace_member(t.workspace_id))
  );

DROP POLICY IF EXISTS task_assignees_delete ON task_assignees;
CREATE POLICY task_assignees_delete ON task_assignees
  FOR DELETE USING (
    EXISTS (SELECT 1 FROM tasks t WHERE t.id = task_id AND is_workspace_member(t.workspace_id))
  );

-- ============================================================================
-- TASK COMMENTS
-- ============================================================================

ALTER TABLE task_comments ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS task_comments_select ON task_comments;
CREATE POLICY task_comments_select ON task_comments
  FOR SELECT USING (is_workspace_member(workspace_id));

DROP POLICY IF EXISTS task_comments_insert ON task_comments;
CREATE POLICY task_comments_insert ON task_comments
  FOR INSERT WITH CHECK (is_workspace_member(workspace_id) AND sender_id = auth.uid());

DROP POLICY IF EXISTS task_comments_update ON task_comments;
CREATE POLICY task_comments_update ON task_comments
  FOR UPDATE USING (sender_id = auth.uid());

DROP POLICY IF EXISTS task_comments_delete ON task_comments;
CREATE POLICY task_comments_delete ON task_comments
  FOR DELETE USING (sender_id = auth.uid() OR is_workspace_admin(workspace_id));

-- ============================================================================
-- CUSTOMERS
-- ============================================================================

ALTER TABLE customers ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS customers_select ON customers;
CREATE POLICY customers_select ON customers
  FOR SELECT USING (is_workspace_member(workspace_id));

DROP POLICY IF EXISTS customers_insert ON customers;
CREATE POLICY customers_insert ON customers
  FOR INSERT WITH CHECK (is_workspace_member(workspace_id));

DROP POLICY IF EXISTS customers_update ON customers;
CREATE POLICY customers_update ON customers
  FOR UPDATE USING (is_workspace_member(workspace_id));

DROP POLICY IF EXISTS customers_delete ON customers;
CREATE POLICY customers_delete ON customers
  FOR DELETE USING (is_pm_or_admin(workspace_id));

-- ============================================================================
-- CUSTOMER CONTACTS
-- ============================================================================

ALTER TABLE customer_contacts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS customer_contacts_select ON customer_contacts;
CREATE POLICY customer_contacts_select ON customer_contacts
  FOR SELECT USING (
    EXISTS (SELECT 1 FROM customers c WHERE c.id = customer_id AND is_workspace_member(c.workspace_id))
  );

DROP POLICY IF EXISTS customer_contacts_insert ON customer_contacts;
CREATE POLICY customer_contacts_insert ON customer_contacts
  FOR INSERT WITH CHECK (
    EXISTS (SELECT 1 FROM customers c WHERE c.id = customer_id AND is_workspace_member(c.workspace_id))
  );

DROP POLICY IF EXISTS customer_contacts_update ON customer_contacts;
CREATE POLICY customer_contacts_update ON customer_contacts
  FOR UPDATE USING (
    EXISTS (SELECT 1 FROM customers c WHERE c.id = customer_id AND is_workspace_member(c.workspace_id))
  );

DROP POLICY IF EXISTS customer_contacts_delete ON customer_contacts;
CREATE POLICY customer_contacts_delete ON customer_contacts
  FOR DELETE USING (
    EXISTS (SELECT 1 FROM customers c WHERE c.id = customer_id AND is_workspace_member(c.workspace_id))
  );

-- ============================================================================
-- VENDORS
-- ============================================================================

ALTER TABLE vendors ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS vendors_select ON vendors;
CREATE POLICY vendors_select ON vendors
  FOR SELECT USING (is_workspace_member(workspace_id));

DROP POLICY IF EXISTS vendors_insert ON vendors;
CREATE POLICY vendors_insert ON vendors
  FOR INSERT WITH CHECK (is_workspace_member(workspace_id));

DROP POLICY IF EXISTS vendors_update ON vendors;
CREATE POLICY vendors_update ON vendors
  FOR UPDATE USING (is_workspace_member(workspace_id));

DROP POLICY IF EXISTS vendors_delete ON vendors;
CREATE POLICY vendors_delete ON vendors
  FOR DELETE USING (is_pm_or_admin(workspace_id));

-- ============================================================================
-- VENDOR CONTACTS
-- ============================================================================

ALTER TABLE vendor_contacts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS vendor_contacts_select ON vendor_contacts;
CREATE POLICY vendor_contacts_select ON vendor_contacts
  FOR SELECT USING (
    EXISTS (SELECT 1 FROM vendors v WHERE v.id = vendor_id AND is_workspace_member(v.workspace_id))
  );

DROP POLICY IF EXISTS vendor_contacts_insert ON vendor_contacts;
CREATE POLICY vendor_contacts_insert ON vendor_contacts
  FOR INSERT WITH CHECK (
    EXISTS (SELECT 1 FROM vendors v WHERE v.id = vendor_id AND is_workspace_member(v.workspace_id))
  );

DROP POLICY IF EXISTS vendor_contacts_update ON vendor_contacts;
CREATE POLICY vendor_contacts_update ON vendor_contacts
  FOR UPDATE USING (
    EXISTS (SELECT 1 FROM vendors v WHERE v.id = vendor_id AND is_workspace_member(v.workspace_id))
  );

DROP POLICY IF EXISTS vendor_contacts_delete ON vendor_contacts;
CREATE POLICY vendor_contacts_delete ON vendor_contacts
  FOR DELETE USING (
    EXISTS (SELECT 1 FROM vendors v WHERE v.id = vendor_id AND is_workspace_member(v.workspace_id))
  );

-- ============================================================================
-- SKILLS & ASSETS
-- ============================================================================

ALTER TABLE skills ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS skills_select ON skills;
CREATE POLICY skills_select ON skills FOR SELECT USING (is_workspace_member(workspace_id));
DROP POLICY IF EXISTS skills_insert ON skills;
CREATE POLICY skills_insert ON skills FOR INSERT WITH CHECK (is_workspace_member(workspace_id));
DROP POLICY IF EXISTS skills_update ON skills;
CREATE POLICY skills_update ON skills FOR UPDATE USING (is_workspace_member(workspace_id));
DROP POLICY IF EXISTS skills_delete ON skills;
CREATE POLICY skills_delete ON skills FOR DELETE USING (is_pm_or_admin(workspace_id));

ALTER TABLE assets ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS assets_select ON assets;
CREATE POLICY assets_select ON assets FOR SELECT USING (is_workspace_member(workspace_id));
DROP POLICY IF EXISTS assets_insert ON assets;
CREATE POLICY assets_insert ON assets FOR INSERT WITH CHECK (is_workspace_member(workspace_id));
DROP POLICY IF EXISTS assets_update ON assets;
CREATE POLICY assets_update ON assets FOR UPDATE USING (is_workspace_member(workspace_id));
DROP POLICY IF EXISTS assets_delete ON assets;
CREATE POLICY assets_delete ON assets FOR DELETE USING (is_pm_or_admin(workspace_id));

-- ============================================================================
-- PROPERTIES & AREAS (Restoration)
-- ============================================================================

ALTER TABLE properties ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS properties_select ON properties;
CREATE POLICY properties_select ON properties FOR SELECT USING (is_workspace_member(workspace_id));
DROP POLICY IF EXISTS properties_insert ON properties;
CREATE POLICY properties_insert ON properties FOR INSERT WITH CHECK (is_workspace_member(workspace_id));
DROP POLICY IF EXISTS properties_update ON properties;
CREATE POLICY properties_update ON properties FOR UPDATE USING (is_workspace_member(workspace_id));
DROP POLICY IF EXISTS properties_delete ON properties;
CREATE POLICY properties_delete ON properties FOR DELETE USING (is_workspace_member(workspace_id));

ALTER TABLE areas ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS areas_select ON areas;
CREATE POLICY areas_select ON areas FOR SELECT USING (is_workspace_member(workspace_id));
DROP POLICY IF EXISTS areas_insert ON areas;
CREATE POLICY areas_insert ON areas FOR INSERT WITH CHECK (is_workspace_member(workspace_id));
DROP POLICY IF EXISTS areas_update ON areas;
CREATE POLICY areas_update ON areas FOR UPDATE USING (is_workspace_member(workspace_id));
DROP POLICY IF EXISTS areas_delete ON areas;
CREATE POLICY areas_delete ON areas FOR DELETE USING (is_workspace_member(workspace_id));

ALTER TABLE property_contents ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS property_contents_select ON property_contents;
CREATE POLICY property_contents_select ON property_contents FOR SELECT USING (is_workspace_member(workspace_id));
DROP POLICY IF EXISTS property_contents_insert ON property_contents;
CREATE POLICY property_contents_insert ON property_contents FOR INSERT WITH CHECK (is_workspace_member(workspace_id));
DROP POLICY IF EXISTS property_contents_update ON property_contents;
CREATE POLICY property_contents_update ON property_contents FOR UPDATE USING (is_workspace_member(workspace_id));
DROP POLICY IF EXISTS property_contents_delete ON property_contents;
CREATE POLICY property_contents_delete ON property_contents FOR DELETE USING (is_workspace_member(workspace_id));

ALTER TABLE property_notes ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS property_notes_select ON property_notes;
CREATE POLICY property_notes_select ON property_notes FOR SELECT USING (is_workspace_member(workspace_id));
DROP POLICY IF EXISTS property_notes_insert ON property_notes;
CREATE POLICY property_notes_insert ON property_notes FOR INSERT WITH CHECK (is_workspace_member(workspace_id) AND author_id = auth.uid());
DROP POLICY IF EXISTS property_notes_delete ON property_notes;
CREATE POLICY property_notes_delete ON property_notes FOR DELETE USING (author_id = auth.uid());

-- ============================================================================
-- FINANCIAL TABLES
-- ============================================================================

ALTER TABLE cost_categories ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS cost_categories_select ON cost_categories;
CREATE POLICY cost_categories_select ON cost_categories FOR SELECT USING (is_workspace_member(workspace_id));
DROP POLICY IF EXISTS cost_categories_insert ON cost_categories;
CREATE POLICY cost_categories_insert ON cost_categories FOR INSERT WITH CHECK (is_pm_or_admin(workspace_id));
DROP POLICY IF EXISTS cost_categories_update ON cost_categories;
CREATE POLICY cost_categories_update ON cost_categories FOR UPDATE USING (is_pm_or_admin(workspace_id));
DROP POLICY IF EXISTS cost_categories_delete ON cost_categories;
CREATE POLICY cost_categories_delete ON cost_categories FOR DELETE USING (is_workspace_admin(workspace_id));

ALTER TABLE budget_items ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS budget_items_select ON budget_items;
CREATE POLICY budget_items_select ON budget_items FOR SELECT USING (is_workspace_member(workspace_id));
DROP POLICY IF EXISTS budget_items_insert ON budget_items;
CREATE POLICY budget_items_insert ON budget_items FOR INSERT WITH CHECK (is_workspace_member(workspace_id));
DROP POLICY IF EXISTS budget_items_update ON budget_items;
CREATE POLICY budget_items_update ON budget_items FOR UPDATE USING (is_workspace_member(workspace_id));
DROP POLICY IF EXISTS budget_items_delete ON budget_items;
CREATE POLICY budget_items_delete ON budget_items FOR DELETE USING (is_pm_or_admin(workspace_id));

ALTER TABLE budget_templates ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS budget_templates_select ON budget_templates;
CREATE POLICY budget_templates_select ON budget_templates FOR SELECT USING (is_workspace_member(workspace_id));
DROP POLICY IF EXISTS budget_templates_insert ON budget_templates;
CREATE POLICY budget_templates_insert ON budget_templates FOR INSERT WITH CHECK (is_pm_or_admin(workspace_id));
DROP POLICY IF EXISTS budget_templates_update ON budget_templates;
CREATE POLICY budget_templates_update ON budget_templates FOR UPDATE USING (is_pm_or_admin(workspace_id));
DROP POLICY IF EXISTS budget_templates_delete ON budget_templates;
CREATE POLICY budget_templates_delete ON budget_templates FOR DELETE USING (is_workspace_admin(workspace_id));

ALTER TABLE cost_items ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS cost_items_select ON cost_items;
CREATE POLICY cost_items_select ON cost_items FOR SELECT USING (is_workspace_member(workspace_id));
DROP POLICY IF EXISTS cost_items_insert ON cost_items;
CREATE POLICY cost_items_insert ON cost_items FOR INSERT WITH CHECK (is_workspace_member(workspace_id));
DROP POLICY IF EXISTS cost_items_update ON cost_items;
CREATE POLICY cost_items_update ON cost_items FOR UPDATE USING (is_workspace_member(workspace_id));
DROP POLICY IF EXISTS cost_items_delete ON cost_items;
CREATE POLICY cost_items_delete ON cost_items FOR DELETE USING (is_pm_or_admin(workspace_id));

ALTER TABLE invoices ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS invoices_select ON invoices;
CREATE POLICY invoices_select ON invoices FOR SELECT USING (is_workspace_member(workspace_id));
DROP POLICY IF EXISTS invoices_insert ON invoices;
CREATE POLICY invoices_insert ON invoices FOR INSERT WITH CHECK (is_workspace_member(workspace_id));
DROP POLICY IF EXISTS invoices_update ON invoices;
CREATE POLICY invoices_update ON invoices FOR UPDATE USING (is_workspace_member(workspace_id));
DROP POLICY IF EXISTS invoices_delete ON invoices;
CREATE POLICY invoices_delete ON invoices FOR DELETE USING (is_pm_or_admin(workspace_id));

ALTER TABLE bills ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS bills_select ON bills;
CREATE POLICY bills_select ON bills FOR SELECT USING (is_workspace_member(workspace_id));
DROP POLICY IF EXISTS bills_insert ON bills;
CREATE POLICY bills_insert ON bills FOR INSERT WITH CHECK (is_workspace_member(workspace_id));
DROP POLICY IF EXISTS bills_update ON bills;
CREATE POLICY bills_update ON bills FOR UPDATE USING (is_workspace_member(workspace_id));
DROP POLICY IF EXISTS bills_delete ON bills;
CREATE POLICY bills_delete ON bills FOR DELETE USING (is_pm_or_admin(workspace_id));

ALTER TABLE purchase_orders ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS purchase_orders_select ON purchase_orders;
CREATE POLICY purchase_orders_select ON purchase_orders FOR SELECT USING (is_workspace_member(workspace_id));
DROP POLICY IF EXISTS purchase_orders_insert ON purchase_orders;
CREATE POLICY purchase_orders_insert ON purchase_orders FOR INSERT WITH CHECK (is_workspace_member(workspace_id));
DROP POLICY IF EXISTS purchase_orders_update ON purchase_orders;
CREATE POLICY purchase_orders_update ON purchase_orders FOR UPDATE USING (is_workspace_member(workspace_id));
DROP POLICY IF EXISTS purchase_orders_delete ON purchase_orders;
CREATE POLICY purchase_orders_delete ON purchase_orders FOR DELETE USING (is_pm_or_admin(workspace_id));

ALTER TABLE change_orders ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS change_orders_select ON change_orders;
CREATE POLICY change_orders_select ON change_orders FOR SELECT USING (is_workspace_member(workspace_id));
DROP POLICY IF EXISTS change_orders_insert ON change_orders;
CREATE POLICY change_orders_insert ON change_orders FOR INSERT WITH CHECK (is_workspace_member(workspace_id));
DROP POLICY IF EXISTS change_orders_update ON change_orders;
CREATE POLICY change_orders_update ON change_orders FOR UPDATE USING (is_workspace_member(workspace_id));
DROP POLICY IF EXISTS change_orders_delete ON change_orders;
CREATE POLICY change_orders_delete ON change_orders FOR DELETE USING (is_pm_or_admin(workspace_id));

ALTER TABLE bid_requests ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS bid_requests_select ON bid_requests;
CREATE POLICY bid_requests_select ON bid_requests FOR SELECT USING (is_workspace_member(workspace_id));
DROP POLICY IF EXISTS bid_requests_insert ON bid_requests;
CREATE POLICY bid_requests_insert ON bid_requests FOR INSERT WITH CHECK (is_workspace_member(workspace_id));
DROP POLICY IF EXISTS bid_requests_update ON bid_requests;
CREATE POLICY bid_requests_update ON bid_requests FOR UPDATE USING (is_workspace_member(workspace_id));
DROP POLICY IF EXISTS bid_requests_delete ON bid_requests;
CREATE POLICY bid_requests_delete ON bid_requests FOR DELETE USING (is_pm_or_admin(workspace_id));

ALTER TABLE refunds ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS refunds_select ON refunds;
CREATE POLICY refunds_select ON refunds FOR SELECT USING (is_workspace_member(workspace_id));
DROP POLICY IF EXISTS refunds_insert ON refunds;
CREATE POLICY refunds_insert ON refunds FOR INSERT WITH CHECK (is_pm_or_admin(workspace_id));
DROP POLICY IF EXISTS refunds_update ON refunds;
CREATE POLICY refunds_update ON refunds FOR UPDATE USING (is_pm_or_admin(workspace_id));
DROP POLICY IF EXISTS refunds_delete ON refunds;
CREATE POLICY refunds_delete ON refunds FOR DELETE USING (is_workspace_admin(workspace_id));

ALTER TABLE service_agreements ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS service_agreements_select ON service_agreements;
CREATE POLICY service_agreements_select ON service_agreements FOR SELECT USING (is_workspace_member(workspace_id));
DROP POLICY IF EXISTS service_agreements_insert ON service_agreements;
CREATE POLICY service_agreements_insert ON service_agreements FOR INSERT WITH CHECK (is_workspace_member(workspace_id));
DROP POLICY IF EXISTS service_agreements_update ON service_agreements;
CREATE POLICY service_agreements_update ON service_agreements FOR UPDATE USING (is_workspace_member(workspace_id));
DROP POLICY IF EXISTS service_agreements_delete ON service_agreements;
CREATE POLICY service_agreements_delete ON service_agreements FOR DELETE USING (is_pm_or_admin(workspace_id));

-- ============================================================================
-- TIME ENTRIES
-- ============================================================================

ALTER TABLE time_entries ENABLE ROW LEVEL SECURITY;

-- Workers can see their own entries, managers can see all in workspace
DROP POLICY IF EXISTS time_entries_select ON time_entries;
CREATE POLICY time_entries_select ON time_entries
  FOR SELECT USING (
    worker_id = auth.uid() OR is_pm_or_admin(workspace_id)
  );

-- Workers can create their own entries
DROP POLICY IF EXISTS time_entries_insert ON time_entries;
CREATE POLICY time_entries_insert ON time_entries
  FOR INSERT WITH CHECK (
    is_workspace_member(workspace_id) AND worker_id = auth.uid()
  );

-- Workers can update draft entries, managers can update any
DROP POLICY IF EXISTS time_entries_update ON time_entries;
CREATE POLICY time_entries_update ON time_entries
  FOR UPDATE USING (
    (worker_id = auth.uid() AND status = 'draft') OR is_pm_or_admin(workspace_id)
  );

DROP POLICY IF EXISTS time_entries_delete ON time_entries;
CREATE POLICY time_entries_delete ON time_entries
  FOR DELETE USING (
    (worker_id = auth.uid() AND status = 'draft') OR is_workspace_admin(workspace_id)
  );

-- ============================================================================
-- DOCUMENTS
-- ============================================================================

ALTER TABLE document_templates ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS document_templates_select ON document_templates;
CREATE POLICY document_templates_select ON document_templates FOR SELECT USING (is_workspace_member(workspace_id));
DROP POLICY IF EXISTS document_templates_insert ON document_templates;
CREATE POLICY document_templates_insert ON document_templates FOR INSERT WITH CHECK (is_pm_or_admin(workspace_id));
DROP POLICY IF EXISTS document_templates_update ON document_templates;
CREATE POLICY document_templates_update ON document_templates FOR UPDATE USING (is_pm_or_admin(workspace_id));
DROP POLICY IF EXISTS document_templates_delete ON document_templates;
CREATE POLICY document_templates_delete ON document_templates FOR DELETE USING (is_workspace_admin(workspace_id));

ALTER TABLE generated_documents ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS generated_documents_select ON generated_documents;
CREATE POLICY generated_documents_select ON generated_documents FOR SELECT USING (is_workspace_member(workspace_id));
DROP POLICY IF EXISTS generated_documents_insert ON generated_documents;
CREATE POLICY generated_documents_insert ON generated_documents FOR INSERT WITH CHECK (is_workspace_member(workspace_id));
DROP POLICY IF EXISTS generated_documents_update ON generated_documents;
CREATE POLICY generated_documents_update ON generated_documents FOR UPDATE USING (is_workspace_member(workspace_id));
DROP POLICY IF EXISTS generated_documents_delete ON generated_documents;
CREATE POLICY generated_documents_delete ON generated_documents FOR DELETE USING (is_pm_or_admin(workspace_id));

ALTER TABLE file_folders ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS file_folders_select ON file_folders;
CREATE POLICY file_folders_select ON file_folders FOR SELECT USING (is_workspace_member(workspace_id));
DROP POLICY IF EXISTS file_folders_insert ON file_folders;
CREATE POLICY file_folders_insert ON file_folders FOR INSERT WITH CHECK (is_workspace_member(workspace_id));
DROP POLICY IF EXISTS file_folders_update ON file_folders;
CREATE POLICY file_folders_update ON file_folders FOR UPDATE USING (is_workspace_member(workspace_id));
DROP POLICY IF EXISTS file_folders_delete ON file_folders;
CREATE POLICY file_folders_delete ON file_folders FOR DELETE USING (is_workspace_member(workspace_id));

ALTER TABLE file_attachments ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS file_attachments_select ON file_attachments;
CREATE POLICY file_attachments_select ON file_attachments FOR SELECT USING (is_workspace_member(workspace_id));
DROP POLICY IF EXISTS file_attachments_insert ON file_attachments;
CREATE POLICY file_attachments_insert ON file_attachments FOR INSERT WITH CHECK (is_workspace_member(workspace_id));
DROP POLICY IF EXISTS file_attachments_update ON file_attachments;
CREATE POLICY file_attachments_update ON file_attachments FOR UPDATE USING (uploaded_by = auth.uid() OR is_pm_or_admin(workspace_id));
DROP POLICY IF EXISTS file_attachments_delete ON file_attachments;
CREATE POLICY file_attachments_delete ON file_attachments FOR DELETE USING (uploaded_by = auth.uid() OR is_pm_or_admin(workspace_id));

-- ============================================================================
-- COMMUNICATION
-- ============================================================================

ALTER TABLE conversations ENABLE ROW LEVEL SECURITY;

-- Users can only see conversations they're part of
DROP POLICY IF EXISTS conversations_select ON conversations;
CREATE POLICY conversations_select ON conversations
  FOR SELECT USING (
    is_workspace_member(workspace_id) AND auth.uid() = ANY(participant_ids)
  );

DROP POLICY IF EXISTS conversations_insert ON conversations;
CREATE POLICY conversations_insert ON conversations
  FOR INSERT WITH CHECK (
    is_workspace_member(workspace_id) AND auth.uid() = ANY(participant_ids)
  );

DROP POLICY IF EXISTS conversations_update ON conversations;
CREATE POLICY conversations_update ON conversations
  FOR UPDATE USING (
    is_workspace_member(workspace_id) AND auth.uid() = ANY(participant_ids)
  );

ALTER TABLE messages ENABLE ROW LEVEL SECURITY;

-- Users can see messages in conversations they're part of
DROP POLICY IF EXISTS messages_select ON messages;
CREATE POLICY messages_select ON messages
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM conversations c
      WHERE c.id = conversation_id
      AND auth.uid() = ANY(c.participant_ids)
    )
  );

DROP POLICY IF EXISTS messages_insert ON messages;
CREATE POLICY messages_insert ON messages
  FOR INSERT WITH CHECK (
    sender_id = auth.uid() AND EXISTS (
      SELECT 1 FROM conversations c
      WHERE c.id = conversation_id
      AND auth.uid() = ANY(c.participant_ids)
    )
  );

-- Only sender can edit their messages
DROP POLICY IF EXISTS messages_update ON messages;
CREATE POLICY messages_update ON messages
  FOR UPDATE USING (sender_id = auth.uid());

DROP POLICY IF EXISTS messages_delete ON messages;
CREATE POLICY messages_delete ON messages
  FOR DELETE USING (sender_id = auth.uid());

-- ============================================================================
-- MISC TABLES
-- ============================================================================

ALTER TABLE maintenance_logs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS maintenance_logs_select ON maintenance_logs;
CREATE POLICY maintenance_logs_select ON maintenance_logs FOR SELECT USING (is_workspace_member(workspace_id));
DROP POLICY IF EXISTS maintenance_logs_insert ON maintenance_logs;
CREATE POLICY maintenance_logs_insert ON maintenance_logs FOR INSERT WITH CHECK (is_workspace_member(workspace_id));
DROP POLICY IF EXISTS maintenance_logs_update ON maintenance_logs;
CREATE POLICY maintenance_logs_update ON maintenance_logs FOR UPDATE USING (is_workspace_member(workspace_id));
DROP POLICY IF EXISTS maintenance_logs_delete ON maintenance_logs;
CREATE POLICY maintenance_logs_delete ON maintenance_logs FOR DELETE USING (is_pm_or_admin(workspace_id));

ALTER TABLE construction_plans ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS construction_plans_select ON construction_plans;
CREATE POLICY construction_plans_select ON construction_plans FOR SELECT USING (is_workspace_member(workspace_id));
DROP POLICY IF EXISTS construction_plans_insert ON construction_plans;
CREATE POLICY construction_plans_insert ON construction_plans FOR INSERT WITH CHECK (is_workspace_member(workspace_id));
DROP POLICY IF EXISTS construction_plans_update ON construction_plans;
CREATE POLICY construction_plans_update ON construction_plans FOR UPDATE USING (is_workspace_member(workspace_id));
DROP POLICY IF EXISTS construction_plans_delete ON construction_plans;
CREATE POLICY construction_plans_delete ON construction_plans FOR DELETE USING (is_pm_or_admin(workspace_id));

ALTER TABLE catalog_items ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS catalog_items_select ON catalog_items;
CREATE POLICY catalog_items_select ON catalog_items FOR SELECT USING (is_workspace_member(workspace_id));
DROP POLICY IF EXISTS catalog_items_insert ON catalog_items;
CREATE POLICY catalog_items_insert ON catalog_items FOR INSERT WITH CHECK (is_workspace_member(workspace_id));
DROP POLICY IF EXISTS catalog_items_update ON catalog_items;
CREATE POLICY catalog_items_update ON catalog_items FOR UPDATE USING (is_workspace_member(workspace_id));
DROP POLICY IF EXISTS catalog_items_delete ON catalog_items;
CREATE POLICY catalog_items_delete ON catalog_items FOR DELETE USING (is_pm_or_admin(workspace_id));

ALTER TABLE user_preferences ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS user_preferences_select ON user_preferences;
CREATE POLICY user_preferences_select ON user_preferences FOR SELECT USING (user_id = auth.uid());
DROP POLICY IF EXISTS user_preferences_insert ON user_preferences;
CREATE POLICY user_preferences_insert ON user_preferences FOR INSERT WITH CHECK (user_id = auth.uid());
DROP POLICY IF EXISTS user_preferences_update ON user_preferences;
CREATE POLICY user_preferences_update ON user_preferences FOR UPDATE USING (user_id = auth.uid());

ALTER TABLE counters ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS counters_select ON counters;
CREATE POLICY counters_select ON counters FOR SELECT USING (is_workspace_member(workspace_id));
DROP POLICY IF EXISTS counters_update ON counters;
CREATE POLICY counters_update ON counters FOR UPDATE USING (is_workspace_member(workspace_id));

-- Customer tags
ALTER TABLE customer_tags ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS customer_tags_select ON customer_tags;
CREATE POLICY customer_tags_select ON customer_tags FOR SELECT USING (is_workspace_member(workspace_id));
DROP POLICY IF EXISTS customer_tags_insert ON customer_tags;
CREATE POLICY customer_tags_insert ON customer_tags FOR INSERT WITH CHECK (is_workspace_member(workspace_id));
DROP POLICY IF EXISTS customer_tags_update ON customer_tags;
CREATE POLICY customer_tags_update ON customer_tags FOR UPDATE USING (is_workspace_member(workspace_id));
DROP POLICY IF EXISTS customer_tags_delete ON customer_tags;
CREATE POLICY customer_tags_delete ON customer_tags FOR DELETE USING (is_pm_or_admin(workspace_id));

ALTER TABLE customer_tag_assignments ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS customer_tag_assignments_select ON customer_tag_assignments;
CREATE POLICY customer_tag_assignments_select ON customer_tag_assignments
  FOR SELECT USING (
    EXISTS (SELECT 1 FROM customers c WHERE c.id = customer_id AND is_workspace_member(c.workspace_id))
  );

DROP POLICY IF EXISTS customer_tag_assignments_insert ON customer_tag_assignments;
CREATE POLICY customer_tag_assignments_insert ON customer_tag_assignments
  FOR INSERT WITH CHECK (
    EXISTS (SELECT 1 FROM customers c WHERE c.id = customer_id AND is_workspace_member(c.workspace_id))
  );

DROP POLICY IF EXISTS customer_tag_assignments_delete ON customer_tag_assignments;
CREATE POLICY customer_tag_assignments_delete ON customer_tag_assignments
  FOR DELETE USING (
    EXISTS (SELECT 1 FROM customers c WHERE c.id = customer_id AND is_workspace_member(c.workspace_id))
  );

-- Task junction tables
ALTER TABLE task_required_assets ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS task_required_assets_all ON task_required_assets;
CREATE POLICY task_required_assets_all ON task_required_assets
  FOR ALL USING (
    EXISTS (SELECT 1 FROM tasks t WHERE t.id = task_id AND is_workspace_member(t.workspace_id))
  );

ALTER TABLE task_required_skills ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS task_required_skills_all ON task_required_skills;
CREATE POLICY task_required_skills_all ON task_required_skills
  FOR ALL USING (
    EXISTS (SELECT 1 FROM tasks t WHERE t.id = task_id AND is_workspace_member(t.workspace_id))
  );

ALTER TABLE task_dependencies ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS task_dependencies_all ON task_dependencies;
CREATE POLICY task_dependencies_all ON task_dependencies
  FOR ALL USING (
    EXISTS (SELECT 1 FROM tasks t WHERE t.id = task_id AND is_workspace_member(t.workspace_id))
  );

ALTER TABLE task_progress_history ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS task_progress_history_select ON task_progress_history;
CREATE POLICY task_progress_history_select ON task_progress_history
  FOR SELECT USING (
    EXISTS (SELECT 1 FROM tasks t WHERE t.id = task_id AND is_workspace_member(t.workspace_id))
  );

DROP POLICY IF EXISTS task_progress_history_insert ON task_progress_history;
CREATE POLICY task_progress_history_insert ON task_progress_history
  FOR INSERT WITH CHECK (
    EXISTS (SELECT 1 FROM tasks t WHERE t.id = task_id AND is_workspace_member(t.workspace_id))
  );

-- Client tables (accessed via service role only - for magic links)
ALTER TABLE client_users ENABLE ROW LEVEL SECURITY;
ALTER TABLE client_sessions ENABLE ROW LEVEL SECURITY;
-- No policies = only accessible via service role (edge functions)
