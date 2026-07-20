#!/bin/bash
# =============================================================================
# FieldFleet Deployment Script
# Run on any server with Docker to deploy the full stack
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_DIR="$(dirname "$SCRIPT_DIR")"

echo "=========================================="
echo "FieldFleet Deployment"
echo "=========================================="

# Check prerequisites
command -v docker >/dev/null 2>&1 || { echo "Docker is required but not installed. Aborting." >&2; exit 1; }
command -v docker-compose >/dev/null 2>&1 || command -v "docker compose" >/dev/null 2>&1 || { echo "Docker Compose is required but not installed. Aborting." >&2; exit 1; }

# Use docker compose or docker-compose
if command -v "docker compose" >/dev/null 2>&1; then
    COMPOSE="docker compose"
else
    COMPOSE="docker-compose"
fi

cd "$DEPLOY_DIR"

# Check for .env file
if [ ! -f .env ]; then
    echo "Error: .env file not found!"
    echo "Copy .env.example to .env and configure it first:"
    echo "  cp .env.example .env"
    echo "  nano .env"
    exit 1
fi

# Validate required env vars
source .env
REQUIRED_VARS="POSTGRES_PASSWORD JWT_SECRET ANON_KEY SERVICE_ROLE_KEY API_EXTERNAL_URL SITE_URL"
for var in $REQUIRED_VARS; do
    if [ -z "${!var}" ]; then
        echo "Error: $var is not set in .env"
        exit 1
    fi
done

echo "Environment validated."

# Create necessary directories
mkdir -p functions/main
mkdir -p migrations

# Copy migrations if not present
if [ ! -f migrations/001_initial_schema.sql ]; then
    echo "Copying migrations from supabase/migrations..."
    cp -r ../supabase/migrations/* migrations/ 2>/dev/null || echo "Note: No migrations found in ../supabase/migrations"
fi

# Copy edge functions if not present
if [ ! -f functions/main/index.ts ]; then
    echo "Copying edge functions from supabase/functions..."
    cp -r ../supabase/functions/* functions/ 2>/dev/null || echo "Note: No functions found in ../supabase/functions"
fi

# Pull latest images
echo "Pulling Docker images..."
$COMPOSE pull

# Start services
echo "Starting services..."
$COMPOSE up -d

# Wait for database to be ready
echo "Waiting for database to be ready..."
sleep 10

# Check if database is healthy
until $COMPOSE exec -T db pg_isready -U postgres; do
    echo "Waiting for PostgreSQL..."
    sleep 2
done

echo "Database is ready."

# Run migrations if tables don't exist
echo "Checking if migrations are needed..."
TABLE_EXISTS=$($COMPOSE exec -T db psql -U postgres -d postgres -tAc "SELECT EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'workspaces');")

if [ "$TABLE_EXISTS" = "f" ]; then
    echo "Running migrations..."
    for migration in migrations/*.sql; do
        if [ -f "$migration" ]; then
            echo "Applying $migration..."
            $COMPOSE exec -T db psql -U postgres -d postgres -f "/docker-entrypoint-initdb.d/$(basename $migration)"
        fi
    done
    echo "Migrations complete."
else
    echo "Tables already exist, skipping migrations."
fi

# Show status
echo ""
echo "=========================================="
echo "Deployment Complete!"
echo "=========================================="
echo ""
$COMPOSE ps
echo ""
echo "Services:"
echo "  API:     ${API_EXTERNAL_URL}"
echo "  Studio:  https://${STUDIO_DOMAIN:-studio.localhost}"
echo ""
echo "Next steps:"
echo "  1. Configure DNS to point to this server"
echo "  2. Test the API: curl ${API_EXTERNAL_URL}/rest/v1/"
echo "  3. Access Studio to manage your database"
echo ""
