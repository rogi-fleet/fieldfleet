-- R1: workspace-level WIP schedule + cash-flow projection data.
--
-- get_wip_report: one row per project with the classic WIP schedule columns.
--   * estimated_cost / estimated_revenue come from LEAF budget items only
--     (parents are client-side rollups), preferring projected_cost /
--     approved_price and falling back to qty*unit numbers.
--   * cost_to_date intentionally mirrors the in-app budget "Actual" column:
--     cost_items (field-logged costs by category) + APPROVED time entries.
--     Vendor commitments show separately as committed_cost (open POs),
--     standard on WIP schedules — they are not yet incurred cost.
--   * earned_revenue: fixed-price = contract x percent-complete (cost basis);
--     cost-plus = cost + proportional fee; T&M = billed to date.
--   * billed_to_date counts customer invoices (incl. deposits & AIA apps)
--     that left draft, minus credits; collected_to_date sums amount_paid.
--
-- get_cash_flow_entries: raw open-balance rows (inflow = unpaid customer
-- invoices, outflow = unpaid vendor bills) with due dates; the client buckets
-- by week/month. Documents stuck in draft are excluded.
--
-- Both are SECURITY INVOKER: RLS keeps them workspace-scoped.

CREATE OR REPLACE FUNCTION public.get_wip_report(p_workspace_id uuid)
RETURNS TABLE(
  project_id uuid,
  project_name text,
  project_status text,
  price_type text,
  contract_amount numeric,
  estimated_cost numeric,
  estimated_revenue numeric,
  cost_to_date numeric,
  committed_cost numeric,
  percent_complete numeric,
  earned_revenue numeric,
  billed_to_date numeric,
  collected_to_date numeric,
  over_under_billing numeric
)
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
WITH leaf_budget AS (
  SELECT
    bi.project_id,
    SUM(CASE WHEN bi.projected_cost > 0 THEN bi.projected_cost
             ELSE COALESCE(bi.quantity, 1) * COALESCE(bi.unit_cost, 0) END)
      AS estimated_cost,
    SUM(CASE WHEN bi.approved_price > 0 THEN bi.approved_price
             ELSE COALESCE(bi.quantity, 1) * COALESCE(bi.unit_price, 0) END)
      AS estimated_revenue,
    SUM(COALESCE(bi.committed_cost, 0)) AS committed_cost
  FROM budget_items bi
  WHERE bi.workspace_id = p_workspace_id
    AND NOT EXISTS (
      SELECT 1 FROM budget_items c WHERE c.parent_id = bi.id
    )
  GROUP BY bi.project_id
),
field_costs AS (
  SELECT ci.project_id,
         SUM(COALESCE(ci.total_cost, ci.quantity * ci.unit_price, 0)) AS total
  FROM cost_items ci
  WHERE ci.workspace_id = p_workspace_id
  GROUP BY ci.project_id
),
labor_costs AS (
  SELECT te.project_id, SUM(COALESCE(te.total_cost, 0)) AS total
  FROM time_entries te
  WHERE te.workspace_id = p_workspace_id AND te.status = 'approved'
  GROUP BY te.project_id
),
billings AS (
  SELECT
    gd.project_id,
    SUM(CASE WHEN gd.document_type::text = 'credit'
             THEN -COALESCE(gd.total_amount, 0)
             ELSE COALESCE(gd.total_amount, 0) END) AS billed,
    SUM(COALESCE(gd.amount_paid, 0)) AS collected
  FROM generated_documents gd
  WHERE gd.workspace_id = p_workspace_id
    AND gd.document_type::text IN
      ('invoice', 'progress_invoice', 'aia_pay_app', 'deposit', 'credit')
    AND gd.status::text NOT IN
      ('draft', 'denied', 'withdrawn', 'not_selected', 'changes_requested')
  GROUP BY gd.project_id
)
SELECT
  p.id,
  p.name,
  p.status::text,
  p.price_type::text,
  contract.amount,
  COALESCE(lb.estimated_cost, 0),
  COALESCE(lb.estimated_revenue, 0),
  costs.total,
  COALESCE(lb.committed_cost, 0),
  pct.value,
  earned.value,
  COALESCE(b.billed, 0),
  COALESCE(b.collected, 0),
  COALESCE(b.billed, 0) - earned.value
