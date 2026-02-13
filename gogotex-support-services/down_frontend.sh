#!/usr/bin/env bash
set -euo pipefail

docker compose -f frontend-service/frontend.yaml down || true

echo "frontend service stopped"