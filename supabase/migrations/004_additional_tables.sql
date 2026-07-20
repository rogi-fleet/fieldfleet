-- Additional tables and schema updates for complete Supabase migration
-- This adds missing tables and fields identified during service migration

-- ============================================================================
-- VEHICLES TABLE
-- ============================================================================

DO $$ BEGIN
  CREATE TYPE vehicle_status AS ENUM ('available', 'active', 'maintenance', 'retired');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE TYPE fuel_type AS ENUM ('gasoline', 'diesel', 'electric', 'hybrid', 'other');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE TABLE IF NOT EXISTS vehicles (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  make TEXT,
  model TEXT,
  year INTEGER,
  license_plate TEXT,
  vin TEXT,
  status vehicle_status DEFAULT 'available',
  assigned_to_user_id UUID REFERENCES users(id),
  current_mileage INTEGER,
  fuel_type fuel_type,
  insurance_expiry DATE,
  registration_expiry DATE,
  notes TEXT,
  image_url TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_vehicles_workspace ON vehicles(workspace_id);
CREATE INDEX IF NOT EXISTS idx_vehicles_assigned_user ON vehicles(assigned_to_user_id);
CREATE INDEX IF NOT EXISTS idx_vehicles_status ON vehicles(workspace_id, status);

CREATE OR REPLACE TRIGGER update_vehicles_updated_at
  BEFORE UPDATE ON vehicles
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ============================================================================
-- UPDATE MAINTENANCE_LOGS TABLE
-- Make it work with both assets and vehicles using entity pattern
-- ============================================================================

-- Drop the old foreign key constraint
ALTER TABLE maintenance_logs DROP CONSTRAINT IF EXISTS maintenance_logs_asset_id_fkey;

-- Rename asset_id to entity_id and add entity_type
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'maintenance_logs' AND column_name = 'asset_id'
  ) THEN
    ALTER TABLE maintenance_logs RENAME COLUMN asset_id TO entity_id;
  END IF;
END $$;
ALTER TABLE maintenance_logs ADD COLUMN IF NOT EXISTS entity_type TEXT DEFAULT 'asset';

-- Add more fields for comprehensive maintenance tracking
ALTER TABLE maintenance_logs ADD COLUMN IF NOT EXISTS type TEXT;
ALTER TABLE maintenance_logs ADD COLUMN IF NOT EXISTS cost DECIMAL(10,2);
ALTER TABLE maintenance_logs ADD COLUMN IF NOT EXISTS vendor TEXT;
ALTER TABLE maintenance_logs ADD COLUMN IF NOT EXISTS mileage INTEGER;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'maintenance_logs' AND column_name = 'maintenance_date'
  ) THEN
    ALTER TABLE maintenance_logs RENAME COLUMN maintenance_date TO date;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_maintenance_logs_entity ON maintenance_logs(entity_id, entity_type);

-- ============================================================================
-- FORMS TABLE
-- ============================================================================

