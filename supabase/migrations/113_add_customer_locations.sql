-- ============================================================================
-- Customer Locations: multi-tier location structure under customers
-- ============================================================================

-- Create customer_locations table
CREATE TABLE IF NOT EXISTS customer_locations (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
  customer_id UUID NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  address TEXT,
  city TEXT,
  state TEXT,
  zip_code TEXT,
  country TEXT,
  latitude DECIMAL,
  longitude DECIMAL,
  contact_id UUID REFERENCES customer_contacts(id) ON DELETE SET NULL,
  access_details TEXT,
  notes TEXT,
  is_active BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes
CREATE INDEX idx_customer_locations_customer_id ON customer_locations(customer_id);
CREATE INDEX idx_customer_locations_workspace_id ON customer_locations(workspace_id);

-- Enable realtime
ALTER PUBLICATION supabase_realtime ADD TABLE customer_locations;

-- Add customer_location_id to projects
ALTER TABLE projects ADD COLUMN IF NOT EXISTS customer_location_id UUID REFERENCES customer_locations(id) ON DELETE SET NULL;
CREATE INDEX idx_projects_customer_location_id ON projects(customer_location_id);

-- ============================================================================
-- RLS Policies for customer_locations
-- ============================================================================

ALTER TABLE customer_locations ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS customer_locations_select ON customer_locations;
CREATE POLICY customer_locations_select ON customer_locations
  FOR SELECT USING (
    EXISTS (SELECT 1 FROM customers c WHERE c.id = customer_id AND is_workspace_member(c.workspace_id))
  );

DROP POLICY IF EXISTS customer_locations_insert ON customer_locations;
CREATE POLICY customer_locations_insert ON customer_locations
  FOR INSERT WITH CHECK (
    EXISTS (SELECT 1 FROM customers c WHERE c.id = customer_id AND is_workspace_member(c.workspace_id))
  );

DROP POLICY IF EXISTS customer_locations_update ON customer_locations;
CREATE POLICY customer_locations_update ON customer_locations
  FOR UPDATE USING (
    EXISTS (SELECT 1 FROM customers c WHERE c.id = customer_id AND is_workspace_member(c.workspace_id))
  );

DROP POLICY IF EXISTS customer_locations_delete ON customer_locations;
CREATE POLICY customer_locations_delete ON customer_locations
  FOR DELETE USING (
    EXISTS (SELECT 1 FROM customers c WHERE c.id = customer_id AND is_workspace_member(c.workspace_id))
  );
