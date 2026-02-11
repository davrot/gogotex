#!/usr/bin/env bash
set -euo pipefail

# scripts/mongo-init-recreate.sh
# Re-run the MongoDB initialization script safely (idempotent).
# Usage: ./scripts/mongo-init-recreate.sh [--container CONTAINER_NAME]

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SUPPORT_ENV="$ROOT_DIR/gogotex-support-services/.env"
if [ -f "$SUPPORT_ENV" ]; then
  set -o allexport
  source "$SUPPORT_ENV"
  set +o allexport
fi

MONGO_CONTAINER=${1:-${MONGO_CONTAINER:-mongodb-mongodb}}
INIT_JS_HOST="$ROOT_DIR/gogotex-support-services/mongodb-service/mongodb-init.js"

if [ ! -f "$INIT_JS_HOST" ]; then
  echo "ERROR: MongoDB init script not found: $INIT_JS_HOST" >&2
  exit 2
fi

echo "Using Mongo container: $MONGO_CONTAINER"
# copy script into container and run via mongosh (works whether auth enabled or not)
TMP_PATH="/tmp/gogotex-mongo-init.js"

echo "Copying init script into container..."
docker cp "$INIT_JS_HOST" "$MONGO_CONTAINER":"$TMP_PATH"

echo "Executing init script inside MongoDB container (idempotent)..."
docker exec -i "$MONGO_CONTAINER" mongosh --quiet "$TMP_PATH"

# cleanup
docker exec -i "$MONGO_CONTAINER" rm -f "$TMP_PATH" || true

echo "✅ MongoDB init script executed"
exit 0
