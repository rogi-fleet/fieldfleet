-- Migration: Make customer types and vendor types/categories configurable per workspace
-- Instead of fixed enums, types are stored in lookup tables that users can customize.

-- ============================================================================
-- PART 1: CUSTOMER TYPES
-- ============================================================================

-- 1a. Create the customer_types lookup table
CREATE TABLE IF NOT EXISTS customer_types (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  color TEXT NOT NULL DEFAULT '#4CAF50',
  description TEXT,
  sort_order INTEGER NOT NULL DEFAULT 0,
  is_default BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(workspace_id, name)
);

CREATE INDEX IF NOT EXISTS idx_customer_types_workspace
  ON customer_types(workspace_id, sort_order);

-- Auto-update updated_at trigger (consistent with all other tables)
CREATE OR REPLACE TRIGGER update_customer_types_updated_at
  BEFORE UPDATE ON customer_types
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- RLS: any member can read, only admins can write
ALTER TABLE customer_types ENABLE ROW LEVEL SECURITY;

CREATE POLICY "customer_types_select" ON customer_types
  FOR SELECT USING (
    workspace_id IN (
      SELECT workspace_id FROM workspace_members WHERE user_id = auth.uid()
    )
  );

CREATE POLICY "customer_types_insert" ON customer_types
  FOR INSERT WITH CHECK (is_workspace_admin(workspace_id));

CREATE POLICY "customer_types_update" ON customer_types
  FOR UPDATE USING (is_workspace_admin(workspace_id));

CREATE POLICY "customer_types_delete" ON customer_types
  FOR DELETE USING (is_workspace_admin(workspace_id));

-- 1b. Change customers.customer_type from enum to TEXT
ALTER TABLE customers
  ALTER COLUMN customer_type TYPE TEXT USING customer_type::TEXT;

ALTER TABLE customers
  ALTER COLUMN customer_type SET DEFAULT 'Residential';

-- 1c. Migrate existing enum values to display names
UPDATE customers SET customer_type = 'Residential' WHERE customer_type = 'residential';
UPDATE customers SET customer_type = 'Commercial' WHERE customer_type = 'commercial';
UPDATE customers SET customer_type = 'Government' WHERE customer_type = 'government';

-- 1d. Seed default customer types for all existing workspaces
INSERT INTO customer_types (workspace_id, name, color, description, sort_order, is_default)
SELECT
  w.id, t.name, t.color, t.description, t.sort_order, TRUE
FROM workspaces w
CROSS JOIN (VALUES
  ('Residential',        '#4CAF50', 'Individual homeowners and residential properties', 0),
  ('Commercial',         '#2196F3', 'Businesses, commercial properties, and contractors', 1),
  ('Government',         '#9C27B0', 'Government agencies, schools, and municipal projects', 2),
  ('Industrial',         '#FF9800', 'Factories, warehouses, and manufacturing facilities', 3),
  ('Non-Profit',         '#E91E63', 'Non-profit organizations and charities', 4),
  ('Healthcare',         '#00BCD4', 'Hospitals, clinics, and healthcare facilities', 5),
  ('Educational',        '#3F51B5', 'Schools, universities, and educational institutions', 6),
  ('HOA',                '#8BC34A', 'Homeowners associations and community organizations', 7),
  ('Property Management','#607D8B', 'Property management companies and landlords', 8),
  ('Religious',          '#795548', 'Churches, temples, and religious organizations', 9),
  ('Retail',             '#FF5722', 'Retail stores, shopping centers, and malls', 10),
  ('Hospitality',        '#009688', 'Hotels, restaurants, and hospitality businesses', 11)
) AS t(name, color, description, sort_order)
ON CONFLICT (workspace_id, name) DO NOTHING;

-- 1e. Drop the old enum type
DROP TYPE IF EXISTS customer_type;

