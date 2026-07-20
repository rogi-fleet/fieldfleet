-- ============================================================================
-- Vendor Subdivisions: departments/units under vendors, each with an address
-- ============================================================================

CREATE TABLE IF NOT EXISTS vendor_subdivisions (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
  vendor_id UUID NOT NULL REFERENCES vendors(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  address TEXT,
  city TEXT,
  state TEXT,
  zip_code TEXT,
  country TEXT,
  latitude DOUBLE PRECISION,
  longitude DOUBLE PRECISION,
  contact_id UUID REFERENCES vendor_contacts(id) ON DELETE SET NULL,
  access_details TEXT,
  notes TEXT,
  is_active BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes
CREATE INDEX idx_vendor_subdivisions_vendor_id ON vendor_subdivisions(vendor_id);
CREATE INDEX idx_vendor_subdivisions_workspace_id ON vendor_subdivisions(workspace_id);

-- Enable realtime
ALTER PUBLICATION supabase_realtime ADD TABLE vendor_subdivisions;

-- Add vendor_subdivision_id to projects
ALTER TABLE projects ADD COLUMN IF NOT EXISTS vendor_subdivision_id UUID REFERENCES vendor_subdivisions(id) ON DELETE SET NULL;
CREATE INDEX idx_projects_vendor_subdivision_id ON projects(vendor_subdivision_id);

-- ============================================================================
-- RLS Policies
-- ============================================================================

ALTER TABLE vendor_subdivisions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS vendor_subdivisions_select ON vendor_subdivisions;
CREATE POLICY vendor_subdivisions_select ON vendor_subdivisions
  FOR SELECT USING (
    EXISTS (SELECT 1 FROM vendors v WHERE v.id = vendor_id AND is_workspace_member(v.workspace_id))
  );

DROP POLICY IF EXISTS vendor_subdivisions_insert ON vendor_subdivisions;
CREATE POLICY vendor_subdivisions_insert ON vendor_subdivisions
  FOR INSERT WITH CHECK (
    EXISTS (SELECT 1 FROM vendors v WHERE v.id = vendor_id AND is_workspace_member(v.workspace_id))
  );

DROP POLICY IF EXISTS vendor_subdivisions_update ON vendor_subdivisions;
CREATE POLICY vendor_subdivisions_update ON vendor_subdivisions
  FOR UPDATE USING (
    EXISTS (SELECT 1 FROM vendors v WHERE v.id = vendor_id AND is_workspace_member(v.workspace_id))
  );

DROP POLICY IF EXISTS vendor_subdivisions_delete ON vendor_subdivisions;
CREATE POLICY vendor_subdivisions_delete ON vendor_subdivisions
  FOR DELETE USING (
    EXISTS (SELECT 1 FROM vendors v WHERE v.id = vendor_id AND is_workspace_member(v.workspace_id))
  );
