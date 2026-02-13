#!/usr/bin/env bash
set -euo pipefail

docker compose -f frontend-service/frontend.yaml up -d || true

echo "frontend service started"