-- 1f. Seed function for new workspaces
CREATE OR REPLACE FUNCTION seed_customer_types_for_workspace(p_workspace_id UUID)
RETURNS VOID AS $$
BEGIN
  INSERT INTO customer_types (workspace_id, name, color, description, sort_order, is_default)
  VALUES
    (p_workspace_id, 'Residential',        '#4CAF50', 'Individual homeowners and residential properties', 0, TRUE),
    (p_workspace_id, 'Commercial',         '#2196F3', 'Businesses, commercial properties, and contractors', 1, TRUE),
    (p_workspace_id, 'Government',         '#9C27B0', 'Government agencies, schools, and municipal projects', 2, TRUE),
    (p_workspace_id, 'Industrial',         '#FF9800', 'Factories, warehouses, and manufacturing facilities', 3, TRUE),
    (p_workspace_id, 'Non-Profit',         '#E91E63', 'Non-profit organizations and charities', 4, TRUE),
    (p_workspace_id, 'Healthcare',         '#00BCD4', 'Hospitals, clinics, and healthcare facilities', 5, TRUE),
    (p_workspace_id, 'Educational',        '#3F51B5', 'Schools, universities, and educational institutions', 6, TRUE),
    (p_workspace_id, 'HOA',                '#8BC34A', 'Homeowners associations and community organizations', 7, TRUE),
    (p_workspace_id, 'Property Management','#607D8B', 'Property management companies and landlords', 8, TRUE),
    (p_workspace_id, 'Religious',          '#795548', 'Churches, temples, and religious organizations', 9, TRUE),
    (p_workspace_id, 'Retail',             '#FF5722', 'Retail stores, shopping centers, and malls', 10, TRUE),
    (p_workspace_id, 'Hospitality',        '#009688', 'Hotels, restaurants, and hospitality businesses', 11, TRUE)
  ON CONFLICT (workspace_id, name) DO NOTHING;
END;
$$ LANGUAGE plpgsql;

-- 1g. Atomic update function (renames + updates color/description in one transaction)
CREATE OR REPLACE FUNCTION update_customer_type_full(
  p_workspace_id UUID,
  p_type_id UUID,
  p_old_name TEXT,
  p_new_name TEXT,
  p_color TEXT DEFAULT NULL,
  p_description TEXT DEFAULT NULL
) RETURNS VOID AS $$
BEGIN
  UPDATE customer_types
    SET name = p_new_name,
        color = COALESCE(p_color, color),
        description = COALESCE(p_description, description),
        updated_at = NOW()
    WHERE id = p_type_id AND workspace_id = p_workspace_id;

  IF p_old_name IS DISTINCT FROM p_new_name THEN
    UPDATE customers
      SET customer_type = p_new_name, updated_at = NOW()
      WHERE workspace_id = p_workspace_id AND customer_type = p_old_name;
  END IF;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- PART 2: VENDOR TYPES
-- ============================================================================

-- 2a. Create the vendor_types lookup table
CREATE TABLE IF NOT EXISTS vendor_types (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  color TEXT NOT NULL DEFAULT '#2196F3',
  description TEXT,
  sort_order INTEGER NOT NULL DEFAULT 0,
  is_default BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(workspace_id, name)
);

CREATE INDEX IF NOT EXISTS idx_vendor_types_workspace
  ON vendor_types(workspace_id, sort_order);

CREATE OR REPLACE TRIGGER update_vendor_types_updated_at
  BEFORE UPDATE ON vendor_types
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

ALTER TABLE vendor_types ENABLE ROW LEVEL SECURITY;

CREATE POLICY "vendor_types_select" ON vendor_types
  FOR SELECT USING (
    workspace_id IN (
      SELECT workspace_id FROM workspace_members WHERE user_id = auth.uid()
    )
  );

CREATE POLICY "vendor_types_insert" ON vendor_types
  FOR INSERT WITH CHECK (is_workspace_admin(workspace_id));

CREATE POLICY "vendor_types_update" ON vendor_types
  FOR UPDATE USING (is_workspace_admin(workspace_id));

CREATE POLICY "vendor_types_delete" ON vendor_types
  FOR DELETE USING (is_workspace_admin(workspace_id));

