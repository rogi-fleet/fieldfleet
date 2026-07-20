-- Document statuses for losing / withdrawn bids inside a multi-vendor
-- bid package. Separate from the bid_packages table migration because
-- ALTER TYPE ... ADD VALUE cannot run in the same transaction as DDL
-- that uses the type.

ALTER TYPE document_status ADD VALUE IF NOT EXISTS 'not_selected';
ALTER TYPE document_status ADD VALUE IF NOT EXISTS 'withdrawn';
