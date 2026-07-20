# FieldFleet Deployment

Portable, self-hosted Supabase deployment for FieldFleet.

## Quick Start

```bash
# 1. Configure environment
cp .env.example .env
nano .env  # Fill in your values

# 2. Deploy
./scripts/deploy.sh
```

## Directory Structure

```
deployment/
├── docker-compose.yml    # All services definition
├── kong.yml              # API gateway config
├── Caddyfile             # Reverse proxy + HTTPS
├── .env.example          # Environment template
├── .env                  # Your configuration (git-ignored)
├── migrations/           # Database migrations
├── functions/            # Edge functions
├── backups/              # Backup storage
└── scripts/
    ├── deploy.sh         # Initial deployment
    ├── backup.sh         # Create backup
    ├── restore.sh        # Restore from backup
    └── migrate-server.sh # Migrate to new server
```

## Services

| Service | Port | Description |
|---------|------|-------------|
| Kong | 8000 | API Gateway |
| PostgreSQL | 5432 | Database |
| GoTrue | 9999 | Authentication |
| PostgREST | 3000 | REST API |
| Realtime | 4000 | WebSocket subscriptions |
| Storage | 5000 | File storage |
| Studio | 3000 | Admin dashboard |
| Caddy | 80/443 | HTTPS reverse proxy |

## Common Commands

```bash
# View logs
docker compose logs -f

# View specific service
docker compose logs -f db
docker compose logs -f auth

# Restart services
docker compose restart

# Stop everything
docker compose down

# Stop and remove volumes (DESTROYS DATA)
docker compose down -v
```

## Backup & Restore

### Create Backup
```bash
./scripts/backup.sh
```

Creates:
- `backups/db_TIMESTAMP.sql.gz` - Database
- `backups/storage_TIMESTAMP.tar.gz` - Files
- `backups/config_TIMESTAMP.tar.gz` - Configuration
- `backups/taskfleet_backup_TIMESTAMP.tar.gz` - Combined

### Restore on New Server
```bash
./scripts/restore.sh taskfleet_backup_20240115_120000.tar.gz
```

### Migrate to New Server
```bash
./scripts/migrate-server.sh user@newserver.com api.newdomain.com
```

## Server Migration Checklist

1. **Before Migration**
   - [ ] Run `./scripts/backup.sh` on current server
   - [ ] Note down any custom `.env` values

2. **On New Server**
   - [ ] Install Docker and Docker Compose
   - [ ] Copy deployment folder
   - [ ] Run `./scripts/restore.sh <backup>`
   - [ ] Update `.env` with new domain

3. **DNS Updates**
   - [ ] Point API domain to new server
   - [ ] Point Studio domain to new server
   - [ ] Wait for propagation

4. **App Updates**
   - [ ] Update Flutter app's Supabase URL
   - [ ] Test authentication
   - [ ] Test file uploads

5. **Cleanup**
   - [ ] Verify everything works
   - [ ] Shut down old server

## Updating Supabase

```bash
# Pull latest images
docker compose pull

# Restart with new images
docker compose up -d

# Check logs for issues
docker compose logs -f
```

## Troubleshooting

### Database won't start
```bash
docker compose logs db
# Check disk space
df -h
```

### Auth not working
```bash
docker compose logs auth
# Verify JWT_SECRET matches in all services
```

### Storage uploads fail
```bash
docker compose logs storage
# Check permissions
docker compose exec storage ls -la /var/lib/storage
```

If browser devtools shows `net::ERR_FAILED 413 (Content Too Large)` with a CORS error,
the 413 is usually coming from Kong/nginx before CORS headers are applied.

Set `KONG_CLIENT_MAX_BODY_SIZE` in `.env` (for example `100m`) and restart Kong:
```bash
docker compose up -d kong caddy
docker compose logs --tail=100 kong
```

### SSL certificate issues
```bash
docker compose logs caddy
# Caddy auto-renews, check if ports 80/443 are open
```

## Security Checklist

- [ ] Generated unique `POSTGRES_PASSWORD`
- [ ] Generated unique `JWT_SECRET` (min 32 chars)
- [ ] Generated proper `ANON_KEY` and `SERVICE_ROLE_KEY`
- [ ] HTTPS enabled (Caddy handles this)
- [ ] Studio behind VPN or basic auth
- [ ] Regular backups scheduled
- [ ] Firewall configured (only 80/443 open)
