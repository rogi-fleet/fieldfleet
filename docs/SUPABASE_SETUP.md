# Self-Hosted Supabase Setup Guide

This guide covers setting up Supabase on your local server for FieldFleet.

## Prerequisites

- Docker & Docker Compose installed
- Domain name pointing to your server (e.g., `api.example.com`)
- Ports 80/443 available (or configure reverse proxy)

## 1. Clone Supabase Docker

```bash
# On your server
cd /opt
git clone --depth 1 https://github.com/supabase/supabase
cd supabase/docker
```

## 2. Configure Environment

```bash
cp .env.example .env
```

Edit `.env` with secure values:

```env
############
# Secrets - GENERATE NEW VALUES FOR PRODUCTION
############

# Generate with: openssl rand -base64 32
POSTGRES_PASSWORD=your-super-secret-postgres-password
JWT_SECRET=your-super-secret-jwt-token-with-at-least-32-characters
ANON_KEY=generate-from-jwt-secret
SERVICE_ROLE_KEY=generate-from-jwt-secret

############
# Database
############
POSTGRES_HOST=db
POSTGRES_DB=postgres
POSTGRES_PORT=5432

############
# API
############
SITE_URL=https://app.example.com
API_EXTERNAL_URL=https://api.example.com

############
# Auth
############
GOTRUE_SITE_URL=https://app.example.com
GOTRUE_URI_ALLOW_LIST=https://app.example.com,http://localhost:*

# Email (using Resend)
GOTRUE_SMTP_HOST=smtp.resend.com
GOTRUE_SMTP_PORT=465
GOTRUE_SMTP_USER=resend
GOTRUE_SMTP_PASS=your-resend-api-key
GOTRUE_SMTP_ADMIN_EMAIL=noreply@example.com

# OAuth (optional)
GOTRUE_EXTERNAL_GOOGLE_ENABLED=true
GOTRUE_EXTERNAL_GOOGLE_CLIENT_ID=your-google-client-id
GOTRUE_EXTERNAL_GOOGLE_SECRET=your-google-client-secret
GOTRUE_EXTERNAL_GOOGLE_REDIRECT_URI=https://api.example.com/auth/v1/callback

############
# Storage
############
STORAGE_BACKEND=file
FILE_SIZE_LIMIT=209715200  # 200MB

############
# Studio (Admin Dashboard)
############
STUDIO_DEFAULT_ORGANIZATION=FieldFleet
STUDIO_DEFAULT_PROJECT=FieldFleet
```

### Generate JWT Keys

```bash
# Generate ANON_KEY and SERVICE_ROLE_KEY
# Use https://supabase.com/docs/guides/self-hosting#api-keys
# Or use this script:

npm install -g @supabase/cli
supabase gen keys --jwt-secret "your-jwt-secret"
```

## 3. Configure Reverse Proxy (Caddy)

Install Caddy:
```bash
apt install -y caddy
```

Create `/etc/caddy/Caddyfile`:

```caddyfile
api.example.com {
    reverse_proxy localhost:8000
}

studio.example.com {
    reverse_proxy localhost:3000
}
```

Reload Caddy:
```bash
systemctl reload caddy
```

## 4. Start Supabase

```bash
cd /opt/supabase/docker
docker compose up -d
```

Check status:
```bash
docker compose ps
docker compose logs -f
```

## Local Startup For This Repo

This repository uses the Supabase CLI with Podman or Docker for local
development. The public checkout is configured as Supabase project
`fieldfleet_public` on ports `55321`-`55329`. Those nonstandard ports avoid
accidentally connecting to another local Supabase stack that uses the default
`54321`-`54329` range.

Before applying migrations on a workstation that already runs Supabase, inspect
the active containers and migration history:

```bash
supabase status
docker ps --filter name=supabase_
docker exec supabase_db_fieldfleet_public psql -U postgres -d postgres \
  -c "select count(*) from supabase_migrations.schema_migrations;"
```

If the database has migration versions that are not present in this checkout,
or if it contains data you need, do not run `supabase db reset`, `supabase
migration repair`, or `supabase db pull`. Use a separate project id/port range
or stop the unrelated stack intentionally before continuing.

On macOS with Podman, a reboot can leave the local Supabase containers stopped
until the Podman VM is started again.

### Start after reboot

```bash
cd /path/to/fieldfleet
podman machine start
supabase start
```

### Verify local endpoints

```bash
curl -I http://127.0.0.1:55321
curl -I http://127.0.0.1:55323
docker ps --filter name=supabase_
```

Expected ports:

