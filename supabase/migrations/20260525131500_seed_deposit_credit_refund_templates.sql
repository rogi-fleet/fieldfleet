-- The original document-template seeder (migration 038) only seeded
-- quotation, change_order, invoice, progress_invoice, purchase_order,
-- request_for_bid, service_agreement, bill, vendor_credit, expense,
-- and vendor_refund. The workflow buttons Collect Deposit, Credit Note,
-- and Refund / Adjustment all route into _startCreateForType(deposit /
-- credit / refund), which queries the workspace's default template for
-- that type and falls back to a blank generic-create when none exists.
-- That left the buttons feeling dead: the user always landed on
-- a Vendor Bill picker with no idea which template to pick.
--
-- Seed the missing customer-facing templates (deposit, credit, refund)
-- for every existing workspace. We also seed work_auth_services since
-- the Work Authorization workflow button is wired to that typed
-- variant rather than the legacy generic 'work_auth' template.

DO $$
DECLARE
  ws RECORD;
BEGIN
  FOR ws IN SELECT id, owner_id FROM workspaces LOOP
    -- Deposit
    IF NOT EXISTS (
      SELECT 1 FROM document_templates
      WHERE workspace_id = ws.id
        AND type = 'deposit'::document_template_type
        AND is_default = TRUE
    ) THEN
      INSERT INTO document_templates (
        workspace_id, name, type, markdown_content, is_default,
        created_by, created_at, updated_at
      ) VALUES (
        ws.id,
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
        ws.owner_id,
        NOW(),
        NOW()
      );
    END IF;

    -- Credit Note (customer credit)
    IF NOT EXISTS (
      SELECT 1 FROM document_templates
      WHERE workspace_id = ws.id
        AND type = 'credit'::document_template_type
        AND is_default = TRUE
    ) THEN
      INSERT INTO document_templates (
        workspace_id, name, type, markdown_content, is_default,
        created_by, created_at, updated_at
      ) VALUES (
        ws.id,
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
        ws.owner_id,
        NOW(),
        NOW()
      );
    END IF;

    -- Refund (customer refund)
    IF NOT EXISTS (
      SELECT 1 FROM document_templates
      WHERE workspace_id = ws.id
        AND type = 'refund'::document_template_type
        AND is_default = TRUE
    ) THEN
      INSERT INTO document_templates (
        workspace_id, name, type, markdown_content, is_default,
        created_by, created_at, updated_at
      ) VALUES (
        ws.id,
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
        ws.owner_id,
        NOW(),
        NOW()
      );
    END IF;

    -- Work Authorization (Services) — the workflow's Work Authorization
    -- node routes into _startCreateForType(workAuthServices). The catalog
    -- has a generic 'work_auth' template but not the typed services one.
    IF NOT EXISTS (
      SELECT 1 FROM document_templates
      WHERE workspace_id = ws.id
        AND type = 'work_auth_services'::document_template_type
        AND is_default = TRUE
    ) THEN
      INSERT INTO document_templates (
        workspace_id, name, type, markdown_content, is_default,
        created_by, created_at, updated_at
      ) VALUES (
        ws.id,
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
        ws.owner_id,
        NOW(),
        NOW()
      );
    END IF;
  END LOOP;
END $$;
