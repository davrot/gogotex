#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR" || true

docker compose -f frontend-service/frontend.yaml up -d || true

echo "frontend service started"