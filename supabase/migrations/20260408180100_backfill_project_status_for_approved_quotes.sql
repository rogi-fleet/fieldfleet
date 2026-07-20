-- Backfill: advance projects that already have an approved (or sent/signed)
-- quotation but are still stuck in lead/bidding.
--
-- This is a one-time migration to bring existing data in line with the new
-- trigger added in 20260408180000_auto_advance_project_on_quote_approved.sql.

UPDATE projects
SET status = 'proposal_sent',
    updated_at = NOW()
WHERE status IN ('lead', 'bidding')
  AND id IN (
    SELECT DISTINCT project_id
    FROM generated_documents
    WHERE document_type = 'quotation'
      AND status IN ('approved', 'sent', 'signed')
      AND project_id IS NOT NULL
  );
