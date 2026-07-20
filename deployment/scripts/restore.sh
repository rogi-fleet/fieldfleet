#!/bin/bash
# =============================================================================
# FieldFleet Restore Script
# Restores from a backup archive to a new server
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_DIR="$(dirname "$SCRIPT_DIR")"

# Use docker compose or docker-compose
if command -v "docker compose" >/dev/null 2>&1; then
    COMPOSE="docker compose"
else
    COMPOSE="docker-compose"
fi

# -----------------------------------------------------------------------------
# Parse arguments
# -----------------------------------------------------------------------------
if [ -z "$1" ]; then
    echo "Usage: $0 <backup_archive.tar.gz> [--skip-storage]"
    echo ""
    echo "Examples:"
    echo "  $0 taskfleet_backup_20240115_120000.tar.gz"
    echo "  $0 taskfleet_backup_20240115_120000.tar.gz --skip-storage"
    echo ""
    exit 1
fi

BACKUP_ARCHIVE="$1"
SKIP_STORAGE=false

if [ "$2" = "--skip-storage" ]; then
    SKIP_STORAGE=true
fi

if [ ! -f "$BACKUP_ARCHIVE" ]; then
    echo "Error: Backup archive not found: $BACKUP_ARCHIVE"
    exit 1
fi

echo "=========================================="
echo "FieldFleet Restore"
echo "=========================================="
echo "Backup: $BACKUP_ARCHIVE"
echo ""

# -----------------------------------------------------------------------------
# Extract backup
# -----------------------------------------------------------------------------
TEMP_DIR=$(mktemp -d)
echo "Extracting backup to $TEMP_DIR..."
tar -xzf "$BACKUP_ARCHIVE" -C "$TEMP_DIR"

# Find the backup files
DB_BACKUP=$(find "$TEMP_DIR" -name "db_*.sql.gz" | head -1)
CONFIG_BACKUP=$(find "$TEMP_DIR" -name "config_*.tar.gz" | head -1)
STORAGE_BACKUP=$(find "$TEMP_DIR" -name "storage_*.tar.gz" | head -1)

echo "Found backups:"
echo "  Database: $DB_BACKUP"
echo "  Config:   $CONFIG_BACKUP"
echo "  Storage:  ${STORAGE_BACKUP:-none}"
echo ""

# -----------------------------------------------------------------------------
# Restore configuration
# -----------------------------------------------------------------------------
if [ -n "$CONFIG_BACKUP" ]; then
    echo "Restoring configuration..."
    tar -xzf "$CONFIG_BACKUP" -C "$TEMP_DIR"
    CONFIG_DIR=$(find "$TEMP_DIR" -type d -name "config_*" | head -1)

    if [ -d "$CONFIG_DIR" ]; then
        # Copy config files
        cp "$CONFIG_DIR/docker-compose.yml" "$DEPLOY_DIR/" 2>/dev/null || true
        cp "$CONFIG_DIR/kong.yml" "$DEPLOY_DIR/" 2>/dev/null || true
        cp "$CONFIG_DIR/Caddyfile" "$DEPLOY_DIR/" 2>/dev/null || true
        cp -r "$CONFIG_DIR/functions" "$DEPLOY_DIR/" 2>/dev/null || true
        cp -r "$CONFIG_DIR/migrations" "$DEPLOY_DIR/" 2>/dev/null || true

        # Handle .env specially - don't overwrite if exists
        if [ ! -f "$DEPLOY_DIR/.env" ]; then
            cp "$CONFIG_DIR/.env" "$DEPLOY_DIR/"
            echo "  .env restored (REVIEW AND UPDATE DOMAINS!)"
        else
            echo "  .env exists, not overwriting (backup saved as .env.restored)"
            cp "$CONFIG_DIR/.env" "$DEPLOY_DIR/.env.restored"
        fi
    fi
    echo "  Configuration restored."
fi

# -----------------------------------------------------------------------------
# Check/update .env for new server
# -----------------------------------------------------------------------------
cd "$DEPLOY_DIR"

if [ -f .env ]; then
    echo ""
    echo "IMPORTANT: Review your .env file!"
    echo "You may need to update these for the new server:"
    echo "  - API_EXTERNAL_URL"
    echo "  - API_DOMAIN"
    echo "  - STUDIO_DOMAIN"
    echo "  - SITE_URL"
    echo ""
    read -p "Have you updated .env for this server? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Please update .env and run this script again."
        rm -rf "$TEMP_DIR"
        exit 1
    fi
fi

source .env

# -----------------------------------------------------------------------------
# Start services (without data)
# -----------------------------------------------------------------------------
echo "Starting services..."
$COMPOSE up -d db

echo "Waiting for database to be ready..."
sleep 10
until $COMPOSE exec -T db pg_isready -U postgres; do
    echo "Waiting for PostgreSQL..."
    sleep 2
done

# -----------------------------------------------------------------------------
# Restore database
# -----------------------------------------------------------------------------
if [ -n "$DB_BACKUP" ]; then
    echo "Restoring database..."

    # Drop existing connections and restore
    $COMPOSE exec -T db psql -U postgres -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = 'postgres' AND pid <> pg_backend_pid();" 2>/dev/null || true

    gunzip -c "$DB_BACKUP" | $COMPOSE exec -T db psql -U postgres -d postgres

    echo "  Database restored."
fi

# -----------------------------------------------------------------------------
# Restore storage
# -----------------------------------------------------------------------------
if [ -n "$STORAGE_BACKUP" ] && [ "$SKIP_STORAGE" = false ]; then
    echo "Restoring storage..."
    tar -xzf "$STORAGE_BACKUP" -C "$TEMP_DIR"
    STORAGE_DIR=$(find "$TEMP_DIR" -type d -name "storage_*" | head -1)

    if [ -d "$STORAGE_DIR" ]; then
        # Start storage service
        $COMPOSE up -d storage
        sleep 5

        # Copy files into container
        STORAGE_CONTAINER=$($COMPOSE ps -q storage)
        docker cp "$STORAGE_DIR/." "$STORAGE_CONTAINER:/var/lib/storage/"

        echo "  Storage restored."
    fi
else
    if [ "$SKIP_STORAGE" = true ]; then
        echo "Skipping storage restore (--skip-storage flag)"
    fi
fi

# -----------------------------------------------------------------------------
# Start all services
# -----------------------------------------------------------------------------
echo "Starting all services..."
$COMPOSE up -d

# -----------------------------------------------------------------------------
# Cleanup
# -----------------------------------------------------------------------------
rm -rf "$TEMP_DIR"

# -----------------------------------------------------------------------------
# Verify
# -----------------------------------------------------------------------------
echo ""
echo "=========================================="
echo "Restore Complete!"
echo "=========================================="
echo ""
$COMPOSE ps
echo ""
echo "Next steps:"
echo "  1. Update DNS to point to this server"
echo "  2. Test the API: curl ${API_EXTERNAL_URL}/rest/v1/"
echo "  3. Update your Flutter app's Supabase URL if changed"
echo ""