- API gateway: `55321`
- Studio: `55323`
- Postgres: `55322`

The API gateway root can return `404 Not Found` to a `curl -I` request and
still be healthy; the important signal is that Kong responds on `55321`.
Studio normally redirects to `/project/default`.

### Fresh-install migration notes

During public-checkout validation, a clean isolated replay exposed several
classes of migration drift that should stay fixed:

- Local project id and ports must not overlap another Supabase stack. This repo
  uses `fieldfleet_public` and `55321`-`55329`.
- Public migrations must not assume private-only tables such as `public.notes`.
  Guard legacy-table policy or DDL changes with `to_regclass(...)` checks.
- Migration filenames must have unique timestamp prefixes; duplicate versions
  fail when Supabase records `schema_migrations`.
- Index and function-hardening migrations should tolerate optional/private
  schema objects by checking for the column or function before altering it.
- Data migrations must target columns present in the public schema. Supplier
  contact phone/email belongs in `vendor_contacts`, not nonexistent vendor
  company phone/email columns.

### macOS Podman note

If you see a `vfkit` app or process after startup, leave it running while you want local Supabase available. `vfkit` is the Podman VM backend, so closing it stops the container runtime and the Supabase stack with it.

## 5. Run Migrations

```bash
# Copy migration files to server
scp -r supabase/migrations/* user@server:/opt/supabase/docker/volumes/db/

# Run migrations
docker compose exec db psql -U postgres -d postgres -f /var/lib/postgresql/data/001_initial_schema.sql
docker compose exec db psql -U postgres -d postgres -f /var/lib/postgresql/data/002_row_level_security.sql
docker compose exec db psql -U postgres -d postgres -f /var/lib/postgresql/data/003_storage_buckets.sql
```

Or use Supabase CLI:
```bash
supabase db push --db-url postgres://postgres:password@localhost:5432/postgres
```

## 6. Configure Storage Volume

For large file storage, mount a dedicated disk:

```bash
# Create storage directory
mkdir -p /mnt/storage/supabase

# Edit docker-compose.yml to use external volume
# Under storage service:
volumes:
  - /mnt/storage/supabase:/var/lib/storage
```

## 7. Backup Configuration

Create `/opt/supabase/backup.sh`:

```bash
#!/bin/bash
BACKUP_DIR=/mnt/backups/supabase
DATE=$(date +%Y%m%d_%H%M%S)

# Database backup
docker compose exec -T db pg_dump -U postgres postgres | gzip > $BACKUP_DIR/db_$DATE.sql.gz

# Storage backup (optional - large)
# tar -czf $BACKUP_DIR/storage_$DATE.tar.gz /mnt/storage/supabase

# Keep last 7 days
find $BACKUP_DIR -name "*.gz" -mtime +7 -delete
```

Add to crontab:
```bash
crontab -e
# Add: 0 2 * * * /opt/supabase/backup.sh
```

## 8. Verify Installation

1. **API Health**: `curl https://api.example.com/rest/v1/`
2. **Auth Health**: `curl https://api.example.com/auth/v1/health`
3. **Studio**: Open `https://studio.example.com`

## Security Checklist

- [ ] Changed all default passwords
- [ ] Generated unique JWT secrets
- [ ] HTTPS configured (Caddy handles this)
- [ ] Firewall configured (only 80/443 open)
- [ ] Regular backups scheduled
- [ ] Studio behind authentication or VPN

## Flutter Configuration

Update your Flutter app to use the self-hosted instance:

```dart
// lib/config/supabase_config.dart
class SupabaseConfig {
  static const String url = 'https://api.example.com';
  static const String anonKey = 'your-anon-key';
}
```

## Monitoring

View logs:
```bash
# All services
docker compose logs -f

# Specific service
docker compose logs -f db
docker compose logs -f auth
docker compose logs -f rest
docker compose logs -f storage
```

## Updating Supabase

```bash
cd /opt/supabase/docker
git pull
docker compose pull
docker compose up -d
```

## Troubleshooting

### Database Connection Issues
```bash
docker compose exec db psql -U postgres -c "SELECT 1"
```

### Auth Not Working
```bash
docker compose logs auth
# Check GOTRUE_* env vars
```

### Storage Upload Fails
```bash
# Check permissions
ls -la /mnt/storage/supabase
# Should be owned by container user (usually 1000:1000)
chown -R 1000:1000 /mnt/storage/supabase
```

### Performance Tuning

Edit PostgreSQL config for your server specs:
```bash
# docker-compose.yml under db service
command: postgres -c shared_buffers=256MB -c max_connections=200
```
