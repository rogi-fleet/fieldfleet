-- Add payment reference number and attachment URL to generated documents
-- for tracking proof of payment (bank transfer IDs, check numbers, receipts, etc.)

ALTER TABLE generated_documents
  ADD COLUMN IF NOT EXISTS payment_reference TEXT,
  ADD COLUMN IF NOT EXISTS payment_attachment_url TEXT;
