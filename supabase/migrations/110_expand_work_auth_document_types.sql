-- Expand the single 'work_auth' document_template_type into distinct subtypes
-- so each work-order / work-authorization variant round-trips without data loss.

ALTER TYPE document_template_type ADD VALUE IF NOT EXISTS 'work_auth_emergency';
ALTER TYPE document_template_type ADD VALUE IF NOT EXISTS 'work_auth_restoration';
ALTER TYPE document_template_type ADD VALUE IF NOT EXISTS 'work_auth_services';
ALTER TYPE document_template_type ADD VALUE IF NOT EXISTS 'work_order';
ALTER TYPE document_template_type ADD VALUE IF NOT EXISTS 'work_order_emergency';
ALTER TYPE document_template_type ADD VALUE IF NOT EXISTS 'work_order_maintenance';
