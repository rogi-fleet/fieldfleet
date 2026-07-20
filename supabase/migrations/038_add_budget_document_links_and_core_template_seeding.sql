-- Phase 1: normalize generated document <-> budget item relations
-- and seed core default document templates for every workspace.

-- ============================================================================
-- DOCUMENT TEMPLATE DEFAULT SAFETY
-- ============================================================================

WITH ranked_defaults AS (
  SELECT
    id,
    ROW_NUMBER() OVER (
      PARTITION BY workspace_id, type
      ORDER BY updated_at DESC NULLS LAST, created_at DESC NULLS LAST, id DESC
    ) AS rn
  FROM document_templates
  WHERE is_default = TRUE
)
UPDATE document_templates dt
SET is_default = FALSE,
    updated_at = NOW()
FROM ranked_defaults rd
WHERE dt.id = rd.id
  AND rd.rn > 1;

-- Ensure one default template per (workspace, type).
CREATE UNIQUE INDEX IF NOT EXISTS uq_document_templates_workspace_type_default
  ON document_templates(workspace_id, type)
  WHERE is_default = TRUE;

-- ============================================================================
-- CORE TEMPLATE SEED FUNCTION
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

## Pricing
{{#lineItems}}
- {{description}}: ${{amount}}
{{/lineItems}}

**Total:** ${{quote.total}}',
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

## Cost Impact
{{#lineItems}}
- {{description}}: ${{amount}}
{{/lineItems}}

**Total Change:** ${{changeOrder.total}}',
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

{{#lineItems}}
- {{description}}: ${{amount}}
{{/lineItems}}

**Subtotal:** ${{invoice.subtotal}}
**Tax:** ${{invoice.taxAmount}}
**Total:** ${{invoice.total}}',
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

## Progress Billing
{{#lineItems}}
- {{description}}: ${{amount}}
{{/lineItems}}

**Amount Due This Period:** ${{invoice.total}}',
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

{{#lineItems}}
- {{description}}: ${{amount}}
{{/lineItems}}

**Total:** ${{po.total}}',
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

## Requested Pricing
{{#lineItems}}
- {{description}}
{{/lineItems}}',
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

**Total Contract Amount:** ${{agreement.total}}',
      TRUE,
      p_created_by,
      NOW(),
      NOW()
    );
  END IF;
END;
$$;

-- Backfill core defaults for all existing workspaces.
DO $$
DECLARE
  ws RECORD;
BEGIN
  FOR ws IN SELECT id, owner_id FROM workspaces LOOP
    PERFORM seed_core_document_templates(ws.id, ws.owner_id);
  END LOOP;
END $$;

-- ============================================================================
-- NORMALIZED GENERATED DOCUMENT <-> BUDGET ITEM LINKS
-- ============================================================================

DO $$ BEGIN
  CREATE TYPE budget_document_link_source AS ENUM ('manual', 'from_budget_selection');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE TABLE IF NOT EXISTS budget_document_links (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
  project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  generated_document_id UUID NOT NULL REFERENCES generated_documents(id) ON DELETE CASCADE,
  budget_item_id UUID NOT NULL REFERENCES budget_items(id) ON DELETE CASCADE,
  amount DECIMAL(12,2) NOT NULL DEFAULT 0,
  source budget_document_link_source NOT NULL DEFAULT 'from_budget_selection',
  created_by UUID REFERENCES users(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_budget_document_links_doc_item
  ON budget_document_links(generated_document_id, budget_item_id);
CREATE INDEX IF NOT EXISTS idx_budget_document_links_workspace_project_item
  ON budget_document_links(workspace_id, project_id, budget_item_id);
CREATE INDEX IF NOT EXISTS idx_budget_document_links_workspace_project_doc
  ON budget_document_links(workspace_id, project_id, generated_document_id);
CREATE INDEX IF NOT EXISTS idx_budget_document_links_budget_item
  ON budget_document_links(budget_item_id);
CREATE INDEX IF NOT EXISTS idx_budget_document_links_generated_document
  ON budget_document_links(generated_document_id);

ALTER TABLE budget_document_links ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS budget_document_links_select ON budget_document_links;
CREATE POLICY budget_document_links_select ON budget_document_links
  FOR SELECT USING (is_workspace_member(workspace_id));
DROP POLICY IF EXISTS budget_document_links_insert ON budget_document_links;
CREATE POLICY budget_document_links_insert ON budget_document_links
  FOR INSERT WITH CHECK (is_workspace_member(workspace_id));
DROP POLICY IF EXISTS budget_document_links_update ON budget_document_links;
CREATE POLICY budget_document_links_update ON budget_document_links
  FOR UPDATE USING (is_workspace_member(workspace_id));
DROP POLICY IF EXISTS budget_document_links_delete ON budget_document_links;
CREATE POLICY budget_document_links_delete ON budget_document_links
  FOR DELETE USING (is_pm_or_admin(workspace_id));

-- Backfill from legacy generated_documents array + json map fields.
INSERT INTO budget_document_links (
  workspace_id,
  project_id,
  generated_document_id,
  budget_item_id,
  amount,
  source,
  created_by,
  created_at
)
SELECT
  gd.workspace_id,
  COALESCE(gd.project_id, bi.project_id) AS project_id,
  gd.id AS generated_document_id,
  bid.budget_item_id,
  COALESCE(
    NULLIF(gd.budget_item_amounts ->> bid.budget_item_id::TEXT, '')::DECIMAL,
    bi.approved_price,
    0
  ) AS amount,
  'from_budget_selection'::budget_document_link_source AS source,
  gd.created_by,
  COALESCE(gd.created_at, NOW())
FROM generated_documents gd
CROSS JOIN LATERAL unnest(gd.budget_item_ids) AS bid(budget_item_id)
JOIN budget_items bi
  ON bi.id = bid.budget_item_id
 AND bi.workspace_id = gd.workspace_id
WHERE gd.budget_item_ids IS NOT NULL
  AND array_length(gd.budget_item_ids, 1) > 0
ON CONFLICT (generated_document_id, budget_item_id) DO NOTHING;
