-- Add source mode for document line items.
-- snapshot: lock values at creation
-- resync_until_signed: keep non-overridden values in sync until signed

DO $$ BEGIN
  CREATE TYPE line_item_source_mode AS ENUM ('snapshot', 'resync_until_signed');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

ALTER TABLE generated_documents
  ADD COLUMN IF NOT EXISTS line_item_source_mode line_item_source_mode
  DEFAULT 'snapshot';

UPDATE generated_documents
SET line_item_source_mode = 'snapshot'
WHERE line_item_source_mode IS NULL;

ALTER TABLE generated_documents
  ALTER COLUMN line_item_source_mode SET NOT NULL;

CREATE INDEX IF NOT EXISTS idx_generated_documents_line_item_source_mode
  ON generated_documents(workspace_id, line_item_source_mode);
