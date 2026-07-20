-- Add workspace-level workflow templates with core default seeding
CREATE TABLE IF NOT EXISTS workflow_templates (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  slug TEXT NOT NULL,
  description TEXT,
  workflow_markdown TEXT NOT NULL,
  workflow_schema JSONB NOT NULL DEFAULT '{}'::jsonb,
  is_system BOOLEAN NOT NULL DEFAULT FALSE,
  created_by UUID NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT workflow_templates_workspace_slug_unique UNIQUE (workspace_id, slug)
);

CREATE INDEX IF NOT EXISTS idx_workflow_templates_workspace
  ON workflow_templates(workspace_id);

CREATE INDEX IF NOT EXISTS idx_workflow_templates_workspace_system
  ON workflow_templates(workspace_id, is_system);

ALTER TABLE workflow_templates ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS workflow_templates_select ON workflow_templates;
CREATE POLICY workflow_templates_select ON workflow_templates
  FOR SELECT USING (is_workspace_member(workspace_id));

DROP POLICY IF EXISTS workflow_templates_insert ON workflow_templates;
CREATE POLICY workflow_templates_insert ON workflow_templates
  FOR INSERT WITH CHECK (is_workspace_admin(workspace_id));

DROP POLICY IF EXISTS workflow_templates_update ON workflow_templates;
CREATE POLICY workflow_templates_update ON workflow_templates
  FOR UPDATE USING (is_workspace_admin(workspace_id));

DROP POLICY IF EXISTS workflow_templates_delete ON workflow_templates;
CREATE POLICY workflow_templates_delete ON workflow_templates
  FOR DELETE USING (is_workspace_admin(workspace_id));

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'set_workflow_templates_updated_at') THEN
    CREATE TRIGGER set_workflow_templates_updated_at
    BEFORE UPDATE ON workflow_templates
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();
  END IF;
END $$;