-- 2b. Create the vendor_categories lookup table
CREATE TABLE IF NOT EXISTS vendor_categories (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  color TEXT NOT NULL DEFAULT '#FF9800',
  description TEXT,
  sort_order INTEGER NOT NULL DEFAULT 0,
  is_default BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(workspace_id, name)
);

CREATE INDEX IF NOT EXISTS idx_vendor_categories_workspace
  ON vendor_categories(workspace_id, sort_order);

CREATE OR REPLACE TRIGGER update_vendor_categories_updated_at
  BEFORE UPDATE ON vendor_categories
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

ALTER TABLE vendor_categories ENABLE ROW LEVEL SECURITY;

CREATE POLICY "vendor_categories_select" ON vendor_categories
  FOR SELECT USING (
    workspace_id IN (
      SELECT workspace_id FROM workspace_members WHERE user_id = auth.uid()
    )
  );

CREATE POLICY "vendor_categories_insert" ON vendor_categories
  FOR INSERT WITH CHECK (is_workspace_admin(workspace_id));

CREATE POLICY "vendor_categories_update" ON vendor_categories
  FOR UPDATE USING (is_workspace_admin(workspace_id));

CREATE POLICY "vendor_categories_delete" ON vendor_categories
  FOR DELETE USING (is_workspace_admin(workspace_id));

-- 2c. Change vendors.vendor_type and vendors.category from enum to TEXT
ALTER TABLE vendors
  ALTER COLUMN vendor_type TYPE TEXT USING vendor_type::TEXT;

ALTER TABLE vendors
  ALTER COLUMN vendor_type SET DEFAULT 'Subcontractor';

ALTER TABLE vendors
  ALTER COLUMN category TYPE TEXT USING category::TEXT;

ALTER TABLE vendors
  ALTER COLUMN category SET DEFAULT 'Other';

-- 2d. Migrate existing vendor_type enum values to display names
UPDATE vendors SET vendor_type = 'Material Supplier' WHERE vendor_type = 'materialSupplier' OR vendor_type = 'supplier';
UPDATE vendors SET vendor_type = 'Subcontractor' WHERE vendor_type = 'subcontractor' OR vendor_type = 'contractor';
UPDATE vendors SET vendor_type = 'Equipment Rental' WHERE vendor_type = 'equipmentRental';
UPDATE vendors SET vendor_type = 'Professional Service' WHERE vendor_type = 'professionalService' OR vendor_type = 'service';
UPDATE vendors SET vendor_type = 'Other' WHERE vendor_type = 'other';

-- 2e. Migrate existing category enum values to display names
UPDATE vendors SET category = 'Electrical Supplier' WHERE category = 'electricalSupplier';
UPDATE vendors SET category = 'Plumbing Supplier' WHERE category = 'plumbingSupplier';
UPDATE vendors SET category = 'HVAC Supplier' WHERE category = 'hvacSupplier';
UPDATE vendors SET category = 'Lumber Yard' WHERE category = 'lumberYard';
UPDATE vendors SET category = 'Concrete Supplier' WHERE category = 'concreteSupplier';
UPDATE vendors SET category = 'Roofing Supplier' WHERE category = 'roofingSupplier';
UPDATE vendors SET category = 'Paint Supplier' WHERE category = 'paintSupplier';
UPDATE vendors SET category = 'Flooring Supplier' WHERE category = 'flooringSupplier';
UPDATE vendors SET category = 'Cabinetry' WHERE category = 'cabinetry';
UPDATE vendors SET category = 'Windows' WHERE category = 'windows';
UPDATE vendors SET category = 'Doors' WHERE category = 'doors';
UPDATE vendors SET category = 'Electrical Contractor' WHERE category = 'electricalContractor';
UPDATE vendors SET category = 'Plumbing Contractor' WHERE category = 'plumbingContractor';
UPDATE vendors SET category = 'HVAC Contractor' WHERE category = 'hvacContractor';
UPDATE vendors SET category = 'Framing Contractor' WHERE category = 'framingContractor';
UPDATE vendors SET category = 'Roofing Contractor' WHERE category = 'roofingContractor';
UPDATE vendors SET category = 'Siding Contractor' WHERE category = 'sidingContractor';
UPDATE vendors SET category = 'Drywall' WHERE category = 'drywall';
UPDATE vendors SET category = 'Painting' WHERE category = 'painting';
UPDATE vendors SET category = 'Flooring' WHERE category = 'flooring';
UPDATE vendors SET category = 'Excavation' WHERE category = 'excavation';
UPDATE vendors SET category = 'Concrete' WHERE category = 'concrete';
UPDATE vendors SET category = 'Masonry' WHERE category = 'masonry';
UPDATE vendors SET category = 'Landscaping' WHERE category = 'landscaping';
UPDATE vendors SET category = 'Equipment Rental' WHERE category = 'equipmentRental';
UPDATE vendors SET category = 'Dumpster Rental' WHERE category = 'dumpsterRental';
UPDATE vendors SET category = 'Engineering Services' WHERE category = 'engineeringServices';
UPDATE vendors SET category = 'Architecture' WHERE category = 'architecture';
UPDATE vendors SET category = 'Inspection' WHERE category = 'inspection';
UPDATE vendors SET category = 'Other' WHERE category = 'other';
-- Legacy broad categories → Other (users can recategorize)
UPDATE vendors SET category = 'Other' WHERE category IN ('materials', 'labor', 'equipment', 'services', 'professional');

