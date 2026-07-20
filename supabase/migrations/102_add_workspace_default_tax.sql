-- Add default tax settings to workspaces
ALTER TABLE workspaces
  ADD COLUMN IF NOT EXISTS default_tax_enabled BOOLEAN DEFAULT TRUE,
  ADD COLUMN IF NOT EXISTS default_tax_name TEXT DEFAULT 'Tax',
  ADD COLUMN IF NOT EXISTS default_tax_rate NUMERIC DEFAULT 0;

-- Add default tax settings to workspace settings profiles
ALTER TABLE workspace_settings_profiles
  ADD COLUMN IF NOT EXISTS default_tax_enabled BOOLEAN DEFAULT TRUE,
  ADD COLUMN IF NOT EXISTS default_tax_name TEXT DEFAULT 'Tax',
  ADD COLUMN IF NOT EXISTS default_tax_rate NUMERIC DEFAULT 0;
