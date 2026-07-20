#!/bin/bash

# Script to build and serve the Flutter web app
# This is a better alternative to 'flutter run -d web-server' for hosting/testing the build

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

PORT=3000

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}FieldFleet Web Server${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Step 1: Build the web app
echo -e "${YELLOW}[1/2] Building Flutter web app (release mode)...${NC}"
flutter build web --release --no-wasm-dry-run

echo -e "${GREEN}✓ Build completed${NC}"
echo ""

# Step 2: Serve the app
echo -e "${YELLOW}[2/2] Starting web server on port ${PORT}...${NC}"
HOST_IP=$(hostname -I | cut -d' ' -f1)
echo -e "Local Access:   ${GREEN}http://localhost:${PORT}${NC}"
echo -e "Network Access: ${GREEN}http://${HOST_IP}:${PORT}${NC}"
echo -e "Press ${YELLOW}Ctrl+C${NC} to stop the server."
echo ""

cd build/web
python3 -m http.server $PORT --bind 0.0.0.0
