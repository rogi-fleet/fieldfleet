#!/bin/bash
# =============================================================================
# FieldFleet Server Migration Script
# One-command migration from one server to another
# =============================================================================

set -e

echo "=========================================="
echo "FieldFleet Server Migration"
echo "=========================================="
echo ""

# -----------------------------------------------------------------------------
# Parse arguments
# -----------------------------------------------------------------------------
if [ -z "$1" ] || [ -z "$2" ]; then
    echo "Usage: $0 <new_server> <new_api_domain> [new_studio_domain]"
    echo ""
    echo "Example:"
    echo "  $0 user@newserver.com api.newdomain.com studio.newdomain.com"
    echo ""
    echo "This script will:"
    echo "  1. Create a full backup on this server"
    echo "  2. Copy deployment files to the new server"
    echo "  3. Transfer the backup to the new server"
    echo "  4. Provide instructions to complete migration"
    echo ""
    exit 1
fi

NEW_SERVER="$1"
NEW_API_DOMAIN="$2"
NEW_STUDIO_DOMAIN="${3:-studio.${NEW_API_DOMAIN#api.}}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_DIR="$(dirname "$SCRIPT_DIR")"

cd "$DEPLOY_DIR"

# -----------------------------------------------------------------------------
# Step 1: Create backup
# -----------------------------------------------------------------------------
echo "Step 1: Creating backup..."
./scripts/backup.sh

# Find latest backup
LATEST_BACKUP=$(ls -t backups/taskfleet_backup_*.tar.gz 2>/dev/null | head -1)

if [ -z "$LATEST_BACKUP" ]; then
    echo "Error: No backup found"
    exit 1
fi

echo "  Backup created: $LATEST_BACKUP"

# -----------------------------------------------------------------------------
# Step 2: Prepare new server
# -----------------------------------------------------------------------------
echo ""
echo "Step 2: Preparing new server..."

# Create deployment directory on new server
ssh "$NEW_SERVER" "mkdir -p ~/taskfleet/deployment/scripts ~/taskfleet/deployment/migrations ~/taskfleet/deployment/functions"

# Copy deployment files
echo "  Copying deployment files..."
scp docker-compose.yml "$NEW_SERVER:~/taskfleet/deployment/"
scp kong.yml "$NEW_SERVER:~/taskfleet/deployment/"
scp Caddyfile "$NEW_SERVER:~/taskfleet/deployment/"
scp .env.example "$NEW_SERVER:~/taskfleet/deployment/"
scp -r scripts/* "$NEW_SERVER:~/taskfleet/deployment/scripts/"
scp -r migrations/* "$NEW_SERVER:~/taskfleet/deployment/migrations/" 2>/dev/null || true
scp -r functions/* "$NEW_SERVER:~/taskfleet/deployment/functions/" 2>/dev/null || true

# -----------------------------------------------------------------------------
# Step 3: Create .env for new server
# -----------------------------------------------------------------------------
echo "  Creating .env for new server..."

# Copy current .env as base
scp .env "$NEW_SERVER:~/taskfleet/deployment/.env.old"

# Update domains in .env on new server
ssh "$NEW_SERVER" "cd ~/taskfleet/deployment && \
    cp .env.old .env && \
    sed -i 's|API_EXTERNAL_URL=.*|API_EXTERNAL_URL=https://${NEW_API_DOMAIN}|' .env && \
    sed -i 's|API_DOMAIN=.*|API_DOMAIN=${NEW_API_DOMAIN}|' .env && \
    sed -i 's|STUDIO_DOMAIN=.*|STUDIO_DOMAIN=${NEW_STUDIO_DOMAIN}|' .env && \
    sed -i 's|SITE_URL=.*|SITE_URL=https://app.${NEW_API_DOMAIN#api.}|' .env"

# -----------------------------------------------------------------------------
# Step 4: Transfer backup
# -----------------------------------------------------------------------------
echo ""
echo "Step 3: Transferring backup..."
scp "$LATEST_BACKUP" "$NEW_SERVER:~/taskfleet/deployment/backups/"

# -----------------------------------------------------------------------------
# Step 5: Make scripts executable
# -----------------------------------------------------------------------------
ssh "$NEW_SERVER" "chmod +x ~/taskfleet/deployment/scripts/*.sh"

# -----------------------------------------------------------------------------
# Instructions
# -----------------------------------------------------------------------------
BACKUP_FILENAME=$(basename "$LATEST_BACKUP")

echo ""
echo "=========================================="
echo "Migration Prepared!"
echo "=========================================="
echo ""
echo "Files have been copied to: $NEW_SERVER:~/taskfleet/deployment/"
echo ""
echo "To complete the migration, SSH to the new server and run:"
echo ""
echo "  ssh $NEW_SERVER"
echo "  cd ~/taskfleet/deployment"
echo ""
echo "  # Review and update .env if needed"
echo "  nano .env"
echo ""
echo "  # Restore from backup"
echo "  ./scripts/restore.sh backups/$BACKUP_FILENAME"
echo ""
echo "After restore completes:"
echo "  1. Update DNS:"
echo "     - Point ${NEW_API_DOMAIN} to the new server IP"
echo "     - Point ${NEW_STUDIO_DOMAIN} to the new server IP"
echo ""
echo "  2. Update your Flutter app config:"
echo "     - Change Supabase URL to https://${NEW_API_DOMAIN}"
echo ""
echo "  3. Test the deployment:"
echo "     - curl https://${NEW_API_DOMAIN}/rest/v1/"
echo "     - Open https://${NEW_STUDIO_DOMAIN}"
echo ""
