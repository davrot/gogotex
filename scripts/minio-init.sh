#!/usr/bin/env bash
set -euo pipefail

# scripts/minio-init.sh
# Create MinIO buckets used by GoGoTeX (idempotent)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SUPPORT_ENV="$ROOT_DIR/gogotex-support-services/.env"
if [ -f "$SUPPORT_ENV" ]; then
  set -o allexport
  source "$SUPPORT_ENV"
  set +o allexport
fi

MINIO_HOST=${MINIO_HOST:-minio-minio:9000}
MINIO_ALIAS=${MINIO_ALIAS:-myminio}
MINIO_USER=${MINIO_ROOT_USER:-admin}
MINIO_PASS=${MINIO_ROOT_PASSWORD:-changeme_minio}
# Primary application bucket can be supplied via MINIO_BUCKET (defaults to 'gogotex')
MINIO_BUCKET=${MINIO_BUCKET:-gogotex}

# Default helpful buckets; include configured MINIO_BUCKET if not already present
DEFAULT_BUCKETS=(projects templates backups plugins)
BUCKETS=(${DEFAULT_BUCKETS[@]})
for _b in "${BUCKETS[@]}"; do
  if [ "$_b" = "$MINIO_BUCKET" ]; then
    HAS_BUCKET=1
    break
  fi
done
if [ -z "${HAS_BUCKET:-}" ]; then
  BUCKETS+=("$MINIO_BUCKET")
fi

# Ensure mc is available via Docker image
MC_IMAGE=${MC_IMAGE:-minio/mc:latest}

echo "Creating MinIO buckets on $MINIO_HOST (alias: $MINIO_ALIAS)"

echo "- Setting alias..."
docker run --rm --network tex-network $MC_IMAGE alias set "$MINIO_ALIAS" "http://$MINIO_HOST" "$MINIO_USER" "$MINIO_PASS" >/dev/null

for b in "${BUCKETS[@]}"; do
  echo -n "- Ensuring bucket '$b'... "
  docker run --rm --network tex-network $MC_IMAGE mb "$MINIO_ALIAS/$b" --ignore-existing >/dev/null 2>&1 || true
  echo "done"
done

echo "MinIO buckets ensured: ${BUCKETS[*]}"
exit 0
