-- Patch existing "Work Completion Report" default templates so the
-- "follow_up_needed" field only shows when completion_status is not
-- "Fully Complete". Idempotent: skips templates that already have a
-- visibleWhen rule on that field.

UPDATE field_form_templates t
SET fields = (
  SELECT jsonb_agg(
    CASE
      WHEN elem->>'id' = 'follow_up_needed'
      THEN elem || jsonb_build_object(
        'visibleWhen',
        jsonb_build_object(
          'completion_status',
          jsonb_build_array('Partially Complete', 'Requires Follow-Up')
        )
      )
      ELSE elem
    END
    ORDER BY ord
  )
  FROM jsonb_array_elements(t.fields) WITH ORDINALITY AS arr(elem, ord)
)
WHERE t.name = 'Work Completion Report'
  AND t.is_default = TRUE
  AND EXISTS (
    SELECT 1
    FROM jsonb_array_elements(t.fields) e
    WHERE e->>'id' = 'follow_up_needed'
      AND NOT (e ? 'visibleWhen')
  );
