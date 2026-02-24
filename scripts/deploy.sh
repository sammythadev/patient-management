#!/bin/bash
# =============================================================================
# deploy.sh — Pull latest images and restart all containers
# =============================================================================
# This script runs on the EC2 instance (called directly or via SSH from CI/CD).
# Usage:
#   ./deploy.sh                  # Deploy with defaults from .env
#   ./deploy.sh v1.0.0           # Deploy a specific tag
# =============================================================================

set -euo pipefail

APP_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$APP_DIR"

TAG="${1:-latest}"
ENV_FILE="$APP_DIR/.env"
COMPOSE_FILE="$APP_DIR/docker-compose.prod.yml"

# Validate files exist
if [ ! -f "$ENV_FILE" ]; then
    echo "ERROR: $ENV_FILE not found. Copy .env.prod and fill in your values."
    exit 1
fi

if [ ! -f "$COMPOSE_FILE" ]; then
    echo "ERROR: $COMPOSE_FILE not found."
    exit 1
fi

# Override IMAGE_TAG if provided
if [ "$TAG" != "latest" ]; then
    export IMAGE_TAG="$TAG"
fi

echo "============================================="
echo " Deploying Patient Management (tag: $TAG)"
echo "============================================="

# ---- 1. Pull latest images ----
echo ""
echo ">>> Pulling latest images..."
docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" pull

# ---- 2. Stop existing containers ----
echo ""
echo ">>> Stopping existing containers..."
docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" down --remove-orphans

# ---- 3. Start containers ----
echo ""
echo ">>> Starting containers..."
docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" up -d

# ---- 4. Wait and check health ----
echo ""
echo ">>> Waiting for containers to start (30s)..."
sleep 30

echo ""
echo ">>> Container status:"
docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" ps

# ---- 5. Quick health check ----
echo ""
echo ">>> Health check (api-gateway on port 4004)..."
if curl -sf http://localhost:4004 > /dev/null 2>&1; then
    echo "    ✓ api-gateway is responding"
else
    echo "    ⚠ api-gateway not responding yet (may still be starting)"
    echo "    Check logs: docker compose -f $COMPOSE_FILE logs -f api-gateway"
fi

echo ""
echo "============================================="
echo " Deployment complete!"
echo "============================================="
echo " View logs:  docker compose -f $COMPOSE_FILE --env-file $ENV_FILE logs -f"
echo " Stop all:   docker compose -f $COMPOSE_FILE --env-file $ENV_FILE down"
echo "============================================="
