-- Add shared financial workflow fields to generated_documents.
-- These support the migration of standalone financial models
-- (refunds, bid requests, POs, bills, invoices) into the document system.

-- Vendor linkage (for POs, bills, bid requests)
ALTER TABLE generated_documents
  ADD COLUMN IF NOT EXISTS vendor_id UUID REFERENCES vendors(id);

-- Source document chain (bid request → PO → bill, invoice → refund)
ALTER TABLE generated_documents
  ADD COLUMN IF NOT EXISTS source_document_id UUID REFERENCES generated_documents(id);

-- Payment tracking (for invoices, bills, refunds)
ALTER TABLE generated_documents
  ADD COLUMN IF NOT EXISTS paid_date TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS payment_method TEXT;

-- Document number (e.g. INV-001, PO-042, REF-003)
ALTER TABLE generated_documents
  ADD COLUMN IF NOT EXISTS document_number TEXT;

-- Due date (for invoices, bills, bid requests)
ALTER TABLE generated_documents
  ADD COLUMN IF NOT EXISTS due_date TIMESTAMPTZ;

-- Type-specific metadata (JSONB for fields unique to one document type)
-- Examples: refund reason/transactionId, bid vendor response, retainage fields
ALTER TABLE generated_documents
  ADD COLUMN IF NOT EXISTS metadata JSONB DEFAULT '{}'::jsonb;

-- Index for common queries
CREATE INDEX IF NOT EXISTS idx_generated_documents_vendor_id
  ON generated_documents(vendor_id) WHERE vendor_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_generated_documents_source_document_id
  ON generated_documents(source_document_id) WHERE source_document_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_generated_documents_document_number
  ON generated_documents(workspace_id, document_number) WHERE document_number IS NOT NULL;
