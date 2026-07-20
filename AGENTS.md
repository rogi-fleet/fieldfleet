IMPORTANT:
This checkout is the public source-available distribution of FieldFleet,
built by TaskFleet (https://taskfleet.app). Treat it differently from the
private production repository.

## Repository Purpose
- This is the public distribution of FieldFleet: usable, self-hostable, and
  open to contributions under the Elastic License 2.0.
- It is not the production deployment repository.
- Do not add customer data, QA credentials, database/auth dumps, private
  deployment scripts, screenshots containing real data, or local secrets.

## Working Rules
- After a big change, commit it before starting a new change.
- Keep edits scoped and consistent with the existing Flutter/Supabase patterns.
- Do not reintroduce private TaskFleet production domains, credentials, or
  environment-specific host paths. The public marketing site
  `https://taskfleet.app` is fine to link.
- Use placeholders such as `https://api.example.com`,
  `https://app.example.com`, `your-firebase-project-id`, and
  `your-production-supabase-anon-key` in public examples.
- Never commit `.env`, `*.env`, auth-state files, SQL dumps, backup archives,
  Playwright runtime artifacts, or one-off local automation scripts.
- If a change needs a secret, document the environment variable name instead of
  committing a value.

## License And Monetization
- The project is licensed under the Elastic License 2.0 (source-available,
  not OSI open source).
- Keep `LICENSE` and README language aligned: anyone may use, self-host,
  modify, and contribute; offering FieldFleet to third parties as a hosted
  or managed service requires a commercial agreement with TaskFleet.
- Do not change the license to MIT, Apache, GPL, or another open-source license
  unless the owner explicitly requests that.

## Supabase Local Development
- Uses Docker or Podman for local services.
- Start local Supabase with:
  - `supabase start`
  - `supabase migration up --local`
- Verify local services after startup:
  - API gateway: `curl -I http://127.0.0.1:54321`
  - Studio: `curl -I http://127.0.0.1:54323`
- Edge Function secrets belong in local env files only and must not be
  committed.

## Configuration
- Local Flutter defaults point at `http://127.0.0.1:54321`.
- Non-local builds should pass explicit values:
  - `--dart-define=ENV=prod`
  - `--dart-define=SUPABASE_URL=https://api.example.com`
  - `--dart-define=SUPABASE_ANON_KEY=your-anon-key`
  - `--dart-define=SITE_URL=https://app.example.com`
- Optional provider keys such as `OPENROUTER_API_KEY`, `WEATHER_API_KEY`,
  `RESEND_API_KEY`, `STRIPE_SECRET_KEY`, and `STRIPE_WEBHOOK_SECRET` must come
  from environment/secret stores.

## Secret Scanning
Before pushing, run a quick scan for obvious leaks:

```bash
rg -n --hidden \
  -g '!.git/**' \
  -g '!build/**' \
  -g '!.dart_tool/**' \
  "(sk_live_|sk_test_|whsec_|re_[A-Za-z0-9_]{20,}|sk-or-v1-|SERVICE_ROLE|JWT_SECRET|POSTGRES_PASSWORD|PRIVATE KEY)"
```

If possible, also run a dedicated scanner such as Gitleaks before publishing.

## UI Testing
After adding or changing a UI feature, exercise it end-to-end before considering
the work done.

- Prefer a local dev URL for testing this public checkout.
- The portal is a Flutter web app that renders to canvas. Enable semantics once
  per page load by clicking:
  - `document.querySelector('flt-semantics-placeholder').click()`
- Use accessibility refs when available rather than coordinate clicks.
- After major actions, check browser console errors and capture screenshots for
  visual confirmation.
- Test login only with credentials provided in-session; never store them.
