-- Ensure required storage buckets exist in environments where config.toml
-- bucket declarations were not materialized into storage.buckets rows.

INSERT INTO storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
)
VALUES
  (
    'project-files',
    'project-files',
    false,
    104857600,
    ARRAY[
      'image/jpeg',
      'image/png',
      'image/gif',
      'image/webp',
      'image/heic',
      'image/heif',
      'video/mp4',
      'video/quicktime',
      'video/webm',
      'application/pdf',
      'application/msword',
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'application/vnd.ms-excel',
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
    ]::text[]
  ),
  (
    'avatars',
    'avatars',
    true,
    5242880,
    ARRAY[
      'image/jpeg',
      'image/png',
      'image/gif',
      'image/webp'
    ]::text[]
  ),
  (
    'workspace-logos',
    'workspace-logos',
    true,
    5242880,
    ARRAY[
      'image/jpeg',
      'image/png',
      'image/gif',
      'image/webp',
      'image/svg+xml'
    ]::text[]
  ),
  (
    'construction-plans',
    'construction-plans',
    false,
    209715200,
    ARRAY[
      'application/pdf',
      'image/jpeg',
      'image/png',
      'image/tiff'
    ]::text[]
  ),
  (
    'project-images',
    'project-images',
    true,
    52428800,
    ARRAY[
      'image/jpeg',
      'image/png',
      'image/gif',
      'image/webp',
      'image/heic',
      'image/heif'
    ]::text[]
  ),
  (
    'project-documents',
    'project-documents',
    false,
    104857600,
    ARRAY[
      'application/pdf',
      'application/msword',
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'application/vnd.ms-excel',
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
    ]::text[]
  )
ON CONFLICT (id) DO UPDATE
SET
  name = EXCLUDED.name,
  public = EXCLUDED.public,
  file_size_limit = EXCLUDED.file_size_limit,
  allowed_mime_types = EXCLUDED.allowed_mime_types,
  updated_at = now();
