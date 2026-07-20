-- Portal messaging attachments: let portal-authenticated customers upload
-- files into the `project-files` bucket under the conversation subpath
-- (`{workspace_id}/conversations/{conversation_id}/...`), and read every
-- file scoped to a portal-visible conversation they're authorized for.
--
-- The default `project-files` storage policies gate on workspace
-- membership, which excludes portal customers. These two extra policies
-- are OR'd with the defaults and only kick in for paths whose conversation
-- segment maps to a portal-visible thread the calling email is on.

CREATE OR REPLACE FUNCTION public.get_conversation_from_storage_path(path TEXT)
RETURNS UUID
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  parts TEXT[];
BEGIN
  parts := string_to_array(coalesce(path, ''), '/');
  IF array_length(parts, 1) < 4 THEN
    RETURN NULL;
  END IF;
  IF parts[2] <> 'conversations' THEN
    RETURN NULL;
  END IF;
  BEGIN
    RETURN parts[3]::UUID;
  EXCEPTION WHEN OTHERS THEN
    RETURN NULL;
  END;
END;
$$;

REVOKE ALL ON FUNCTION public.get_conversation_from_storage_path(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_conversation_from_storage_path(TEXT) TO authenticated;

DROP POLICY IF EXISTS "Portal customers can upload conversation attachments" ON storage.objects;
CREATE POLICY "Portal customers can upload conversation attachments"
  ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'project-files'
    AND public._portal_can_read_conversation(
      public.get_conversation_from_storage_path(name)
    )
  );

DROP POLICY IF EXISTS "Portal customers can read conversation attachments" ON storage.objects;
CREATE POLICY "Portal customers can read conversation attachments"
  ON storage.objects FOR SELECT TO authenticated
  USING (
    bucket_id = 'project-files'
    AND public._portal_can_read_conversation(
      public.get_conversation_from_storage_path(name)
    )
  );

COMMENT ON FUNCTION public.get_conversation_from_storage_path(TEXT) IS
  'Extracts the conversation UUID from a project-files storage path of shape `{workspace_id}/conversations/{conversation_id}/...`. Returns NULL if the path does not match.';
