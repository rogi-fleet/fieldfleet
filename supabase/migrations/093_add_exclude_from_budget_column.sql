-- Add exclude_from_budget flag to generated_documents
-- When true, the document's line items are excluded from budget rollup calculations
-- This mirrors JobTread's "preliminary" document toggle
ALTER TABLE generated_documents
  ADD COLUMN IF NOT EXISTS exclude_from_budget BOOLEAN NOT NULL DEFAULT FALSE;
