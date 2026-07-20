-- Backfill the new file_tags + file_attachment_tags tables from the legacy
-- file_attachments.tags TEXT[] column.
--
-- Safe to re-run: ON CONFLICT DO NOTHING keeps this idempotent. The legacy
-- TEXT[] column is retained for one release so existing callers that read
-- FileAttachment.tags keep working; it will be dropped in a follow-up
-- migration once everything has moved to resolvedTags.

-- 1. Materialize every distinct (workspace_id, tag_name) currently in use.
WITH distinct_tags AS (
  SELECT DISTINCT
    fa.workspace_id,
    trim(tag.tag_name) AS name
  FROM file_attachments fa
  CROSS JOIN LATERAL unnest(fa.tags) AS tag(tag_name)
  WHERE fa.tags IS NOT NULL
    AND array_length(fa.tags, 1) > 0
    AND trim(tag.tag_name) <> ''
)
INSERT INTO file_tags (workspace_id, name, color)
SELECT workspace_id, name, '#64748B'
FROM distinct_tags
ON CONFLICT (workspace_id, lower(name)) DO NOTHING;

-- 2. Link each file row to the canonical file_tags row via the join table.
--    Join on lower(name) so casing differences all collapse onto the same
--    canonical tag row.
INSERT INTO file_attachment_tags (file_attachment_id, file_tag_id)
SELECT DISTINCT fa.id, ft.id
FROM file_attachments fa
CROSS JOIN LATERAL unnest(fa.tags) AS tag(tag_name)
JOIN file_tags ft
  ON ft.workspace_id = fa.workspace_id
 AND lower(ft.name) = lower(trim(tag.tag_name))
WHERE fa.tags IS NOT NULL
  AND array_length(fa.tags, 1) > 0
  AND trim(tag.tag_name) <> ''
ON CONFLICT (file_attachment_id, file_tag_id) DO NOTHING;
