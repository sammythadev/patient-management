#!/bin/bash
# =============================================================================
# docker-start.sh - Start Docker and bring up the stack with docker compose
# =============================================================================
# Usage:
#   ./docker-start.sh
#   ./docker-start.sh dev
#   ./docker-start.sh prod --env-file .env.prod --tag v1.0.0
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODE="dev"
ENV_FILE=""
COMPOSE_FILE=""
TAG=""
BUILD="false"
PROJECT_NAME=""
CLEAN="false"

usage() {
  echo "Usage:"
  echo "  ./docker-start.sh [dev|prod] [--tag TAG] [--env-file FILE] [--compose-file FILE] [--build] [--project-name NAME] [--clean]"
  echo ""
  echo "Examples:"
  echo "  ./docker-start.sh"
  echo "  ./docker-start.sh --build"
  echo "  ./docker-start.sh --project-name patient-management"
  echo "  ./docker-start.sh --clean"
  echo "  ./docker-start.sh prod --env-file .env.prod --tag v1.0.0"
}

require_var() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    echo "ERROR: Required variable not set in $ENV_FILE: $name"
    exit 1
  fi
}

ensure_docker() {
  if docker info >/dev/null 2>&1; then
    return
  fi

  echo "Docker engine not responding. Attempting to start..."

  if [[ "$(uname -s)" == "Linux" ]]; then
    if command -v systemctl >/dev/null 2>&1; then
      sudo systemctl start docker || true
    elif command -v service >/dev/null 2>&1; then
      sudo service docker start || true
    fi
  fi

  for _ in {1..60}; do
    if docker info >/dev/null 2>&1; then
      echo "Docker is running."
      return
    fi
    sleep 2
  done

  echo "ERROR: Docker engine did not become ready. Start Docker and retry."
  exit 1
}

ensure_project_name() {
  if [[ -z "$PROJECT_NAME" ]]; then
    if [[ -n "${COMPOSE_PROJECT_NAME:-}" ]]; then
      PROJECT_NAME="$COMPOSE_PROJECT_NAME"
    else
      PROJECT_NAME="patient-management"
    fi
  fi

  export COMPOSE_PROJECT_NAME="$PROJECT_NAME"
}

ensure_network() {
  local network="internal"
  if ! docker network inspect "$network" >/dev/null 2>&1; then
    echo "Creating network: $network"
    docker network create --driver bridge "$network" >/dev/null
  fi
}

ensure_volumes() {
  local vol_auth="${COMPOSE_PROJECT_NAME}_auth-db-data"
  local vol_patient="${COMPOSE_PROJECT_NAME}_patient-db-data"

  if ! docker volume inspect "$vol_auth" >/dev/null 2>&1; then
    echo "Creating volume: $vol_auth"
    docker volume create "$vol_auth" >/dev/null
  fi

  if ! docker volume inspect "$vol_patient" >/dev/null 2>&1; then
    echo "Creating volume: $vol_patient"
    docker volume create "$vol_patient" >/dev/null
  fi
}

cleanup_containers() {
  local names=(
    auth-service-db
    patient-service-db
    zookeeper
    kafka
    auth-service
    billing-service
    analytics-service
    patient-service
    api-gateway
  )

  for name in "${names[@]}"; do
    if docker ps -a --format '{{.Names}}' | grep -qx "$name"; then
      echo "Removing container: $name"
      docker rm -f "$name" >/dev/null
    fi
  done
}

build_images() {
  local services=(
    auth-service
    patient-service
    billing-service
    analytics-service
    api-gateway
  )

  if [[ -z "${IMAGE_TAG:-}" ]]; then
    IMAGE_TAG="latest"
  fi

  echo "============================================="
  echo "Building local images"
  echo "Tag: $IMAGE_TAG"
  echo "============================================="

  for service in "${services[@]}"; do
    local context="$SCRIPT_DIR/$service"
    if [[ ! -d "$context" ]]; then
      echo "ERROR: Service folder not found: $context"
      exit 1
    fi

    local image="${DOCKER_USERNAME}/${service}:${IMAGE_TAG}"
    echo ""
    echo ">>> [$service] Building $image ..."
    docker build -t "$image" "$context"
  done
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    dev|--dev)
      MODE="dev"
      shift
      ;;
    prod|--prod)
      MODE="prod"
      shift
      ;;
    --env-file)
      ENV_FILE="${2:-}"
      shift 2
      ;;
    --compose-file)
      COMPOSE_FILE="${2:-}"
      shift 2
      ;;
    --tag)
      TAG="${2:-}"
      shift 2
      ;;
    --build)
      BUILD="true"
      shift
      ;;
    --project-name|-p)
      PROJECT_NAME="${2:-}"
      shift 2
      ;;
    --clean)
      CLEAN="true"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: Unknown argument $1"
      usage
      exit 1
      ;;
  esac
done

if [[ -z "$COMPOSE_FILE" ]]; then
  if [[ "$MODE" == "prod" ]]; then
    COMPOSE_FILE="$SCRIPT_DIR/docker-compose.prod.yml"
  else
    COMPOSE_FILE="$SCRIPT_DIR/docker-compose.dev.yml"
  fi
fi

if [[ -z "$ENV_FILE" ]]; then
  if [[ "$MODE" == "prod" ]]; then
    ENV_FILE="$SCRIPT_DIR/.env.prod"
  else
    ENV_FILE="$SCRIPT_DIR/.env"
  fi
fi

if [[ ! -f "$COMPOSE_FILE" ]]; then
  echo "ERROR: Compose file not found: $COMPOSE_FILE"
  exit 1
fi

if [[ ! -f "$ENV_FILE" ]]; then
  echo "ERROR: Env file not found: $ENV_FILE"
  exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "ERROR: docker is not available on PATH."
  exit 1
fi

set -a
# shellcheck disable=SC1090
. "$ENV_FILE"
set +a

if [[ "$MODE" == "dev" ]]; then
  require_var DOCKER_USERNAME
else
  require_var DOCKER_USERNAME
  require_var IMAGE_TAG
  require_var DB_USERNAME
  require_var DB_PASSWORD
  require_var AUTH_DB_NAME
  require_var PATIENT_DB_NAME
  require_var KAFKA_BOOTSTRAP_SERVERS
  require_var JWT_SECRET
  require_var BILLING_SERVICE_ADDRESS
  require_var BILLING_SERVICE_GRPC_PORT
fi

if [[ -n "$TAG" ]]; then
  export IMAGE_TAG="$TAG"
fi

ensure_project_name
ensure_docker
ensure_network
ensure_volumes
if [[ "$CLEAN" == "true" ]]; then
  cleanup_containers
fi
if [[ "$BUILD" == "true" ]]; then
  build_images
fi

echo "============================================="
echo "Starting stack ($MODE)"
echo "Compose: $COMPOSE_FILE"
echo "Env:     $ENV_FILE"
echo "Project: $COMPOSE_PROJECT_NAME"
echo "============================================="

docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" up -d --remove-orphans
docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" ps
