#!/usr/bin/env bash
set -euo pipefail

# scripts/redis-fix-perms.sh
# Fix host-mounted Redis data directory permissions so Redis can persist RDB/AOF
# Usage: ./scripts/redis-fix-perms.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SUPPORT_DIR="$ROOT_DIR/gogotex-support-services/redis-service"
SUPPORT_ENV="$ROOT_DIR/gogotex-support-services/.env"
if [ -f "$SUPPORT_ENV" ]; then
  set -o allexport
  source "$SUPPORT_ENV"
  set +o allexport
fi

REDIS_DATA_DIR=${REDIS_DATA_DIR:-$SUPPORT_DIR/data}
REDIS_CONTAINER=${REDIS_CONTAINER:-redis-redis}

if [ ! -d "$REDIS_DATA_DIR" ]; then
  echo "ERROR: Redis data dir does not exist: $REDIS_DATA_DIR" >&2
  exit 2
fi

echo "Fixing permissions for $REDIS_DATA_DIR (chmod 0777)"
chmod -R 0777 "$REDIS_DATA_DIR"

# Restart container to clear MISCONF and allow bgsave
if docker ps --format '{{.Names}}' | grep -q "^$REDIS_CONTAINER$"; then
  echo "Restarting $REDIS_CONTAINER"
  docker restart "$REDIS_CONTAINER"
  sleep 2
  echo "Checking Redis PING..."
  if docker exec -i "$REDIS_CONTAINER" sh -c "command -v redis-cli >/dev/null 2>&1 && redis-cli PING" 2>/dev/null | grep -q "PONG"; then
    echo "✅ Redis PING OK"
  else
    echo "⚠️ Redis PING did not return PONG; inspect logs (docker logs $REDIS_CONTAINER)" >&2
    exit 3
  fi
else
  echo "WARNING: Redis container $REDIS_CONTAINER not running; please start it and re-run this script" >&2
  exit 2
fi

echo "✅ Redis file permissions fixed and container restarted"
exit 0
