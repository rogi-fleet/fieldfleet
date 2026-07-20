#!/usr/bin/env bash
set -euo pipefail

# Creates a disposable local-only Supabase Auth user for smoke testing.
# This intentionally refuses non-local Supabase URLs.

SUPABASE_URL="${SUPABASE_URL:-http://127.0.0.1:55321}"
DEMO_EMAIL="${DEMO_EMAIL:-demo@fieldfleet.local}"
DEMO_PASSWORD="${DEMO_PASSWORD:-local-demo-pass}"
DEMO_NAME="${DEMO_NAME:-Local Demo Admin}"

case "$SUPABASE_URL" in
  http://127.0.0.1:*|http://localhost:*) ;;
  *)
    echo "Refusing to create a demo user for non-local SUPABASE_URL: $SUPABASE_URL" >&2
    echo "Set SUPABASE_URL to a localhost URL for the isolated local stack." >&2
    exit 1
    ;;
esac

if ! command -v curl >/dev/null 2>&1; then
  echo "curl is required." >&2
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is required for JSON encoding." >&2
  exit 1
fi

status_env="$(supabase status -o env 2>/dev/null || true)"

SERVICE_ROLE_KEY="${SERVICE_ROLE_KEY:-$(printf '%s\n' "$status_env" | sed -n 's/^SERVICE_ROLE_KEY="\(.*\)"$/\1/p')}"
ANON_KEY="${ANON_KEY:-$(printf '%s\n' "$status_env" | sed -n 's/^ANON_KEY="\(.*\)"$/\1/p')}"

if [[ -z "${SERVICE_ROLE_KEY:-}" || -z "${ANON_KEY:-}" ]]; then
  echo "Could not read local Supabase keys. Is the local stack running?" >&2
  echo "Run: supabase start" >&2
  exit 1
fi

payload="$(
  DEMO_EMAIL="$DEMO_EMAIL" DEMO_PASSWORD="$DEMO_PASSWORD" DEMO_NAME="$DEMO_NAME" \
    python3 - <<'PY'
import json
import os

print(json.dumps({
    "email": os.environ["DEMO_EMAIL"],
    "password": os.environ["DEMO_PASSWORD"],
    "email_confirm": True,
    "user_metadata": {"display_name": os.environ["DEMO_NAME"]},
}))
PY
)"

create_status="$(
  curl -sS -o /tmp/fieldfleet-demo-user-create.json -w '%{http_code}' \
    -X POST "$SUPABASE_URL/auth/v1/admin/users" \
    -H "apikey: $SERVICE_ROLE_KEY" \
    -H "Authorization: Bearer $SERVICE_ROLE_KEY" \
    -H 'Content-Type: application/json' \
    --data "$payload"
)"

if [[ "$create_status" =~ ^2 ]]; then
  echo "Created local demo auth user: $DEMO_EMAIL"
else
  echo "Create returned HTTP $create_status; checking whether the demo login already works."
fi

login_payload="$(
  DEMO_EMAIL="$DEMO_EMAIL" DEMO_PASSWORD="$DEMO_PASSWORD" \
    python3 - <<'PY'
import json
import os

print(json.dumps({
    "email": os.environ["DEMO_EMAIL"],
    "password": os.environ["DEMO_PASSWORD"],
}))
PY
)"

login_status="$(
  curl -sS -o /tmp/fieldfleet-demo-user-login.json -w '%{http_code}' \
    -X POST "$SUPABASE_URL/auth/v1/token?grant_type=password" \
    -H "apikey: $ANON_KEY" \
    -H 'Content-Type: application/json' \
    --data "$login_payload"
)"

if [[ "$login_status" =~ ^2 ]]; then
  echo "Local demo login is ready."
  echo "Email: $DEMO_EMAIL"
  echo "Password: $DEMO_PASSWORD"
  echo
  echo "The first app login bootstraps the demo workspace through the normal signup path."
else
  echo "Demo login verification failed with HTTP $login_status." >&2
  echo "If the user already exists with a different password, remove it in local Studio and rerun." >&2
  echo "Studio: http://127.0.0.1:55323" >&2
  exit 1
fi
