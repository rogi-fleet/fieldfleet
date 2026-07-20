-- Preserve file_events when the parent file_attachment is deleted.
--
-- The original schema used ON DELETE CASCADE so the event rows disappeared
-- with their file. That matches per-file audit timelines (the file is
-- gone, nothing to attach to), but it destroys the forensic "who deleted
-- what and when" trail. Flip to ON DELETE SET NULL: the event row stays,
-- workspace_id remains populated so workspace-level audits see it, and
-- file_attachment_id becomes NULL so the per-file feed simply filters it
-- out naturally via its `.eq('file_attachment_id', X)` query.

ALTER TABLE public.file_events
  DROP CONSTRAINT IF EXISTS file_events_file_attachment_id_fkey;

ALTER TABLE public.file_events
  ALTER COLUMN file_attachment_id DROP NOT NULL;

ALTER TABLE public.file_events
  ADD CONSTRAINT file_events_file_attachment_id_fkey
  FOREIGN KEY (file_attachment_id)
  REFERENCES public.file_attachments(id)
  ON DELETE SET NULL;

COMMENT ON COLUMN public.file_events.file_attachment_id IS
  'Null once the underlying file is deleted — workspace-level audits can '
  'still see the event row; per-file timelines filter these out naturally.';