FROM projects p
LEFT JOIN leaf_budget lb ON lb.project_id = p.id
LEFT JOIN field_costs fc ON fc.project_id = p.id
LEFT JOIN labor_costs lc ON lc.project_id = p.id
LEFT JOIN billings b ON b.project_id = p.id
CROSS JOIN LATERAL (
  SELECT COALESCE(fc.total, 0) + COALESCE(lc.total, 0) AS total
) costs
CROSS JOIN LATERAL (
  -- Effective contract: explicit amount, else cost-plus formula over the
  -- estimate, else the estimated revenue from the budget.
  SELECT CASE
    WHEN COALESCE(p.contract_amount, 0) > 0 THEN p.contract_amount
    WHEN p.price_type::text = 'cost_plus'
         AND p.cost_plus_type::text = 'percentage'
      THEN COALESCE(lb.estimated_cost, 0) *
           (1 + COALESCE(p.cost_plus_value, 0) / 100.0)
    WHEN p.price_type::text = 'cost_plus'
         AND p.cost_plus_type::text = 'fixed_fee'
      THEN COALESCE(lb.estimated_cost, 0) + COALESCE(p.cost_plus_value, 0)
    ELSE COALESCE(lb.estimated_revenue, 0)
  END AS amount
) contract
CROSS JOIN LATERAL (
  SELECT CASE
    WHEN COALESCE(lb.estimated_cost, 0) > 0
      THEN LEAST(costs.total / lb.estimated_cost, 1.0)
    ELSE 0
  END AS value
) pct
CROSS JOIN LATERAL (
  SELECT CASE
    WHEN p.price_type::text = 'cost_plus' AND p.cost_plus_type::text = 'percentage'
      THEN costs.total * (1 + COALESCE(p.cost_plus_value, 0) / 100.0)
    WHEN p.price_type::text = 'cost_plus' AND p.cost_plus_type::text = 'fixed_fee'
      THEN costs.total + COALESCE(p.cost_plus_value, 0) * pct.value
    WHEN p.price_type::text = 'time_and_material'
      THEN COALESCE(b.billed, 0)
    ELSE contract.amount * pct.value
  END AS value
) earned
WHERE p.workspace_id = p_workspace_id
ORDER BY p.name;
$$;

REVOKE ALL ON FUNCTION public.get_wip_report(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_wip_report(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_cash_flow_entries(p_workspace_id uuid)
RETURNS TABLE(
  document_id uuid,
  document_number text,
  document_type text,
  direction text,           -- 'inflow' | 'outflow'
  project_id uuid,
  project_name text,
  counterparty text,
  due_date timestamptz,
  balance numeric
)
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
SELECT
  gd.id,
  gd.document_number,
  gd.document_type::text,
  CASE WHEN gd.document_type::text = 'bill' THEN 'outflow' ELSE 'inflow' END,
  gd.project_id,
  p.name,
  CASE WHEN gd.document_type::text = 'bill'
       THEN v.company_name
       ELSE COALESCE(c.company_name, gd.customer_name) END,
  COALESCE(gd.due_date, gd.created_at + INTERVAL '30 days'),
  COALESCE(gd.total_amount, 0) - COALESCE(gd.amount_paid, 0)
FROM generated_documents gd
LEFT JOIN projects p ON p.id = gd.project_id
LEFT JOIN vendors v ON v.id = gd.vendor_id
LEFT JOIN customers c ON c.id = gd.customer_id
WHERE gd.workspace_id = p_workspace_id
  AND gd.document_type::text IN
    ('invoice', 'progress_invoice', 'aia_pay_app', 'deposit', 'bill')
  AND gd.status::text NOT IN
    ('draft', 'denied', 'withdrawn', 'not_selected', 'changes_requested')
  AND gd.paid_date IS NULL
  AND COALESCE(gd.total_amount, 0) - COALESCE(gd.amount_paid, 0) > 0.005
ORDER BY 8;
$$;

REVOKE ALL ON FUNCTION public.get_cash_flow_entries(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_cash_flow_entries(uuid) TO authenticated;