CREATE OR REPLACE FUNCTION seed_core_workflow_templates(
  p_workspace_id UUID,
  p_created_by UUID
) RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO workflow_templates (
    workspace_id,
    name,
    slug,
    description,
    workflow_markdown,
    workflow_schema,
    is_system,
    created_by
  ) VALUES
  (
    p_workspace_id,
    'Roof Tarping Emergency Workflow',
    'roof-tarping-emergency',
    'Emergency roof weatherproofing with safety-first sequencing and follow-up checks.',
    $roof$
# Roof Tarping Emergency Workflow (v1.0.0)

## Phase 1: Intake, Authorization & Initial Assessment
- Job setup and intake review
- PM confirms cause of loss, roof type, hazards, weather window, and tarping method
- Authorization and dispatch planning

## Phase 2: Mobilize, Safety & Interior Protection
- Site safety assessment and fall protection setup
- Optional interior leak protection
- Roof access and damage verification

## Phase 3: Tarp Installation & Water Diversion
- Install and secure tarp correctly
- Optional temporary water diversion
- Site reset and client instructions

## Phase 4: Follow-Up Monitoring & Re-Tarp
- Recurring daily follow-up checks
- Re-tarp or reinforce if needed

## Phase 5: Tarp Removal & Permanent Repair Transition
- Verify permanent repair schedule
- Safe tarp removal and final documentation

## Phase 6: Estimating & Billing
- Build estimate and submit file documentation

## Phase 7: Reconstruction Transition
- Handoff to permanent roof repair scope

## Adaptive Rules
- Pre-1990 building -> add asbestos check task
- Roof >=20ft or lift required -> add lift + harness planning tasks
- Nearby power lines -> block until safe clearance
- High wind/severe weather -> block tarp install until safe window
- Flat roof -> add drainage/scupper checks
- Active leak -> force interior protection
- Uninsured -> remove carrier touchpoints and add customer approval tasks
    $roof$,
    '{"version":"1.0.0","job_type":"emergency_restoration","source":"tmp_templates/Roof Tarping Workflow.md"}'::jsonb,
    TRUE,
    p_created_by
  ),
  (
    p_workspace_id,
    'Emergency Board Up Workflow',
    'emergency-board-up',
    'Secure openings after fire, storm, or impact loss to prevent secondary damage.',
    $boardup$
# Emergency Board Up Workflow (Core)

Phases:
1. Intake and dispatch
2. Site safety and opening assessment
3. Board-up installation and temporary weatherproofing
4. Daily integrity checks (as needed)
5. Removal and reconstruction transition
6. Estimate and billing

Rules:
- Unsafe structure -> require stabilization before board-up
- Electrical hazards -> utility clearance required
- Active weather threat -> prioritize weather-facing openings first
    $boardup$,
    '{"version":"1.0.0","job_type":"emergency_restoration","source":"tmp_templates/Emergency Board Up Workflow.md"}'::jsonb,
    TRUE,
    p_created_by
  ),
  (
    p_workspace_id,
    'Water Damage Mitigation Workflow',
    'water-damage-mitigation',
    'Water extraction, drying, monitoring, and mitigation closeout workflow.',
    $water$
# Water Damage Mitigation Workflow (Core)

Phases:
1. FNOL, intake, and authorization
2. Emergency extraction and stabilization
3. Equipment setup (air movers/dehumidifiers)
4. Daily monitoring and moisture logging
5. Mitigation completion and teardown
6. Estimate, documentation, and billing
7. Reconstruction handoff

Rules:
- Category 3 contamination -> force sanitation/PPE containment tasks
- Elevated moisture after target date -> extend monitoring cycle
- Multi-unit loss -> create per-unit tracking tasks
    $water$,
    '{"version":"1.0.0","job_type":"emergency_restoration","source":"tmp_templates/Water Damage Workflow.md"}'::jsonb,
    TRUE,
    p_created_by
  ),
  (
    p_workspace_id,
    'Fire and Smoke Cleaning Workflow',
    'fire-smoke-cleaning',
    'Post-fire cleaning, deodorization, and structural/contents recovery workflow.',
    $fire$
# Fire and Smoke Cleaning Workflow (Core)

Phases:
1. Intake, safety clearance, and authorization
2. Site stabilization and containment
3. Contents triage and cleaning plan
4. Structural smoke/soot cleaning and deodorization
5. QA, re-cleaning, and final walkthrough
6. Estimate and billing
7. Reconstruction transition

Rules:
- Structural instability -> force engineer/stabilization gate
- Hazardous residue detected -> add specialty remediation tasks
- Occupant sensitivity -> force HEPA and IAQ verification tasks
    $fire$,
    '{"version":"1.0.0","job_type":"emergency_restoration","source":"tmp_templates/Fire and Smoke Cleaning Workflow.md"}'::jsonb,
    TRUE,
    p_created_by
  ),
  (
    p_workspace_id,
    'Mould Remediation Workflow',
    'mould-remediation',
    'Containment-led mould remediation with post-remediation verification handoff.',
    $mold$
# Mould Remediation Workflow (Core)

Phases:
1. Intake, assessment, and protocol
2. Containment and PPE setup
3. Removal and cleaning
4. Drying and source correction
5. Post-remediation verification prep
6. Estimate, documentation, and billing
7. Repair/rebuild transition

Rules:
- Occupied property -> sequence containment to maintain safe access
- Positive post-remediation test -> reopen remediation loop
- HVAC involvement -> add duct/system cleaning tasks
    $mold$,
    '{"version":"1.0.0","job_type":"emergency_restoration","source":"tmp_templates/Mould Remediation Workflow.md"}'::jsonb,
    TRUE,
    p_created_by
  )
  ON CONFLICT (workspace_id, slug) DO NOTHING;
END;
$$;

DO $$
DECLARE
  ws RECORD;
BEGIN
  FOR ws IN SELECT id, owner_id FROM workspaces LOOP
    PERFORM seed_core_workflow_templates(ws.id, ws.owner_id);
  END LOOP;
END $$;
