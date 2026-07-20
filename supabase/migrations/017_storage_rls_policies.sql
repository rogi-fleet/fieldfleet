-- ============================================================================
-- STORAGE BUCKET RLS POLICIES
-- Enables authenticated users to access storage buckets based on workspace membership
-- Made idempotent with DROP POLICY IF EXISTS
-- ============================================================================

-- ============================================================================
-- PROJECT-IMAGES BUCKET (public read, authenticated write)
-- ============================================================================

DROP POLICY IF EXISTS "Authenticated users can upload to project-images" ON storage.objects;
CREATE POLICY "Authenticated users can upload to project-images"
  ON storage.objects FOR INSERT
  TO authenticated
  WITH CHECK (
    bucket_id = 'project-images'
    AND public.is_workspace_member(public.get_workspace_from_storage_path(name))
  );

DROP POLICY IF EXISTS "Authenticated users can update their uploads in project-images" ON storage.objects;
CREATE POLICY "Authenticated users can update their uploads in project-images"
  ON storage.objects FOR UPDATE
  TO authenticated
  USING (
    bucket_id = 'project-images'
    AND public.is_workspace_member(public.get_workspace_from_storage_path(name))
  );

DROP POLICY IF EXISTS "Authenticated users can delete from project-images" ON storage.objects;
CREATE POLICY "Authenticated users can delete from project-images"
  ON storage.objects FOR DELETE
  TO authenticated
  USING (
    bucket_id = 'project-images'
    AND public.is_workspace_member(public.get_workspace_from_storage_path(name))
  );

DROP POLICY IF EXISTS "Anyone can view project-images" ON storage.objects;
CREATE POLICY "Anyone can view project-images"
  ON storage.objects FOR SELECT
  TO public
  USING (bucket_id = 'project-images');

-- ============================================================================
-- PROJECT-DOCUMENTS BUCKET (workspace members only)
-- ============================================================================

DROP POLICY IF EXISTS "Workspace members can upload to project-documents" ON storage.objects;
CREATE POLICY "Workspace members can upload to project-documents"
  ON storage.objects FOR INSERT
  TO authenticated
  WITH CHECK (
    bucket_id = 'project-documents'
    AND public.is_workspace_member(public.get_workspace_from_storage_path(name))
  );

DROP POLICY IF EXISTS "Workspace members can view project-documents" ON storage.objects;
CREATE POLICY "Workspace members can view project-documents"
  ON storage.objects FOR SELECT
  TO authenticated
  USING (
    bucket_id = 'project-documents'
    AND public.is_workspace_member(public.get_workspace_from_storage_path(name))
  );

DROP POLICY IF EXISTS "Workspace members can update project-documents" ON storage.objects;
CREATE POLICY "Workspace members can update project-documents"
  ON storage.objects FOR UPDATE
  TO authenticated
  USING (
    bucket_id = 'project-documents'
    AND public.is_workspace_member(public.get_workspace_from_storage_path(name))
  );

DROP POLICY IF EXISTS "Workspace members can delete from project-documents" ON storage.objects;
CREATE POLICY "Workspace members can delete from project-documents"
  ON storage.objects FOR DELETE
  TO authenticated
  USING (
    bucket_id = 'project-documents'
    AND public.is_workspace_member(public.get_workspace_from_storage_path(name))
  );

-- ============================================================================
-- PROJECT-FILES BUCKET (workspace members only)
-- ============================================================================

DROP POLICY IF EXISTS "Workspace members can upload to project-files" ON storage.objects;
CREATE POLICY "Workspace members can upload to project-files"
  ON storage.objects FOR INSERT
  TO authenticated
  WITH CHECK (
    bucket_id = 'project-files'
    AND public.is_workspace_member(public.get_workspace_from_storage_path(name))
  );

DROP POLICY IF EXISTS "Workspace members can view project-files" ON storage.objects;
CREATE POLICY "Workspace members can view project-files"
  ON storage.objects FOR SELECT
  TO authenticated
  USING (
    bucket_id = 'project-files'
    AND public.is_workspace_member(public.get_workspace_from_storage_path(name))
  );

DROP POLICY IF EXISTS "Workspace members can update project-files" ON storage.objects;
CREATE POLICY "Workspace members can update project-files"
  ON storage.objects FOR UPDATE
  TO authenticated
  USING (
    bucket_id = 'project-files'
    AND public.is_workspace_member(public.get_workspace_from_storage_path(name))
  );