-- 2f. Seed default vendor types for all existing workspaces
INSERT INTO vendor_types (workspace_id, name, color, description, sort_order, is_default)
SELECT
  w.id, t.name, t.color, t.description, t.sort_order, TRUE
FROM workspaces w
CROSS JOIN (VALUES
  ('Material Supplier',    '#4CAF50', 'Suppliers of building materials and products', 0),
  ('Subcontractor',        '#2196F3', 'Trade subcontractors and labor', 1),
  ('Equipment Rental',     '#FF9800', 'Equipment and tool rental companies', 2),
  ('Professional Service', '#9C27B0', 'Engineering, architecture, and consulting', 3),
  ('Other',                '#607D8B', 'Other vendor types', 4)
) AS t(name, color, description, sort_order)
ON CONFLICT (workspace_id, name) DO NOTHING;

-- 2g. Seed default vendor categories for all existing workspaces
INSERT INTO vendor_categories (workspace_id, name, color, description, sort_order, is_default)
SELECT
  w.id, t.name, t.color, t.description, t.sort_order, TRUE
FROM workspaces w
CROSS JOIN (VALUES
  ('Electrical Supplier',   '#FF9800', 'Electrical parts and materials', 0),
  ('Plumbing Supplier',     '#2196F3', 'Plumbing parts and materials', 1),
  ('HVAC Supplier',         '#00BCD4', 'HVAC parts and equipment', 2),
  ('Lumber Yard',           '#795548', 'Lumber and wood products', 3),
  ('Concrete Supplier',     '#9E9E9E', 'Concrete and masonry materials', 4),
  ('Roofing Supplier',      '#F44336', 'Roofing materials', 5),
  ('Paint Supplier',        '#E91E63', 'Paint and coatings', 6),
  ('Flooring Supplier',     '#8BC34A', 'Flooring materials', 7),
  ('Cabinetry',             '#FF5722', 'Cabinets and millwork', 8),
  ('Windows',               '#03A9F4', 'Windows and glass', 9),
  ('Doors',                 '#673AB7', 'Interior and exterior doors', 10),
  ('Electrical Contractor', '#FFC107', 'Licensed electricians', 11),
  ('Plumbing Contractor',   '#3F51B5', 'Licensed plumbers', 12),
  ('HVAC Contractor',       '#009688', 'HVAC installation and repair', 13),
  ('Framing Contractor',    '#CDDC39', 'Structural framing', 14),
  ('Roofing Contractor',    '#FF7043', 'Roof installation and repair', 15),
  ('Siding Contractor',     '#26C6DA', 'Siding installation', 16),
  ('Drywall',               '#BDBDBD', 'Drywall installation and finishing', 17),
  ('Painting',              '#AB47BC', 'Interior and exterior painting', 18),
  ('Flooring',              '#66BB6A', 'Floor installation', 19),
  ('Excavation',            '#8D6E63', 'Excavation and grading', 20),
  ('Concrete',              '#78909C', 'Concrete work and finishing', 21),
  ('Masonry',               '#A1887F', 'Brick, stone, and block work', 22),
  ('Landscaping',           '#4CAF50', 'Landscape design and maintenance', 23),
  ('Equipment Rental',      '#FF9800', 'Heavy equipment and tool rental', 24),
  ('Dumpster Rental',       '#607D8B', 'Waste removal and dumpsters', 25),
  ('Engineering Services',  '#7E57C2', 'Structural and civil engineering', 26),
  ('Architecture',          '#5C6BC0', 'Architectural design services', 27),
  ('Inspection',            '#EF5350', 'Building and code inspection', 28),
  ('Other',                 '#9E9E9E', 'Other vendor categories', 29)
) AS t(name, color, description, sort_order)
ON CONFLICT (workspace_id, name) DO NOTHING;

