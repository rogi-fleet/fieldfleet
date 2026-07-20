-- The sync_project_custom_field_values trigger fires AFTER INSERT/UPDATE on
-- projects and writes to project_custom_field_values, but that table has
-- INSERT/UPDATE/DELETE revoked from `authenticated`. Without SECURITY DEFINER
-- the trigger runs as the caller and fails with "permission denied for table
-- project_custom_field_values", which surfaces as a 403 on project create.
ALTER FUNCTION public.sync_project_custom_field_values()
  SECURITY DEFINER;
