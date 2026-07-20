-- Make seed_core_document_templates cover every document type that has a
-- "New X" / workflow entry point in the UI, and backfill the stragglers.
--
-- Background: migration 20260525131500 backfilled deposit, credit, refund
-- and work_auth_services templates for the workspaces that existed when it
-- ran, but it never updated seed_core_document_templates — the function the
-- create-workspace RPC calls for brand-new workspaces. So every workspace
-- created after that migration (and before this one) is missing those four
-- templates, leaving the Collect Deposit / Credit Note / Refund / Work
-- Authorization workflow buttons dead (they look up a default template,
-- find none, and silently fall back to a generic Create Document screen).
-- Migration 20260529040000 added bill + expense to the function; this one
-- folds in the remaining four so the seeder is the single source of truth.

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

  -- Deposit (customer deposit request)
  IF NOT EXISTS (
    SELECT 1 FROM document_templates
    WHERE workspace_id = p_workspace_id
      AND type = 'deposit'::document_template_type
      AND is_default = TRUE
  ) THEN
    INSERT INTO document_templates (
      workspace_id, name, type, markdown_content, is_default, created_by, created_at, updated_at
    ) VALUES (
      p_workspace_id,
      'Deposit',
      'deposit'::document_template_type,
      '# Deposit Request {{deposit.number}}

**Project:** {{project.name}}
**Customer:** {{customer.name}}
**Date:** {{date.today}}
**Due Date:** {{deposit.dueDate}}

## Description
{{deposit.description}}

## Amount Due
**Deposit Total:** ${{deposit.total}}

Please remit this deposit to begin work on the project.',
      TRUE,
      p_created_by,
      NOW(),
      NOW()
    );
  END IF;

  -- Credit Note (customer credit)
  IF NOT EXISTS (
    SELECT 1 FROM document_templates
    WHERE workspace_id = p_workspace_id
      AND type = 'credit'::document_template_type
      AND is_default = TRUE
  ) THEN
    INSERT INTO document_templates (
      workspace_id, name, type, markdown_content, is_default, created_by, created_at, updated_at
    ) VALUES (
      p_workspace_id,
      'Credit Note',
      'credit'::document_template_type,
      '# Credit Note {{credit.number}}

**Project:** {{project.name}}
**Customer:** {{customer.name}}
**Date:** {{date.today}}

## Reason
{{credit.description}}

## Credit Items
{{#lineItems}}
- {{description}}: ${{amount}}
{{/lineItems}}

**Credit Total:** ${{credit.total}}

This credit will be applied against a future invoice.',
      TRUE,
      p_created_by,
      NOW(),
      NOW()
    );
  END IF;

  -- Refund (customer refund)
  IF NOT EXISTS (
    SELECT 1 FROM document_templates
    WHERE workspace_id = p_workspace_id
      AND type = 'refund'::document_template_type
      AND is_default = TRUE
  ) THEN
    INSERT INTO document_templates (
      workspace_id, name, type, markdown_content, is_default, created_by, created_at, updated_at
    ) VALUES (
      p_workspace_id,
      'Customer Refund',
      'refund'::document_template_type,
      '# Customer Refund {{refund.number}}

**Project:** {{project.name}}
**Customer:** {{customer.name}}
**Date:** {{date.today}}

## Reason
{{refund.description}}

## Refund Items
{{#lineItems}}
- {{description}}: ${{amount}}
{{/lineItems}}

**Refund Total:** ${{refund.total}}

This refund will be remitted to the customer.',
      TRUE,
      p_created_by,
      NOW(),
      NOW()
    );
  END IF;

  -- Work Authorization (Services)
  IF NOT EXISTS (
    SELECT 1 FROM document_templates
    WHERE workspace_id = p_workspace_id
      AND type = 'work_auth_services'::document_template_type
      AND is_default = TRUE
  ) THEN
    INSERT INTO document_templates (
      workspace_id, name, type, markdown_content, is_default, created_by, created_at, updated_at
    ) VALUES (
      p_workspace_id,
      'Work Authorization',
      'work_auth_services'::document_template_type,
      '# Work Authorization {{workAuth.number}}

**Project:** {{project.name}}
**Customer:** {{customer.name}}
**Date:** {{date.today}}

## Scope of Work
{{workAuth.description}}

## Authorized Items
{{#lineItems}}
- {{description}}: ${{amount}}
{{/lineItems}}

**Authorized Amount:** ${{workAuth.total}}

By signing below, the customer authorizes the contractor to perform
the work described above for the amount stated.

Signature: __________________________  Date: __________',
      TRUE,
      p_created_by,
      NOW(),
      NOW()
    );
  END IF;
END;
$function$;

-- Backfill the newly added types for every existing workspace.
DO $$
DECLARE
  ws RECORD;
BEGIN
  FOR ws IN SELECT id, owner_id FROM workspaces LOOP
    PERFORM seed_core_document_templates(ws.id, ws.owner_id);
  END LOOP;
END $$;
