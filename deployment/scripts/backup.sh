#!/bin/bash
# =============================================================================
# FieldFleet Backup Script
# Creates portable backups that can be restored on any server
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_DIR="$(dirname "$SCRIPT_DIR")"
BACKUP_DIR="${BACKUP_DIR:-$DEPLOY_DIR/backups}"
DATE=$(date +%Y%m%d_%H%M%S)

# Use docker compose or docker-compose
if command -v "docker compose" >/dev/null 2>&1; then
    COMPOSE="docker compose"
else
    COMPOSE="docker-compose"
fi

cd "$DEPLOY_DIR"

echo "=========================================="
echo "FieldFleet Backup - $DATE"
echo "=========================================="

# Create backup directory
mkdir -p "$BACKUP_DIR"

# Load environment
source .env

# -----------------------------------------------------------------------------
# Database Backup
# -----------------------------------------------------------------------------
echo "Backing up database..."
$COMPOSE exec -T db pg_dump -U postgres -d postgres --clean --if-exists | gzip > "$BACKUP_DIR/db_$DATE.sql.gz"
echo "  Database backup: $BACKUP_DIR/db_$DATE.sql.gz"

# -----------------------------------------------------------------------------
# Storage Backup (files)
# -----------------------------------------------------------------------------
echo "Backing up storage..."
STORAGE_CONTAINER=$($COMPOSE ps -q storage)
if [ -n "$STORAGE_CONTAINER" ]; then
    docker cp "$STORAGE_CONTAINER:/var/lib/storage" "$BACKUP_DIR/storage_$DATE" 2>/dev/null || echo "  No storage data to backup"
    if [ -d "$BACKUP_DIR/storage_$DATE" ]; then
        tar -czf "$BACKUP_DIR/storage_$DATE.tar.gz" -C "$BACKUP_DIR" "storage_$DATE"
        rm -rf "$BACKUP_DIR/storage_$DATE"
        echo "  Storage backup: $BACKUP_DIR/storage_$DATE.tar.gz"
    fi
else
    echo "  Storage container not running, skipping"
fi

# -----------------------------------------------------------------------------
# Configuration Backup
# -----------------------------------------------------------------------------
echo "Backing up configuration..."
mkdir -p "$BACKUP_DIR/config_$DATE"
cp .env "$BACKUP_DIR/config_$DATE/.env" 2>/dev/null || true
cp docker-compose.yml "$BACKUP_DIR/config_$DATE/" 2>/dev/null || true
cp kong.yml "$BACKUP_DIR/config_$DATE/" 2>/dev/null || true
cp Caddyfile "$BACKUP_DIR/config_$DATE/" 2>/dev/null || true
cp -r functions "$BACKUP_DIR/config_$DATE/" 2>/dev/null || true
cp -r migrations "$BACKUP_DIR/config_$DATE/" 2>/dev/null || true

tar -czf "$BACKUP_DIR/config_$DATE.tar.gz" -C "$BACKUP_DIR" "config_$DATE"
rm -rf "$BACKUP_DIR/config_$DATE"
echo "  Config backup: $BACKUP_DIR/config_$DATE.tar.gz"

# -----------------------------------------------------------------------------
# Create combined archive for easy transfer
# -----------------------------------------------------------------------------
echo "Creating combined archive..."
COMBINED_BACKUP="$BACKUP_DIR/taskfleet_backup_$DATE.tar.gz"
tar -czf "$COMBINED_BACKUP" \
    -C "$BACKUP_DIR" \
    "db_$DATE.sql.gz" \
    "config_$DATE.tar.gz" \
    $([ -f "$BACKUP_DIR/storage_$DATE.tar.gz" ] && echo "storage_$DATE.tar.gz")

echo "  Combined backup: $COMBINED_BACKUP"

# -----------------------------------------------------------------------------
# Cleanup old backups (keep last 7 days)
# -----------------------------------------------------------------------------
echo "Cleaning up old backups..."
find "$BACKUP_DIR" -name "db_*.sql.gz" -mtime +7 -delete 2>/dev/null || true
find "$BACKUP_DIR" -name "storage_*.tar.gz" -mtime +7 -delete 2>/dev/null || true
find "$BACKUP_DIR" -name "config_*.tar.gz" -mtime +7 -delete 2>/dev/null || true
find "$BACKUP_DIR" -name "taskfleet_backup_*.tar.gz" -mtime +7 -delete 2>/dev/null || true

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------
echo ""
echo "=========================================="
echo "Backup Complete!"
echo "=========================================="
echo ""
echo "Backup location: $BACKUP_DIR"
echo ""
echo "Files created:"
ls -lh "$BACKUP_DIR"/*$DATE* 2>/dev/null || echo "  (none)"
echo ""
echo "To transfer to another server:"
echo "  scp $COMBINED_BACKUP user@newserver:/path/to/backups/"
echo ""
