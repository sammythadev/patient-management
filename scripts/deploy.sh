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

# Load .env variables so we can validate and use defaults
set -a
# shellcheck disable=SC1090
. "$ENV_FILE"
set +a

if [ -z "${DOCKER_USERNAME:-}" ]; then
    echo "ERROR: DOCKER_USERNAME is not set in $ENV_FILE."
    exit 1
fi

DOCKER_BIN="docker"
if ! $DOCKER_BIN info >/dev/null 2>&1; then
    if command -v sudo >/dev/null 2>&1 && sudo -n docker info >/dev/null 2>&1; then
        DOCKER_BIN="sudo docker"
    else
        echo "ERROR: Docker is not available or not running for the current user."
        echo "       Try: sudo systemctl start docker"
        exit 1
    fi
fi

if $DOCKER_BIN compose version >/dev/null 2>&1; then
    COMPOSE_CMD="$DOCKER_BIN compose"
elif command -v docker-compose >/dev/null 2>&1; then
    if [ "$DOCKER_BIN" = "docker" ]; then
        COMPOSE_CMD="docker-compose"
    else
        COMPOSE_CMD="sudo docker-compose"
    fi
else
    echo "ERROR: Docker Compose plugin not found."
    exit 1
fi

TAG="${1:-${IMAGE_TAG:-latest}}"

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
$COMPOSE_CMD -f "$COMPOSE_FILE" --env-file "$ENV_FILE" pull

# ---- 2. Stop existing containers ----
echo ""
echo ">>> Stopping existing containers..."
$COMPOSE_CMD -f "$COMPOSE_FILE" --env-file "$ENV_FILE" down --remove-orphans

# ---- 3. Start containers ----
echo ""
echo ">>> Starting containers..."
$COMPOSE_CMD -f "$COMPOSE_FILE" --env-file "$ENV_FILE" up -d

# ---- 4. Wait and check health ----
echo ""
echo ">>> Waiting for containers to start (30s)..."
sleep 30

echo ""
echo ">>> Container status:"
$COMPOSE_CMD -f "$COMPOSE_FILE" --env-file "$ENV_FILE" ps

# ---- 5. Quick health check ----
echo ""
echo ">>> Health check (api-gateway on port 4004)..."
if curl -sf http://localhost:4004 > /dev/null 2>&1; then
    echo "    ✓ api-gateway is responding"
else
    echo "    ⚠ api-gateway not responding yet (may still be starting)"
    echo "    Check logs: $COMPOSE_CMD -f $COMPOSE_FILE logs -f api-gateway"
fi

echo ""
echo "============================================="
echo " Deployment complete!"
echo "============================================="
echo " View logs:  $COMPOSE_CMD -f $COMPOSE_FILE --env-file $ENV_FILE logs -f"
echo " Stop all:   $COMPOSE_CMD -f $COMPOSE_FILE --env-file $ENV_FILE down"
echo "============================================="
