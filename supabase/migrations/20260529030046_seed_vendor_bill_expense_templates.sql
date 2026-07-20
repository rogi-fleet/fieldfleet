-- Seed the missing Vendor Bill and Expense document templates.
--
-- The Bills and Expenses document flows both expose a
-- "New bill" / "New expense" button that routes to
--   /documents/create?prefer_type=bill   (resp. expense)
-- CreateDocumentScreen then preselects the first template whose type
-- matches the preferred type. Neither `seed_core_document_templates`
-- (run on every new workspace via the create-workspace RPC) nor any of
-- the prior backfill migrations ever seeded a `bill` or `expense`
-- default template — despite the comment in
-- 20260525131500_seed_deposit_credit_refund_templates.sql claiming
-- migration 038 covered them (it did not; 038 only seeded the seven
-- customer-/vendor-order types).
--
-- The result: clicking "New bill" or "New expense" lands the user on a
-- generic Create Document screen with only the Customer Order /
-- Customer Invoice / Vendor Order categories visible and nothing
-- preselected — there is no way to actually create a bill or expense.
--
-- This migration (1) adds the Bill and Expense blocks to
-- seed_core_document_templates so freshly created workspaces get them,
-- and (2) backfills both templates for every existing workspace.
-- Template content mirrors DocumentTemplate.getDefaultTemplate() for
-- DocumentType.bill / DocumentType.expense in the Flutter source.

