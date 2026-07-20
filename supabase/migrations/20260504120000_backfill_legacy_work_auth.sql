-- Backfill legacy 'work_auth' document rows to 'work_order'.
--
-- Background: Migration 110 expanded the original single 'work_auth' value in
-- the document_template_type enum into six explicit subtypes (work_auth_*,
-- work_order_*). The old enum value remains valid (PG can't easily drop enum
-- values), and rows created before migration 110 still carry document_type =
-- 'work_auth'. The Dart enum has no member that round-trips to 'work_auth';
-- it relied on a read-side fallback in document_type.dart that mapped
-- 'work_auth' → DocumentType.workOrder, but writing back produced 'work_order'.
--
-- This migration converts those legacy rows so the read-side fallback can be
-- removed and so all document_type values in the DB match a Dart enum member
-- exactly.

UPDATE public.generated_documents
SET document_type = 'work_order'::document_template_type,
    updated_at = NOW()
WHERE document_type::text = 'work_auth';

UPDATE public.document_templates
SET type = 'work_order'::document_template_type,
    updated_at = NOW()
WHERE type::text = 'work_auth';
