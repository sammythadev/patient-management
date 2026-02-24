#!/bin/bash
set -euo pipefail

# Usage:
#   ./start-dev.sh [additional docker-start.sh args]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/docker-start.sh" dev "$@"