DROP POLICY IF EXISTS "Workspace members can delete from project-files" ON storage.objects;
CREATE POLICY "Workspace members can delete from project-files"
  ON storage.objects FOR DELETE
  TO authenticated
  USING (
    bucket_id = 'project-files'
    AND public.is_workspace_member(public.get_workspace_from_storage_path(name))
  );

-- ============================================================================
-- AVATARS BUCKET (public read, owner write)
-- ============================================================================

DROP POLICY IF EXISTS "Authenticated users can upload avatars" ON storage.objects;
CREATE POLICY "Authenticated users can upload avatars"
  ON storage.objects FOR INSERT
  TO authenticated
  WITH CHECK (bucket_id = 'avatars');

DROP POLICY IF EXISTS "Anyone can view avatars" ON storage.objects;
CREATE POLICY "Anyone can view avatars"
  ON storage.objects FOR SELECT
  TO public
  USING (bucket_id = 'avatars');

DROP POLICY IF EXISTS "Users can update their avatars" ON storage.objects;
CREATE POLICY "Users can update their avatars"
  ON storage.objects FOR UPDATE
  TO authenticated
  USING (bucket_id = 'avatars');

DROP POLICY IF EXISTS "Users can delete their avatars" ON storage.objects;
CREATE POLICY "Users can delete their avatars"
  ON storage.objects FOR DELETE
  TO authenticated
  USING (bucket_id = 'avatars');

-- ============================================================================
-- WORKSPACE-LOGOS BUCKET (public read, admin write)
-- ============================================================================

DROP POLICY IF EXISTS "Admins can upload workspace logos" ON storage.objects;
CREATE POLICY "Admins can upload workspace logos"
  ON storage.objects FOR INSERT
  TO authenticated
  WITH CHECK (bucket_id = 'workspace-logos');

DROP POLICY IF EXISTS "Anyone can view workspace logos" ON storage.objects;
CREATE POLICY "Anyone can view workspace logos"
  ON storage.objects FOR SELECT
  TO public
  USING (bucket_id = 'workspace-logos');

DROP POLICY IF EXISTS "Admins can update workspace logos" ON storage.objects;
CREATE POLICY "Admins can update workspace logos"
  ON storage.objects FOR UPDATE
  TO authenticated
  USING (bucket_id = 'workspace-logos');

DROP POLICY IF EXISTS "Admins can delete workspace logos" ON storage.objects;
CREATE POLICY "Admins can delete workspace logos"
  ON storage.objects FOR DELETE
  TO authenticated
  USING (bucket_id = 'workspace-logos');

-- ============================================================================
-- CONSTRUCTION-PLANS BUCKET (workspace members only)
-- ============================================================================

DROP POLICY IF EXISTS "Workspace members can upload to construction-plans" ON storage.objects;
CREATE POLICY "Workspace members can upload to construction-plans"
  ON storage.objects FOR INSERT
  TO authenticated
  WITH CHECK (
    bucket_id = 'construction-plans'
    AND public.is_workspace_member(public.get_workspace_from_storage_path(name))
  );

DROP POLICY IF EXISTS "Workspace members can view construction-plans" ON storage.objects;
CREATE POLICY "Workspace members can view construction-plans"
  ON storage.objects FOR SELECT
  TO authenticated
  USING (
    bucket_id = 'construction-plans'
    AND public.is_workspace_member(public.get_workspace_from_storage_path(name))
  );

DROP POLICY IF EXISTS "Workspace members can update construction-plans" ON storage.objects;
CREATE POLICY "Workspace members can update construction-plans"
  ON storage.objects FOR UPDATE
  TO authenticated
  USING (
    bucket_id = 'construction-plans'
    AND public.is_workspace_member(public.get_workspace_from_storage_path(name))
  );

DROP POLICY IF EXISTS "Workspace members can delete from construction-plans" ON storage.objects;
CREATE POLICY "Workspace members can delete from construction-plans"
  ON storage.objects FOR DELETE
  TO authenticated
  USING (
    bucket_id = 'construction-plans'
    AND public.is_workspace_member(public.get_workspace_from_storage_path(name))
  );