CREATE TABLE IF NOT EXISTS forms (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
  project_id UUID REFERENCES projects(id) ON DELETE SET NULL,
  name TEXT NOT NULL,
  description TEXT,
  fields JSONB DEFAULT '[]',
  is_public BOOLEAN DEFAULT FALSE,
  public_slug TEXT UNIQUE,
  created_by UUID REFERENCES users(id),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_forms_workspace ON forms(workspace_id);
CREATE INDEX IF NOT EXISTS idx_forms_project ON forms(project_id);
CREATE INDEX IF NOT EXISTS idx_forms_public_slug ON forms(public_slug) WHERE is_public = TRUE;

CREATE OR REPLACE TRIGGER update_forms_updated_at
  BEFORE UPDATE ON forms
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ============================================================================
-- FORM SUBMISSIONS TABLE
-- ============================================================================

CREATE TABLE IF NOT EXISTS form_submissions (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  form_template_id UUID NOT NULL REFERENCES forms(id) ON DELETE CASCADE,
  workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
  data JSONB NOT NULL DEFAULT '{}',
  submitted_at TIMESTAMPTZ DEFAULT NOW(),
  submitted_by_email TEXT,
  submitted_by_name TEXT,
  ip_address TEXT
);

CREATE INDEX IF NOT EXISTS idx_form_submissions_form ON form_submissions(form_template_id);
CREATE INDEX IF NOT EXISTS idx_form_submissions_workspace ON form_submissions(workspace_id);
CREATE INDEX IF NOT EXISTS idx_form_submissions_date ON form_submissions(submitted_at DESC);

-- ============================================================================
-- WORKSPACE SUBSCRIPTIONS TABLE
-- For tracking Stripe subscription details
-- ============================================================================

CREATE TABLE IF NOT EXISTS workspace_subscriptions (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE UNIQUE,
  tier TEXT DEFAULT 'free',
  status TEXT DEFAULT 'active',
  stripe_customer_id TEXT,
  stripe_subscription_id TEXT,
  current_period_start TIMESTAMPTZ,
  current_period_end TIMESTAMPTZ,
  cancel_at_period_end BOOLEAN DEFAULT FALSE,
  canceled_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_workspace_subscriptions_workspace ON workspace_subscriptions(workspace_id);
CREATE INDEX IF NOT EXISTS idx_workspace_subscriptions_stripe ON workspace_subscriptions(stripe_subscription_id);

CREATE OR REPLACE TRIGGER update_workspace_subscriptions_updated_at
  BEFORE UPDATE ON workspace_subscriptions
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ============================================================================
-- UPDATE CATALOG_ITEMS TABLE
-- Add missing fields from catalog_service
-- ============================================================================

ALTER TABLE catalog_items ADD COLUMN IF NOT EXISTS unit_cost DECIMAL(12,2) DEFAULT 0;
ALTER TABLE catalog_items ADD COLUMN IF NOT EXISTS markup DECIMAL(5,2) DEFAULT 0;
ALTER TABLE catalog_items ADD COLUMN IF NOT EXISTS margin DECIMAL(5,2) DEFAULT 0;
ALTER TABLE catalog_items ADD COLUMN IF NOT EXISTS is_taxable BOOLEAN DEFAULT TRUE;
ALTER TABLE catalog_items ADD COLUMN IF NOT EXISTS cost_type_name TEXT;
ALTER TABLE catalog_items ADD COLUMN IF NOT EXISTS cost_code_name TEXT;
ALTER TABLE catalog_items ADD COLUMN IF NOT EXISTS image_url TEXT;
ALTER TABLE catalog_items ADD COLUMN IF NOT EXISTS sku TEXT;

-- Rename unit_price to match service (it already exists)
-- Add index for SKU lookup
CREATE INDEX IF NOT EXISTS idx_catalog_items_sku ON catalog_items(workspace_id, sku) WHERE sku IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_catalog_items_category ON catalog_items(workspace_id, category) WHERE category IS NOT NULL;

-- ============================================================================
-- UPDATE SERVICE_AGREEMENTS TABLE
-- Add missing fields from agreement_service
-- ============================================================================

ALTER TABLE service_agreements ADD COLUMN IF NOT EXISTS scope TEXT;
ALTER TABLE service_agreements ADD COLUMN IF NOT EXISTS timeline TEXT;
ALTER TABLE service_agreements ADD COLUMN IF NOT EXISTS payment_terms TEXT;
ALTER TABLE service_agreements ADD COLUMN IF NOT EXISTS terms_and_conditions TEXT;
ALTER TABLE service_agreements ADD COLUMN IF NOT EXISTS created_by UUID REFERENCES users(id);
ALTER TABLE service_agreements ADD COLUMN IF NOT EXISTS sent_date TIMESTAMPTZ;
ALTER TABLE service_agreements ADD COLUMN IF NOT EXISTS signed_date TIMESTAMPTZ;
ALTER TABLE service_agreements ADD COLUMN IF NOT EXISTS contractor_signature JSONB;
ALTER TABLE service_agreements ADD COLUMN IF NOT EXISTS client_signature JSONB;
ALTER TABLE service_agreements ADD COLUMN IF NOT EXISTS budget_item_ids UUID[] DEFAULT '{}';
ALTER TABLE service_agreements ADD COLUMN IF NOT EXISTS budget_item_prices JSONB DEFAULT '{}';
ALTER TABLE service_agreements ADD COLUMN IF NOT EXISTS total_amount DECIMAL(12,2) DEFAULT 0;

-- Update status enum to match service
ALTER TYPE agreement_status ADD VALUE IF NOT EXISTS 'sent';
ALTER TYPE agreement_status ADD VALUE IF NOT EXISTS 'signed';

-- ============================================================================
-- PLANS TABLE (construction_plans renamed for service compatibility)
-- ============================================================================

-- Create an alias view for the plans table used by plan_service
CREATE OR REPLACE VIEW plans AS
SELECT
  id,
  workspace_id,
  project_id,
  name,
  discipline,
  sheet_number,
  version,
  is_current_version,
  drawing_date,
  file_url,
  file_name,
  file_size,
  uploaded_by,
  uploaded_at,
  notes,
  linked_task_ids,
  created_at,
  updated_at
FROM construction_plans;

-- ============================================================================
-- MESSAGES TABLE - Add read_by column
-- ============================================================================

ALTER TABLE messages ADD COLUMN IF NOT EXISTS read_by UUID[] DEFAULT '{}';

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'messages' AND column_name = 'created_at'
  ) THEN
    ALTER TABLE messages RENAME COLUMN created_at TO timestamp;
  END IF;
END $$;

-- ============================================================================
-- DOCUMENT COUNTERS
-- For financial document number generation
-- ============================================================================

-- The counters table already exists, just ensure proper structure
-- Add unique constraint for workspace + type combination
CREATE UNIQUE INDEX IF NOT EXISTS idx_counters_workspace_type
  ON counters(workspace_id, counter_type);

-- ============================================================================
-- ANALYTICS EVENTS TABLE (optional)
-- For storing analytics if using Supabase-based analytics
-- ============================================================================

CREATE TABLE IF NOT EXISTS analytics_events (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  event_name TEXT NOT NULL,
  parameters JSONB DEFAULT '{}',
  user_id UUID,
  workspace_id UUID,
  user_role TEXT,
  platform TEXT,
  timestamp TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_analytics_events_timestamp ON analytics_events(timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_analytics_events_name ON analytics_events(event_name);
CREATE INDEX IF NOT EXISTS idx_analytics_events_workspace ON analytics_events(workspace_id) WHERE workspace_id IS NOT NULL;

-- ============================================================================
-- ADD MISSING INDEXES
-- ============================================================================

-- Bills
CREATE INDEX IF NOT EXISTS idx_bills_workspace ON bills(workspace_id);
CREATE INDEX IF NOT EXISTS idx_bills_vendor ON bills(vendor_id);

-- Purchase Orders
CREATE INDEX IF NOT EXISTS idx_purchase_orders_workspace ON purchase_orders(workspace_id);
CREATE INDEX IF NOT EXISTS idx_purchase_orders_vendor ON purchase_orders(vendor_id);

-- Change Orders
CREATE INDEX IF NOT EXISTS idx_change_orders_workspace ON change_orders(workspace_id);
CREATE INDEX IF NOT EXISTS idx_change_orders_project ON change_orders(project_id);

-- Bid Requests
CREATE INDEX IF NOT EXISTS idx_bid_requests_workspace ON bid_requests(workspace_id);
CREATE INDEX IF NOT EXISTS idx_bid_requests_project ON bid_requests(project_id);
CREATE INDEX IF NOT EXISTS idx_bid_requests_vendor ON bid_requests(vendor_id);

-- Refunds
CREATE INDEX IF NOT EXISTS idx_refunds_workspace ON refunds(workspace_id);
CREATE INDEX IF NOT EXISTS idx_refunds_project ON refunds(project_id);

-- Service Agreements
CREATE INDEX IF NOT EXISTS idx_service_agreements_workspace ON service_agreements(workspace_id);
CREATE INDEX IF NOT EXISTS idx_service_agreements_project ON service_agreements(project_id);

-- Document Templates
CREATE INDEX IF NOT EXISTS idx_document_templates_workspace ON document_templates(workspace_id);
CREATE INDEX IF NOT EXISTS idx_document_templates_type ON document_templates(workspace_id, type);

-- Generated Documents
CREATE INDEX IF NOT EXISTS idx_generated_documents_workspace ON generated_documents(workspace_id);
CREATE INDEX IF NOT EXISTS idx_generated_documents_project ON generated_documents(project_id);


-- Cost Items
CREATE INDEX IF NOT EXISTS idx_cost_items_workspace ON cost_items(workspace_id);
CREATE INDEX IF NOT EXISTS idx_cost_items_project ON cost_items(project_id);

-- Budget Templates
CREATE INDEX IF NOT EXISTS idx_budget_templates_workspace ON budget_templates(workspace_id);

-- Catalog Items
CREATE INDEX IF NOT EXISTS idx_catalog_items_workspace ON catalog_items(workspace_id);

-- Customer Tags
CREATE INDEX IF NOT EXISTS idx_customer_tags_workspace ON customer_tags(workspace_id);

-- Skills
CREATE INDEX IF NOT EXISTS idx_skills_workspace ON skills(workspace_id);

-- File Folders
CREATE INDEX IF NOT EXISTS idx_file_folders_workspace ON file_folders(workspace_id);
CREATE INDEX IF NOT EXISTS idx_file_folders_project ON file_folders(project_id);
CREATE INDEX IF NOT EXISTS idx_file_folders_parent ON file_folders(parent_folder_id);
