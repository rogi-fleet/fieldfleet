-- Fix permissions for supabase_auth_admin on auth schema.
-- Modern Supabase local stacks often run migrations with a role that is not
-- owner/superuser for auth objects. Keep this migration non-fatal.
DO $$
DECLARE
  table_name text;
BEGIN
  BEGIN
    EXECUTE 'ALTER SCHEMA auth OWNER TO supabase_auth_admin';
  EXCEPTION
    WHEN insufficient_privilege THEN
      RAISE NOTICE 'Skipping ALTER SCHEMA auth OWNER (insufficient_privilege)';
    WHEN invalid_schema_name THEN
      RAISE NOTICE 'Skipping ALTER SCHEMA auth OWNER (schema auth missing)';
  END;

  FOREACH table_name IN ARRAY ARRAY[
    'users',
    'refresh_tokens',
    'instances',
    'audit_log_entries',
    'schema_migrations',
    'identities',
    'sessions',
    'mfa_factors',
    'mfa_challenges',
    'mfa_amr_claims',
    'sso_providers',
    'sso_domains',
    'saml_providers',
    'saml_relay_states',
    'flow_state',
    'one_time_tokens'
  ] LOOP
    BEGIN
      EXECUTE format('ALTER TABLE auth.%I OWNER TO supabase_auth_admin', table_name);
    EXCEPTION
      WHEN insufficient_privilege THEN
        RAISE NOTICE 'Skipping ALTER TABLE auth.% OWNER (insufficient_privilege)', table_name;
      WHEN undefined_table THEN
        RAISE NOTICE 'Skipping ALTER TABLE auth.% OWNER (table missing)', table_name;
    END;
  END LOOP;

  BEGIN
    EXECUTE 'GRANT USAGE ON SCHEMA auth TO supabase_auth_admin';
  EXCEPTION
    WHEN insufficient_privilege THEN
      RAISE NOTICE 'Skipping GRANT USAGE ON SCHEMA auth (insufficient_privilege)';
    WHEN invalid_schema_name THEN
      RAISE NOTICE 'Skipping GRANT USAGE ON SCHEMA auth (schema auth missing)';
  END;

  BEGIN
    EXECUTE 'GRANT ALL ON ALL TABLES IN SCHEMA auth TO supabase_auth_admin';
  EXCEPTION
    WHEN insufficient_privilege THEN
      RAISE NOTICE 'Skipping GRANT on auth tables (insufficient_privilege)';
    WHEN invalid_schema_name THEN
      RAISE NOTICE 'Skipping GRANT on auth tables (schema auth missing)';
  END;

  BEGIN
    EXECUTE 'GRANT ALL ON ALL SEQUENCES IN SCHEMA auth TO supabase_auth_admin';
  EXCEPTION
    WHEN insufficient_privilege THEN
      RAISE NOTICE 'Skipping GRANT on auth sequences (insufficient_privilege)';
    WHEN invalid_schema_name THEN
      RAISE NOTICE 'Skipping GRANT on auth sequences (schema auth missing)';
  END;
END $$;

-- Add missing column required by GoTrue, but do not fail local boot if role cannot alter auth table.
DO $$
BEGIN
  BEGIN
    ALTER TABLE auth.flow_state ADD COLUMN IF NOT EXISTS email_optional boolean DEFAULT false;
  EXCEPTION
    WHEN insufficient_privilege THEN
      RAISE NOTICE 'Skipping flow_state.email_optional patch (insufficient_privilege)';
    WHEN undefined_table THEN
      RAISE NOTICE 'Skipping flow_state.email_optional patch (table missing)';
    WHEN invalid_schema_name THEN
      RAISE NOTICE 'Skipping flow_state.email_optional patch (schema auth missing)';
  END;
END $$;
