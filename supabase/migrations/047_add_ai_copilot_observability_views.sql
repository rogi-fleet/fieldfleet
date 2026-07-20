-- Migration: AI copilot observability views

CREATE OR REPLACE VIEW ai_copilot_daily_metrics AS
SELECT
  workspace_id,
  operation,
  date_trunc('day', created_at) AS day,
  COUNT(*)::BIGINT AS total_requests,
  COUNT(*) FILTER (WHERE status = 'success')::BIGINT AS success_requests,
  COUNT(*) FILTER (WHERE status <> 'success')::BIGINT AS failed_requests,
  ROUND(AVG(latency_ms)::NUMERIC, 2) AS avg_latency_ms,
  ROUND(PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY latency_ms)::NUMERIC, 2) AS p95_latency_ms
FROM ai_copilot_events
GROUP BY workspace_id, operation, date_trunc('day', created_at);

CREATE OR REPLACE VIEW ai_copilot_schedule_apply_metrics AS
SELECT
  workspace_id,
  date_trunc('day', created_at) AS day,
  COUNT(*) FILTER (WHERE operation = 'schedule_optimize')::BIGINT AS suggestion_generations,
  COUNT(*) FILTER (WHERE operation = 'schedule_optimize_apply' AND status = 'approved')::BIGINT AS suggestion_applies,
  CASE
    WHEN COUNT(*) FILTER (WHERE operation = 'schedule_optimize') = 0 THEN 0
    ELSE ROUND(
      (
        COUNT(*) FILTER (WHERE operation = 'schedule_optimize_apply' AND status = 'approved')::NUMERIC
        / COUNT(*) FILTER (WHERE operation = 'schedule_optimize')::NUMERIC
      ) * 100,
      2
    )
  END AS apply_rate_percent
FROM ai_copilot_events
GROUP BY workspace_id, date_trunc('day', created_at);

COMMENT ON VIEW ai_copilot_daily_metrics IS
  'Daily AI copilot reliability and latency metrics by workspace and operation.';

COMMENT ON VIEW ai_copilot_schedule_apply_metrics IS
  'Daily schedule suggestion generation-to-apply conversion metrics by workspace.';
