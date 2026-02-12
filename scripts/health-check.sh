#!/usr/bin/env bash
set -euo pipefail

# scripts/health-check.sh
# Basic infrastructure health checks for Phase 1

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# If not already running inside the helper Docker runner, re-exec this script
# inside an Ubuntu container attached to the `tex-network` so internal container
# hostnames (e.g. keycloak-keycloak, mongodb-mongodb) resolve reliably.
if [ "${HEALTH_CHECK_IN_DOCKER:-}" != "1" ]; then
  echo "Re-running health checks inside ephemeral Ubuntu container on network 'tex-network'..."
  docker run --rm -v "$ROOT_DIR":"$ROOT_DIR" -w "$ROOT_DIR" -v /var/run/docker.sock:/var/run/docker.sock --network tex-network ubuntu:24.04 \
    bash -lc "set -euo pipefail; export DEBIAN_FRONTEND=noninteractive; apt-get update -qq >/dev/null; apt-get install -y -qq docker.io curl jq bash >/dev/null; HEALTH_CHECK_IN_DOCKER=1 bash '$ROOT_DIR/scripts/health-check.sh' \"$@\""
  exit $?
fi

SUPPORT_DIR="$ROOT_DIR/gogotex-support-services"
KEYCLOAK_SECRET_FILE="$SUPPORT_DIR/keycloak-service/client-secret_gogotex-backend.txt"
KEYCLOAK_USER="admin"
# load .env if exists
if [ -f "$SUPPORT_DIR/.env" ]; then
  # shellcheck disable=SC1091
  set -o allexport
  source "$SUPPORT_DIR/.env"
  set +o allexport
fi
KEYCLOAK_ADMIN_PASSWORD=${KEYCLOAK_ADMIN_PASSWORD:-changeme_keycloak}
REDIS_PASSWORD=${REDIS_PASSWORD:-changeme_redis}

PASSED=0
FAILED=0

ok() { echo "✅ $1"; PASSED=$((PASSED+1)); }
fail() { echo "❌ $1"; FAILED=$((FAILED+1)); }

echo "== Basic Docker / containers check =="
if docker info >/dev/null 2>&1; then
  ok "Docker daemon reachable"
else
  fail "Docker daemon not reachable"
fi

# list local container names for later per-service checks
CONTAINERS=$(docker ps --format '{{.Names}}')

# Key services to look for (prefer exact or typical service names)
KEYCLOAK_C="keycloak-keycloak"
MONGO_C="mongodb-mongodb"
REDIS_C="redis-redis"
MINIO_C="minio-minio"
PROM_C="grafana-prometheus"
GRAF_C="grafana-grafana"
NGINX_C="nginx-nginx"

# Keycloak checks are now in a separate script for clarity
source "$ROOT_DIR/scripts/health-check/keycloak.sh"

# MongoDB checks moved to separate file
source "$ROOT_DIR/scripts/health-check/mongodb.sh"

# Redis checks moved to separate file
source "$ROOT_DIR/scripts/health-check/redis.sh"

# MinIO checks moved to a dedicated script
source "$ROOT_DIR/scripts/health-check/minio.sh"

# Prometheus and Grafana checks are now separate
source "$ROOT_DIR/scripts/health-check/prometheus.sh"
source "$ROOT_DIR/scripts/health-check/grafana.sh"

# nginx quick check moved to its own script
source "$ROOT_DIR/scripts/health-check/nginx.sh"


# Summary
echo
echo "== Summary: Passed=$PASSED Failed=$FAILED =="
if [ $FAILED -gt 0 ]; then
  echo "Some checks failed. Please inspect the output above and fix issues."
  exit 2
else
  echo "All checks passed"
  exit 0
fi
