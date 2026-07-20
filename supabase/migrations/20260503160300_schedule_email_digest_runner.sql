-- Schedule the email-digest-runner edge function via pg_cron + pg_net.
--
-- Hourly mode runs at :05 of every hour; daily mode runs at 16:05 UTC
-- (≈ 9 AM Pacific). Both pull from the same email_notification_queue but
-- only consume rows whose digest_mode matches.
--
-- pg_net needs the function URL and service role key to authenticate the
-- POST. We resolve them from database GUCs so the migration is portable
-- across local / staging / prod. After applying this migration, an
-- operator needs to configure the two settings once per environment:
--
--   ALTER DATABASE postgres
--     SET app.settings.supabase_url = 'https://<project>.supabase.co';
--   ALTER DATABASE postgres
--     SET app.settings.service_role_key = '<service-role-jwt>';
--
-- (The cron job will silently no-op until both are set, since
-- public.invoke_email_digest_runner returns early if either is missing.)

CREATE EXTENSION IF NOT EXISTS pg_cron;
CREATE EXTENSION IF NOT EXISTS pg_net;

-- Wrapper SQL function so the cron expression stays simple and we can
-- evolve the pg_net call without rewriting cron entries.
CREATE OR REPLACE FUNCTION public.invoke_email_digest_runner(p_mode TEXT)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  base_url TEXT;
  service_key TEXT;
  request_id BIGINT;
BEGIN
  base_url := NULLIF(current_setting('app.settings.supabase_url', true), '');
  service_key := NULLIF(current_setting('app.settings.service_role_key', true), '');

  IF base_url IS NULL OR service_key IS NULL THEN
    RAISE WARNING 'invoke_email_digest_runner: app.settings.supabase_url / service_role_key not configured; skipping';
    RETURN NULL;
  END IF;

  IF p_mode NOT IN ('hourly', 'daily') THEN
    RAISE EXCEPTION 'Unsupported digest mode: %', p_mode;
  END IF;

  SELECT net.http_post(
    url := base_url || '/functions/v1/email-digest-runner',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || service_key,
      'Content-Type', 'application/json'
    ),
    body := jsonb_build_object('mode', p_mode)
  )
  INTO request_id;

  RETURN request_id;
END;
$$;

REVOKE ALL ON FUNCTION public.invoke_email_digest_runner(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.invoke_email_digest_runner(TEXT) TO service_role;

-- Idempotent re-schedule for both modes.
DO $$
DECLARE
  existing_jobid BIGINT;
BEGIN
  FOR existing_jobid IN
    SELECT jobid FROM cron.job
    WHERE jobname IN ('email_digest_hourly', 'email_digest_daily')
  LOOP
    PERFORM cron.unschedule(existing_jobid);
  END LOOP;
END $$;

-- Hourly: every hour at :05 UTC.
SELECT cron.schedule(
  'email_digest_hourly',
  '5 * * * *',
  $cron$SELECT public.invoke_email_digest_runner('hourly');$cron$
);

-- Daily: 16:05 UTC (~ 9:05 AM Pacific Standard Time, midmorning roll-up).
SELECT cron.schedule(
  'email_digest_daily',
  '5 16 * * *',
  $cron$SELECT public.invoke_email_digest_runner('daily');$cron$
);
