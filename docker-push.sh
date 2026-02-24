#!/bin/bash
# =============================================================================
# docker-push.sh - Build and push all service images to Docker Hub
# =============================================================================
# Prerequisites:
#   docker login
#
# Usage:
#   ./docker-push.sh
#   ./docker-push.sh --username your-dockerhub-username
#   ./docker-push.sh --tag v1.0.0
#   ./docker-push.sh --username your-dockerhub-username --tag v1.0.0
#   ./docker-push.sh --env-file .env
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"
USERNAME=""
TAG=""

usage() {
  echo "Usage:"
  echo "  ./docker-push.sh [--username USERNAME] [--tag TAG] [--env-file FILE]"
  echo ""
  echo "Examples:"
  echo "  ./docker-push.sh"
  echo "  ./docker-push.sh --username myuser --tag v1.0.0"
  echo "  ./docker-push.sh --env-file .env"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -u|--username)
      USERNAME="${2:-}"
      shift 2
      ;;
    -t|--tag)
      TAG="${2:-}"
      shift 2
      ;;
    --env-file)
      ENV_FILE="${2:-}"
      shift 2
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

if ! command -v docker >/dev/null 2>&1; then
  echo "ERROR: docker is not available on PATH."
  exit 1
fi

if [[ -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  . "$ENV_FILE"
  set +a
fi

if [[ -z "$USERNAME" ]]; then
  USERNAME="${DOCKER_USERNAME:-}"
fi

if [[ -z "$TAG" ]]; then
  TAG="${IMAGE_TAG:-}"
fi

if [[ -z "$TAG" ]]; then
  TAG="latest"
fi

if [[ -z "$USERNAME" ]]; then
  echo "ERROR: DOCKER_USERNAME not set. Provide --username or set it in $ENV_FILE."
  exit 1
fi

services=(
  auth-service
  patient-service
  billing-service
  analytics-service
  api-gateway
)

echo "============================================="
echo " Building & Pushing Docker Images"
echo " Username: $USERNAME | Tag: $TAG"
echo "============================================="

for service in "${services[@]}"; do
  context="$SCRIPT_DIR/$service"
  if [[ ! -d "$context" ]]; then
    echo "ERROR: Service folder not found: $context"
    exit 1
  fi

  image="${USERNAME}/${service}:${TAG}"

  echo ""
  echo ">>> [$service] Building $image ..."
  docker build -t "$image" "$context"

  echo ">>> [$service] Pushing $image ..."
  docker push "$image"

  echo ">>> [$service] Done!"
done

echo ""
echo "============================================="
echo " All images pushed successfully!"
echo "============================================="