-- 2h. Drop old enum types
DROP TYPE IF EXISTS vendor_type;
DROP TYPE IF EXISTS vendor_category;

-- 2i. Seed functions for new workspaces
CREATE OR REPLACE FUNCTION seed_vendor_types_for_workspace(p_workspace_id UUID)
RETURNS VOID AS $$
BEGIN
  INSERT INTO vendor_types (workspace_id, name, color, description, sort_order, is_default)
  VALUES
    (p_workspace_id, 'Material Supplier',    '#4CAF50', 'Suppliers of building materials and products', 0, TRUE),
    (p_workspace_id, 'Subcontractor',        '#2196F3', 'Trade subcontractors and labor', 1, TRUE),
    (p_workspace_id, 'Equipment Rental',     '#FF9800', 'Equipment and tool rental companies', 2, TRUE),
    (p_workspace_id, 'Professional Service', '#9C27B0', 'Engineering, architecture, and consulting', 3, TRUE),
    (p_workspace_id, 'Other',                '#607D8B', 'Other vendor types', 4, TRUE)
  ON CONFLICT (workspace_id, name) DO NOTHING;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION seed_vendor_categories_for_workspace(p_workspace_id UUID)
RETURNS VOID AS $$
BEGIN
  INSERT INTO vendor_categories (workspace_id, name, color, description, sort_order, is_default)
  VALUES
    (p_workspace_id, 'Electrical Supplier',   '#FF9800', 'Electrical parts and materials', 0, TRUE),
    (p_workspace_id, 'Plumbing Supplier',     '#2196F3', 'Plumbing parts and materials', 1, TRUE),
    (p_workspace_id, 'HVAC Supplier',         '#00BCD4', 'HVAC parts and equipment', 2, TRUE),
    (p_workspace_id, 'Lumber Yard',           '#795548', 'Lumber and wood products', 3, TRUE),
    (p_workspace_id, 'Concrete Supplier',     '#9E9E9E', 'Concrete and masonry materials', 4, TRUE),
    (p_workspace_id, 'Roofing Supplier',      '#F44336', 'Roofing materials', 5, TRUE),
    (p_workspace_id, 'Paint Supplier',        '#E91E63', 'Paint and coatings', 6, TRUE),
    (p_workspace_id, 'Flooring Supplier',     '#8BC34A', 'Flooring materials', 7, TRUE),
    (p_workspace_id, 'Cabinetry',             '#FF5722', 'Cabinets and millwork', 8, TRUE),
    (p_workspace_id, 'Windows',               '#03A9F4', 'Windows and glass', 9, TRUE),
    (p_workspace_id, 'Doors',                 '#673AB7', 'Interior and exterior doors', 10, TRUE),
    (p_workspace_id, 'Electrical Contractor', '#FFC107', 'Licensed electricians', 11, TRUE),
    (p_workspace_id, 'Plumbing Contractor',   '#3F51B5', 'Licensed plumbers', 12, TRUE),
    (p_workspace_id, 'HVAC Contractor',       '#009688', 'HVAC installation and repair', 13, TRUE),
    (p_workspace_id, 'Framing Contractor',    '#CDDC39', 'Structural framing', 14, TRUE),
    (p_workspace_id, 'Roofing Contractor',    '#FF7043', 'Roof installation and repair', 15, TRUE),
    (p_workspace_id, 'Siding Contractor',     '#26C6DA', 'Siding installation', 16, TRUE),
    (p_workspace_id, 'Drywall',               '#BDBDBD', 'Drywall installation and finishing', 17, TRUE),
    (p_workspace_id, 'Painting',              '#AB47BC', 'Interior and exterior painting', 18, TRUE),
    (p_workspace_id, 'Flooring',              '#66BB6A', 'Floor installation', 19, TRUE),
    (p_workspace_id, 'Excavation',            '#8D6E63', 'Excavation and grading', 20, TRUE),
    (p_workspace_id, 'Concrete',              '#78909C', 'Concrete work and finishing', 21, TRUE),
    (p_workspace_id, 'Masonry',               '#A1887F', 'Brick, stone, and block work', 22, TRUE),
    (p_workspace_id, 'Landscaping',           '#4CAF50', 'Landscape design and maintenance', 23, TRUE),
    (p_workspace_id, 'Equipment Rental',      '#FF9800', 'Heavy equipment and tool rental', 24, TRUE),
    (p_workspace_id, 'Dumpster Rental',       '#607D8B', 'Waste removal and dumpsters', 25, TRUE),
    (p_workspace_id, 'Engineering Services',  '#7E57C2', 'Structural and civil engineering', 26, TRUE),
    (p_workspace_id, 'Architecture',          '#5C6BC0', 'Architectural design services', 27, TRUE),
    (p_workspace_id, 'Inspection',            '#EF5350', 'Building and code inspection', 28, TRUE),
    (p_workspace_id, 'Other',                 '#9E9E9E', 'Other vendor categories', 29, TRUE)
  ON CONFLICT (workspace_id, name) DO NOTHING;