-- ============================================================================
-- 1. Update the per-workspace seeder used at workspace-creation time.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.seed_core_document_templates(
  p_workspace_id uuid,
  p_created_by uuid
)
RETURNS void
LANGUAGE plpgsql
SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  -- Quotation
  IF NOT EXISTS (
    SELECT 1 FROM document_templates
    WHERE workspace_id = p_workspace_id
      AND type = 'quotation'::document_template_type
      AND is_default = TRUE
  ) THEN
    INSERT INTO document_templates (
      workspace_id, name, type, markdown_content, is_default, created_by, created_at, updated_at
    ) VALUES (
      p_workspace_id,
      'Quotation',
      'quotation'::document_template_type,
      '# Quotation {{quote.number}}

**Project:** {{project.name}}
**Customer:** {{customer.name}}
**Date:** {{date.today}}
**Valid Until:** {{quote.validUntil}}

## Scope
{{quote.description}}

{{#if pricing}}## Pricing
{{#lineItems}}
- {{description}}: ${{amount}}
{{/lineItems}}

**Total:** ${{quote.total}}
{{/if}}',
      TRUE,
      p_created_by,
      NOW(),
      NOW()
    );
  END IF;

  -- Change Order
  IF NOT EXISTS (
    SELECT 1 FROM document_templates
    WHERE workspace_id = p_workspace_id
      AND type = 'change_order'::document_template_type
      AND is_default = TRUE
  ) THEN
    INSERT INTO document_templates (
      workspace_id, name, type, markdown_content, is_default, created_by, created_at, updated_at
    ) VALUES (
      p_workspace_id,
      'Change Order',
      'change_order'::document_template_type,
      '# Change Order {{changeOrder.number}}

**Project:** {{project.name}}
**Customer:** {{customer.name}}
**Date:** {{date.today}}

## Change Description
{{changeOrder.description}}

{{#if pricing}}## Cost Impact
{{#lineItems}}
- {{description}}: ${{amount}}
{{/lineItems}}

**Total Change:** ${{changeOrder.total}}
{{/if}}',
      TRUE,
      p_created_by,
      NOW(),
      NOW()
    );
  END IF;

  -- Invoice
  IF NOT EXISTS (
    SELECT 1 FROM document_templates
    WHERE workspace_id = p_workspace_id
      AND type = 'invoice'::document_template_type
      AND is_default = TRUE
  ) THEN
    INSERT INTO document_templates (
      workspace_id, name, type, markdown_content, is_default, created_by, created_at, updated_at
    ) VALUES (
      p_workspace_id,
      'Invoice',
      'invoice'::document_template_type,
      '# Invoice {{invoice.number}}

**Project:** {{project.name}}
{{#if project.purchaseOrderNumber}}**Purchase Order:** {{project.purchaseOrderNumber}}
{{/if}}
{{#if pricing}}{{#lineItems}}
- {{description}}: ${{amount}}
{{/lineItems}}

**Subtotal:** ${{invoice.subtotal}}
**Tax:** ${{invoice.taxAmount}}
**Total:** ${{invoice.total}}
{{/if}}',
      TRUE,
      p_created_by,
      NOW(),
      NOW()
    );
  END IF;

  -- Progress Invoice
  IF NOT EXISTS (
    SELECT 1 FROM document_templates
    WHERE workspace_id = p_workspace_id
      AND type = 'progress_invoice'::document_template_type
      AND is_default = TRUE
  ) THEN
    INSERT INTO document_templates (
      workspace_id, name, type, markdown_content, is_default, created_by, created_at, updated_at
    ) VALUES (
      p_workspace_id,
      'Progress Invoice',
      'progress_invoice'::document_template_type,
      '# Progress Invoice {{invoice.number}}

**Project:** {{project.name}}
{{#if project.purchaseOrderNumber}}**Purchase Order:** {{project.purchaseOrderNumber}}
{{/if}}
{{#if pricing}}## Progress Billing
{{#lineItems}}
- {{description}}: ${{amount}}
{{/lineItems}}

**Amount Due This Period:** ${{invoice.total}}
{{/if}}',
      TRUE,
      p_created_by,
      NOW(),
      NOW()
    );
  END IF;

  -- Purchase Order
  IF NOT EXISTS (
    SELECT 1 FROM document_templates
    WHERE workspace_id = p_workspace_id
      AND type = 'purchase_order'::document_template_type
      AND is_default = TRUE
  ) THEN
    INSERT INTO document_templates (
      workspace_id, name, type, markdown_content, is_default, created_by, created_at, updated_at
    ) VALUES (
      p_workspace_id,
      'Purchase Order',
      'purchase_order'::document_template_type,
      '# Purchase Order {{po.number}}

**Project:** {{project.name}}
**Vendor:** {{vendor.name}}
**Date:** {{date.today}}

{{#if pricing}}{{#lineItems}}
- {{description}}: ${{amount}}
{{/lineItems}}

**Total:** ${{po.total}}
{{/if}}',
      TRUE,
      p_created_by,
      NOW(),
      NOW()
    );
  END IF;

  -- Request for Bid
  IF NOT EXISTS (
    SELECT 1 FROM document_templates
    WHERE workspace_id = p_workspace_id
      AND type = 'request_for_bid'::document_template_type
      AND is_default = TRUE
  ) THEN
    INSERT INTO document_templates (
      workspace_id, name, type, markdown_content, is_default, created_by, created_at, updated_at
    ) VALUES (
      p_workspace_id,
      'Request for Bid',
      'request_for_bid'::document_template_type,
      '# Request for Bid {{bid.number}}

**Project:** {{project.name}}
**Vendor:** {{vendor.name}}
**Due Date:** {{bid.dueDate}}

## Scope
{{bid.scope}}

{{#if pricing}}## Requested Pricing
{{#lineItems}}
- {{description}}
{{/lineItems}}
{{/if}}',
      TRUE,
      p_created_by,
      NOW(),
      NOW()
    );
  END IF;

  -- Service Agreement
  IF NOT EXISTS (
    SELECT 1 FROM document_templates
    WHERE workspace_id = p_workspace_id
      AND type = 'service_agreement'::document_template_type
      AND is_default = TRUE
  ) THEN
    INSERT INTO document_templates (
      workspace_id, name, type, markdown_content, is_default, created_by, created_at, updated_at
    ) VALUES (
      p_workspace_id,
      'Service Agreement',
      'service_agreement'::document_template_type,
      '# Service Agreement {{agreement.number}}

**Project:** {{project.name}}
**Customer:** {{customer.name}}
**Date:** {{date.today}}

## Scope of Services
{{agreement.scope}}

## Terms
{{agreement.terms}}

{{#if pricing}}**Total Contract Amount:** ${{agreement.total}}
{{/if}}',
      TRUE,
      p_created_by,
      NOW(),
      NOW()
    );
  END IF;

  -- Bill (vendor bill)
  IF NOT EXISTS (
    SELECT 1 FROM document_templates
    WHERE workspace_id = p_workspace_id
      AND type = 'bill'::document_template_type
      AND is_default = TRUE
  ) THEN
    INSERT INTO document_templates (
      workspace_id, name, type, markdown_content, is_default, created_by, created_at, updated_at
    ) VALUES (
      p_workspace_id,
      'Bill',
      'bill'::document_template_type,
      '# Bill {{bill.number}}

---

{{#if pricing}}## Items

| Description | Amount |
|-------------|--------|
{{#lineItems}}
| {{description}} | ${{amount}} |
{{/lineItems}}

---

**Total:** ${{bill.total}}

---

{{/if}}**Payment Status:** {{bill.status}}
',
      TRUE,
      p_created_by,
      NOW(),
      NOW()
    );
  END IF;

  -- Expense (expense report)
  IF NOT EXISTS (
    SELECT 1 FROM document_templates
    WHERE workspace_id = p_workspace_id
      AND type = 'expense'::document_template_type
      AND is_default = TRUE
  ) THEN
    INSERT INTO document_templates (
      workspace_id, name, type, markdown_content, is_default, created_by, created_at, updated_at
    ) VALUES (
      p_workspace_id,
      'Expense',
      'expense'::document_template_type,
      '# Expense Report

**Employee:** {{user.name}}
**{{project_terminology}}:** {{project.name}}

---

{{#if pricing}}## Expenses

| Date | Description | Category | Amount |
|------|-------------|----------|--------|
{{#expenses}}
| {{date}} | {{description}} | {{category}} | ${{amount}} |
{{/expenses}}

---

**Total Expenses:** ${{expense.total}}

---

{{/if}}## Approval

**Submitted By:** {{user.name}}
**Approved By:** ______________________
**Date:** __________
',
      TRUE,
      p_created_by,
      NOW(),
      NOW()
    );
  END IF;
END;
$function$;

-- ============================================================================
-- 2. Backfill Bill + Expense defaults for every existing workspace.
--    seed_core_document_templates is idempotent (each block guards with
--    IF NOT EXISTS), so it is safe to call for every workspace; it will
--    only insert the two newly added types where they are missing.
-- ============================================================================
DO $$
DECLARE
  ws RECORD;
BEGIN
  FOR ws IN SELECT id, owner_id FROM workspaces LOOP
    PERFORM seed_core_document_templates(ws.id, ws.owner_id);
  END LOOP;
END $$;
