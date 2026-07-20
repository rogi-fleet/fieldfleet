-- Add hierarchy columns to catalog_items table
ALTER TABLE catalog_items
ADD COLUMN IF NOT EXISTS parent_id UUID REFERENCES catalog_items(id) ON DELETE CASCADE,
ADD COLUMN IF NOT EXISTS hierarchy_level INT DEFAULT 0 NOT NULL,
ADD COLUMN IF NOT EXISTS item_type TEXT DEFAULT 'item' NOT NULL,
ADD COLUMN IF NOT EXISTS sort_order INT DEFAULT 0 NOT NULL;

-- Create index for faster hierarchy queries
CREATE INDEX IF NOT EXISTS idx_catalog_items_parent_id ON catalog_items(parent_id);
CREATE INDEX IF NOT EXISTS idx_catalog_items_sort_order ON catalog_items(workspace_id, parent_id, sort_order);