END;
$$ LANGUAGE plpgsql;

-- 2j. Atomic update functions for vendor types/categories
CREATE OR REPLACE FUNCTION update_vendor_type_full(
  p_workspace_id UUID, p_type_id UUID, p_old_name TEXT, p_new_name TEXT,
  p_color TEXT DEFAULT NULL, p_description TEXT DEFAULT NULL
) RETURNS VOID AS $$
BEGIN
  UPDATE vendor_types
    SET name = p_new_name,
        color = COALESCE(p_color, color),
        description = COALESCE(p_description, description),
        updated_at = NOW()
    WHERE id = p_type_id AND workspace_id = p_workspace_id;
  IF p_old_name IS DISTINCT FROM p_new_name THEN
    UPDATE vendors SET vendor_type = p_new_name, updated_at = NOW()
      WHERE workspace_id = p_workspace_id AND vendor_type = p_old_name;
  END IF;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION update_vendor_category_full(
  p_workspace_id UUID, p_category_id UUID, p_old_name TEXT, p_new_name TEXT,
  p_color TEXT DEFAULT NULL, p_description TEXT DEFAULT NULL
) RETURNS VOID AS $$
BEGIN
  UPDATE vendor_categories
    SET name = p_new_name,
        color = COALESCE(p_color, color),
        description = COALESCE(p_description, description),
        updated_at = NOW()
    WHERE id = p_category_id AND workspace_id = p_workspace_id;
  IF p_old_name IS DISTINCT FROM p_new_name THEN
    UPDATE vendors SET category = p_new_name, updated_at = NOW()
      WHERE workspace_id = p_workspace_id AND category = p_old_name;
  END IF;
END;
$$ LANGUAGE plpgsql;
