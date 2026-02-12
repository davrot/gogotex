#!/usr/bin/env bash
set -euo pipefail

# scripts/health-check.sh
# Basic infrastructure health checks for Phase 1

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

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

# helper to find a container by regex (prefers common service names)
find_container() {
  # Prefer exact/full-name matches first, then fallback to the first partial match.
  # This avoids selecting exporter/auxiliary containers (e.g. mongodb-express)
  echo "$CONTAINERS" | grep -xE "$1" | head -n1 || \
    echo "$CONTAINERS" | grep -E "$1" | grep -v -E "exporter|healthcheck" | head -n1 || true
}

# Detect the actual container names (fallback to sensible defaults)
KEYCLOAK_C=$(find_container '(^keycloak-keycloak$|keycloak|gogotex-keycloak)')
MONGO_C=$(find_container '(^mongodb-mongodb$|mongo|mongodb)')
REDIS_C=$(find_container '(^redis-redis$|redis)')
MINIO_C=$(find_container '(^minio-minio$|minio)')
PROM_C=$(find_container '(^grafana-prometheus$|prometheus|prom)')
GRAF_C=$(find_container '(^grafana-grafana$|grafana)')
NGINX_C=$(find_container '(^nginx-nginx$|nginx)')

# Fallback values (used by standalone sub-scripts if detection fails)
KEYCLOAK_C=${KEYCLOAK_C:-keycloak-keycloak}
MONGO_C=${MONGO_C:-mongodb-mongodb}
REDIS_C=${REDIS_C:-redis-redis}
MINIO_C=${MINIO_C:-minio-minio}
PROM_C=${PROM_C:-grafana-prometheus}
GRAF_C=${GRAF_C:-grafana-grafana}
NGINX_C=${NGINX_C:-nginx-nginx}

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
