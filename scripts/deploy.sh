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
ROOT_DIR="$(cd "$APP_DIR/.." && pwd)"
cd "$ROOT_DIR"

ENV_FILE="$ROOT_DIR/.env"
COMPOSE_FILE="$ROOT_DIR/docker-compose.prod.yml"

# Validate files exist
if [ ! -f "$ENV_FILE" ]; then
    echo "ERROR: $ENV_FILE not found. Copy .env.prod to $ROOT_DIR/.env and fill in your values."
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
echo ">>> Waiting for containers to become ready..."

WAIT_TIMEOUT="${WAIT_TIMEOUT:-300}"
WAIT_INTERVAL="${WAIT_INTERVAL:-5}"

wait_for_container() {
    local name="$1"
    local mode="$2" # health|running
    local start
    start="$(date +%s)"

    while true; do
        local status health elapsed
        status=$($DOCKER_BIN inspect -f '{{.State.Status}}' "$name" 2>/dev/null || echo "missing")
        health=$($DOCKER_BIN inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$name" 2>/dev/null || echo "missing")
        elapsed=$(( $(date +%s) - start ))

        if [ "$status" = "running" ]; then
            if [ "$mode" = "health" ]; then
                if [ "$health" = "healthy" ]; then
                    echo "    OK: $name is healthy"
                    return 0
                fi
            else
                echo "    OK: $name is running"
                return 0
            fi
        fi

        if [ "$status" = "exited" ] || [ "$status" = "dead" ]; then
            echo "ERROR: $name is $status"
            $COMPOSE_CMD -f "$COMPOSE_FILE" --env-file "$ENV_FILE" logs --no-color --tail 200 "$name" || true
            return 1
        fi

        if [ "$elapsed" -ge "$WAIT_TIMEOUT" ]; then
            echo "ERROR: Timed out waiting for $name ($mode)"
            $COMPOSE_CMD -f "$COMPOSE_FILE" --env-file "$ENV_FILE" logs --no-color --tail 200 "$name" || true
            return 1
        fi

        sleep "$WAIT_INTERVAL"
    done
}

wait_for_http() {
    local url="$1"
    local timeout="${2:-120}"
    local start
    start="$(date +%s)"

    if ! command -v curl >/dev/null 2>&1; then
        echo "WARN: curl not installed; skipping HTTP readiness check for $url"
        return 0
    fi

    while true; do
        # Treat any HTTP response as "ready"; only a connection failure should retry.
        local code
        code=$(curl -sS -o /dev/null -w '%{http_code}' --connect-timeout 2 --max-time 5 "$url" || echo "000")
        if [ "$code" != "000" ]; then
            echo "    OK: $url is responding (HTTP $code)"
            return 0
        fi

        if [ $(( $(date +%s) - start )) -ge "$timeout" ]; then
            echo "ERROR: Timed out waiting for $url"
            $COMPOSE_CMD -f "$COMPOSE_FILE" --env-file "$ENV_FILE" logs --no-color --tail 200 api-gateway || true
            return 1
        fi

        sleep "$WAIT_INTERVAL"
    done
}

HEALTHY_CONTAINERS=(
    auth-service-db
    patient-service-db
    kafka
)

RUNNING_CONTAINERS=(
    auth-service
    billing-service
    analytics-service
    patient-service
    api-gateway
)

for name in "${HEALTHY_CONTAINERS[@]}"; do
    wait_for_container "$name" "health"
done

for name in "${RUNNING_CONTAINERS[@]}"; do
    wait_for_container "$name" "running"
done

echo ""
echo ">>> Container status:"
$COMPOSE_CMD -f "$COMPOSE_FILE" --env-file "$ENV_FILE" ps

# ---- 5. HTTP readiness check ----
echo ""
echo ">>> Waiting for api-gateway on port 4004..."
API_GATEWAY_URL="${API_GATEWAY_URL:-http://localhost:4004}"
wait_for_http "$API_GATEWAY_URL" 120

echo ""
echo "============================================="
echo " Deployment complete!"
echo "============================================="
echo " View logs:  $COMPOSE_CMD -f $COMPOSE_FILE --env-file $ENV_FILE logs -f"
echo " Stop all:   $COMPOSE_CMD -f $COMPOSE_FILE --env-file $ENV_FILE down"
echo "============================================="
