-- Add document status values used by the Request-for-Bid lifecycle.
--
-- `responded`  — vendor has submitted itemized bid prices on the document.
-- `applied`    — the GC has applied the vendor's bid to the project's
--                budget items; terminal state for an RFB.
--
-- These extend document_status without breaking any existing rows; no
-- existing row transitions to either value as part of this migration.

ALTER TYPE document_status ADD VALUE IF NOT EXISTS 'responded';
ALTER TYPE document_status ADD VALUE IF NOT EXISTS 'applied';
