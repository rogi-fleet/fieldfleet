-- Wrap pricing sections in {{#if pricing}} so they only render when the
-- line-items widget is hidden (lineItemVisibility == none).  This removes
-- the duplicate totals that appeared when the widget was visible.

-- ============================================================================
-- 1. UPDATE EXISTING DEFAULT TEMPLATES
-- ============================================================================

-- Quotation
UPDATE document_templates
SET markdown_content = '# Quotation {{quote.number}}

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
    updated_at = NOW()
WHERE is_default = TRUE
  AND type = 'quotation'::document_template_type;

-- Change Order
UPDATE document_templates
SET markdown_content = '# Change Order {{changeOrder.number}}

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
    updated_at = NOW()
WHERE is_default = TRUE
  AND type = 'change_order'::document_template_type;

-- Invoice
UPDATE document_templates
SET markdown_content = '# Invoice {{invoice.number}}

**Project:** {{project.name}}
**Customer:** {{customer.name}}
**Date:** {{date.today}}
**Due Date:** {{invoice.dueDate}}

{{#if pricing}}{{#lineItems}}
- {{description}}: ${{amount}}
{{/lineItems}}

**Subtotal:** ${{invoice.subtotal}}
**Tax:** ${{invoice.taxAmount}}
**Total:** ${{invoice.total}}
{{/if}}',
    updated_at = NOW()
WHERE is_default = TRUE
  AND type = 'invoice'::document_template_type;

-- Progress Invoice
UPDATE document_templates
SET markdown_content = '# Progress Invoice {{invoice.number}}

**Project:** {{project.name}}
**Customer:** {{customer.name}}
**Date:** {{date.today}}

{{#if pricing}}## Progress Billing
{{#lineItems}}
- {{description}}: ${{amount}}
{{/lineItems}}

**Amount Due This Period:** ${{invoice.total}}
{{/if}}',
    updated_at = NOW()
WHERE is_default = TRUE
  AND type = 'progress_invoice'::document_template_type;

-- Purchase Order
UPDATE document_templates
SET markdown_content = '# Purchase Order {{po.number}}

**Project:** {{project.name}}
**Vendor:** {{vendor.name}}
**Date:** {{date.today}}

{{#if pricing}}{{#lineItems}}
- {{description}}: ${{amount}}
{{/lineItems}}

**Total:** ${{po.total}}
{{/if}}',
    updated_at = NOW()
WHERE is_default = TRUE
  AND type = 'purchase_order'::document_template_type;

-- Service Agreement
UPDATE document_templates
SET markdown_content = '# Service Agreement {{agreement.number}}

**Project:** {{project.name}}
**Customer:** {{customer.name}}
**Date:** {{date.today}}

## Scope of Services
{{agreement.scope}}

## Terms
{{agreement.terms}}

{{#if pricing}}**Total Contract Amount:** ${{agreement.total}}
{{/if}}',
    updated_at = NOW()
WHERE is_default = TRUE
  AND type = 'service_agreement'::document_template_type;

-- ============================================================================
-- 2. UPDATE SEED FUNCTION FOR NEW WORKSPACES
-- ============================================================================

CREATE OR REPLACE FUNCTION seed_core_document_templates(
  p_workspace_id UUID,
  p_created_by UUID
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
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
**Customer:** {{customer.name}}
**Date:** {{date.today}}
**Due Date:** {{invoice.dueDate}}

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
**Customer:** {{customer.name}}
**Date:** {{date.today}}

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
END;
$$;
